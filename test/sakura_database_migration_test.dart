import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sakura_read/src/core/database/legacy_migrator.dart';
import 'package:sakura_read/src/core/database/sakura_database.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tmpDir;
  late SakuraDatabase db;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('sakura_db_test_');
    db = await SakuraDatabase.open(
      dbPath: p.join(tmpDir.path, 'sakura_test.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  test('SQLite schema 建表、写入、置顶标记与重载一致', () async {
    final book = Book(
      id: 'b1',
      title: '雪国列车',
      author: '川端',
      format: BookFormat.epub,
      path: '/books/snow.epub',
      intro: '穿过长长的隧道便是雪国。',
      totalChars: 12000,
      chapterIndex: 1,
      charOffset: 240,
      lastReadAt: 1700000000000,
      group: '文学',
      pinned: true,
      chapters: [
        ChapterRef(title: '第一章', href: 'ch1.xhtml', charCount: 5000),
        ChapterRef(title: '第二章', href: 'ch2.xhtml', charCount: 7000),
      ],
    );

    await db.upsertBook(book);
    final loaded = await db.loadAllBooks();
    expect(loaded, hasLength(1));
    final first = loaded.first;
    expect(first.id, 'b1');
    expect(first.title, '雪国列车');
    expect(first.author, '川端');
    expect(first.format, BookFormat.epub);
    expect(first.group, '文学');
    expect(first.pinned, isTrue);
    expect(first.chapterIndex, 1);
    expect(first.charOffset, 240);
    expect(first.chapters, hasLength(2));
    expect(first.chapters[1].href, 'ch2.xhtml');
  });

  test('v1.3.0 library.json 与 bookmarks.json 迁移幂等且保留原文件', () async {
    final libraryFile = File(p.join(tmpDir.path, 'library.json'));
    final bookmarksFile = File(p.join(tmpDir.path, 'bookmarks.json'));

    final libraryPayload = jsonEncode({
      'version': 1,
      'books': [
        Book(
          id: 'txt-1',
          title: '本地小说',
          author: '佚名',
          format: BookFormat.txt,
          path: '/sdcard/local.txt',
          totalChars: 300,
          chapters: [
            ChapterRef(title: '第1章', start: 0, end: 150, charCount: 150),
            ChapterRef(title: '第2章', start: 150, end: 300, charCount: 150),
          ],
        ).toJson(),
        Book(
          id: 'epub-1',
          title: '插图电子书',
          author: '作者乙',
          format: BookFormat.epub,
          path: '/sdcard/book.epub',
          chapters: [
            ChapterRef(title: '序章', href: 'intro.xhtml', charCount: 800),
          ],
        ).toJson(),
        Book(
          id: 'online-1',
          title: '连载网文',
          author: '作者丙',
          format: BookFormat.online,
          path: 'https://book.example/1',
          sourceUrl: 'https://book.example',
          chapters: [
            ChapterRef(
              title: '最新章',
              href: 'https://book.example/1/c1',
              charCount: 2000,
            ),
          ],
        ).toJson(),
        'malformed-entry',
      ],
    });
    await libraryFile.writeAsString(libraryPayload);

    final bookmarksPayload = jsonEncode({
      'version': 1,
      'items': [
        {
          'id': 'bm-1',
          'bookId': 'txt-1',
          'chapterIndex': 1,
          'charOffset': 45,
          'chapterTitle': '第2章',
          'excerpt': '窗外樱花正盛。',
          'createdAt': 1700000001000,
        },
        {
          'id': 'bm-2',
          'bookId': 'online-1',
          'chapterIndex': 0,
          'charOffset': 12,
          'chapterTitle': '最新章',
          'excerpt': '少年推开书店门。',
          'createdAt': 1700000002000,
        },
      ],
    });
    await bookmarksFile.writeAsString(bookmarksPayload);

    final report1 = await LegacyMigrator.migrateIfNeeded(
      db: db,
      filesDir: tmpDir.path,
    );
    expect(report1.alreadyMigrated, isFalse);
    expect(report1.booksMigrated, 3);
    expect(report1.bookmarksMigrated, 2);

    final books = await db.loadAllBooks();
    expect(books, hasLength(3));
    expect(books.map((b) => b.id).toSet(), {'txt-1', 'epub-1', 'online-1'});
    expect(await db.countAnnotations(), 2);

    // 幂等性校验：再次运行不重复导入
    final report2 = await LegacyMigrator.migrateIfNeeded(
      db: db,
      filesDir: tmpDir.path,
    );
    expect(report2.alreadyMigrated, isTrue);
    expect(report2.booksMigrated, 0);
    expect(report2.bookmarksMigrated, 0);
    expect(await db.loadAllBooks(), hasLength(3));
    expect(await db.countAnnotations(), 2);

    // 原 JSON 文件完好保留
    expect(await libraryFile.readAsString(), libraryPayload);
    expect(await bookmarksFile.readAsString(), bookmarksPayload);
  });

  test('BookStore 接入 SQLite 后支持快速进度更新、置顶、分组与级联删除', () async {
    final dirs = AppDirs(files: tmpDir.path, cache: tmpDir.path);
    final store = BookStore(dirsOverride: dirs, database: db);
    await store.load();

    store.addOnline(
      Book(
        id: 'ol-1',
        title: '追更中',
        format: BookFormat.online,
        path: 'https://example.test/book1',
        sourceUrl: 'https://example.test',
        chapters: [
          ChapterRef(title: '第1章', href: 'c1', charCount: 1000),
          ChapterRef(title: '第2章', href: 'c2', charCount: 1200),
        ],
      ),
    );
    store.updateProgress('ol-1', chapter: 1, offset: 88);
    store.setPinned('ol-1', true);
    store.setGroup('ol-1', '玄幻');
    await store.flush();

    final reloaded = BookStore(dirsOverride: dirs, database: db);
    await reloaded.load();
    final book = reloaded.byId('ol-1');
    expect(book, isNotNull);
    expect(book!.chapterIndex, 1);
    expect(book.charOffset, 88);
    expect(book.pinned, isTrue);
    expect(book.group, '玄幻');
    expect(book.chapters, hasLength(2));

    await reloaded.removeById('ol-1');
    await reloaded.flush();
    expect(await db.loadAllBooks(), isEmpty);
    final orphanChapters = await db.raw.query(
      'chapters',
      where: 'book_id = ?',
      whereArgs: ['ol-1'],
    );
    expect(orphanChapters, isEmpty);
  });
}
