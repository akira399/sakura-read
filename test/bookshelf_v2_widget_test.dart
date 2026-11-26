import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/book_grid_card.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/book_list_tile.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/continue_reading_card.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';

void main() {
  late Directory tmpDir;
  late AppPrefs prefs;
  late BookStore store;
  late SourceStore sourceStore;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('sakura_shelf_v2_');
    final dirs = AppDirs(files: tmpDir.path, cache: tmpDir.path);
    prefs = AppPrefs(dirsOverride: dirs);
    await prefs.load();
    store = BookStore(dirsOverride: dirs);
    await store.load();
    sourceStore = SourceStore(dirsOverride: dirs);
    await sourceStore.load();

    store.addOnline(
      Book(
        id: 'book-recent',
        title: '星夜下的约定',
        author: '樱井小夜',
        format: BookFormat.txt,
        path: '/tmp/star.txt',
        group: '轻小说',
        lastReadAt: 1700000005000,
        chapterIndex: 1,
        charOffset: 120,
        chapters: [
          ChapterRef(title: '第一章 相遇', charCount: 1000),
          ChapterRef(title: '第二章 约定', charCount: 1000),
        ],
      ),
    );
    store.addOnline(
      Book(
        id: 'book-pinned',
        title: '置顶必读卷',
        author: '作者B',
        format: BookFormat.epub,
        path: '/tmp/pinned.epub',
        group: '文学',
        pinned: true,
        lastReadAt: 1700000001000,
        chapters: [ChapterRef(title: '序幕', href: 'c0.xhtml', charCount: 500)],
      ),
    );
    store.addOnline(
      Book(
        id: 'book-online',
        title: '连载幻想录',
        author: '作者C',
        format: BookFormat.online,
        path: 'https://example.test/novel',
        sourceUrl: 'https://example.test',
        chapters: [
          ChapterRef(
            title: '第一话',
            href: 'https://example.test/1',
            charCount: 800,
          ),
        ],
      ),
    );
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  Widget buildShelf({Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: SakuraTheme.build(prefs.accent, brightness),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 32),
          disableAnimations: true,
        ),
        child: Scaffold(
          extendBody: true,
          body: ShelfPage(store: store, prefs: prefs, sourceStore: sourceStore),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
  }

  testWidgets('显示继续阅读卡片、置顶优先排序、格式徽标与分组筛选', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildShelf());
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(ContinueReadingCard), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('第二章 约定'), findsOneWidget);

    // 置顶书籍在网格中排在第一位
    final gridCards = tester.widgetList<BookGridCard>(
      find.byType(BookGridCard),
    );
    expect(gridCards.first.book.id, 'book-pinned');

    // 格式徽标完整渲染
    expect(find.text('TXT'), findsWidgets);
    expect(find.text('EPUB'), findsWidgets);
    expect(find.text('在线'), findsWidgets);

    // 分组筛选：切到「轻小说」只剩星夜下的约定，且聚焦卡片收起
    final groupChip = find.text('轻小说 (1)');
    await tester.ensureVisible(groupChip);
    await tester.tap(groupChip);
    await tester.pumpAndSettle();
    final filtered = tester
        .widgetList<BookGridCard>(find.byType(BookGridCard))
        .toList();
    expect(filtered, hasLength(1));
    expect(filtered.first.book.id, 'book-recent');
    expect(find.byType(ContinueReadingCard), findsNothing);
  });

  testWidgets('小图、列表、大封面与暗色模式均无布局溢出或异常', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildShelf(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    prefs.setShelfView(ShelfViewMode.list);
    await tester.pumpAndSettle();
    expect(find.byType(BookListTile), findsNWidgets(3));
    expect(find.byType(ErrorWidget), findsNothing);

    prefs.setShelfView(ShelfViewMode.compact);
    await tester.pumpAndSettle();
    expect(find.byType(BookGridCard), findsNWidgets(3));
    expect(find.byType(ErrorWidget), findsNothing);

    prefs.setShelfView(ShelfViewMode.cover);
    await tester.pumpAndSettle();
    expect(find.byType(BookGridCard), findsNWidgets(3));
    expect(find.byType(ErrorWidget), findsNothing);
    // 排空 AppPrefs 防抖写盘定时器
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('单本书去重：仅显示继续阅读焦点卡与迎新架位，不重复平铺', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final singleDir = Directory.systemTemp.createTempSync('sakura_single_');
    addTearDown(() {
      if (singleDir.existsSync()) singleDir.deleteSync(recursive: true);
    });
    final sDirs = AppDirs(files: singleDir.path, cache: singleDir.path);
    final sPrefs = AppPrefs(dirsOverride: sDirs);
    final sStore = BookStore(dirsOverride: sDirs);
    await tester.runAsync(() async {
      await sPrefs.load();
      await sStore.load();
    });
    sStore.addOnline(
      Book(
        id: 'only-one',
        title: '雪国',
        author: '川端康成',
        format: BookFormat.txt,
        path: '/tmp/snow.txt',
        lastReadAt: 1700000009000,
        chapters: [ChapterRef(title: '第一章 穿过县界长长的隧道', charCount: 800)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(sPrefs.accent, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 32),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: ShelfPage(
              store: sStore,
              prefs: sPrefs,
              sourceStore: sourceStore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ContinueReadingCard), findsOneWidget);
    expect(find.byType(BookGridCard), findsNothing);
    expect(find.text('书架还有充裕的藏书空间'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('切换 4 套书房视觉风格预设均能无异常渲染', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildShelf());
    await tester.pumpAndSettle();

    for (final preset in VisualStylePreset.values) {
      prefs.applyVisualStylePreset(preset);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.byType(BookGridCard), findsNWidgets(3));
    }
    await tester.pump(const Duration(milliseconds: 400));
  });
}
