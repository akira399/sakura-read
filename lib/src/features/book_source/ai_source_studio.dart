import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart' as xml;

import '../../data/ai_service.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../source/analyze_rule.dart';
import '../../source/analyze_url.dart';
import '../../source/http_client.dart';
import '../../source/models.dart';
import '../../source/online_book_service.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';

/// 书源四阶段调试环节。
enum SourceDebugStage { search, info, toc, content }

/// 单个调试阶段的状态。
enum DebugStageStatus { pending, running, success, warning, error }

/// 单个调试阶段的详细跟踪数据。
class SourceDebugStageResult {
  const SourceDebugStageResult({
    required this.stage,
    required this.status,
    this.url,
    this.httpStatus,
    this.elapsedMs = 0,
    this.summary = '',
    this.matchedRules = const {},
    this.extractedFields = const {},
    this.jsLogs = const [],
    this.rawSnippet = '',
    this.error,
  });

  final SourceDebugStage stage;
  final DebugStageStatus status;
  final String? url;
  final int? httpStatus;
  final int elapsedMs;
  final String summary;
  final Map<String, String> matchedRules;
  final Map<String, String> extractedFields;
  final List<String> jsLogs;
  final String rawSnippet;
  final String? error;

  bool get ok => status == DebugStageStatus.success;

  String get stageTitle => switch (stage) {
    SourceDebugStage.search => '1. 搜索（Search）',
    SourceDebugStage.info => '2. 详情（BookInfo）',
    SourceDebugStage.toc => '3. 目录（TOC）',
    SourceDebugStage.content => '4. 正文（Content）',
  };
}

/// 完整的四阶段调试报告。
class SourceDebugTrace {
  const SourceDebugTrace({
    required this.source,
    required this.keyword,
    required this.stages,
    this.sampleBook,
    this.sampleChapters = const [],
    this.sampleContent = '',
  });

  final BookSource source;
  final String keyword;
  final List<SourceDebugStageResult> stages;
  final SearchBook? sampleBook;
  final List<ChapterRef> sampleChapters;
  final String sampleContent;

  bool get allPassed =>
      stages.length == 4 &&
      stages.every((s) => s.status == DebugStageStatus.success);

  int get passedCount =>
      stages.where((s) => s.status == DebugStageStatus.success).length;

  String get errorSummary {
    final failed = stages.where((s) => s.status == DebugStageStatus.error);
    if (failed.isEmpty) return '';
    return failed
        .map((s) => '${s.stageTitle}: ${s.error ?? s.summary}')
        .join('\n');
  }
}

