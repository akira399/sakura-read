// 在线书籍服务：详情 / 目录 / 正文的获取与解析。
//
// 数据流（对应内置「笔趣阁家族」源）：
//   搜索（HTTP，M2 已有）
//   → 详情页 HTTP 抓取 + ruleBookInfo 解析（OG meta 等）
//   → 目录：与详情页同页解析（ruleToc），或按 tocUrl 规则单独请求
//   → 正文：隐藏 WebView 渲染（令牌墙 / SPA / 加密接口全部由页面 JS 完成）
//     - 支持 `gatewayPath` 扩展：章节链接先改写到网关（如 /userverify/book/...），
//       由站点服务端 301 到真正的阅读页。
//
// 本文件不依赖 UI；WebView 引擎仅在「取正文」时被调用。
import 'dart:convert';

import '../data/models.dart';
import 'analyze_rule.dart';
import 'analyze_url.dart';
import 'http_client.dart';
import 'models.dart';
import 'webview_engine.dart';

/// 详情页解析结果。
class OnlineBookInfo {
  const OnlineBookInfo({
    this.name,
    this.author,
    this.intro,
    this.coverUrl,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.chapters = const [],
  });

  final String? name;
  final String? author;
  final String? intro;
  final String? coverUrl;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final List<ChapterRef> chapters;
}

/// 在线书籍服务。
class OnlineBookService {
  OnlineBookService({SourceHttpClient? client})
    : _client = client ?? SourceHttpClient();

  final SourceHttpClient _client;

  static const Duration _httpTimeout = Duration(seconds: 20);

  // ---------- 详情 / 目录 ----------

  /// 抓取详情页并解析（含目录；目录为空且有 tocUrl 规则时单独请求）。
  Future<OnlineBookInfo> fetchInfo(BookSource source, String bookUrl) async {
    final html = await _getHtml(source, bookUrl);
    final engine = AnalyzeRule(html, baseUrl: source.bookSourceUrl);
    final info = source.bookInfoRule;

    String? g(String? rule) {
      final r = rule?.trim();
      if (r == null || r.isEmpty) return null;
      final v = engine.getString(r);
      return (v == null || v.isEmpty) ? null : v;
    }

    var chapters = source.tocRule == null
        ? const <ChapterRef>[]
        : parseChapters(engine, source.tocRule!, bookUrl);

    if (chapters.isEmpty) {
      final tocUrlRule = g(info?.tocUrl);
      if (tocUrlRule != null && tocUrlRule != bookUrl) {
        final tocHtml = await _getHtml(source, tocUrlRule);
        final tocEngine = AnalyzeRule(tocHtml, baseUrl: source.bookSourceUrl);
        chapters = parseChapters(tocEngine, source.tocRule!, tocUrlRule);
      }
    }

    return OnlineBookInfo(
      name: g(info?.name),
      author: g(info?.author),
      intro: g(info?.intro),
      coverUrl: g(info?.coverUrl),
      kind: g(info?.kind),
      lastChapter: g(info?.lastChapter),
      updateTime: g(info?.updateTime),
      chapters: chapters,
    );
  }

  /// 解析目录：chapterList 产出「条目」，逐条取章节名 / 章节链接。
  ///
  /// 支持一个条目里取到多个章节名（如 chapterList 直接选 `<dl>` 的站点），
  /// 也支持一条一个章节（如 `dl.1@tag.dd` 的笔趣阁模板）；按链接去重。
  static List<ChapterRef> parseChapters(
    AnalyzeRule engine,
    TocRule rule,
    String baseUrl,
  ) {
    final listRule = rule.chapterList?.trim() ?? '';
    if (listRule.isEmpty) return const [];
    final nameRule = rule.chapterName?.trim() ?? '';
    final urlRule = (rule.chapterUrl?.trim().isNotEmpty ?? false)
        ? rule.chapterUrl!.trim()
        : 'tag.a@href';

    final out = <ChapterRef>[];
    final seen = <String>{};
    for (final item in engine.getRawList(listRule)) {
      final titles = nameRule.isEmpty
          ? const <String>[]
          : engine.getStrings(nameRule, ctx: item);
      final hrefs = engine.getStrings(urlRule, ctx: item);
      final n = titles.length < hrefs.length ? titles.length : hrefs.length;
      for (var i = 0; i < n; i++) {
        final title = titles[i].trim();
        final rawHref = hrefs[i].trim();
        if (title.isEmpty || rawHref.isEmpty) continue;
        // 跳过「展开全部章节」等 JS 伪链接
        final lower = rawHref.toLowerCase();
        if (lower.startsWith('javascript:') ||
            lower.startsWith('mailto:') ||
            lower.startsWith('tel:')) {
          continue;
        }
        final href = resolveUrl(rawHref, baseUrl);
        if (href.isEmpty) continue;
        if (!seen.add(href)) continue;
        out.add(ChapterRef(title: title, href: href));
      }
    }
    return out;
  }

  // ---------- 正文 ----------

