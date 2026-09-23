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
