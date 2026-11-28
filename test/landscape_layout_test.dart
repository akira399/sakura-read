import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/core/theme/sakura_layout.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/book_grid_card.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/book_list_tile.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/continue_reading_card.dart';
import 'package:sakura_read/src/features/settings/reading_defaults_page.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/reader/reader_settings_panel.dart';
import 'package:sakura_read/src/ui/settings_page.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';

void main() {
  late Directory tmpDir;
  late AppPrefs prefs;
  late BookStore store;
  late SourceStore sourceStore;
  late StatsStore statsStore;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('sakura_landscape_');
    final dirs = AppDirs(files: tmpDir.path, cache: tmpDir.path);
    prefs = AppPrefs(dirsOverride: dirs);
    await prefs.load();
    store = BookStore(dirsOverride: dirs);
    await store.load();
    sourceStore = SourceStore(dirsOverride: dirs);
    await sourceStore.load();
    statsStore = StatsStore(dirsOverride: dirs);
    await statsStore.load();
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  test('SakuraLayout 在横屏/宽屏下限制悬浮 Dock 宽度并保留竖屏全宽', () {
    expect(SakuraLayout.dockMaxWidth(390), double.infinity);
    expect(SakuraLayout.dockMaxWidth(700), 540);
    expect(SakuraLayout.dockMaxWidth(960), 560);
  });

  testWidgets('横屏单本书架将「继续阅读」与「藏书空间引导」并排陈列且底部按钮完整可见', (tester) async {
    tester.view.physicalSize = const Size(960 * 2, 540 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    store.addOnline(
      Book(
        id: 'only-book',
        title: '雪国',
        author: '川端康成',
        format: BookFormat.txt,
        path: '/tmp/snow.txt',
        lastReadAt: 1700000009000,
        chapters: [ChapterRef(title: '第一章', charCount: 600)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(960, 540),
            padding: EdgeInsets.only(top: 24, left: 24),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: ShelfPage(
              store: store,
              prefs: prefs,
              sourceStore: sourceStore,
              statsStore: statsStore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    final continueRect = tester.getRect(find.byType(ContinueReadingCard));
    final inviteRect = tester.getRect(find.text('书架还有充裕的藏书空间'));
    final importBtnRect = tester.getRect(find.text('导入新书'));
    final searchBtnRect = tester.getRect(find.text('在线搜书'));

    expect(continueRect.right, lessThan(inviteRect.left));
    expect(importBtnRect.bottom, lessThanOrEqualTo(540));
    expect(searchBtnRect.bottom, lessThanOrEqualTo(540));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('横屏多本书架列表视图切换为双栏排布，无溢出错位', (tester) async {
    tester.view.physicalSize = const Size(960 * 2, 540 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    store.addOnline(
      Book(
        id: 'b1',
        title: '第一册',
        author: '作者甲',
        format: BookFormat.txt,
        path: '/tmp/1.txt',
        chapters: [ChapterRef(title: '1', charCount: 400)],
      ),
    );
    store.addOnline(
      Book(
        id: 'b2',
        title: '第二册',
        author: '作者乙',
        format: BookFormat.epub,
        path: '/tmp/2.epub',
        chapters: [ChapterRef(title: '1', charCount: 400)],
      ),
    );
    prefs.setShelfView(ShelfViewMode.list);

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(960, 540),
            padding: EdgeInsets.only(top: 24),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: ShelfPage(
              store: store,
              prefs: prefs,
              sourceStore: sourceStore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    final tiles = tester.widgetList<BookListTile>(find.byType(BookListTile));
    expect(tiles, hasLength(2));
    final r1 = tester.getRect(find.byType(BookListTile).at(0));
    final r2 = tester.getRect(find.byType(BookListTile).at(1));
    expect(r1.top, r2.top);
    expect(r1.left, lessThan(r2.left));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('横屏多本书架网格视图顶部双栏并排且至少 5 列紧凑展示', (tester) async {
    tester.view.physicalSize = const Size(960 * 2, 540 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    for (var i = 1; i <= 6; i++) {
      store.addOnline(
        Book(
          id: 'gb$i',
          title: '书籍 $i',
          author: '作者 $i',
          format: BookFormat.epub,
          path: '/tmp/$i.epub',
          lastReadAt: i == 1 ? 1700000010000 : 0,
          chapters: [ChapterRef(title: '1', charCount: 400)],
        ),
      );
    }
    prefs.setShelfView(ShelfViewMode.grid);

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(960, 540),
            padding: EdgeInsets.only(top: 16),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: ShelfPage(
              store: store,
              prefs: prefs,
              sourceStore: sourceStore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    final continueRect = tester.getRect(find.byType(ContinueReadingCard));
    final summaryRect = tester.getRect(find.textContaining('藏书 6 本'));
    expect(continueRect.right, lessThan(summaryRect.left));

    final card0 = tester.getRect(find.byType(BookGridCard).at(0));
    final card4 = tester.getRect(find.byType(BookGridCard).at(4));
    expect(card0.top, card4.top);
    expect(card0.height, lessThanOrEqualTo(260));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('横屏设置主控台与排版设置页均启用双栏自适应布局', (tester) async {
    tester.view.physicalSize = const Size(960 * 2, 540 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: SettingsPage(
          store: store,
          prefs: prefs,
          sourceStore: sourceStore,
          statsStore: statsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    final leftSection = tester.getRect(find.text('书房视觉与排版'));
    final rightSection = tester.getRect(find.text('书源与阅读记录'));
    expect(leftSection.left, lessThan(rightSection.left));

    await tester.tap(find.text('阅读默认排版'));
    await tester.pumpAndSettle();

    expect(find.byType(ReadingDefaultsPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    final previewRect = tester.getRect(find.textContaining('实时排版预览'));
    final panelRect = tester.getRect(find.byType(ReaderSettingsPanel));
    expect(previewRect.left, lessThan(panelRect.left));

    await tester.pump(const Duration(milliseconds: 500));
  });
}
