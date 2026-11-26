import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/models.dart';

/// Sakura Read 2.0 规范化 SQLite 数据库。
///
/// 替代旧版整库序列化 `library.json`，支持万章级网文毫秒查询、单行进度更新，
/// 以及后续阶段的划线批注、正文净化规则与防剧透 AI 记忆库。
class SakuraDatabase {
  SakuraDatabase._(this._db);

  /// 进程内共享数据库实例（后台水合完成后赋值）。
  static SakuraDatabase? shared;

  final Database _db;

  Database get raw => _db;

  /// 打开数据库（测试可传入 `databaseFactoryFfi` 与 `:memory:` 或临时路径）。
  static Future<SakuraDatabase> open({
    required String dbPath,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    if (dbPath != ':memory:') {
      await Directory(p.dirname(dbPath)).create(recursive: true);
    }
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          if (dbPath != ':memory:') {
            try {
              await db.rawQuery('PRAGMA journal_mode = WAL');
            } catch (_) {
              // 个别文件系统不支持 WAL 时安全回落
            }
          }
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    return SakuraDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        format TEXT NOT NULL,
        path TEXT NOT NULL,
        source_url TEXT,
        cover_path TEXT,
        generated_cover INTEGER NOT NULL DEFAULT 1,
        intro TEXT NOT NULL DEFAULT '',
        total_chars INTEGER NOT NULL DEFAULT 0,
        chapter_index INTEGER NOT NULL DEFAULT 0,
        char_offset INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        last_read_at INTEGER NOT NULL DEFAULT 0,
        finished INTEGER NOT NULL DEFAULT 0,
        book_group TEXT NOT NULL DEFAULT '',
        pinned INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        title TEXT NOT NULL,
        start_offset INTEGER,
        end_offset INTEGER,
        href TEXT,
        char_count INTEGER NOT NULL DEFAULT 0,
        UNIQUE(book_id, idx),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chapters_book_idx ON chapters(book_id, idx)',
    );

    await db.execute('''
      CREATE TABLE annotations (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        start_offset INTEGER NOT NULL,
        end_offset INTEGER NOT NULL,
        quote TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        color_index INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'bookmark',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_annotations_book ON annotations(book_id, chapter_index)',
    );

    await db.execute('''
      CREATE TABLE replace_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pattern TEXT NOT NULL,
        replacement TEXT NOT NULL DEFAULT '',
        is_regex INTEGER NOT NULL DEFAULT 1,
        scope TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_book_memory (
        book_id TEXT NOT NULL,
        max_chapter_index INTEGER NOT NULL,
        kind TEXT NOT NULL,
        content_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, kind)
      )
    ''');

    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<String?> getMeta(String key) async {
    final rows = await _db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    await _db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 读取全部书籍及对应章节目录（按章节 idx 升序）。
  Future<List<Book>> loadAllBooks() async {
    final bookRows = await _db.query(
      'books',
      orderBy: 'pinned DESC, last_read_at DESC, added_at DESC',
    );
    if (bookRows.isEmpty) return [];

    final chapterRows = await _db.query(
      'chapters',
      orderBy: 'book_id ASC, idx ASC',
    );
    final chaptersByBook = <String, List<ChapterRef>>{};
    for (final row in chapterRows) {
      final bookId = row['book_id'] as String;
      (chaptersByBook[bookId] ??= []).add(
        ChapterRef(
          title: row['title'] as String? ?? '',
          start: row['start_offset'] as int?,
          end: row['end_offset'] as int?,
          href: row['href'] as String?,
          charCount: row['char_count'] as int? ?? 0,
        ),
      );
    }

    return [
      for (final row in bookRows)
        Book(
          id: row['id'] as String,
          title: row['title'] as String? ?? '未命名',
          author: row['author'] as String? ?? '',
          format: _parseFormat(row['format'] as String?),
          path: row['path'] as String? ?? '',
          sourceUrl: row['source_url'] as String?,
          coverPath: row['cover_path'] as String?,
          generatedCover: (row['generated_cover'] as int? ?? 1) != 0,
          intro: row['intro'] as String? ?? '',
          chapters: chaptersByBook[row['id'] as String] ?? [],
          totalChars: row['total_chars'] as int? ?? 0,
          chapterIndex: row['chapter_index'] as int? ?? 0,
          charOffset: row['char_offset'] as int? ?? 0,
          addedAt: row['added_at'] as int?,
          lastReadAt: row['last_read_at'] as int? ?? 0,
          finished: (row['finished'] as int? ?? 0) != 0,
          group: row['book_group'] as String? ?? '',
          pinned: (row['pinned'] as int? ?? 0) != 0,
        ),
    ];
  }

  /// 插入或更新书籍；使用 ON CONFLICT DO UPDATE 避免触发 ON DELETE CASCADE 误删章节。
  Future<void> upsertBook(Book book, {bool replaceChapters = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT INTO books (
          id, title, author, format, path, source_url, cover_path,
          generated_cover, intro, total_chars, chapter_index, char_offset,
          added_at, last_read_at, finished, book_group, pinned, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          author = excluded.author,
          format = excluded.format,
          path = excluded.path,
          source_url = excluded.source_url,
          cover_path = excluded.cover_path,
          generated_cover = excluded.generated_cover,
          intro = excluded.intro,
          total_chars = excluded.total_chars,
          chapter_index = excluded.chapter_index,
          char_offset = excluded.char_offset,
          added_at = excluded.added_at,
          last_read_at = excluded.last_read_at,
          finished = excluded.finished,
          book_group = excluded.book_group,
          pinned = excluded.pinned,
          updated_at = excluded.updated_at
        ''',
        [
          book.id,
          book.title,
          book.author,
          book.format.name,
          book.path,
          book.sourceUrl,
          book.coverPath,
          book.generatedCover ? 1 : 0,
          book.intro,
          book.totalChars,
          book.chapterIndex,
          book.charOffset,
          book.addedAt,
          book.lastReadAt,
          book.finished ? 1 : 0,
          book.group,
          book.pinned ? 1 : 0,
          now,
        ],
      );