/// 四阶段实时书源调试器（Search → Info → TOC → Content）。
class SourceDebugRunner {
  SourceDebugRunner({
    SourceHttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? SourceHttpClient(),
       _ownsClient = client == null;

  final SourceHttpClient _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void dispose() {
    _cancelled = true;
    if (_ownsClient) _client.close();
  }

  /// 对指定书源执行完整的 4 阶段实时追踪，每阶段完成都会通过 [onStage] 回调。
  Future<SourceDebugTrace> run(
    BookSource source,
    String keyword, {
    void Function(SourceDebugStageResult stage)? onStage,
  }) async {
    _cancelled = false;
    final stages = <SourceDebugStageResult>[];

    void emit(SourceDebugStageResult r) {
      final idx = stages.indexWhere((s) => s.stage == r.stage);
      if (idx >= 0) {
        stages[idx] = r;
      } else {
        stages.add(r);
      }
      onStage?.call(r);
    }

    // ---------- Stage 1: Search ----------
    emit(
      const SourceDebugStageResult(
        stage: SourceDebugStage.search,
        status: DebugStageStatus.running,
        summary: '正在构建搜索请求…',
      ),
    );
    final searchSw = Stopwatch()..start();
    final searchLogs = <String>[];
    SearchBook? firstBook;
    try {
      final rawUrl = source.searchUrl?.trim() ?? '';
      if (rawUrl.isEmpty) {
        throw const FormatException('未配置 searchUrl');
      }
      final req = await buildRequestAsync(
        rawUrl,
        source.bookSourceUrl,
        {'key': keyword, 'page': 1},
        sourceKey: source.bookSourceUrl,
        cookieBridge: _client,
        httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
        jsLogs: searchLogs,
      );
      final headers = _mergeHeaders(source, req.options);
      final method = (req.options['method']?.toString() ?? 'GET').toUpperCase();
      final charset = req.options['charset']?.toString();

      await _runPreRequests(source, headers, keyword);

      SourceResponse resp;
      if (method == 'POST') {
        final bodyTpl = req.options['body']?.toString() ?? '';
        final body = await renderUrlTemplateAsync(
          bodyTpl,
          {'key': keyword, 'page': 1},
          baseUrl: source.bookSourceUrl,
          sourceKey: source.bookSourceUrl,
          cookieBridge: _client,
          httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
          jsLogs: searchLogs,
        );
        resp = await _client.post(
          req.url,
          headers: headers,
          body: body,
          charset: charset,
          timeout: timeout,
          retries: 0,
        );
      } else {
        resp = await _client.get(
          req.url,
          headers: headers,
          charset: charset,
          timeout: timeout,
          retries: 0,
        );
      }
      searchSw.stop();
      if (!resp.ok) {
        throw SourceHttpException('HTTP ${resp.statusCode}');
      }

      final repo = OnlineRepo(
        store: SourceStore(initial: [source]),
        client: _client,
        perSourceTimeout: timeout,
      );
      final books = await repo.parseSearchPageAsync(
        source,
        resp.body,
        key: keyword,
        jsLogs: searchLogs,
      );
      firstBook = books.isNotEmpty ? books.first : null;
      final rule = source.searchRule;
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.search,
          status: books.isNotEmpty
              ? DebugStageStatus.success
              : DebugStageStatus.warning,
          url: resp.finalUrl,
          httpStatus: resp.statusCode,
          elapsedMs: searchSw.elapsedMilliseconds,
          summary: books.isNotEmpty
              ? '命中 ${books.length} 本书，首本《${firstBook!.name}》'
              : 'HTTP ${resp.statusCode}，但未匹配到任何书籍（检查 bookList / name 规则）',
          matchedRules: {
            'searchUrl': rawUrl,
            if (rule?.bookList != null) 'bookList': rule!.bookList!,
            if (rule?.name != null) 'name': rule!.name!,
            if (rule?.bookUrl != null) 'bookUrl': rule!.bookUrl!,
          },
          extractedFields: firstBook == null
              ? const {'命中数': '0'}
              : {
                  '命中数': '${books.length}',
                  '书名': firstBook.name ?? '',
                  if ((firstBook.author ?? '').isNotEmpty)
                    '作者': firstBook.author!,
                  if ((firstBook.bookUrl ?? '').isNotEmpty)
                    '详情页': firstBook.bookUrl!,
                  if ((firstBook.coverUrl ?? '').isNotEmpty)
                    '封面': firstBook.coverUrl!,
                },
          jsLogs: List.unmodifiable(searchLogs),
          rawSnippet: _clipSnippet(resp.body),
        ),
      );
    } catch (e) {
      searchSw.stop();
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.search,
          status: DebugStageStatus.error,
          elapsedMs: searchSw.elapsedMilliseconds,
          summary: '搜索阶段失败',
          jsLogs: List.unmodifiable(searchLogs),
          error: '$e',
        ),
      );
      return SourceDebugTrace(source: source, keyword: keyword, stages: stages);
    }

    if (_cancelled || firstBook == null || (firstBook.bookUrl ?? '').isEmpty) {
      return SourceDebugTrace(
        source: source,
        keyword: keyword,
        stages: stages,
        sampleBook: firstBook,
      );
    }

    // ---------- Stage 2: BookInfo ----------
    final bookUrl = firstBook.bookUrl!;
    emit(
      SourceDebugStageResult(
        stage: SourceDebugStage.info,
        status: DebugStageStatus.running,
        url: bookUrl,
        summary: '正在抓取详情页…',
      ),
    );
    final infoSw = Stopwatch()..start();
    final infoLogs = <String>[];
    String infoHtml = '';
    AnalyzeRule? infoEngine;
    String? tocUrlResolved;
    try {
      final headers = OnlineBookService.headerMap(source)
        ..putIfAbsent('Referer', () => source.bookSourceUrl);
      final resp = await _client.get(
        bookUrl,
        headers: headers,
        timeout: timeout,
        retries: 1,
      );
      infoSw.stop();
      if (!resp.ok) throw SourceHttpException('HTTP ${resp.statusCode}');
      infoHtml = resp.body;
      final httpCb = _client.asJsAsyncHttpCallback(timeout: timeout);
      infoEngine = AnalyzeRule(
        infoHtml,
        baseUrl: bookUrl,
        sourceKey: source.bookSourceUrl,
        cookieBridge: _client,
        httpAsync: httpCb,
        jsLogs: infoLogs,
      );
      final infoRule = source.bookInfoRule;
      if ((infoRule?.init ?? '').trim().isNotEmpty) {
        final initOut = await infoEngine.getStringAsync(infoRule!.init!);
        if (initOut != null && initOut.isNotEmpty) {
          infoHtml = initOut;
          infoEngine = AnalyzeRule(
            infoHtml,
            baseUrl: bookUrl,
            sourceKey: source.bookSourceUrl,
            cookieBridge: _client,
            httpAsync: httpCb,
            jsLogs: infoLogs,
          );
        }
      }
      final name = infoRule?.name == null
          ? null
          : await infoEngine.getStringAsync(infoRule!.name!);
      final author = infoRule?.author == null
          ? null
          : await infoEngine.getStringAsync(infoRule!.author!);
      final intro = infoRule?.intro == null
          ? null
          : await infoEngine.getStringAsync(infoRule!.intro!);
      final cover = infoRule?.coverUrl == null
          ? null
          : await infoEngine.getStringAsync(infoRule!.coverUrl!);
      final rawTocUrl = infoRule?.tocUrl == null
          ? null
          : await infoEngine.getStringAsync(infoRule!.tocUrl!);
      if (rawTocUrl != null && rawTocUrl.trim().isNotEmpty) {
        tocUrlResolved = resolveUrl(rawTocUrl, bookUrl);
      }

      final extracted = <String, String>{
        if ((name ?? '').isNotEmpty) '书名': name!,
        if ((author ?? '').isNotEmpty) '作者': author!,
        if ((intro ?? '').isNotEmpty) '简介': _clipSnippet(intro!, max: 140),
        if ((cover ?? '').isNotEmpty) '封面': resolveUrl(cover!, bookUrl),
        if ((tocUrlResolved ?? '').isNotEmpty) '目录地址': tocUrlResolved!,
      };
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.info,
          status: extracted.isNotEmpty
              ? DebugStageStatus.success
              : DebugStageStatus.warning,
          url: resp.finalUrl,
          httpStatus: resp.statusCode,
          elapsedMs: infoSw.elapsedMilliseconds,
          summary: extracted.isNotEmpty
              ? '成功提取 ${extracted.length} 个详情字段'
              : '详情页返回 ${resp.statusCode}，但未命中详情字段',
          matchedRules: {
            if (infoRule?.name != null) 'name': infoRule!.name!,
            if (infoRule?.author != null) 'author': infoRule!.author!,
            if (infoRule?.intro != null) 'intro': infoRule!.intro!,
            if (infoRule?.tocUrl != null) 'tocUrl': infoRule!.tocUrl!,
          },
          extractedFields: extracted,
          jsLogs: List.unmodifiable(infoLogs),
          rawSnippet: _clipSnippet(infoHtml),
        ),
      );
    } catch (e) {
      infoSw.stop();
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.info,
          status: DebugStageStatus.error,
          url: bookUrl,
          elapsedMs: infoSw.elapsedMilliseconds,
          summary: '详情页阶段失败',
          jsLogs: List.unmodifiable(infoLogs),
          error: '$e',
        ),
      );
      return SourceDebugTrace(
        source: source,
        keyword: keyword,
        stages: stages,
        sampleBook: firstBook,
      );
    }

    if (_cancelled) {
      return SourceDebugTrace(
        source: source,
        keyword: keyword,
        stages: stages,
        sampleBook: firstBook,
      );
    }

    // ---------- Stage 3: TOC ----------
    final targetTocUrl = tocUrlResolved ?? bookUrl;
    emit(
      SourceDebugStageResult(
        stage: SourceDebugStage.toc,
        status: DebugStageStatus.running,
        url: targetTocUrl,
        summary: '正在解析目录…',
      ),
    );
    final tocSw = Stopwatch()..start();
    final tocLogs = <String>[];
    var chapters = const <ChapterRef>[];
    try {
      final tocRule = source.tocRule;
      if (tocRule == null || (tocRule.chapterList ?? '').trim().isEmpty) {
        throw const FormatException('未配置 ruleToc.chapterList');
      }
      int? tocStatus;
      String tocHtml = infoHtml;
      var tocEngine = AnalyzeRule(
        infoHtml,
        baseUrl: bookUrl,
        sourceKey: source.bookSourceUrl,
        cookieBridge: _client,
        httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
        jsLogs: tocLogs,
      );
      if (targetTocUrl != bookUrl) {
        final headers = OnlineBookService.headerMap(source)
          ..putIfAbsent('Referer', () => bookUrl);
        final resp = await _client.get(
          targetTocUrl,
          headers: headers,
          timeout: timeout,
          retries: 1,
        );
        tocStatus = resp.statusCode;
        if (!resp.ok) throw SourceHttpException('HTTP ${resp.statusCode}');
        tocHtml = resp.body;
        tocEngine = AnalyzeRule(
          tocHtml,
          baseUrl: targetTocUrl,
          sourceKey: source.bookSourceUrl,
          cookieBridge: _client,
          httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
          jsLogs: tocLogs,
        );
      } else {
        tocStatus = 200;
      }

      chapters = await OnlineBookService.parseChaptersAsync(
        tocEngine,
        tocRule,
        targetTocUrl,
      );
      tocSw.stop();
      final preview = <String, String>{
        '章节总数': '${chapters.length}',
        if (chapters.isNotEmpty)
          '第 1 章': '${chapters.first.title} (${chapters.first.href ?? ''})',
        if (chapters.length > 1) '第 2 章': chapters[1].title,
        if (chapters.length > 2) '最新章': chapters.last.title,
      };
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.toc,
          status: chapters.isNotEmpty
              ? DebugStageStatus.success
              : DebugStageStatus.warning,
          url: targetTocUrl,
          httpStatus: tocStatus,
          elapsedMs: tocSw.elapsedMilliseconds,
          summary: chapters.isNotEmpty
              ? '解析出 ${chapters.length} 章，首章「${chapters.first.title}」'
              : '未提取到任何章节（检查 chapterList / chapterName / chapterUrl）',
          matchedRules: {
            'chapterList': tocRule.chapterList!,
            if (tocRule.chapterName != null)
              'chapterName': tocRule.chapterName!,
            if (tocRule.chapterUrl != null) 'chapterUrl': tocRule.chapterUrl!,
          },
          extractedFields: preview,
          jsLogs: List.unmodifiable(tocLogs),
          rawSnippet: _clipSnippet(tocHtml),
        ),
      );
    } catch (e) {
      tocSw.stop();
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.toc,
          status: DebugStageStatus.error,
          url: targetTocUrl,
          elapsedMs: tocSw.elapsedMilliseconds,
          summary: '目录解析失败',
          jsLogs: List.unmodifiable(tocLogs),
          error: '$e',
        ),
      );
      return SourceDebugTrace(
        source: source,
        keyword: keyword,
        stages: stages,
        sampleBook: firstBook,
      );
    }

    if (_cancelled || chapters.isEmpty || (chapters.first.href ?? '').isEmpty) {
      return SourceDebugTrace(
        source: source,
        keyword: keyword,
        stages: stages,
        sampleBook: firstBook,
        sampleChapters: chapters,
      );
    }

    // ---------- Stage 4: Content ----------
    final chapterUrl = chapters.first.href!;
    emit(
      SourceDebugStageResult(
        stage: SourceDebugStage.content,
        status: DebugStageStatus.running,
        url: chapterUrl,
        summary: '正在抓取首章正文…',
      ),
    );
    final contentSw = Stopwatch()..start();
    final contentLogs = <String>[];
    var contentText = '';
    try {
      final contentRule = source.contentRule;
      final ruleStr = contentRule?.content?.trim() ?? '';
      if (ruleStr.isEmpty) {
        throw const FormatException('未配置 ruleContent.content');
      }
      final headers = OnlineBookService.headerMap(source)
        ..putIfAbsent('Referer', () => targetTocUrl);
      final resp = await _client.get(
        chapterUrl,
        headers: headers,
        timeout: timeout,
        retries: 1,
      );
      if (!resp.ok) throw SourceHttpException('HTTP ${resp.statusCode}');
      final engine = AnalyzeRule(
        resp.body,
        baseUrl: chapterUrl,
        sourceKey: source.bookSourceUrl,
        cookieBridge: _client,
        httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
        jsLogs: contentLogs,
      );
      final rawParts = await engine.getStringsAsync(ruleStr);
      contentText = OnlineBookService.cleanChapterText(rawParts.join('\n'));
      contentSw.stop();
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.content,
          status: contentText.isNotEmpty
              ? DebugStageStatus.success
              : DebugStageStatus.warning,
          url: resp.finalUrl,
          httpStatus: resp.statusCode,
          elapsedMs: contentSw.elapsedMilliseconds,
          summary: contentText.isNotEmpty
              ? '成功抓取正文（${contentText.length} 字）'
              : '正文提取为空（检查 ruleContent.content 或站点是否需要 WebView）',
          matchedRules: {
            'content': ruleStr,
            if ((contentRule?.nextContentUrl ?? '').isNotEmpty)
              'nextContentUrl': contentRule!.nextContentUrl!,
          },
          extractedFields: {
            '章节标题': chapters.first.title,
            '正文字数': '${contentText.length}',
            '正文预览': _clipSnippet(contentText, max: 240),
          },
          jsLogs: List.unmodifiable(contentLogs),
          rawSnippet: _clipSnippet(resp.body),
        ),
      );
    } catch (e) {
      contentSw.stop();
      emit(
        SourceDebugStageResult(
          stage: SourceDebugStage.content,
          status: DebugStageStatus.error,
          url: chapterUrl,
          elapsedMs: contentSw.elapsedMilliseconds,
          summary: '正文抓取失败',
          jsLogs: List.unmodifiable(contentLogs),
          error: '$e',
        ),
      );
    }

    return SourceDebugTrace(
      source: source,
      keyword: keyword,
      stages: stages,
      sampleBook: firstBook,
      sampleChapters: chapters,
      sampleContent: contentText,
    );
  }

  Future<void> _runPreRequests(
    BookSource source,
    Map<String, String> headers,
    String keyword,
  ) async {
    final pre = source.extra['preRequest'];
    if (pre is! List) return;
    for (final item in pre) {
      final tmpl = item.toString().trim();
      if (tmpl.isEmpty) continue;
      try {
        final req = await buildRequestAsync(
          tmpl,
          source.bookSourceUrl,
          {'key': keyword, 'page': 1},
          sourceKey: source.bookSourceUrl,
          cookieBridge: _client,
          httpAsync: _client.asJsAsyncHttpCallback(timeout: timeout),
        );
        await _client.get(
          req.url,
          headers: headers,
          timeout: timeout,
          retries: 0,
        );
      } catch (_) {}
    }
  }

  static Map<String, String> _mergeHeaders(
    BookSource source,
    Map<String, dynamic> options,
  ) {
    final out = OnlineBookService.headerMap(source);
    final opts = options['headers'];
    if (opts is Map) {
      opts.forEach((k, v) => out[k.toString()] = v.toString());
    }
    return out;
  }

  static String _clipSnippet(String raw, {int max = 500}) {
    final clean = raw.trim();
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max)}…';
  }
}

