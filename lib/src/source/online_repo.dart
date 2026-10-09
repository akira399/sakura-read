// 在线聚合：多源并发搜索（超时 / 错误隔离 / 限流 / 结果归一化）。
//
// 搜索数据流：
//   关键词 → 每源 searchUrl 模板渲染 → HTTP 请求（可 POST）
//          → AnalyzeRule(响应) + SearchRule 解析 → [SearchBook]
import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart' as xml;

import 'analyze_rule.dart';
import 'analyze_url.dart';
import 'http_client.dart';
import 'models.dart';
import 'source_store.dart';

/// 单源搜索的结果（或错误）。
class SourceSearchResult {
  SourceSearchResult({
    required this.source,
    this.books = const [],
    this.error,
    this.elapsedMs = 0,
  });

  final BookSource source;
  final List<SearchBook> books;
  final String? error;
  final int elapsedMs;

  bool get ok => error == null;
}

/// 归一化搜索文本（去空白 / 全角空格，小写）。
String normalizeSearchText(String? s) =>
    (s ?? '').trim().replaceAll(RegExp(r'[\s\u3000]+'), '').toLowerCase();

/// 多源搜索结果合并键：书名 + 作者（去空白、忽略常见装饰后缀）。
///
/// 同键的书视为「同一本书的不同来源」，在搜索页合并为一条，
/// 详情页可在各来源间切换。
String bookMergeKey(SearchBook b) {
  var name = normalizeSearchText(b.name);
  // 去掉结尾的装饰括号（如「（大结局）」「【完结】」），增强跨源匹配
  name = name.replaceAll(RegExp(r'[（(【\[][^（(【\[]*[）)】\]]$'), '');
  return '$name|${normalizeSearchText(b.author)}';
}

/// 搜索相关性分数（越高越相关）——用于搜索结果与换源候选排序。
///
/// 规则：书名完全一致 > 书名前缀（与关键词越接近越前）> 书名包含 >
/// 作者匹配 > 无关（保底 100 分，让完全不沾边的书沉底）。
int bookRelevanceScore(SearchBook b, String key) {
  final k = normalizeSearchText(key);
  if (k.isEmpty) return 0;
  final name = normalizeSearchText(b.name);
  final author = normalizeSearchText(b.author);
  var score = 0;
  if (name.isNotEmpty) {
    if (name == k) {
      score = 1000;
    } else if (name.startsWith(k)) {
      score = 820 - (name.length - k.length).clamp(0, 200).toInt();
    } else if (name.contains(k)) {
      final pos = name.indexOf(k);
      score = 650 - pos.clamp(0, 60).toInt();
    }
  }
  if (author.isNotEmpty) {
    if (author == k && score < 560) {
      score = 560;
    } else if (author.contains(k) && score < 480) {
      score = 480;
    }
  }
  if (score == 0) score = 100;
  return score;
}

/// 发现页的一个分类（书源 exploreUrl 的一行）。
class ExploreCategory {
  const ExploreCategory({required this.title, required this.url});

  /// 分类名（如「玄幻」「排行榜」）。
  final String title;

  /// 该分类的地址（已渲染模板变量）。
  final String url;
}

/// 单源「发现页」抓取结果。
class SourceExploreResult {
  const SourceExploreResult({
    required this.source,
    this.books = const [],
    this.error,
    this.elapsedMs = 0,
  });

  final BookSource source;
  final List<SearchBook> books;
  final String? error;
  final int elapsedMs;
}

/// 书源「发现页」：解析 exploreUrl 分类并抓取分类下的书单。
///
/// 用户反馈（社区最期待的功能之一）：希望有「发现页」直接逛书，
/// 而不是每次都先想好关键词去搜。这里实现 Legado 的 `exploreUrl` 规则：
///
/// ```
/// 玄幻::https://site/list/xuanhuan/{{page}}.html
/// 排行::https://site/rank/all/{{page}}.html   // 可用 {{page}} 占位
/// ```
///
/// 多分类之间用换行分隔；标题与地址用 `::` 分隔（也兼容 `,`）。
///
/// 多源搜索聚合器。
class OnlineRepo {
  OnlineRepo({
    required this.store,
    SourceHttpClient? client,
    this.concurrency = 8,
    this.perSourceTimeout = const Duration(seconds: 15),
  }) : _client = client ?? SourceHttpClient();

