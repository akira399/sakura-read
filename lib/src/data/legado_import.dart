// 「阅读」(legado) 备份导入：解析备份 → 在本地书源里重新匹配 → 抓目录 → 入架。
//
// 为什么按书名重新匹配，而不是直接复用备份里的 bookUrl / origin？
// legado 备份里的地址指向的是**导出那台手机**上的书源实例（同一个源可能换了
// 域名、或者用户在本 App 里根本没导入那个源），直接复用大概率抓不到正文。
// 所以这里只把备份当「书目清单 + 阅读进度」，书和目录都从本机已有书源重新取。
//
// 这个文件刻意不依赖 BuildContext：解析、匹配、导入都是可单测的纯逻辑，
// 页面只负责收集路径、展示进度和结果。
import 'dart:convert';
import 'dart:io';

import '../source/models.dart';
import '../source/online_book_service.dart';
import '../source/online_repo.dart';
import '../source/source_store.dart';
import 'book_store.dart';
import 'models.dart';

/// legado 备份里的一本书：只保留导入真正用得上的字段。
class LegadoBook {
  const LegadoBook({
    required this.name,
    this.author = '',
    this.bookUrl = '',
    this.origin = '',
    this.originName = '',
    this.durChapterIndex = 0,
    this.durChapterTitle = '',
    this.intro = '',
    this.coverUrl = '',
  });

  final String name;
  final String author;

  /// 备份里记录的正文地址 / 来源地址。
  ///
  /// 不直接复用（见文件头注释），留着是为了排查「这本书到底来自哪个源」。
  final String bookUrl;
  final String origin;

  /// 备份里记录的来源名，用户对「我在哪个源看的」更有印象。
  final String originName;

  /// 读到第几章（0 起）。目录可能比备份时短，入架前要夹到范围内。
  final int durChapterIndex;
  final String durChapterTitle;
  final String intro;
  final String coverUrl;

  @override
  String toString() => 'LegadoBook($name / $author)';
}

/// 读取备份文件的结果：成功时 [books] 非空，失败时 [error] 是给用户看的中文原因。
class LegadoBackupRead {
  const LegadoBackupRead({this.books = const [], this.error});

  final List<LegadoBook> books;
  final String? error;

  bool get ok => error == null;
}

/// 一次导入的统计结果。
class LegadoImportResult {
  const LegadoImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
    this.failures = const [],
  });

  /// 成功入架的本数。
  final int imported;

  /// 书架里已经有的本数（按归一化书名 / 正文地址判重）。
  final int skipped;

  final int failed;

  /// 每本失败的原因，形如「《书名》：书源里没搜到对得上的书」。
  final List<String> failures;
}

/// legado 备份导入器。
///
/// 单次导入是无状态的一次性任务，所以不需要持有任何字段。
class LegadoImporter {
  const LegadoImporter();

  /// 备份文件读取上限。
  ///
  /// 超过这个体积基本不可能是书目 json（更可能是整库备份或别的文件），
  /// 而且一次性读进内存会直接把低端机顶掉，所以先看大小再读。
  static const int maxBackupBytes = 20 * 1024 * 1024;

  /// 候选书的合格线：书名完全一致是 100，包含是 60。
  ///
  /// 低于这条线宁可不导——同名不同书（各种「同人」「番外」）塞进书架，
  /// 用户读起来更难受。
  static const int matchThreshold = 60;

  /// 解析 legado 备份 json，返回书目清单。
  ///
  /// 备份是别的 App 导出的，字段类型、BOM、空数组都不可信，所以全程宽松处理：
  /// 读不出来就返回空列表，让页面给出「确认是不是备份文件」的提示。
  static List<LegadoBook> parseBackup(String jsonText) {
    // BOM 是「文件能打开、json 解析却报错」的经典坑（经 PC 中转过的备份常带）。
    var text = jsonText.trim();
    while (text.startsWith('\uFEFF')) {
      text = text.substring(1).trimLeft();
    }
    if (text.isEmpty) return const [];

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    // 顶层必须是对象；数组 / 字符串 / 数字都不是我们认识的备份格式。
    if (decoded is! Map) return const [];
    final rawBooks = decoded['books'];
    if (rawBooks is! List) return const [];

    final books = <LegadoBook>[];
    for (final raw in rawBooks) {
      if (raw is! Map) continue; // 混杂了脏数据项就跳过，别连累其它书
      final name = _textOf(raw['name']);
      // 没名字的书既没法匹配也没法显示，跳过。
      if (name.isEmpty) continue;
      books.add(
        LegadoBook(
          name: name,
          author: _textOf(raw['author']),
          bookUrl: _textOf(raw['bookUrl']),
          origin: _textOf(raw['origin']),
          originName: _textOf(raw['originName']),
          durChapterIndex: _intOf(raw['durChapterIndex']),
          durChapterTitle: _textOf(raw['durChapterTitle']),
          intro: _textOf(raw['intro']),
          coverUrl: _textOf(raw['coverUrl']),
        ),
      );
    }
    return books;
  }