/// AI 写源 / 修复工坊返回结果。
class AiSourceStudioResult {
  const AiSourceStudioResult({
    required this.source,
    required this.formattedJson,
    required this.rawLlmOutput,
    required this.htmlSnippet,
    this.validationTrace,
  });

  final BookSource source;
  final String formattedJson;
  final String rawLlmOutput;
  final String htmlSnippet;
  final SourceDebugTrace? validationTrace;

  bool get validated => validationTrace?.allPassed ?? false;
}

/// AI 智能书源工坊：抓取网页 HTML 片段 → 构造严格 Legado 3.0 JSON Prompt →
/// 调用用户已配置大模型 (`AiService`) → 解析并自动执行四阶段实测验证。
class AiSourceStudio {
  AiSourceStudio({SourceHttpClient? httpClient, AiService? aiService})
    : _http = httpClient ?? SourceHttpClient(),
      _ownsHttp = httpClient == null,
      _ai = aiService ?? AiService(),
      _ownsAi = aiService == null;

  final SourceHttpClient _http;
  final bool _ownsHttp;
  final AiService _ai;
  final bool _ownsAi;

  void dispose() {
    if (_ownsHttp) _http.close();
    if (_ownsAi) _ai.dispose();
  }

  /// 抓取目标站点并裁剪掉脚本/样式噪音，保留关键 DOM 结构片段供模型分析。
  Future<String> fetchCleanHtmlSnippet(
    String url, {
    int maxChars = 6000,
  }) async {
    final resp = await _http.get(
      url,
      timeout: const Duration(seconds: 15),
      retries: 1,
    );
    if (!resp.ok) {
      throw SourceHttpException('无法访问站点（HTTP ${resp.statusCode}）');
    }
    return sanitizeHtmlSnippet(resp.body, maxChars: maxChars);
  }