  final SourceStore store;
  final SourceHttpClient _client;

  /// 全局并发上限。
  final int concurrency;

  /// 单源超时。
  final Duration perSourceTimeout;

  final Map<String, RateGate> _gates = {};

  RateGate _gateFor(BookSource s) =>
      _gates.putIfAbsent(s.bookSourceUrl, () => RateGate(s.concurrentRate));

  /// 对所有启用的书源并发搜索。
  ///
  /// 每个源完成（成功或失败）时回调 [onSourceDone]；返回按书源顺序排列的完整结果。
  Future<List<SourceSearchResult>> searchAll(
    String key, {
    int page = 1,
    void Function(SourceSearchResult r)? onSourceDone,
  }) async {
    final sources = store.enabled;
    final results = <SourceSearchResult>[];
    if (sources.isEmpty) return results;

    var next = 0;
    final total = sources.length;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= total) return;
        final r = await searchOne(sources[i], key, page: page);
        results.add(r);
        onSourceDone?.call(r);
      }
    }

    final n = concurrency.clamp(1, total);
    await Future.wait(List.generate(n, (_) => worker()));

    final order = <String, int>{
      for (var i = 0; i < sources.length; i++) sources[i].bookSourceUrl: i,
    };
    results.sort(
      (a, b) => (order[a.source.bookSourceUrl] ?? 0).compareTo(
        order[b.source.bookSourceUrl] ?? 0,
      ),
    );
    return results;
  }

  /// 单源搜索（错误隔离在内部消化）。
  Future<SourceSearchResult> searchOne(
    BookSource source,
    String key, {
    int page = 1,
  }) async {
    final started = DateTime.now();
    int elapsed() => DateTime.now().difference(started).inMilliseconds;
    try {
      final rawUrl = source.searchUrl;
      if (rawUrl == null || rawUrl.trim().isEmpty) {
        throw const FormatException('未配置搜索地址（searchUrl）');
      }
      final req = buildRequest(rawUrl, source.bookSourceUrl, {
        'key': key,
        'page': page,
      });
      final headers = _mergeHeaders(source, req.options);
      final method = (req.options['method']?.toString() ?? 'GET').toUpperCase();
      final charset = req.options['charset']?.toString();

      await _gateFor(source).waitSlot();

      await _runPreRequests(source, headers, key, page);

      SourceResponse resp;
      if (method == 'POST') {
        final bodyTpl = req.options['body']?.toString() ?? '';
        final body = renderUrlTemplate(bodyTpl, {'key': key, 'page': page});
        resp = await _client.post(
          req.url,
          headers: headers,
          body: body,
          charset: charset,
          timeout: perSourceTimeout,
        );
      } else {
        resp = await _client.get(
          req.url,
          headers: headers,
          charset: charset,
          timeout: perSourceTimeout,
        );
      }
      if (!resp.ok) {
        throw SourceHttpException('HTTP ${resp.statusCode}');
      }
      final books = parseSearchPage(source, resp.body);
      return SourceSearchResult(
        source: source,
        books: books,
        elapsedMs: elapsed(),
      );
    } on SourceHttpException catch (e) {
      return SourceSearchResult(
        source: source,
        error: e.message,
        elapsedMs: elapsed(),
      );
    } on TimeoutException {
      return SourceSearchResult(
        source: source,
        error: '超时',
        elapsedMs: elapsed(),
      );
    } catch (e) {
      return SourceSearchResult(
        source: source,
        error: '解析失败：$e',
        elapsedMs: elapsed(),
      );
    }
  }

  /// 解析搜索结果页 → [SearchBook] 列表。
  List<SearchBook> parseSearchPage(BookSource source, String body) {
    final rule = source.searchRule;
    if (rule == null) return const [];
    final listRule = (rule.bookList ?? '').trim();
    if (listRule.isEmpty) return const [];

    final engine = AnalyzeRule(body, baseUrl: source.bookSourceUrl);
    final items = engine.getRawList(listRule);
    final books = <SearchBook>[];
    for (final item in items) {
      // 只处理可继续求值的上下文：DOM 元素 / XML 节点 / JSON 对象
      if (!(item is dom.Element || item is xml.XmlElement || item is Map)) {
        continue;
      }
      final name = _field(engine, rule.name, item);
      if (name == null || name.isEmpty) continue;
      final bookUrlRaw = _field(engine, rule.bookUrl, item);
      final coverRaw = _field(engine, rule.coverUrl, item);
      books.add(
        SearchBook(
          origin: source.bookSourceUrl,
          originName: source.bookSourceName,
          name: name,
          author: _field(engine, rule.author, item),
          kind: _field(engine, rule.kind, item),
          intro: _field(engine, rule.intro, item),
          coverUrl: coverRaw == null
              ? null
              : resolveUrl(coverRaw, source.bookSourceUrl),
          bookUrl: bookUrlRaw == null
              ? null
              : resolveUrl(bookUrlRaw, source.bookSourceUrl),
          latestChapterTitle: _field(engine, rule.lastChapter, item),
          time: _field(engine, rule.updateTime, item),
          wordCount: _field(engine, rule.wordCount, item),
        ),
      );
    }
    return books;
  }

  String? _field(AnalyzeRule engine, String? rule, Object item) {
    final r = rule?.trim();
    if (r == null || r.isEmpty) return null;
    final v = engine.getString(r, ctx: item);
    return (v == null || v.isEmpty) ? null : v;
  }

  // ==================== 发现页（exploreUrl / ruleExplore） ====================

  /// 解析书源的 exploreUrl → 分类列表。
  ///
  /// 实测（用户 1093 个真实书源）三种写法并存，必须都支持：
  ///
  /// 1. **行格式**（316 个）：
  ///    ```
  ///    玄幻::https://site/list/xuanhuan/{{page}}.html
  ///    排行::https://site/rank/all/{{page}}.html
  ///    ```
  /// 2. **JSON 数组**（318 个，Legado 主流写法）：
  ///    ```json
  ///    [{"title":"男生","url":""},{"title":"都市","url":"https://..."}]
  ///    ```
  /// 3. **JS 脚本**（168 个，`@js:` 开头）：需要 JS 引擎动态生成，
  ///    静态解析无法支持 —— 返回空列表，由 UI 明确提示（不静默失败）。
  ///
  /// 「标题::地址」也兼容 `标题,地址`；无标题时取 URL 末段。
  static List<ExploreCategory> parseExploreCategories(BookSource source) {
    final raw = source.exploreUrl?.trim();
    if (raw == null || raw.isEmpty) return const [];

    // JS 脚本：无法静态解析
    if (raw.startsWith('@js:') ||
        raw.startsWith('<js>') ||
        raw.startsWith('@JS:')) {
      return const [];
    }

    // JSON 数组格式
    if (raw.startsWith('[')) {
      return _parseJsonCategories(raw);
    }

    // 行格式
    return _parseLineCategories(raw);
  }

  /// 解析 JSON 数组格式的 exploreUrl。
  ///
  /// 每项形如 `{"title":"男生","url":"https://..."}`；
  /// `url` 为空的项是**分组标题**（Legado 用它做分栏），跳过不生成分类。
  static List<ExploreCategory> _parseJsonCategories(String raw) {
    List<dynamic> decoded;
    try {
      final d = jsonDecode(raw);
      if (d is! List) return const [];
      decoded = d;
    } catch (_) {
      // 非法 JSON（书源写坏 / 被截断）：静默返回空，由 UI 提示该源不可用
      return const [];
    }
    final out = <ExploreCategory>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final title = (item['title'] ?? '').toString().trim();
      final url = (item['url'] ?? '').toString().trim();
      // 分组标题（无地址）跳过：它没有可抓取的目标
      if (url.isEmpty) continue;
      if (title.isEmpty) continue;
      out.add(ExploreCategory(title: title, url: url));
    }
    return out;
  }

  /// 解析行格式（`标题::地址` / `标题,地址` / 纯地址）。
  static List<ExploreCategory> _parseLineCategories(String raw) {
    final out = <ExploreCategory>[];
    for (final line in raw.split('\n')) {
      final item = line.trim();
      if (item.isEmpty || item.startsWith('#')) continue;
      var title = '';
      var url = '';
      final sepIdx = item.indexOf('::');
      if (sepIdx >= 0) {
        title = item.substring(0, sepIdx).trim();
        url = item.substring(sepIdx + 2).trim();
      } else {
        final comma = item.indexOf(',');
        if (comma >= 0) {
          title = item.substring(0, comma).trim();
          url = item.substring(comma + 1).trim();
        } else {
          url = item;
        }
      }
      if (url.isEmpty) continue;
      if (title.isEmpty) {
        final seg = url.split('/').where((s) => s.isNotEmpty).toList();
        title = seg.isEmpty ? '分类' : seg.last;
      }
      out.add(ExploreCategory(title: title, url: url));
    }
    return out;
  }

  /// 该书源的 exploreUrl 是否为 JS 脚本（发现页无法支持）。
  static bool hasJsExplore(BookSource source) {
    final raw = source.exploreUrl?.trim() ?? '';
    return raw.startsWith('@js:') ||
        raw.startsWith('<js>') ||
        raw.startsWith('@JS:');
  }

  /// 抓取某个分类的一页书单（复用搜索页解析规则 [ExploreRule]）。
  Future<List<SearchBook>> exploreOne(
    BookSource source,
    ExploreCategory category, {
    int page = 1,
  }) async {
    final url = _renderExploreUrl(category.url, source.bookSourceUrl, page);
    final headers = _mergeHeaders(source, const {});
    await _gateFor(source).waitSlot();
    final resp = await _client.get(
      url,
      headers: headers,
      timeout: perSourceTimeout,
    );
    if (!resp.ok) throw SourceHttpException('HTTP ${resp.statusCode}');
    return parseExplorePage(source, resp.body);
  }

  /// 把分类地址渲染为可请求的绝对地址（补全相对路径 + `{{page}}` 占位）。
  static String _renderExploreUrl(String raw, String base, int page) {
    var s = raw.trim();
    // 分页占位（Legado 支持 {{page}} / {page}）
    s = s.replaceAll('{{page}}', '$page').replaceAll('{page}', '$page');
    return resolveUrl(s, base);
  }

  /// 解析发现页书单。
  ///
  /// 规则选择（实测踩坑）：不能简单用 `exploreRule ?? searchRule`——
  /// 大量书源的 `ruleExplore` 是**空对象 `{}`**（非 null），`??` 不会回退，
  /// 于是 bookList 取不到 → 解析出 0 本书（用户反馈「发现页什么都没有」）。
  /// 这里改为「exploreRule 有 bookList 才用它，否则回退 searchRule」。
  List<SearchBook> parseExplorePage(BookSource source, String body) {
    final rule = _pickExploreRule(source);
    // ExploreRule 与 SearchRule 字段同名，这里统一取字段
    final listRule = _exploreField(rule, 'bookList');
    if (listRule == null || listRule.trim().isEmpty) return const [];

    final engine = AnalyzeRule(body, baseUrl: source.bookSourceUrl);
    final items = engine.getRawList(listRule);
    final books = <SearchBook>[];
    for (final item in items) {
      if (!(item is dom.Element || item is xml.XmlElement || item is Map)) {
        continue;
      }
      final name = _field(engine, _exploreField(rule, 'name'), item);
      if (name == null || name.isEmpty) continue;
      final bookUrlRaw = _field(engine, _exploreField(rule, 'bookUrl'), item);
      final coverRaw = _field(engine, _exploreField(rule, 'coverUrl'), item);
      books.add(
        SearchBook(
          origin: source.bookSourceUrl,
          originName: source.bookSourceName,
          name: name,
          author: _field(engine, _exploreField(rule, 'author'), item),
          kind: _field(engine, _exploreField(rule, 'kind'), item),
          intro: _field(engine, _exploreField(rule, 'intro'), item),
          coverUrl: coverRaw == null
              ? null
              : resolveUrl(coverRaw, source.bookSourceUrl),
          bookUrl: bookUrlRaw == null
              ? null
              : resolveUrl(bookUrlRaw, source.bookSourceUrl),
          latestChapterTitle: _field(
            engine,
            _exploreField(rule, 'lastChapter'),
            item,
          ),
          time: _field(engine, _exploreField(rule, 'updateTime'), item),
          wordCount: _field(engine, _exploreField(rule, 'wordCount'), item),
        ),
      );
    }
    return books;
  }

  /// 选择用于发现页解析的规则。
  ///
  /// 实测（用户 1093 个真实书源）：
  /// - 511 个源有 `ruleExplore`，其中不少 bookList 直接用 `<js>` 或指向搜索规则；
  /// - 291 个源的 `ruleExplore` 是**空对象 `{}`**（非 null），
  ///   此时必须回退到 `ruleSearch`（Legado 里发现页与搜索页列表结构常一致）。
  Object? _pickExploreRule(BookSource source) {
    final er = source.exploreRule;
    if (er != null) {
      final list = er.bookList?.trim();
      // 有可用的 bookList 才认它（空对象 / 空字段一律回退）
      if (list != null && list.isNotEmpty) return er;
    }
    return source.searchRule;
  }

  /// 从 ExploreRule / SearchRule 取同名字段（两者字段名一致）。
  String? _exploreField(Object? rule, String key) {
    if (rule is ExploreRule) {
      return switch (key) {
        'bookList' => rule.bookList,
        'name' => rule.name,
        'author' => rule.author,
        'intro' => rule.intro,
        'kind' => rule.kind,
        'lastChapter' => rule.lastChapter,
        'updateTime' => rule.updateTime,
        'bookUrl' => rule.bookUrl,
        'coverUrl' => rule.coverUrl,
        'wordCount' => rule.wordCount,
        _ => null,
      };
    }
    if (rule is SearchRule) {
      return switch (key) {
        'bookList' => rule.bookList,
        'name' => rule.name,
        'author' => rule.author,
        'intro' => rule.intro,
        'kind' => rule.kind,
        'lastChapter' => rule.lastChapter,
        'updateTime' => rule.updateTime,
        'bookUrl' => rule.bookUrl,
        'coverUrl' => rule.coverUrl,
        'wordCount' => rule.wordCount,
        _ => null,
      };
    }
    return null;
  }

  /// 对**单个书源**抓取其某个分类的一页书单。
  Future<SourceExploreResult> exploreSource(
    BookSource source,
    ExploreCategory category, {
    int page = 1,
  }) async {
    final started = DateTime.now();
    try {
      final books = await exploreOne(source, category, page: page);
      return SourceExploreResult(
        source: source,
        books: books,
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (e) {
      return SourceExploreResult(
        source: source,
        error: '$e',
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    }
  }

  /// 在所有**支持发现页**的书源中，并发抓取「各自第一个分类」。
  ///
  /// 用途：发现页首屏「随便逛逛」——每个源出一个分类的最新书单，
  /// 用户不必先挑书源。分类由各源自己的 exploreUrl 决定。
  Future<List<SourceExploreResult>> exploreFirstOfEach({
    int page = 1,
    int maxSources = 12,
  }) async {
    final tasks = <(BookSource, ExploreCategory)>[];
    for (final s in store.enabled) {
      final cats = parseExploreCategories(s);
      if (cats.isEmpty) continue;
      tasks.add((s, cats.first));
      if (tasks.length >= maxSources) break;
    }
    if (tasks.isEmpty) return const [];
    return _runExploreTasks(tasks, page: page);
  }

  /// 并发执行一批「源 + 分类」抓取任务（结果顺序与任务顺序一致）。
  Future<List<SourceExploreResult>> _runExploreTasks(
    List<(BookSource, ExploreCategory)> tasks, {
    int page = 1,
  }) async {
    final results = List<SourceExploreResult?>.filled(tasks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tasks.length) return;
        final (source, category) = tasks[i];
        results[i] = await exploreSource(source, category, page: page);
      }
    }

    final n = concurrency.clamp(1, tasks.length);
    await Future.wait(List.generate(n, (_) => worker()));
    return [for (final r in results) ?r];
  }

  /// 所有支持发现页的书源（按名称排序），供发现页顶部选择。
  List<BookSource> exploreCapableSources() {
    final out = <BookSource>[];
    for (final s in store.enabled) {
      if (parseExploreCategories(s).isNotEmpty) out.add(s);
    }
    out.sort((a, b) => a.bookSourceName.compareTo(b.bookSourceName));
    return out;
  }

  /// 统计：支持发现页的源数 / 启用总数 / JS 脚本源数（UI 提示用）。
  ({int capable, int total, int jsOnly}) exploreStats() {
    var capable = 0;
    var jsOnly = 0;
    final enabled = store.enabled;
    for (final s in enabled) {
      if (parseExploreCategories(s).isNotEmpty) {
        capable++;
      } else if (hasJsExplore(s)) {
        jsOnly++;
      }
    }
    return (capable: capable, total: enabled.length, jsOnly: jsOnly);
  }

  /// 汇总所有启用书源的发现分类（同名合并，保留出现顺序）。
  ///
  /// 注意：不同书源的同名分类**地址不同**，所以这只用于「跨源联合搜索」
  /// 场景；发现页按书源浏览时请用 [parseExploreCategories]。
  List<ExploreCategory> allExploreCategories() {
    final seen = <String>{};
    final out = <ExploreCategory>[];
    for (final s in store.enabled) {
      for (final c in parseExploreCategories(s)) {
        if (seen.add(c.title)) out.add(c);
      }
    }
    return out;
  }

  /// 预热请求（樱读扩展字段 `preRequest`：字符串数组）。
  ///
  /// 用途：部分站点要求先访问一个“令牌页”（在响应里写 Cookie）后
  /// 才能调用搜索接口（如 /user/hm.html）。预热与主请求共享 Cookie 容器；
  /// 单个预热失败不阻断主流程。
  Future<void> _runPreRequests(
    BookSource source,
    Map<String, String> headers,
    String key,
    int page,
  ) async {
    final pre = source.extra['preRequest'];
    if (pre is! List) return;
    for (final t in pre) {
      final tmpl = t.toString().trim();
      if (tmpl.isEmpty) continue;
      try {
        final url = buildRequest(tmpl, source.bookSourceUrl, {
          'key': key,
          'page': page,
        }).url;
        await _client.get(
          url,
          headers: headers,
          timeout: perSourceTimeout,
          retries: 0,
        );
      } catch (_) {
        // 忽略预热失败（主请求仍会继续）
      }
    }
  }

  /// 合并请求头（源的 header JSON 字符串 + 请求选项里的 headers）。
  Map<String, String> _mergeHeaders(
    BookSource source,
    Map<String, dynamic> options,
  ) {
    final out = <String, String>{};
    final raw = source.header;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) => out[k.toString()] = v.toString());
        }
      } catch (_) {
        // 非 JSON 的 header 忽略（部分老源是空串）
      }
    }
    final opts = options['headers'];
    if (opts is Map) {
      opts.forEach((k, v) => out[k.toString()] = v.toString());
    }
    return out;
  }
}
