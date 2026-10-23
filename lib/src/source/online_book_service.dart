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
      if (tocUrlRule != null) {
        final tocUrl = resolveUrl(tocUrlRule, bookUrl);
        if (tocUrl.isNotEmpty && tocUrl != bookUrl) {
          final tocHtml = await _getHtml(source, tocUrl);
          final tocEngine = AnalyzeRule(tocHtml, baseUrl: source.bookSourceUrl);
          chapters = parseChapters(tocEngine, source.tocRule!, tocUrl);
          // 目录分页（`nextTocUrl`）：不少站点目录被拆成 index_1 / index_2 …
          chapters = await _followTocPages(source, tocEngine, tocUrl, chapters);
        }
      }
    } else {
      chapters = await _followTocPages(source, engine, bookUrl, chapters);
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

  /// 沿 `nextTocUrl` 继续翻目录页，把后续页的章节追加进来。
  ///
  /// 站点的分页目录（`/index_2.html`、`?page=2`）在 Legado 里靠
  /// `ruleToc.nextTocUrl` 表达；不支持就等于只能读到第一页目录。
  Future<List<ChapterRef>> _followTocPages(
    BookSource source,
    AnalyzeRule firstEngine,
    String firstUrl,
    List<ChapterRef> first,
  ) async {
    final rule = source.tocRule?.nextTocUrl?.trim() ?? '';
    if (rule.isEmpty) return first;
    final out = <ChapterRef>[...first];
    final seen = <String>{
      for (final c in first)
        if (c.href != null && c.href!.isNotEmpty) c.href!,
    };
    var engine = firstEngine;
    var url = firstUrl;
    final visited = <String>{firstUrl};
    for (var page = 0; page < 10; page++) {
      final rawNext = engine.getString(rule);
      if (rawNext == null || rawNext.isEmpty) break;
      final next = resolveUrl(rawNext, url);
      if (next.isEmpty || !visited.add(next)) break;
      String html;
      try {
        html = await _getHtml(source, next);
      } catch (_) {
        break;
      }
      final e = AnalyzeRule(html, baseUrl: source.bookSourceUrl);
      final more = parseChapters(e, source.tocRule!, next);
      if (more.isEmpty) break;
      var added = 0;
      for (final c in more) {
        final h = c.href;
        if (h == null || h.isEmpty) continue;
        if (seen.add(h)) {
          out.add(c);
          added++;
        }
      }
      if (added == 0) break;
      engine = e;
      url = next;
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
    var engine = AnalyzeRule(html, baseUrl: source.bookSourceUrl);
    final raw = source.contentRule?.content ?? '';
    if (raw.trim().isEmpty) return '';
    // 正文通常是多段：取规则命中的**全部**结果并按段拼回（getString 只会取第一段）
    final buf = <String>[engine.getStrings(raw).join('\n')];

    // 分页正文（`nextContentUrl`）：一章被站点拆成多页时必须继续抓。
    // 典型写法 `text.下一页@href` / `#linkNext@href` / `a#next:contains(下一页)@href`。
    final nextRule = source.contentRule?.nextContentUrl?.trim() ?? '';
    if (nextRule.isNotEmpty) {
      var url = chapterUrl;
      final visited = <String>{chapterUrl};
      for (var page = 0; page < 5; page++) {
        final rawNext = engine.getString(nextRule);
        if (rawNext == null || rawNext.isEmpty) break;
        final next = resolveUrl(rawNext, url);
        if (next.isEmpty || !visited.add(next) || next == url) break;
        String nextHtml;
        try {
          nextHtml = await _getHtml(source, next);
        } catch (_) {
          break;
        }
        final e = AnalyzeRule(nextHtml, baseUrl: source.bookSourceUrl);
        final part = e.getStrings(raw).join('\n');
        if (part.trim().isEmpty) break;
        buf.add(part);
        engine = e;
        url = next;
      }
    }
    return cleanChapterText(buf.join('\n'));
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
    // 站点转载声明（常见于抓取失败的整页文本里）
    '转载作品',
    '网友上传',
    '请记住本书',
    '首发域名',
  ];

  static final RegExp _junkExact = RegExp(
    r'^[　\s]*(上一章|下一章|返回目录|目录|加入书签|章节报错|举报|书页|书架)[\s　]*$',
  );

  /// 「导航短行」特征：≤12 字、且**全是**汉字/字母/数字（无标点、无空格）——
  /// 站点菜单项都是干净短语，而正文句子几乎必然带标点。
  static final RegExp _navLikeLine = RegExp(
    r'^[\u4e00-\u9fa5A-Za-z0-9]{1,12}$',
  );

  /// 判断是否是站点导航残留（短行 + 命中栏目词）。
  static bool _isNavResidue(String line) =>
      _navLikeLine.hasMatch(line) && _navWords.any(line.contains);

  /// 站点栏目词（命中即视为导航残留，仅对「导航短行」生效）。
  static const List<String> _navWords = [
    '首页',
    '书架',
    '排行榜',
    '排行',
    '分类',
    '玄幻',
    '武侠',
    '都市',
    '历史',
    '网游',
    '科幻',
    '女生',
    '完本',
    '全部小说',
    '最近更新',
    '登录',
    '注册',
    '护眼',
    '关灯',
    '大中小',
    '手机版',
    '字体',
  ];

  static final RegExp _domainWatermark = RegExp(
    r'([a-z0-9-]+\.)*(bqg\d*|biquge|biqg|qbtr|hkmtxt|shw\d*|ddtxt\d*|qbxs\d*|22biqu)\.[a-z]+',
    caseSensitive: false,
  );

  static final RegExp _trailingCode = RegExp(r'\s*\d{1,3}w\d{1,3}-\d{1,6}\s*$');

  /// 清洗：去空行 / 水印行 / 导航行 / 行尾编号，保留段首全角缩进。
  static String cleanChapterText(String raw) {
    if (raw.isEmpty) return '';
    // 先把正文 HTML 变成纯文本：`@html` 取到的内容里全是 <br>/<p>/&nbsp;，
    // 不还原就会把整章压成**一行**（末尾再带一句站点水印），
    // 而下面按行去广告的过滤器一旦命中水印就会把整章丢掉 → 正文空白。
    var text = raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final out = <String>[];
    for (final line in text.split('\n')) {
      var l = line.trimRight();
      l = l.replaceFirst(RegExp(r'^[ \t\u00A0]+'), '');
      if (l.trim().isEmpty) continue;
      var skip = false;
      // 只在**短行**上按水印丢弃：长行是真正的正文段落，
      // 因为命中一句水印就整段删掉是致命的（见上面的单行章节问题）。
      if (l.length < 200) {
        for (final marker in _junkMarkers) {
          if (l.contains(marker)) {
            skip = true;
            break;
          }
        }
      }
      if (skip) continue;
      if (_junkExact.hasMatch(l)) continue;
      // 站点阅读器的工具条（“字体：大 中 小 护眼 关灯”）——整行特征明显
      if (l.contains('护眼') && l.contains('关灯')) continue;
      // 导航短行兜底：短、无标点、且命中栏目词 → 视为菜单残留
      if (_isNavResidue(l.trim())) continue;
      if (l.length < 60 && _domainWatermark.hasMatch(l)) continue;
      // 行内水印（长行末尾常带）：就地删掉，保留正文
      l = l.replaceAll(_inlineWatermark, '');
      l = l.replaceAll(_trailingCode, '').trimRight();
      if (l.trim().isEmpty) continue;
      out.add(l);
    }
    return out.join('\n');
  }

  /// 行内站点水印（「请记住本书首发域名：xxx」「鬼吹灯手机版阅读网址：xxx」等）。
  static final RegExp _inlineWatermark = RegExp(
    r'[（(]?请记住本书[^。\n]{0,60}[。]?|[（(]?首发域名[:：]?\s*\S+|'
    r'\S{0,12}手机版阅读网址[:：]?\s*\S*',
  );

  // ---------- 内部工具 ----------

  Future<String> _getHtml(BookSource source, String url) async {
    final headers = headerMap(source);
    // 不少站点对「没有来路的请求」直接 403；补上站内 Referer
    headers.putIfAbsent('Referer', () => source.bookSourceUrl);
    final resp = await _client.get(
      url,
      headers: headers,
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