  /// 给一个搜索候选打分，用来从一堆同名 / 相似结果里挑最像的那本。
  ///
  /// 分数只用来**排序 + 过阈值**，不代表真实相似度：
  /// 书名归一化后相等 100，互相包含 60，作者一致再加 30。
  static int matchScore(
    LegadoBook target, {
    required String name,
    required String author,
  }) {
    final targetName = normalizeSearchText(target.name);
    final otherName = normalizeSearchText(name);
    var score = 0;
    if (targetName.isNotEmpty && otherName.isNotEmpty) {
      if (targetName == otherName) {
        score = 100;
      } else if (otherName.contains(targetName) ||
          targetName.contains(otherName)) {
        // 源站爱给书名加「（完结）」「最新章节」之类的尾巴，也算同一个。
        score = 60;
      }
    }
    final targetAuthor = normalizeSearchText(target.author);
    final otherAuthor = normalizeSearchText(author);
    // 空作者不算「相等」，否则两本都没填作者的书会被误加成。
    // 书名完全没对上时这 30 分也过不了阈值，所以放心直接加。
    if (targetAuthor.isNotEmpty &&
        otherAuthor.isNotEmpty &&
        targetAuthor == otherAuthor) {
      score += 30;
    }
    return score;
  }

  /// 从用户输入的路径读备份文件，并把常见失败翻译成中文提示。
  ///
  /// 页面拿到 [LegadoBackupRead.error] 直接展示即可，不用自己判断文件系统状态。
  static Future<LegadoBackupRead> readBackupFile(String path) async {
    var raw = path.trim();
    if (raw.isEmpty) {
      return const LegadoBackupRead(error: '先填一下备份文件的路径吧～');
    }
    // 从文件管理器「复制路径」常常带 file:// 前缀或引号，先洗掉再打开。
    if (raw.startsWith('file://')) raw = raw.substring(7);
    raw = raw.replaceAll('"', '').replaceAll("'", '').trim();
    final file = File(raw);
    try {
      if (!await file.exists()) {
        return LegadoBackupRead(error: '没找到 $raw，看看路径是不是写错了～');
      }
      final length = await file.length();
      if (length > maxBackupBytes) {
        final mb = (length / 1024 / 1024).toStringAsFixed(1);
        return LegadoBackupRead(
          error: '这个文件有 $mb MB，太大了，应该不是 legado 的备份 json 吧？',
        );
      }
      final bytes = await file.readAsBytes();
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        return const LegadoBackupRead(error: '备份不是 UTF-8 编码，暂时读不了');
      }
      final books = parseBackup(text);
      if (books.isEmpty) {
        return const LegadoBackupRead(
          error: '这个文件里没读到书的记录，确认是 legado 导出的备份 json 吗？',
        );
      }
      return LegadoBackupRead(books: books);
    } on FileSystemException catch (e) {
      // 常见于没给「所有文件访问」权限，或路径指向了别的 App 的私有目录。
      final reason = (e.message).trim();
      return LegadoBackupRead(error: '读文件失败：$reason');
    }
  }

  /// 把这批书导入书架。
  ///
  /// 每本独立 try/catch：一本书失败不影响后面的书，失败原因收集到
  /// [LegadoImportResult.failures]。`onProgress` 每处理完一本回调一次
  /// （成功、跳过、失败都算），页面据此更新进度条。
  Future<LegadoImportResult> importBooks({
    required List<LegadoBook> books,
    required BookStore shelf,
    required SourceStore sources,
    void Function(int done, int total, String title)? onProgress,
  }) async {
    final total = books.length;
    if (total == 0) return const LegadoImportResult();

    // 并发别开太大：导入是一次性的批量活，宁可慢一点也别把书源站点打挂。
    final repo = OnlineRepo(store: sources, concurrency: 4);
    final service = OnlineBookService();

    // 书架现有书名的快照；每导完一本就补进去，备份里重复的书也能跳过。
    final knownNames = <String>{
      for (final book in shelf.books) normalizeSearchText(book.title),
    };

    var imported = 0;
    var skipped = 0;
    var failed = 0;
    final failures = <String>[];

    for (var i = 0; i < total; i++) {
      final target = books[i];
      final key = normalizeSearchText(target.name);
      try {
        if (knownNames.contains(key)) {
          skipped++;
        } else {
          final candidate = await _bestCandidate(repo, target);
          if (candidate == null) {
            failed++;
            failures.add('《${target.name}》：书源里没搜到对得上的书');
          } else if (shelf.onlineByPath(candidate.bookUrl) != null) {
            // 书名不一样但正文地址相同（改过名 / 同一个源里的同一本），也算已有。
            skipped++;
          } else {
            final info = await service.fetchInfo(
              candidate.source,
              candidate.bookUrl,
            );
            if (info.chapters.isEmpty) {
              failed++;
              failures.add('《${target.name}》：目录是空的，可能这个书源规则失效了');
            } else {
              final chapterIndex = target.durChapterIndex.clamp(
                0,
                info.chapters.length - 1,
              );
              shelf.addOnline(
                Book(
                  id: Book.newId(),
                  // 用备份里的书名：这是用户在自己书架里认识的名字，
                  // 源站标题常带「最新章节」之类的尾巴。
                  title: target.name,
                  author: _firstNonEmpty(
                    info.author,
                    candidate.book.author,
                    target.author,
                  ),
                  format: BookFormat.online,
                  path: candidate.bookUrl,
                  sourceUrl: candidate.source.bookSourceUrl,
                  chapters: info.chapters,
                  chapterIndex: chapterIndex,
                  intro: _firstNonEmpty(
                    info.intro,
                    candidate.book.intro,
                    target.intro,
                  ),
                  coverPath: null,
                  generatedCover: true,
                ),
              );
              knownNames.add(key);
              imported++;
            }
          }
        }
      } catch (e) {
        failed++;
        failures.add('《${target.name}》：${_errorText(e)}');
      } finally {
        // 放 finally：即使上面某本书抛异常、或走了 continue 的分支，
        // 进度也一定会往前走一格，页面不会卡在 99%。
        onProgress?.call(i + 1, total, target.name);
      }
    }

    return LegadoImportResult(
      imported: imported,
      skipped: skipped,
      failed: failed,
      failures: failures,
    );
  }

  /// 搜一遍所有启用的书源，挑分数最高的候选；不够 [matchThreshold] 返回 null。
  static Future<_Candidate?> _bestCandidate(
    OnlineRepo repo,
    LegadoBook target,
  ) async {
    final results = await repo.searchAll(target.name);
    _Candidate? best;
    var bestScore = 0;
    for (final result in results) {
      for (final book in result.books) {
        final bookUrl = (book.bookUrl ?? '').trim();
        // 没有正文地址的候选抓不了目录，直接跳过。
        if (bookUrl.isEmpty) continue;
        final score = matchScore(
          target,
          name: book.name ?? '',
          author: book.author ?? '',
        );
        if (score > bestScore) {
          bestScore = score;
          best = (source: result.source, book: book, bookUrl: bookUrl);
        }
      }
    }
    return bestScore >= matchThreshold ? best : null;
  }
}

/// 匹配到的候选：记下它来自哪个书源，后面还要用这个源抓目录。
typedef _Candidate = ({BookSource source, SearchBook book, String bookUrl});

/// 宽松取字符串：备份里字段类型经常不对（数字、null、对象都有），不能直接 as。
String _textOf(Object? value) {
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  return '';
}

/// 宽松取整数：字符串数字（"12"）、浮点（12.0）都认，认不出给 0。
int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? 0;
  }
  return 0;
}

/// 依次取第一个非空字符串；用于「源站信息优先，备份信息兜底」。
String _firstNonEmpty(String? first, String? second, String fallback) {
  for (final value in [first, second]) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty) return text;
  }
  return fallback.trim();
}

/// 把异常压成一行给用户看的短文案（抓取引擎的报错常带整页 HTML）。
String _errorText(Object error) {
  var text = error.toString().trim();
  const prefix = 'Exception: ';
  if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();
  if (text.isEmpty) text = '未知错误';
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