  /// 取章节正文。
  ///
  /// 书源 `webView=true` 时走隐藏 WebView（可配 `gatewayPath` 网关重写）；
  /// 否则直接 HTTP 抓取 + ruleContent 解析（普通静态站点）。
  Future<String> fetchChapterText(BookSource source, String chapterUrl) async {
    if (_flag(source.extra['webView'])) {
      final target = webViewChapterUrl(source, chapterUrl);
      final text = await WebViewEngine.instance.fetchRenderedText(
        url: target,
        cssSelectors: contentSelectors(source),
      );
      return cleanChapterText(text);
    }

    final html = await _getHtml(source, chapterUrl);
    final engine = AnalyzeRule(html, baseUrl: source.bookSourceUrl);
    final raw = source.contentRule?.content ?? '';
    if (raw.trim().isEmpty) return '';
    // 正文通常是多段：取规则命中的**全部**结果并按段拼回（getString 只会取第一段）
    return cleanChapterText(engine.getStrings(raw).join('\n'));
  }

  /// 章节页在隐藏 WebView 中打开的地址（应用 gatewayPath 网关重写）。
  ///
  /// 例：`https://www.hkmtxt.cc/book/126/2079.html` + gatewayPath `/userverify`
  ///   → `https://www.hkmtxt.cc/userverify/book/126/2079.html`
  ///   （服务端 301 到真正的阅读页）
  static String webViewChapterUrl(BookSource source, String chapterUrl) {
    final gateway = source.extra['gatewayPath']?.toString().trim() ?? '';
    if (gateway.isEmpty) return chapterUrl;
    try {
      final uri = Uri.parse(chapterUrl);
      if (uri.path.startsWith('$gateway/') || uri.path == gateway) {
        return chapterUrl;
      }
      return uri.replace(path: '$gateway${uri.path}').toString();
    } catch (_) {
      return chapterUrl;
    }
  }

  /// 从 ruleContent.content 规则串提取 WebView 可用的 CSS 选择器列表。
  ///
  /// 兼容规则写法：`id.chaptercontent@text || class.content@text`
  ///   → `['#chaptercontent', '.content']`
  static List<String> contentSelectors(BookSource source) {
    final raw = source.contentRule?.content ?? '';
    final out = <String>[];
    for (final alt in raw.split('||')) {
      var seg = alt.trim();
      if (seg.isEmpty) continue;
      seg = seg.split('@').first.trim();
      if (seg.isEmpty || seg.startsWith('@')) continue;
      if (seg.startsWith('tag.')) {
        seg = seg.substring(4);
      } else if (seg.startsWith('class.')) {
        seg = '.${seg.substring(6)}';
      } else if (seg.startsWith('id.')) {
        seg = '#${seg.substring(3)}';
      }
      if (seg.isNotEmpty) out.add(seg);
    }
    return out;
  }

  // ---------- 正文清洗 ----------

  /// 去掉站点水印 / 导航等噪音行。
  static final List<String> _junkMarkers = [
    '请收藏本站',
    '手机版：',
    '手机版:',
    '『点此报错』',
    '『加入书签』',
    '点此报错',
    '加入书签',
    '最新章节',
  ];

  static final RegExp _junkExact = RegExp(
    r'^[　\s]*(上一章|下一章|返回目录|目录|加入书签|章节报错|举报|书页|书架)[\s　]*$',
  );

  static final RegExp _domainWatermark = RegExp(
    r'([a-z0-9-]+\.)*(bqg\d*|biquge|biqg|qbtr|hkmtxt|shw\d*|ddtxt\d*|qbxs\d*|22biqu)\.[a-z]+',
    caseSensitive: false,
  );

  static final RegExp _trailingCode = RegExp(r'\s*\d{1,3}w\d{1,3}-\d{1,6}\s*$');

  /// 清洗：去空行 / 水印行 / 行尾编号，保留段首全角缩进。
  static String cleanChapterText(String raw) {
    if (raw.isEmpty) return '';
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final out = <String>[];
    for (final line in text.split('\n')) {
      var l = line.trimRight();
      l = l.replaceFirst(RegExp(r'^[ \t\u00A0]+'), '');
      if (l.trim().isEmpty) continue;
      var skip = false;
      for (final marker in _junkMarkers) {
        if (l.contains(marker)) {
          skip = true;
          break;
        }
      }
      if (skip) continue;
      if (_junkExact.hasMatch(l)) continue;
      if (l.length < 60 && _domainWatermark.hasMatch(l)) continue;
      l = l.replaceAll(_trailingCode, '').trimRight();
      if (l.trim().isEmpty) continue;
      out.add(l);
    }
    return out.join('\n');
  }

  // ---------- 内部工具 ----------

  Future<String> _getHtml(BookSource source, String url) async {
    final resp = await _client.get(
      url,
      headers: headerMap(source),
      timeout: _httpTimeout,
      retries: 1,
    );
    if (!resp.ok) {
      throw SourceHttpException('HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  /// 书源 header（JSON 字符串）→ 请求头。
  static Map<String, String> headerMap(BookSource source) {
    final out = <String, String>{};
    final raw = source.header;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) => out[k.toString()] = v.toString());
        }
      } catch (_) {
        // 忽略非 JSON 的 header
      }
    }
    return out;
  }

  static bool _flag(dynamic v) =>
      v == true || v == 1 || v == 'true' || v == '1';
}
