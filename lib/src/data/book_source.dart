import 'dart:io';

import 'package:flutter/foundation.dart';

import '../source/online_book_service.dart';
import '../source/source_store.dart';
import 'book_store.dart';
import 'epub_parser.dart';
import 'models.dart';
import 'txt_parser.dart';

/// 章节内容读取接口。
abstract class BookContent {
  Future<String> chapterText(int index);

  Future<void> dispose() async {}
}

/// TXT：整文件解码后在内存中按字符偏移切片。
class TxtBookContent implements BookContent {
  TxtBookContent(this.book);

  final Book book;
  String? _text;
  Future<String>? _loading;

  Future<String> _ensureText() {
    final cached = _text;
    if (cached != null) return Future.value(cached);
    return _loading ??= () async {
      final bytes = await File(book.path).readAsBytes();
      final text = await compute(_decodeTxtIsolate, bytes);
      _text = text;
      return text;
    }();
  }

  @override
  Future<String> chapterText(int index) async {
    if (index < 0 || index >= book.chapters.length) return '';
    final text = await _ensureText();
    final ch = book.chapters[index];
    final start = (ch.start ?? 0).clamp(0, text.length);
    final end = (ch.end ?? text.length).clamp(start, text.length);
    return text.substring(start, end);
  }

  @override
  Future<void> dispose() async {
    _text = null;
  }
}

/// EPUB：读取导入时缓存的章节文本；缓存丢失时从源文件重新提取。
class EpubBookContent implements BookContent {
  EpubBookContent(this.book, this.store);

  final Book book;
  final BookStore store;
  final Map<int, String> _memo = {};

  File _cacheFile(int index) => File(
    '${store.chapterCacheDir(book.id).path}/'
    'ch_${index.toString().padLeft(4, '0')}.txt',
  );

  @override
  Future<String> chapterText(int index) async {
    if (index < 0 || index >= book.chapters.length) return '';
    final memo = _memo[index];
    if (memo != null) return memo;

    final loaded = await _load(index);
    _memo[index] = loaded;
    if (_memo.length > 3) {
      _memo.remove(_memo.keys.first);
    }
    return loaded;
  }

  Future<String> _load(int index) async {
    final file = _cacheFile(index);
    try {
      if (await file.exists()) {
        final cached = await file.readAsString();
        if (cached.isNotEmpty) return cached;
      }
    } catch (_) {}

    final href = book.chapters[index].href ?? '';
    final fresh = await compute(_extractEpubChapterIsolate, {
      'path': book.path,
      'href': href,
    });
    if (fresh.isNotEmpty) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(fresh, flush: false);
      } catch (_) {}
    }
    return fresh;
  }

  @override
  Future<void> dispose() async {
    _memo.clear();
  }
}

/// 在线书籍：隐藏 WebView 渲染正文 + 磁盘缓存。
///
/// 章节链接、正文解析依赖书源规则（[BookSource]）：
/// 通过 [Book.sourceUrl]（书源地址）在 [SourceStore.shared] 中查找。
class OnlineBookContent implements BookContent {
  OnlineBookContent(this.book, this.store);

  final Book book;
  final BookStore store;
  final OnlineBookService _service = OnlineBookService();
  final Map<int, String> _memo = {};

  File _cacheFile(int index) => File(
    '${store.chapterCacheDir(book.id).path}/'
    'ch_${index.toString().padLeft(4, '0')}.txt',
  );

  @override
  Future<String> chapterText(int index) async {
    if (index < 0 || index >= book.chapters.length) return '';
    final memo = _memo[index];
    if (memo != null) return memo;
    final loaded = await _load(index);
    _memo[index] = loaded;
    if (_memo.length > 3) {
      _memo.remove(_memo.keys.first);
    }
    return loaded;
  }

  Future<String> _load(int index) async {
    final file = _cacheFile(index);
    try {
      if (await file.exists()) {
        final cached = await file.readAsString();
        if (cached.isNotEmpty) return cached;
      }
    } catch (_) {}

    final sourceUrl = book.sourceUrl;
    final source = sourceUrl == null
        ? null
        : SourceStore.shared?.byUrl(sourceUrl);
    if (source == null) {
      throw StateError('书源缺失（${sourceUrl ?? '未知'}），可能已被删除');
    }
    final chapter = book.chapters[index];
    final href = (chapter.href ?? '').trim();
    if (href.isEmpty) {
      throw StateError('章节缺少链接（第 ${index + 1} 章）');
    }
    final text = await _service.fetchChapterText(source, href);
    if (text.trim().isEmpty) {
      throw StateError('正文为空（站点可能拦截或改版）');
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(text, flush: false);
    } catch (_) {}
    return text;
  }

  @override
  Future<void> dispose() async {
    _memo.clear();
  }
}

/// 按书籍格式创建内容读取器。
BookContent createBookContent(Book book, BookStore store) {
  switch (book.format) {
    case BookFormat.txt:
      return TxtBookContent(book);
    case BookFormat.epub:
      return EpubBookContent(book, store);
    case BookFormat.online:
      return OnlineBookContent(book, store);
  }
}

// ---------- isolate 入口 ----------

String _decodeTxtIsolate(Uint8List bytes) => TxtParser.decodeBytes(bytes).text;

String _extractEpubChapterIsolate(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final href = args['href'] as String;
  return EpubParser.extractChapterTextFromFile(path, href) ?? '';
}