      if (replaceChapters) {
        await txn.delete(
          'chapters',
          where: 'book_id = ?',
          whereArgs: [book.id],
        );
        if (book.chapters.isNotEmpty) {
          final batch = txn.batch();
          for (var i = 0; i < book.chapters.length; i++) {
            final ch = book.chapters[i];
            batch.insert('chapters', {
              'book_id': book.id,
              'idx': i,
              'title': ch.title,
              'start_offset': ch.start,
              'end_offset': ch.end,
              'href': ch.href,
              'char_count': ch.charCount,
            });
          }
          await batch.commit(noResult: true);
        }
      }
    });
  }

  /// 仅更新单本书的阅读进度，不重写章节目录。
  Future<void> updateBookProgress({
    required String id,
    required int chapterIndex,
    required int charOffset,
    required int lastReadAt,
    required bool finished,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'books',
      {
        'chapter_index': chapterIndex,
        'char_offset': charOffset,
        'last_read_at': lastReadAt,
        'finished': finished ? 1 : 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 更新书架元信息（标题、分组、置顶、最近阅读时间）。
  Future<void> updateBookMeta({
    required String id,
    String? title,
    String? group,
    bool? pinned,
    int? lastReadAt,
  }) async {
    final values = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (title != null) values['title'] = title;
    if (group != null) values['book_group'] = group;
    if (pinned != null) values['pinned'] = pinned ? 1 : 0;
    if (lastReadAt != null) values['last_read_at'] = lastReadAt;
    await _db.update('books', values, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除书籍并级联清理章节与批注。
  Future<void> deleteBook(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('annotations', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('ai_book_memory', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 插入批注或书签（存在同 id 时忽略，供迁移与增量同步用）。
  Future<bool> insertAnnotationIfAbsent({
    required String id,
    required String bookId,
    required int chapterIndex,
    required int startOffset,
    required int endOffset,
    required String quote,
    String note = '',
    int colorIndex = 0,
    String kind = 'bookmark',
    required int createdAt,
    int? updatedAt,
  }) async {
    final rowId = await _db.insert('annotations', {
      'id': id,
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'start_offset': startOffset,
      'end_offset': endOffset,
      'quote': quote,
      'note': note,
      'color_index': colorIndex,
      'kind': kind,
      'created_at': createdAt,
      'updated_at': updatedAt ?? createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return rowId != 0;
  }

  Future<int> countAnnotations({String? bookId}) async {
    final rows = bookId == null
        ? await _db.rawQuery('SELECT COUNT(*) AS c FROM annotations')
        : await _db.rawQuery(
            'SELECT COUNT(*) AS c FROM annotations WHERE book_id = ?',
            [bookId],
          );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 读取全部正文净化/替换规则（按 `sort_order` 升序）。
  Future<List<Map<String, Object?>>> loadReplaceRules() async {
    final rows = await _db.query(
      'replace_rules',
      orderBy: 'sort_order ASC, id ASC',
    );
    return [for (final row in rows) Map<String, Object?>.of(row)];
  }

  /// 插入或替换一条正文净化/替换规则。
  Future<void> upsertReplaceRule(Map<String, Object?> row) async {
    await _db.insert(
      'replace_rules',
      Map<String, Object?>.of(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除指定 id 的正文净化/替换规则。
  Future<void> deleteReplaceRule(String id) async {
    await _db.delete('replace_rules', where: 'id = ?', whereArgs: [id]);
  }

  /// 切换指定正文净化/替换规则的启用状态。
  Future<void> setReplaceRuleEnabled(String id, bool enabled) async {
    await _db.update(
      'replace_rules',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 按书籍（及可选章节索引）读取划线/批注/书签记录。
  Future<List<Map<String, Object?>>> loadAnnotationsForBook(
    String bookId, {
    int? chapterIndex,
  }) async {
    final rows = chapterIndex == null
        ? await _db.query(
            'annotations',
            where: 'book_id = ?',
            whereArgs: [bookId],
            orderBy: 'chapter_index ASC, start_offset ASC, created_at ASC',
          )
        : await _db.query(
            'annotations',
            where: 'book_id = ? AND chapter_index = ?',
            whereArgs: [bookId, chapterIndex],
            orderBy: 'start_offset ASC, created_at ASC',
          );
    return [for (final row in rows) Map<String, Object?>.of(row)];
  }

  /// 插入或更新一条划线/批注/书签记录。
  Future<void> upsertAnnotation(Map<String, Object?> row) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = Map<String, Object?>.of(row);
    values.putIfAbsent('created_at', () => now);
    values.putIfAbsent('updated_at', () => now);
    await _db.insert(
      'annotations',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除指定 id 的划线/批注/书签记录。
  Future<void> deleteAnnotation(String id) async {
    await _db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  /// 读取指定书籍和类型的防剧透 AI 记忆记录（不存在时返回 null）。
  Future<Map<String, Object?>?> getAiMemory(String bookId, String kind) async {
    final rows = await _db.query(
      'ai_book_memory',
      where: 'book_id = ? AND kind = ?',
      whereArgs: [bookId, kind],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.of(rows.first);
  }

  /// 插入或更新指定书籍的防剧透 AI 记忆记录。
  Future<void> upsertAiMemory({
    required String bookId,
    required int maxChapterIndex,
    required String kind,
    required String contentJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('ai_book_memory', {
      'book_id': bookId,
      'max_chapter_index': maxChapterIndex,
      'kind': kind,
      'content_json': contentJson,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除指定书籍的全部 AI 记忆记录。
  Future<void> deleteAiMemoryForBook(String bookId) async {
    await _db.delete(
      'ai_book_memory',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> close() => _db.close();

  static BookFormat _parseFormat(String? raw) => switch (raw) {
    'epub' => BookFormat.epub,
    'online' => BookFormat.online,
    _ => BookFormat.txt,
  };
}
