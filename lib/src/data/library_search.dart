import 'dart:io';

import 'book_source.dart';
import 'book_store.dart';
import 'models.dart';

class LibraryMatch {
  const LibraryMatch(this.book, this.chapter, this.offset, this.excerpt);
  final Book book;
  final int chapter;
  final int offset;
  final String excerpt;
}

/// Exact local retrieval; never fetches unread online chapters or uploads text.
class LibrarySearch {
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
  }

  Future<List<LibraryMatch>> search(
    BookStore store,
    String query, {
    Book? onlyBook,
    void Function(int, int)? onProgress,
  }) async {
    _cancelled = false;
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return [];
    final books = onlyBook == null ? store.books : [onlyBook];
    final matches = <LibraryMatch>[];
    for (var b = 0; b < books.length && !_cancelled; b++) {
      final book = books[b];
      final content = createBookContent(book, store);
      try {
        for (var i = 0; i < book.chapterCount && !_cancelled; i++) {
          String text;
          if (book.format == BookFormat.online) {
            final file = File(
              '${store.chapterCacheDir(book.id).path}/ch_v2_${i.toString().padLeft(4, '0')}.txt',
            );
            if (!await file.exists()) continue;
            text = await file.readAsString();
          } else {
            text = await content.chapterText(i);
          }
          final lower = text.toLowerCase();
          var from = 0;
          while (!_cancelled) {
            final at = lower.indexOf(term, from);
            if (at < 0) break;
            final start = (at - 35).clamp(0, text.length);
            final end = (at + term.length + 80).clamp(start, text.length);
            matches.add(
              LibraryMatch(
                book,
                i,
                at,
                text.substring(start, end).replaceAll('\n', ' '),
              ),
            );
            if (matches.length >= 100) return matches;
            from = at + term.length;
          }
          if (i % 10 == 0) await Future<void>.delayed(Duration.zero);
        }
      } on FileSystemException {
        /* Missing local files do not prevent searching other books. */
      } finally {
        await content.dispose();
      }
      onProgress?.call(b + 1, books.length);
    }
    return matches;
  }
}
