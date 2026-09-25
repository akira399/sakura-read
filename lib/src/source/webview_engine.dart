// 隐藏 WebView 引擎：为「需要 JS 才能出正文」的小说站提供渲染读取。
//
// 背景：部分站点（笔趣阁家族等）的正文走 JS 令牌墙 + SPA 路由 + 加密接口，
// 纯 HTTP 只能拿到「加载中……」壳页；系统 WebView（Chromium 内核）会把整条链
// 跑完并渲染出正文。
//
// 方案：在 App 根挂一个 1×1 像素、不可交互的隐藏 WebView：
//   1. loadRequest 打开目标章节页（自动跟随 301 / JS 跳转）；
//   2. 等 onPageFinished（SPA hash 路由不触发时以轮询兜底）；
//   3. 反复注入抽取脚本，直到正文容器出现且**通过质量校验**；
//   4. 返回纯文本（清洗交给上层）。
//
// ★ 抽取严格化（重要教训）★
// 早期版本在「找不到正文容器」时会**回退到 `document.body.innerText`**，
// 结果整页导航（「我的书架 / 首页 / 玄幻 / 武侠…」）被当成正文抓进读者
// 界面。现在改为**绝不回退整页**：
//   - 只认「明确候选容器」（书源规则给的 CSS 选择器 + 内置猜测）；
//   - 每个候选还要通过质量校验（正文占比 / 导航词占比 / 段落结构）；
//   - 全部候选都不合格 → 返回空串，由上层报错重试，而不是喂给用户一堆菜单。
//
// 注意：
// - 用桌面 UA：站点 common.js 会把 Android/iPhone UA 重定向到 m.* 子站，
//   其 DOM 模板与主站读页不同；桌面 UA 可留在主站 SPA 读页（#chaptercontent）。
// - 单 WebView 实例，所有读取任务串行化。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 隐藏 WebView 引擎（单例）。
class WebViewEngine {
  WebViewEngine._();

  static final WebViewEngine instance = WebViewEngine._();

  /// 桌面 UA（避免被站点重定向到移动版子站）。
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  /// 宿主挂载信号：为 true 时 [WebViewEngineHost] 构建 1×1 的 WebView。
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  WebViewController? _controller;
  bool _warmed = false;
  Completer<void>? _pageFinished;
  Future<void> _queue = Future<void>.value();

  /// 最近一次加载完成的页面地址（诊断用）。
  String lastFinishedUrl = '';

