import 'dart:convert';
import 'dart:io';

import '../../data/models.dart';
import 'sakura_database.dart';

/// v1.3.0 JSON 数据迁移报告。
class MigrationReport {
  const MigrationReport({
    required this.booksMigrated,
    required this.bookmarksMigrated,
    required this.alreadyMigrated,
  });

  final int booksMigrated;
  final int bookmarksMigrated;
  final bool alreadyMigrated;
}

/// 一次性将 v1.3.0 的 `library.json` 与 `bookmarks.json` 无损迁入 SQLite。
///
/// 迁入后**不删除**旧 JSON 文件，保证回退或旧备份恢复时依然安全可追溯。
class LegacyMigrator {
  LegacyMigrator._();

  static const String _metaKey = 'v1_library_migrated';

  static Future<MigrationReport> migrateIfNeeded({
    required SakuraDatabase db,
    required String filesDir,
  }) async {
    if (await db.getMeta(_metaKey) == '1') {
      return const MigrationReport(
        booksMigrated: 0,
        bookmarksMigrated: 0,
        alreadyMigrated: true,
      );
    }

    var booksMigrated = 0;
    final libraryFile = File('$filesDir/library.json');
    if (await libraryFile.exists()) {
      try {
        final raw = jsonDecode(await libraryFile.readAsString());
        if (raw is Map && raw['books'] is List) {
          for (final item in raw['books'] as List) {
            if (item is! Map) continue;
            try {
              final book = Book.fromJson(Map<String, dynamic>.from(item));
              await db.upsertBook(book);
              booksMigrated++;
            } catch (_) {
              // 跳过单条坏数据，避免整库迁移中断
            }
          }
        }
      } catch (_) {
        // library.json 损坏时不覆盖原文件，直接标记完成或由用户恢复
      }
    }

    var bookmarksMigrated = 0;
    final bookmarksFile = File('$filesDir/bookmarks.json');
    if (await bookmarksFile.exists()) {
      try {
        final raw = jsonDecode(await bookmarksFile.readAsString());
        if (raw is Map && raw['items'] is List) {
          for (final item in raw['items'] as List) {
            if (item is! Map) continue;
            try {
              final map = Map<String, dynamic>.from(item);
              final id = map['id'] as String?;
              final bookId = map['bookId'] as String?;
              if (id == null ||
                  id.isEmpty ||
                  bookId == null ||
                  bookId.isEmpty) {
                continue;
              }
              final offset = (map['charOffset'] as num?)?.toInt() ?? 0;
              final inserted = await db.insertAnnotationIfAbsent(
                id: id,
                bookId: bookId,
                chapterIndex: (map['chapterIndex'] as num?)?.toInt() ?? 0,
                startOffset: offset,
                endOffset: offset,
                quote: map['excerpt'] as String? ?? '',
                note: map['chapterTitle'] as String? ?? '',
                kind: 'bookmark',
                createdAt:
                    (map['createdAt'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
              );
              if (inserted) bookmarksMigrated++;
            } catch (_) {
              // 跳过坏书签记录
            }
          }
        }
      } catch (_) {
        // 忽略损坏的 bookmarks.json
      }
    }

    await db.setMeta(_metaKey, '1');
    return MigrationReport(
      booksMigrated: booksMigrated,
      bookmarksMigrated: bookmarksMigrated,
      alreadyMigrated: false,
    );
  }
}