  /// 清理 HTML 片段（去 `<script>` / `<style>` / `<svg>` / 注释与多余空白）。
  static String sanitizeHtmlSnippet(String html, {int maxChars = 6000}) {
    var s = html
        .replaceAll(
          RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<svg\b[^>]*>[\s\S]*?</svg>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (s.length > maxChars) {
      s = '${s.substring(0, maxChars)}\n<!-- truncated -->';
    }
    return s;
  }

  /// 构造严格的 Legado 3.0 书源生成 / 修复提示词。
  static String buildGenerationPrompt({
    required String siteUrl,
    required String htmlSnippet,
    String? searchUrlHint,
    String? keywordHint,
    BookSource? existingToRepair,
    String? repairError,
  }) {
    final modeTitle = existingToRepair == null
        ? '根据下方小说网站 URL 与 HTML 结构，生成一个合法且可直接运行的阅读 3.0（Legado）书源 JSON 对象。'
        : '下方是一个失效的阅读 3.0（Legado）书源及其调试报错与最新页面 HTML，请精准修复它的规则并输出完整 JSON 对象。';

    final buf = StringBuffer()
      ..writeln('你是精通「阅读 3.0（Legado）」书源规则架构的工程师。')
      ..writeln(modeTitle)
      ..writeln()
      ..writeln('【输出硬性要求】')
      ..writeln('1. 只输出一个合法的 JSON 对象（不要输出解释文字，不要输出注释）。')
      ..writeln(
        '2. 必须包含字段：bookSourceUrl, bookSourceName, bookSourceGroup, enabled, searchUrl, '
        'ruleSearch(bookList, name, author, bookUrl, coverUrl, intro, lastChapter), '
        'ruleBookInfo(name, author, intro, coverUrl, tocUrl), '
        'ruleToc(chapterList, chapterName, chapterUrl, nextTocUrl), '
        'ruleContent(content, nextContentUrl, replaceRegex)。',
      )
      ..writeln(
        '3. 规则语法支持 Legado CSS（如 `class.item@tag.a@text` / `.book a@href`）、'
        r'JSONPath（`$.data[*]`）、XPath（`@xpath://...`）、正则替换（`##regex##rep`）及 JS（`@js:` / `<js>...</js>` / `{{...}}`）。',
      )
      ..writeln(
        '4. `searchUrl` 必须使用 `{{key}}` 作为搜索词占位符，POST 请求使用 `,{ "method":"POST", "body":"q={{key}}" }` 尾缀。',
      )
      ..writeln()
      ..writeln('【目标站点】$siteUrl');
    if ((searchUrlHint ?? '').trim().isNotEmpty) {
      buf.writeln('【参考搜索页】$searchUrlHint');
    }
    if ((keywordHint ?? '').trim().isNotEmpty) {
      buf.writeln('【测试关键词】$keywordHint');
    }
    if (existingToRepair != null) {
      buf
        ..writeln()
        ..writeln('【待修复旧书源 JSON】')
        ..writeln(
          const JsonEncoder.withIndent('  ').convert(existingToRepair.toJson()),
        );
    }
    if ((repairError ?? '').trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('【调试失败诊断】')
        ..writeln(repairError);
    }
    buf
      ..writeln()
      ..writeln('【站点 HTML 片段】')
      ..writeln(htmlSnippet);
    return buf.toString();
  }

  /// 从大模型返回文本中容错提取并解析 [BookSource]。
  static BookSource parseBookSourceFromLlm(
    String llmText, {
    String? fallbackUrl,
  }) {
    final cleaned = _extractJsonBlock(llmText);
    if (cleaned.isEmpty) {
      throw const FormatException('AI 未返回有效的 JSON 内容');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      throw FormatException('AI 返回的 JSON 解析失败：$e');
    }

    Map<String, dynamic>? obj;
    if (decoded is Map) {
      obj = decoded.map((k, v) => MapEntry(k.toString(), v));
    } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      obj = (decoded.first as Map).map((k, v) => MapEntry(k.toString(), v));
    }
    if (obj == null) {
      throw const FormatException('AI 返回的 JSON 不是书源对象');
    }
    if ((obj['bookSourceUrl']?.toString().trim() ?? '').isEmpty &&
        fallbackUrl != null &&
        fallbackUrl.trim().isNotEmpty) {
      obj['bookSourceUrl'] = fallbackUrl.trim();
    }
    if ((obj['bookSourceName']?.toString().trim() ?? '').isEmpty) {
      final host = Uri.tryParse(obj['bookSourceUrl']?.toString() ?? '')?.host;
      obj['bookSourceName'] = (host != null && host.isNotEmpty)
          ? host
          : 'AI 生成书源';
    }
    final source = BookSource.fromJson(obj);
    if (source.bookSourceUrl.isEmpty) {
      throw const FormatException('书源缺少 bookSourceUrl 字段');
    }
    return source;
  }