  /// 获取（或惰性创建）控制器；调用即激活宿主。
  WebViewController ensureController() {
    var c = _controller;
    if (c != null) {
      active.value = true;
      return c;
    }
    c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            lastFinishedUrl = url;
            final f = _pageFinished;
            if (f != null && !f.isCompleted) f.complete();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              final f = _pageFinished;
              if (f != null && !f.isCompleted) f.complete();
            }
          },
        ),
      );
    _controller = c;
    active.value = true;
    return c;
  }

  /// 等待宿主挂载并完成一次 JS 往返（确认可执行 JS）。
  Future<void> _ensureWarm(WebViewController c) async {
    if (_warmed) return;
    for (var i = 0; i < 50; i++) {
      try {
        final v = await c.runJavaScriptReturningResult('1+1');
        if (v.toString().contains('2')) {
          _warmed = true;
          return;
        }
      } catch (_) {
        // WebView 还没挂载好：稍后重试
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('隐藏浏览器未就绪（WebView 初始化失败）');
  }

  /// 串行化所有读取任务（单 WebView 实例）。
  Future<T> _enqueue<T>(Future<T> Function() job) {
    final prev = _queue;
    final gate = Completer<void>();
    _queue = gate.future;
    return () async {
      await prev.catchError((_) {});
      try {
        return await job();
      } finally {
        gate.complete();
      }
    }();
  }

  /// 打开 [url]，等待/轮询渲染结果，返回抽取到的文本（可能为空串）。
  ///
  /// [cssSelectors] 为优先尝试的正文选择器（书源 ruleContent 规则转换而来）；
  /// 找不到时回退到内置候选列表。**不会**回退到整页文本。
  Future<String> fetchRenderedText({
    required String url,
    List<String> cssSelectors = const [],
    Duration totalWait = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 700),
    int minChars = 80,
  }) {
    return _enqueue(() async {
      final c = ensureController();
      await _ensureWarm(c);

      // 发起加载，等 onPageFinished（最多 15 秒；SPA 导航靠下面轮询兜底）
      final done = Completer<void>();
      _pageFinished = done;
      try {
        await c.loadRequest(Uri.parse(url));
      } catch (_) {}
      await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      _pageFinished = null;

      final js = _buildExtractScript(cssSelectors);
      final deadline = DateTime.now().add(totalWait);
      var last = '';
      while (DateTime.now().isBefore(deadline)) {
        try {
          final raw = await c.runJavaScriptReturningResult(js);
          final text = _decodeJsString(raw);
          if (text.trim().length > last.trim().length) last = text;
          if (text.trim().length >= minChars) return text;
        } catch (_) {
          // 页面切换间隙执行失败：忽略，继续轮询
        }
        await Future<void>.delayed(pollInterval);
      }
      return last;
    });
  }

  /// 把平台返回的结果解码为字符串（Android 侧是 JSON 编码的字符串）。
  static String _decodeJsString(Object? raw) {
    if (raw == null) return '';
    final s = raw.toString();
    if (s.isEmpty || s == 'null') return '';
    try {
      final decoded = jsonDecode(s);
      if (decoded is String) return decoded;
    } catch (_) {}
    return s;
  }

  /// 注入脚本：只从「明确候选容器」里取正文，并做质量校验。
  ///
  /// 质量校验（任一不通过即视为“抓到的不是正文”）：
  ///   - 纯文本长度 ≥ 80；
  ///   - 导航行占比 ≤ 35%（导航行 = 短行且命中常见站点栏目词）；
  ///   - 不能是一堆「短行 + 无长段落」的目录/菜单结构。
  static String _buildExtractScript(List<String> selectors) {
    final sels = jsonEncode(selectors);
    return '''
(function() {
  try {
    var sels = $sels;
    // 正文候选：书源规则给的优先，其后是常见站点模板的容器 id / class
    var guess = ['#chaptercontent', '#content', '#booktxt', '#nr1',
                 '#htmlContent', '.showtxt', '.Readarea', '#chapter_content',
                 '.content', '.read-content', '.text', 'article'];
    var all = sels.concat(guess);

    var NAV_WORDS = ['首页','书架','我的书架','排行榜','玄幻','武侠','都市',
                     '历史','网游','科幻','女生','完本','分类','排行','登录',
                     '注册','搜索','作者专区','全部小说','最近更新','本站',
                     '收藏本站','加入书签','推荐本书','返回目录','上一章',
                     '下一章','字体','护眼','关灯','大中小','手机版'];

    function norm(t) { return (t || '').replace(/\\r/g, ''); }
    function lines(t) { return norm(t).split('\\n'); }
    function dense(t) { return (t || '').replace(/\\s/g, '').length; }

    // 导航行占比：短行（≤8 字）且命中栏目词 → 记作导航
    function navRatio(t) {
      var ls = lines(t).filter(function(x) { return x.trim().length > 0; });
      if (ls.length === 0) return 1;
      var nav = 0;
      for (var i = 0; i < ls.length; i++) {
        var s = ls[i].trim();
        if (s.length > 8) continue;
        for (var j = 0; j < NAV_WORDS.length; j++) {
          if (s.indexOf(NAV_WORDS[j]) >= 0) { nav++; break; }
        }
      }
      return nav / ls.length;
    }

    // 是否像正文：长段落存在、且导航占比低
    function looksLikeContent(t) {
      if (dense(t) < 80) return false;
      var ls = lines(t).filter(function(x) { return x.trim().length > 0; });
      // 至少要有 2 行「明显是句子」的行（≥18 字）
      var longLines = 0;
      for (var i = 0; i < ls.length; i++) {
        if (ls[i].trim().length >= 18) longLines++;
      }
      if (longLines < 2) return false;
      if (navRatio(t) > 0.35) return false;
      return true;
    }

    var best = '';
    for (var i = 0; i < all.length; i++) {
      var sel = all[i];
      if (!sel) continue;
      try {
        var el = document.querySelector(sel);
        if (!el) continue;
        var t = norm(el.innerText || '');
        if (dense(t) < 80) t = norm(el.textContent || '');
        if (!looksLikeContent(t)) continue;
        if (dense(t) > dense(best)) best = t;
      } catch (e) {}
    }
    if (best) return best;

    // 兜底：在「容器够深、子元素不多」的节点里找最长的合格块，
    // 仍然要求通过质量校验（绝不回退整页 body）。
    try {
      var nodes = document.querySelectorAll('div,article,section,td');
      for (var k = 0; k < nodes.length; k++) {
        var n = nodes[k];
        if (n.children && n.children.length > 2) continue;
        var t3 = norm(n.innerText || '');
        if (!looksLikeContent(t3)) continue;
        if (dense(t3) > dense(best)) best = t3;
      }
    } catch (e) {}
    return best;
  } catch (e) { return ''; }
})()
''';
  }
}

/// 把隐藏 WebView 挂到 App 根部（1×1 像素、不参与交互、只有引擎激活后构建）。
///
/// 放在 `MaterialApp.builder` 里，确保它在所有路由之上长期存活。
class WebViewEngineHost extends StatelessWidget {
  const WebViewEngineHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        child,
        ValueListenableBuilder<bool>(
          valueListenable: WebViewEngine.instance.active,
          builder: (context, active, _) {
            if (!active) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              bottom: 0,
              width: 1,
              height: 1,
              child: IgnorePointer(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ExcludeSemantics(
                    child: WebViewWidget(
                      controller: WebViewEngine.instance.ensureController(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
