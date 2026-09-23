import 'dart:math';

/// 书籍格式。
enum BookFormat { txt, epub, online }

/// 章节引用（TXT 用字符偏移；EPUB 用 zip 条目路径）。
class ChapterRef {
  ChapterRef({
    required this.title,
    this.start,
    this.end,
    this.href,
    this.charCount = 0,
  });

  String title;

  /// TXT：章节起始字符偏移。
  final int? start;

  /// TXT：章节结束字符偏移（不含）。
  final int? end;

  /// EPUB：zip 内条目路径。
  final String? href;

  /// 章节字数（导入时计算）。
  int charCount;

  int get span => (end ?? start ?? 0) - (start ?? 0);

  factory ChapterRef.fromJson(Map<String, dynamic> json) => ChapterRef(
    title: json['title'] as String? ?? '',
    start: (json['start'] as num?)?.toInt(),
    end: (json['end'] as num?)?.toInt(),
    href: json['href'] as String?,
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'start': start,
    'end': end,
    'href': href,
    'charCount': charCount,
  };
}

/// 书架里的书籍。
class Book {
  Book({
    required this.id,
    required this.title,
    this.author = '',
    required this.format,
    required this.path,
    this.sourceUrl,
    this.coverPath,
    this.generatedCover = true,
    this.intro = '',
    List<ChapterRef>? chapters,
    this.totalChars = 0,
    this.chapterIndex = 0,
    this.charOffset = 0,
    int? addedAt,
    int? lastReadAt,
    this.finished = false,
  }) : chapters = chapters ?? [],
       addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch,
       lastReadAt = lastReadAt ?? 0;

  final String id;
  String title;
  String author;
  final BookFormat format;

  /// 书籍源文件绝对路径（在线书籍时为书页地址；换源时可更新）。
  String path;

  /// 在线书籍：来源书源地址（bookSourceUrl；换源时可更新）。
  String? sourceUrl;

  /// 封面图片路径（EPUB 提取后缓存的文件）。
  String? coverPath;

  /// 无封面文件时使用程序生成的渐变封面。
  bool generatedCover;

  String intro;

  final List<ChapterRef> chapters;

  /// 全书总字数（按章节 charCount 汇总）。
  int totalChars;

  /// 阅读进度：章节序号。
  int chapterIndex;

  /// 阅读进度：章节内字符偏移（与排版设置无关）。
  int charOffset;

  int addedAt;
  int lastReadAt;
  bool finished;

  static final Random _rnd = Random();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rnd.nextInt(1 << 30).toRadixString(36)}';

  int get chapterCount => chapters.length;

  int get safeChapterIndex {
    if (chapters.isEmpty) return 0;
    return chapterIndex.clamp(0, chapters.length - 1).toInt();
  }

  ChapterRef? get chapter =>
      chapters.isEmpty ? null : chapters[safeChapterIndex];

  /// 阅读进度 0~1。
  double get progress {
    if (chapters.isEmpty) return 0;
    if (finished) return 1;
    final ch = chapters[safeChapterIndex];
    final local = ch.charCount > 0 ? charOffset / ch.charCount : 0.0;
    return ((safeChapterIndex + local.clamp(0.0, 1.0)) / chapters.length)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// 已读字数（估算）。
  int get readChars {
    var n = 0;
    for (var i = 0; i < safeChapterIndex && i < chapters.length; i++) {
      n += chapters[i].charCount;
    }
    return n + charOffset;
  }

  String get formatLabel => switch (format) {
    BookFormat.txt => 'TXT',
    BookFormat.epub => 'EPUB',
    BookFormat.online => '在线',
  };

  String get progressLabel => '${(progress * 100).round()}%';

  factory Book.fromJson(Map<String, dynamic> json) {
    final chapters = <ChapterRef>[];
    final raw = json['chapters'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          chapters.add(ChapterRef.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return Book(
      id: json['id'] as String? ?? newId(),
      title: json['title'] as String? ?? '未命名',
      author: json['author'] as String? ?? '',
      format: switch (json['format'] as String?) {
        'epub' => BookFormat.epub,
        'online' => BookFormat.online,
        _ => BookFormat.txt,
      },
      path: json['path'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String?,
      coverPath: json['coverPath'] as String?,
      generatedCover: json['generatedCover'] as bool? ?? true,
      intro: json['intro'] as String? ?? '',
      chapters: chapters,
      totalChars: (json['totalChars'] as num?)?.toInt() ?? 0,
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
      addedAt: (json['addedAt'] as num?)?.toInt(),
      lastReadAt: (json['lastReadAt'] as num?)?.toInt(),
      finished: json['finished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format.name,
    'path': path,
    'sourceUrl': sourceUrl,
    'coverPath': coverPath,
    'generatedCover': generatedCover,
    'intro': intro,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'totalChars': totalChars,
    'chapterIndex': chapterIndex,
    'charOffset': charOffset,
    'addedAt': addedAt,
    'lastReadAt': lastReadAt,
    'finished': finished,
  };
}
