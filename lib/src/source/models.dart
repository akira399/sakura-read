// 书源数据模型：与「阅读 3.0（Legado）」书源 JSON 格式兼容。
//
// - 字段命名与 Legado 完全一致（bookSourceUrl / ruleSearch / …）；
// - 解析容错：空值、类型混用、未知字段都不抛异常；
// - 未知顶层字段会收集到 [BookSource.extra]，导出时原样写回（向前兼容）。
//
// 本文件为公开 JSON 格式的独立实现，不包含任何 Legado（GPLv3）源代码。

String? _s(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool _b(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final t = v.toString().toLowerCase();
  if (t == 'true' || t == '1') return true;
  if (t == 'false' || t == '0') return false;
  return fallback;
}

Map<String, dynamic> _compact(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

/// 搜索结果中的一本书（多源搜索时带上来源信息）。
class SearchBook {
  const SearchBook({
    this.origin,
    this.originName,
    this.name,
    this.author,
    this.kind,
    this.intro,
    this.coverUrl,
    this.bookUrl,
    this.tocUrl,
    this.latestChapterTitle,
    this.latestChapterUrl,
    this.wordCount,
    this.time,
  });

  /// 来源书源地址（bookSourceUrl）。
  final String? origin;

  /// 来源书源名称（bookSourceName）。
  final String? originName;

  final String? name;
  final String? author;
  final String? kind;
  final String? intro;
  final String? coverUrl;
  final String? bookUrl;
  final String? tocUrl;
  final String? latestChapterTitle;
  final String? latestChapterUrl;
  final String? wordCount;

  /// 更新时间（源上的展示文本，非时间戳）。
  final String? time;

  factory SearchBook.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return SearchBook(
      origin: _s(m['origin']),
      originName: _s(m['originName']),
      name: _s(m['name']),
      author: _s(m['author']),
      kind: _s(m['kind']),
      intro: _s(m['intro']),
      coverUrl: _s(m['coverUrl']),
      bookUrl: _s(m['bookUrl']),
      tocUrl: _s(m['tocUrl']),
      latestChapterTitle: _s(m['latestChapterTitle']),
      latestChapterUrl: _s(m['latestChapterUrl']),
      wordCount: _s(m['wordCount']),
      time: _s(m['time']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'origin': origin,
    'originName': originName,
    'name': name,
    'author': author,
    'kind': kind,
    'intro': intro,
    'coverUrl': coverUrl,
    'bookUrl': bookUrl,
    'tocUrl': tocUrl,
    'latestChapterTitle': latestChapterTitle,
    'latestChapterUrl': latestChapterUrl,
    'wordCount': wordCount,
    'time': time,
  });
}

/// 搜索规则（ruleSearch）。
class SearchRule {
  const SearchRule({
    this.checkKeyWord,
    this.bookList,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.bookUrl,
    this.coverUrl,
    this.wordCount,
  });

  final String? checkKeyWord;
  final String? bookList;
  final String? name;
  final String? author;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final String? bookUrl;
  final String? coverUrl;
  final String? wordCount;

  factory SearchRule.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return SearchRule(
      checkKeyWord: _s(m['checkKeyWord']),
      bookList: _s(m['bookList']),
      name: _s(m['name']),
      author: _s(m['author']),
      intro: _s(m['intro']),
      kind: _s(m['kind']),
      lastChapter: _s(m['lastChapter']),
      updateTime: _s(m['updateTime']),
      bookUrl: _s(m['bookUrl']),
      coverUrl: _s(m['coverUrl']),
      wordCount: _s(m['wordCount']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'checkKeyWord': checkKeyWord,
    'bookList': bookList,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'bookUrl': bookUrl,
    'coverUrl': coverUrl,
    'wordCount': wordCount,
  });
}

/// 详情页规则（ruleBookInfo）。
class BookInfoRule {
  const BookInfoRule({
    this.init,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.coverUrl,
    this.tocUrl,
    this.wordCount,
    this.canReName,
    this.downloadUrls,
  });

  final String? init;
  final String? name;
  final String? author;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final String? coverUrl;
  final String? tocUrl;
  final String? wordCount;
  final String? canReName;
  final String? downloadUrls;

  factory BookInfoRule.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return BookInfoRule(
      init: _s(m['init']),
      name: _s(m['name']),
      author: _s(m['author']),
      intro: _s(m['intro']),
      kind: _s(m['kind']),
      lastChapter: _s(m['lastChapter']),
      updateTime: _s(m['updateTime']),
      coverUrl: _s(m['coverUrl']),
      tocUrl: _s(m['tocUrl']),
      wordCount: _s(m['wordCount']),
      canReName: _s(m['canReName']),
      downloadUrls: _s(m['downloadUrls']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'init': init,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'coverUrl': coverUrl,
    'tocUrl': tocUrl,
    'wordCount': wordCount,
    'canReName': canReName,
    'downloadUrls': downloadUrls,
  });
}

/// 目录规则（ruleToc）。
class TocRule {
  const TocRule({
    this.preUpdateJs,
    this.chapterList,
    this.chapterName,
    this.chapterUrl,
    this.isVolume,
    this.isVip,
    this.isPay,
    this.updateTime,
    this.nextTocUrl,
  });

  final String? preUpdateJs;
  final String? chapterList;
  final String? chapterName;
  final String? chapterUrl;
  final String? isVolume;
  final String? isVip;
  final String? isPay;
  final String? updateTime;
  final String? nextTocUrl;

  factory TocRule.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return TocRule(
      preUpdateJs: _s(m['preUpdateJs']),
      chapterList: _s(m['chapterList']),
      chapterName: _s(m['chapterName']),
      chapterUrl: _s(m['chapterUrl']),
      isVolume: _s(m['isVolume']),
      isVip: _s(m['isVip']),
      isPay: _s(m['isPay']),
      updateTime: _s(m['updateTime']),
      nextTocUrl: _s(m['nextTocUrl']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'preUpdateJs': preUpdateJs,
    'chapterList': chapterList,
    'chapterName': chapterName,
    'chapterUrl': chapterUrl,
    'isVolume': isVolume,
    'isVip': isVip,
    'isPay': isPay,
    'updateTime': updateTime,
    'nextTocUrl': nextTocUrl,
  });
}

/// 正文规则（ruleContent）。
class ContentRule {
  const ContentRule({
    this.content,
    this.nextContentUrl,
    this.webJs,
    this.sourceRegex,
    this.replaceRegex,
    this.imageStyle,
    this.payAction,
  });

  final String? content;
  final String? nextContentUrl;
  final String? webJs;
  final String? sourceRegex;
  final String? replaceRegex;
  final String? imageStyle;
  final String? payAction;

  factory ContentRule.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return ContentRule(
      content: _s(m['content']),
      nextContentUrl: _s(m['nextContentUrl']),
      webJs: _s(m['webJs']),
      sourceRegex: _s(m['sourceRegex']),
      replaceRegex: _s(m['replaceRegex']),
      imageStyle: _s(m['imageStyle']),
      payAction: _s(m['payAction']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'content': content,
    'nextContentUrl': nextContentUrl,
    'webJs': webJs,
    'sourceRegex': sourceRegex,
    'replaceRegex': replaceRegex,
    'imageStyle': imageStyle,
    'payAction': payAction,
  });
}

/// 发现页规则（ruleExplore，M4 使用）。
class ExploreRule {
  const ExploreRule({
    this.bookList,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.bookUrl,
    this.coverUrl,
    this.wordCount,
  });

  final String? bookList;
  final String? name;
  final String? author;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final String? bookUrl;
  final String? coverUrl;
  final String? wordCount;

  factory ExploreRule.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return ExploreRule(
      bookList: _s(m['bookList']),
      name: _s(m['name']),
      author: _s(m['author']),
      intro: _s(m['intro']),
      kind: _s(m['kind']),
      lastChapter: _s(m['lastChapter']),
      updateTime: _s(m['updateTime']),
      bookUrl: _s(m['bookUrl']),
      coverUrl: _s(m['coverUrl']),
      wordCount: _s(m['wordCount']),
    );
  }

  Map<String, dynamic> toJson() => _compact({
    'bookList': bookList,
    'name': name,
    'author': author,
    'intro': intro,
    'kind': kind,
    'lastChapter': lastChapter,
    'updateTime': updateTime,
    'bookUrl': bookUrl,
    'coverUrl': coverUrl,
    'wordCount': wordCount,
  });
}

/// 书源顶层模型。字段顺序与含义对照 Legado 书源 JSON 的公开格式。
class BookSource {
  BookSource({
    required this.bookSourceUrl,
    required this.bookSourceName,
    this.bookSourceGroup,
    this.bookSourceType = 0,
    this.bookUrlPattern,
    this.customOrder = 0,
    this.enabled = true,
    this.enabledExplore = false,
    this.enabledCookieJar = false,
    this.concurrentRate,
    this.header,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.bookSourceComment,
    this.variableComment,
    this.lastUpdateTime,
    this.respondTime,
    this.weight = 0,
    this.exploreUrl,
    this.exploreRule,
    this.searchUrl,
    this.searchRule,
    this.bookInfoRule,
    this.tocRule,
    this.contentRule,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  final String bookSourceUrl;
  final String bookSourceName;
  final String? bookSourceGroup;
  final int bookSourceType;
  final String? bookUrlPattern;
  final int customOrder;
  final bool enabled;
  final bool enabledExplore;
  final bool enabledCookieJar;

  /// 并发率（如 "10/1" 表示 1 秒 10 次；空 = 不限）。
  final String? concurrentRate;

  /// 请求头（原样保存；可能是 JSON 字符串）。
  final String? header;

  final String? loginUrl;
  final String? loginUi;
  final String? loginCheckJs;
  final String? bookSourceComment;
  final String? variableComment;
  final String? lastUpdateTime;
  final String? respondTime;
  final int weight;
  final String? exploreUrl;
  final ExploreRule? exploreRule;
  final String? searchUrl;
  final SearchRule? searchRule;
  final BookInfoRule? bookInfoRule;
  final TocRule? tocRule;
  final ContentRule? contentRule;

  /// 未识别的顶层字段（导出时原样写回，保证向前兼容）。
  final Map<String, dynamic> extra;

  static const _knownKeys = <String>{
    'bookSourceUrl',
    'bookSourceName',
    'bookSourceGroup',
    'bookSourceType',
    'bookUrlPattern',
    'customOrder',
    'enabled',
    'enabledExplore',
    'enabledCookieJar',
    'concurrentRate',
    'header',
    'loginUrl',
    'loginUi',
    'loginCheckJs',
    'bookSourceComment',
    'variableComment',
    'lastUpdateTime',
    'respondTime',
    'weight',
    'exploreUrl',
    'ruleExplore',
    'searchUrl',
    'ruleSearch',
    'ruleBookInfo',
    'ruleToc',
    'ruleContent',
    // 内置资产专用元数据：只用于升级清理，不写回用户书源文件
    'legacyBuiltinUrls',
  };
  // 说明：`webView` / `gatewayPath` / `preRequest` 是樱读扩展字段，
  // 刻意不列入 _knownKeys —— 它们会进入 [BookSource.extra] 被原样保留。

  factory BookSource.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final unknown = <String, dynamic>{};
    for (final e in m.entries) {
      if (!_knownKeys.contains(e.key.toString())) {
        unknown[e.key.toString()] = e.value;
      }
    }
    return BookSource(
      bookSourceUrl: _s(m['bookSourceUrl']) ?? '',
      bookSourceName: _s(m['bookSourceName']) ?? '',
      bookSourceGroup: _s(m['bookSourceGroup']),
      bookSourceType: _i(m['bookSourceType']) ?? 0,
      bookUrlPattern: _s(m['bookUrlPattern']),
      customOrder: _i(m['customOrder']) ?? 0,
      enabled: _b(m['enabled'], true),
      enabledExplore: _b(m['enabledExplore'], false),
      enabledCookieJar: _b(m['enabledCookieJar'], false),
      concurrentRate: _s(m['concurrentRate']),
      header: _s(m['header']),
      loginUrl: _s(m['loginUrl']),
      loginUi: _s(m['loginUi']),
      loginCheckJs: _s(m['loginCheckJs']),
      bookSourceComment: _s(m['bookSourceComment']),
      variableComment: _s(m['variableComment']),
      lastUpdateTime: _s(m['lastUpdateTime']),
      respondTime: _s(m['respondTime']),
      weight: _i(m['weight']) ?? 0,
      exploreUrl: _s(m['exploreUrl']),
      exploreRule: m['ruleExplore'] == null
          ? null
          : ExploreRule.fromJson(m['ruleExplore']),
      searchUrl: _s(m['searchUrl']),
      searchRule: m['ruleSearch'] == null
          ? null
          : SearchRule.fromJson(m['ruleSearch']),
      bookInfoRule: m['ruleBookInfo'] == null
          ? null
          : BookInfoRule.fromJson(m['ruleBookInfo']),
      tocRule: m['ruleToc'] == null ? null : TocRule.fromJson(m['ruleToc']),
      contentRule: m['ruleContent'] == null
          ? null
          : ContentRule.fromJson(m['ruleContent']),
      extra: unknown,
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'bookSourceUrl': bookSourceUrl,
    'bookSourceName': bookSourceName,
    if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
    'bookSourceType': bookSourceType,
    if (bookUrlPattern != null) 'bookUrlPattern': bookUrlPattern,
    'customOrder': customOrder,
    'enabled': enabled,
    'enabledExplore': enabledExplore,
    'enabledCookieJar': enabledCookieJar,
    if (concurrentRate != null) 'concurrentRate': concurrentRate,
    if (header != null) 'header': header,
    if (loginUrl != null) 'loginUrl': loginUrl,
    if (loginUi != null) 'loginUi': loginUi,
    if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
    if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
    if (variableComment != null) 'variableComment': variableComment,
    if (lastUpdateTime != null) 'lastUpdateTime': lastUpdateTime,
    if (respondTime != null) 'respondTime': respondTime,
    'weight': weight,
    if (exploreUrl != null) 'exploreUrl': exploreUrl,
    if (exploreRule != null) 'ruleExplore': exploreRule!.toJson(),
    if (searchUrl != null) 'searchUrl': searchUrl,
    if (searchRule != null) 'ruleSearch': searchRule!.toJson(),
    if (bookInfoRule != null) 'ruleBookInfo': bookInfoRule!.toJson(),
    if (tocRule != null) 'ruleToc': tocRule!.toJson(),
    if (contentRule != null) 'ruleContent': contentRule!.toJson(),
  };

  /// 复制并替换部分字段（当前用于启用状态切换）。
  BookSource copyWith({bool? enabled}) => BookSource(
    bookSourceUrl: bookSourceUrl,
    bookSourceName: bookSourceName,
    bookSourceGroup: bookSourceGroup,
    bookSourceType: bookSourceType,
    bookUrlPattern: bookUrlPattern,
    customOrder: customOrder,
    enabled: enabled ?? this.enabled,
    enabledExplore: enabledExplore,
    enabledCookieJar: enabledCookieJar,
    concurrentRate: concurrentRate,
    header: header,
    loginUrl: loginUrl,
    loginUi: loginUi,
    loginCheckJs: loginCheckJs,
    bookSourceComment: bookSourceComment,
    variableComment: variableComment,
    lastUpdateTime: lastUpdateTime,
    respondTime: respondTime,
    weight: weight,
    exploreUrl: exploreUrl,
    exploreRule: exploreRule,
    searchUrl: searchUrl,
    searchRule: searchRule,
    bookInfoRule: bookInfoRule,
    tocRule: tocRule,
    contentRule: contentRule,
    extra: extra,
  );

  /// 从 JSON（单个对象或数组）解析书源列表；容错：坏条目跳过。
  static List<BookSource> listFromJson(dynamic json) {
    final items = json is List ? json : [json];
    final out = <BookSource>[];
    for (final item in items) {
      try {
        final src = BookSource.fromJson(item);
        if (src.bookSourceUrl.isNotEmpty) out.add(src);
      } catch (_) {
        // 单条坏数据不影响整体导入
      }
    }
    return out;
  }
}