  /// 执行完整 AI 写源 / 修复流水线：抓页 → 生成 Prompt → 调用 LLM → 解析 JSON → 实测四阶段验证。
  Future<AiSourceStudioResult> generateAndValidate({
    required String siteUrl,
    AppPrefs? prefs,
    String keyword = '西游记',
    String? searchUrlHint,
    BookSource? existingToRepair,
    String? repairError,
    bool autoValidate = true,
    String? htmlSnippetOverride,
    Future<String> Function(String prompt)? llmOverride,
    void Function(String status)? onProgress,
    void Function(SourceDebugStageResult stage)? onValidationStage,
  }) async {
    final normalizedUrl = siteUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw const FormatException('请先输入目标小说网站地址');
    }

    onProgress?.call('正在抓取目标站点 HTML 片段…');
    final snippet =
        htmlSnippetOverride ?? await fetchCleanHtmlSnippet(normalizedUrl);

    final prompt = buildGenerationPrompt(
      siteUrl: normalizedUrl,
      htmlSnippet: snippet,
      searchUrlHint: searchUrlHint,
      keywordHint: keyword,
      existingToRepair: existingToRepair,
      repairError: repairError,
    );

    onProgress?.call('正在请求 AI 生成 Legado 3.0 书源规则…');
    final String rawLlm;
    if (llmOverride != null) {
      rawLlm = await llmOverride(prompt);
    } else {
      if (prefs == null || !prefs.aiConfigured) {
        throw AiException('请先在「AI 设置」中配置可用的大模型接口与模型名称');
      }
      rawLlm = await _ai.analyzeExcerpt(prefs: prefs, prompt: prompt);
    }

