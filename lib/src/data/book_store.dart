import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/native_bridge.dart';
import 'epub_parser.dart';
import 'file_scan.dart';
import 'models.dart';
import 'stats_store.dart';
import 'txt_parser.dart';

/// 导入结果。
class ImportResult {
  ImportResult.ok(Book this.book) : error = null;

  ImportResult.fail(this.error) : book = null;

  final Book? book;
  final String? error;

  bool get success => book != null;
}

/// 书架数据：JSON 持久化 + 导入 + 阅读进度。
class BookStore extends ChangeNotifier {
  BookStore({AppDirs? dirsOverride}) : _dirsOverride = dirsOverride;

  final AppDirs? _dirsOverride;
  final List<Book> _books = [];
  AppDirs? _dirs;
  File? _file;
  Timer? _saveTimer;

  List<Book> get books => List.unmodifiable(_books);

  Directory get coverDir =>
      Directory('${_dirs?.files ?? Directory.systemTemp.path}/covers');

  Directory get chapterCacheRoot =>
      Directory('${_dirs?.cache ?? Directory.systemTemp.path}/books');

  Directory chapterCacheDir(String bookId) =>
      Directory('${chapterCacheRoot.path}/$bookId');

  Future<void> load() async {
    _dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${_dirs!.files}/library.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map && data['books'] is List) {
          for (final item in data['books'] as List) {
            if (item is Map) {
              try {
                _books.add(Book.fromJson(Map<String, dynamic>.from(item)));
              } catch (_) {
                // 跳过坏数据
              }
            }
          }
        }
      }
    } catch (_) {
      // 读取失败时以空书架启动
    }
    notifyListeners();
  }

  Book? byId(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  bool containsPath(String path) => _books.any((b) => b.path == path);

  /// 在线书籍：按书页地址查找。
  Book? onlineByPath(String path) {
    for (final b in _books) {
      if (b.format == BookFormat.online && b.path == path) return b;
    }
    return null;
  }

  /// 加入一本在线书籍（同一书页地址已存在时直接返回已有条目）。
  Book addOnline(Book book) {
    final existing = onlineByPath(book.path);
    if (existing != null) return existing;
    _books.add(book);
    _saveSoon();
    notifyListeners();
    return book;
  }

  /// 在线书籍：切换书源（更新书页地址 / 源地址 / 目录，并清空该书的章节缓存）。
  ///
  /// 保留阅读进度（章节序号夹取到新目录范围，章内偏移归零）。
  Future<void> switchOnlineSource(
    String id, {
    required String path,
    required String sourceUrl,
    required List<ChapterRef> chapters,
    String? title,
    String? author,
    String? intro,
  }) async {
    final b = byId(id);
    if (b == null || b.format != BookFormat.online) return;
    b.path = path;
    b.sourceUrl = sourceUrl;
    b.chapters
      ..clear()
      ..addAll(chapters);
    final t = (title ?? '').trim();
    if (t.isNotEmpty) b.title = t;
    final a = (author ?? '').trim();
    if (a.isNotEmpty) b.author = a;
    final i = (intro ?? '').trim();
    if (i.isNotEmpty) b.intro = i;
    b.chapterIndex = chapters.isEmpty
        ? 0
        : b.chapterIndex.clamp(0, chapters.length - 1).toInt();
    b.charOffset = 0;
    b.lastReadAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final dir = chapterCacheDir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _saveSoon();
    notifyListeners();
  }

  /// 从书架移除一本书。
  ///
  /// [deleteLocalFile] 为 true 时顺带删除这本书的本地文件（用户反馈：
  /// 想把书移走时直接连着本地文件一起删掉）。只删书架里登记的那个文件，
  /// 同一路径被另一本书引用时保留，避免误删别人还在用的书。
  Future<void> removeById(String id, {bool deleteLocalFile = false}) async {
    final book = byId(id);
    if (book == null) return;
    final before = _books.length;
    _books.removeWhere((b) => b.id == id);
    if (_books.length == before) return;
    // 移除书时联动清理其书签
    BookmarkStore.shared?.removeForBook(id);
    _saveSoon();
    notifyListeners();
    if (!deleteLocalFile) return;
    final path = book.path;
    if (path.isEmpty) return;
    // 还有别的书在用同一个文件 → 不删
    final shared = _books.any((b) => b.path == path);
    if (shared) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败（权限 / 文件已被外部删掉）不影响「移除」本身
    }
  }

  void rename(String id, String title) {
    final b = byId(id);
    if (b == null) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == b.title) return;
    b.title = trimmed;
    _saveSoon();
    notifyListeners();
  }

  void touch(String id) {
    final b = byId(id);
    if (b == null) return;
    b.lastReadAt = DateTime.now().millisecondsSinceEpoch;
    _saveSoon();
  }

  void updateProgress(String id, {int? chapter, int? offset, bool? finished}) {
    final b = byId(id);
    if (b == null) return;
    if (chapter != null) b.chapterIndex = chapter;
    if (offset != null) b.charOffset = offset;
    if (finished != null) b.finished = finished;
    b.lastReadAt = DateTime.now().millisecondsSinceEpoch;
    _saveSoon();
    notifyListeners();
  }

  void markUnread(String id) {
    final b = byId(id);
    if (b == null) return;
    b.chapterIndex = 0;
    b.charOffset = 0;
    b.finished = false;
    _saveSoon();
    notifyListeners();
  }

  void markFinished(String id) {
    final b = byId(id);
    if (b == null) return;
    b.finished = true;
    _saveSoon();
    notifyListeners();
  }

  // ---------- 导入 ----------

  Future<ImportResult> importFile(
    String path, {
    void Function(String message)? onProgress,
  }) async {
    if (containsPath(path)) return ImportResult.fail('已经在书架里了');
    final ext = pathExtension(path);
    try {
      if (ext == 'txt') {
        return ImportResult.ok(await _importTxt(path, onProgress));
      }
      if (ext == 'epub') {
        return ImportResult.ok(await _importEpub(path, onProgress));
      }
      return ImportResult.fail('不支持的格式 .$ext（仅支持 txt / epub）');
    } on EpubException catch (e) {
      return ImportResult.fail(e.message);
    } catch (e) {
      return ImportResult.fail('导入失败：$e');
    }
  }

  void _add(Book book) {
    _books.add(book);
    _saveSoon();
    notifyListeners();
  }

  Future<Book> _importTxt(
    String path,
    void Function(String)? onProgress,
  ) async {
    onProgress?.call('读取 TXT…');
    final bytes = await File(path).readAsBytes();
    onProgress?.call('解析编码与章节…');
    final map = await compute(_parseTxtIsolate, bytes);
    final rawChapters = map['chapters'] as List;
    final chapters = <ChapterRef>[];
    for (final item in rawChapters) {
      final m = item as Map;
      final start = (m['start'] as num).toInt();
      final end = (m['end'] as num).toInt();
      chapters.add(
        ChapterRef(
          title: m['title'] as String,
          start: start,
          end: end,
          charCount: end - start,
        ),
      );
    }
    final book = Book(
      id: Book.newId(),
      title: pathBaseName(path),
      author: (map['author'] as String?) ?? '',
      format: BookFormat.txt,
      path: path,
      intro: (map['intro'] as String?) ?? '',
      chapters: chapters,
      totalChars: chapters.fold(0, (sum, c) => sum + c.charCount),
    );
    _add(book);
    return book;
  }

  Future<Book> _importEpub(
    String path,
    void Function(String)? onProgress,
  ) async {
    onProgress?.call('读取 EPUB…');
    final bytes = await File(path).readAsBytes();
    final id = Book.newId();
    final cacheDir = chapterCacheDir(id);
    onProgress?.call('解析 EPUB 结构…');
    final map = await compute(_parseEpubIsolate, {
      'bytes': bytes,
      'cacheDir': cacheDir.path,
    });
    final meta = (map['meta'] as Map?) ?? const {};
    final rawChapters = map['chapters'] as List;
    final chapters = <ChapterRef>[];
    var total = 0;
    for (final item in rawChapters) {
      final m = item as Map;
      final count = (m['charCount'] as num).toInt();
      total += count;
      chapters.add(
        ChapterRef(
          title: m['title'] as String,
          href: m['href'] as String,
          charCount: count,
        ),
      );
    }

    String? coverPath;
    var generatedCover = true;
    final coverBytes = map['cover'] as Uint8List?;
    if (coverBytes != null && coverBytes.length > 100) {
      final ext = (map['coverExt'] as String?) ?? 'png';
      final dir = coverDir;
      await dir.create(recursive: true);
      final f = File('${dir.path}/$id.$ext');
      await f.writeAsBytes(coverBytes, flush: false);
      coverPath = f.path;
      generatedCover = false;
    }

    final title = ((meta['title'] as String?) ?? '').trim();
    final book = Book(
      id: id,
      title: title.isNotEmpty ? title : pathBaseName(path),
      author: ((meta['author'] as String?) ?? '').trim(),
      format: BookFormat.epub,
      path: path,
      coverPath: coverPath,
      generatedCover: generatedCover,
      intro: ((meta['intro'] as String?) ?? '').trim(),
      chapters: chapters,
      totalChars: total,
    );
    _add(book);
    return book;
  }

  // ---------- 缓存管理 ----------

  Future<int> cacheSizeBytes() async {
    var total = 0;
    try {
      if (await chapterCacheRoot.exists()) {
        await for (final e in chapterCacheRoot.list(
          recursive: true,
          followLinks: false,
        )) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> clearCache() async {
    try {
      if (await chapterCacheRoot.exists()) {
        await chapterCacheRoot.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 某本书已缓存的章节数（在线书离线缓存用）。
  ///
  /// 统计 `ch_v2_*.txt` 且内容非空的文件——只有真正抓到正文才会写文件，
  /// 所以这个数字就是「断网也能读的章节数」。
  Future<int> cachedChapterCount(String bookId) async {
    try {
      final dir = chapterCacheDir(bookId);
      if (!await dir.exists()) return 0;
      var n = 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('ch_v2_') || !name.endsWith('.txt')) continue;
        try {
          if (await e.length() > 0) n++;
        } catch (_) {}
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// 某本书的缓存占用（字节）。
  Future<int> bookCacheBytes(String bookId) async {
    var total = 0;
    try {
      final dir = chapterCacheDir(bookId);
      if (await dir.exists()) {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return total;
  }

  /// 清除某本书的章节缓存（该书改源 / 想重新抓取时用）。
  Future<void> clearBookCache(String bookId) async {
    try {
      final dir = chapterCacheDir(bookId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ---------- 持久化 ----------

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'version': 1,
          'books': _books.map((b) => b.toJson()).toList(),
        }),
      );
      await tmp.rename(file.path);
    } catch (_) {
      // 忽略保存失败
    }
  }
}

// ---------- isolate 入口（避免大文件解析卡 UI） ----------

Map<String, dynamic> _parseTxtIsolate(Uint8List bytes) {
  final r = TxtParser.parseBytes(bytes);
  return {
    'chapters': r.chapters
        .map((c) => {'title': c.title, 'start': c.start, 'end': c.end})
        .toList(),
    'author': guessAuthor(r.text),
    'intro': guessIntro(r.text),
  };
}

Map<String, dynamic> _parseEpubIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final cacheDirPath = args['cacheDir'] as String;
  final r = EpubParser.parse(bytes);
  Directory(cacheDirPath).createSync(recursive: true);
  // 插图目录（用户反馈「书里的插图不能加载」）
  final imgDir = Directory('$cacheDirPath/img');
  var imgTotal = 0;
  final chapters = <Map<String, dynamic>>[];
  for (var i = 0; i < r.chapters.length; i++) {
    final c = r.chapters[i];
    // 先把本章插图落盘（正文里的占位标记按文件名查找）
    for (final img in c.images) {
      try {
        imgDir.createSync(recursive: true);
        File('${imgDir.path}/${img.name}').writeAsBytesSync(img.bytes);
        imgTotal++;
      } catch (_) {
        // 单张图失败不影响正文
      }
    }
    final name = 'ch_${i.toString().padLeft(4, '0')}.txt';
    File('$cacheDirPath/$name').writeAsStringSync(c.text);
    chapters.add({'href': c.href, 'title': c.title, 'charCount': c.charCount});
  }
  return {
    'meta': {
      'title': r.meta.title,
      'author': r.meta.author,
      'intro': r.meta.intro,
    },
    'chapters': chapters,
    'cover': r.coverBytes,
    'coverExt': r.coverExtension,
    'imageCount': imgTotal,
  };
}

/// 从开头文本猜测作者（"作者：xxx"）。
String guessAuthor(String text) {
  final head = text.length > 1500 ? text.substring(0, 1500) : text;
  final match = RegExp(r'作\s*者[：:\s]\s*([^\n\r]{1,30})').firstMatch(head);
  final author = match?.group(1)?.trim() ?? '';
  return author.length > 20 ? '' : author;
}

/// 从开头文本猜测简介。
String guessIntro(String text) {
  final lines = text.split('\n');
  final picked = <String>[];
  for (final line in lines.take(12)) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (RegExp(r'^作\s*者|^简\s*介|^第.{1,12}[章回节]').hasMatch(t)) continue;
    picked.add(t);
    if (picked.length >= 2) break;
  }
  var intro = picked.join(' ');
  if (intro.length > 120) intro = '${intro.substring(0, 120)}…';
  return intro;
}
