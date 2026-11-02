import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../source/online_book_service.dart';
import '../source/source_store.dart';
import 'book_store.dart';
import 'models.dart';

List<Map<String, dynamic>> parseLegacyShelf(Uint8List bytes) {
  if (bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('备份文件超过 30 MB');
  }
  if (bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entry = archive.files
        .where(
          (f) =>
              f.isFile &&
              f.name.split('/').last.toLowerCase() == 'bookshelf.json',
        )
        .firstOrNull;
    if (entry == null || entry.size > 30 * 1024 * 1024) {
      throw const FormatException('备份中未找到 bookshelf.json 或文件过大');
    }
    bytes = Uint8List.fromList(entry.content as List<int>);
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  final list = decoded is List
      ? decoded
      : decoded is Map
      ? decoded['books']
      : null;
  if (list is! List || list.length > 10000) {
    throw const FormatException('请选择阅读导出的 bookshelf.json 或含该文件的备份 ZIP');
  }
  return list
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Future<(int, List<String>)> importLegacyShelf(
  List<Map<String, dynamic>> entries,
  BookStore store,
  SourceStore sources, {
  void Function(int, int)? onProgress,
}) async {
  var added = 0;
  final errors = <String>[];
  final service = OnlineBookService();
  try {
    for (var i = 0; i < entries.length; i++) {
      final item = entries[i];
      final name = '${item['name'] ?? item['title'] ?? '未命名'}';
      final url = '${item['bookUrl'] ?? item['path'] ?? ''}';
      try {
        if (store.books.any((b) => b.path == url)) continue;
        Book? book;
        final uri = Uri.tryParse(url);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          final source = sources.byUrl(
            '${item['origin'] ?? item['sourceUrl'] ?? ''}',
          );
          if (source == null) throw StateError('缺少原书源，请先导入对应书源');
          final info = await service
              .fetchInfo(source, url)
              .timeout(const Duration(seconds: 25));
          if (info.chapters.isEmpty) throw StateError('该书源未解析到目录');
          book = store.addOnline(
            Book(
              id: Book.newId(),
              title: name,
              author: '${item['author'] ?? ''}',
              format: BookFormat.online,
              path: url,
              sourceUrl: source.bookSourceUrl,
              intro: info.intro ?? '',
              chapters: info.chapters,
            ),
          );
        } else {
          if (url.isEmpty || !await File(url).exists()) {
            throw StateError('本地原文件未迁移，请先复制 TXT / EPUB 文件');
          }
          final result = await store.importFile(url);
          if (!result.success) throw StateError(result.error ?? '本地文件导入失败');
          book = result.book;
        }
        final chapter = (item['durChapterIndex'] as num?)?.toInt() ?? 0;
        store.updateProgress(
          book!.id,
          chapter: chapter.clamp(0, (book.chapterCount - 1).clamp(0, 1000000)),
          offset: 0,
        );
        await store.flush();
        added++;
      } catch (error) {
        errors.add('$name：$error');
      } finally {
        onProgress?.call(i + 1, entries.length);
      }
    }
  } finally {
    service.dispose();
  }
  return (added, errors);
}