    onProgress?.call('正在解析并校验书源 JSON…');
    final source = parseBookSourceFromLlm(rawLlm, fallbackUrl: normalizedUrl);
    final formattedJson = const JsonEncoder.withIndent('  ')
        .convert(source.toJson());

    SourceDebugTrace? trace;
    if (autoValidate) {
      onProgress?.call('正在执行 4 阶段实测验证…');
      final runner = SourceDebugRunner(client: _http);
      trace = await runner.run(
        source,
        keyword.trim().isEmpty ? '西游记' : keyword.trim(),
        onStage: onValidationStage,
      );
    }

    return AiSourceStudioResult(
      source: source,
      formattedJson: formattedJson,
      rawLlmOutput: rawLlm,
      htmlSnippet: snippet,
      validationTrace: trace,
    );
  }

  static String _extractJsonBlock(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    // 优先提取 ```json ... ``` 或 ``` ... ``` 代码块
    final fence = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) {
      return fence.group(1)!.trim();
    }
    // 兜底：截取最外层 `{ ... }` 或 `[ ... ]`
    final firstObj = text.indexOf('{');
    final lastObj = text.lastIndexOf('}');
    if (firstObj >= 0 && lastObj > firstObj) {
      return text.substring(firstObj, lastObj + 1).trim();
    }
    final firstArr = text.indexOf('[');
    final lastArr = text.lastIndexOf(']');
    if (firstArr >= 0 && lastArr > firstArr) {
      return text.substring(firstArr, lastArr + 1).trim();
    }
    return text;
  }
}

/// 仅供调试与扩展检查用的类型导出防误删提示。
typedef DebugDomNode = dom.Element;
typedef DebugXmlNode = xml.XmlElement;
