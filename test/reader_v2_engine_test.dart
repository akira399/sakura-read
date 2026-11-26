import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_curl/paper_curl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sakura_read/src/core/database/sakura_database.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/paginator.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/xray.dart';
import 'package:sakura_read/src/features/reader/annotation_models.dart';
import 'package:sakura_read/src/features/reader/annotation_sheet.dart';
import 'package:sakura_read/src/features/reader/chapter_paginator_cache.dart';
import 'package:sakura_read/src/features/reader/image_viewer_page.dart';
import 'package:sakura_read/src/features/reader/quote_card_dialog.dart';
import 'package:sakura_read/src/features/reader/reader_chrome.dart';
import 'package:sakura_read/src/features/reader/simulation_turn.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/reader/reader_page.dart';
import 'package:sakura_read/src/ui/reader/reader_settings_panel.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: SakuraTheme.build(const Color(0xFFE86A92), brightness),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('Prefs defaults & PageTurnMode.simulation', () {
    test('xrayHighlight defaults to false (opt-in)', () {
      final prefs = AppPrefs();
      expect(prefs.xrayHighlight, isFalse);
    });

    test('PageTurnMode.simulation persists and reloads cleanly', () async {
      final dir = await Directory.systemTemp.createTemp('sakura_sim_prefs');
      addTearDown(() => dir.delete(recursive: true));
      final dirs = AppDirs(files: dir.path, cache: dir.path);

      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      expect(prefs.xrayHighlight, isFalse);

      prefs.setPageMode(PageTurnMode.simulation);
      await prefs.flush();

      final reloaded = AppPrefs(dirsOverride: dirs);
      await reloaded.load();
      expect(reloaded.pageMode, PageTurnMode.simulation);
      expect(reloaded.xrayHighlight, isFalse);
    });
  });

  group('ChapterPaginatorCache LRU', () {
    test('evicts least-recently-used pages and promotes on hit', () {
      final cache = ChapterPaginatorCache(maxPageEntries: 2, maxTextEntries: 2);
      const p1 = [PageSlice(0, 100)];
      const p2 = [PageSlice(0, 200)];
      const p3 = [PageSlice(0, 300)];

      cache.putPages('k1', p1);
      cache.putPages('k2', p2);
      // Access k1 so k2 becomes the oldest
      expect(cache.getPages('k1'), p1);
      expect(cache.hitCount, 1);

      cache.putPages('k3', p3);
      expect(cache.pageEntryCount, 2);
      expect(cache.hasPages('k1'), isTrue);
      expect(cache.hasPages('k2'), isFalse);
      expect(cache.hasPages('k3'), isTrue);

      expect(cache.getPages('missing'), isNull);
      expect(cache.missCount, 1);

      expect(cache.tryStartPreload('k1'), isFalse); // already cached
      expect(cache.tryStartPreload('k4'), isTrue);
      expect(cache.tryStartPreload('k4'), isFalse); // in flight
      cache.finishPreload('k4');
      expect(cache.tryStartPreload('k4'), isTrue);

      cache.invalidateLayout();
      expect(cache.pageEntryCount, 0);
    });
  });

  group('X-Ray tightened false-positive filtering', () {
    test('rejects ordinary phrases like 里划出, 随即, 电车穿过隧道', () {
      final chapters = List.generate(
        4,
        (i) => '''
　　夜色里划出：「一阵微光。」
　　电车穿过隧道：「轰隆作响。」
　　随即说：「窗外下起了雪。」
　　随后问道：「前面就是站台吗？」
　　西蒙特说：「我们到了。」
　　海因里希问道：「行李都带齐了吗？」
''',
      );

      final index = buildXrayIndex(chapters);
      final names = index.entities.map((e) => e.name).toSet();

      expect(names, contains('西蒙特'));
      expect(names, contains('海因里希'));
      expect(names.any((n) => n.contains('划出')), isFalse);
      expect(names.any((n) => n.contains('随即')), isFalse);
      expect(names.any((n) => n.contains('电车')), isFalse);
      expect(names.any((n) => n.contains('隧道')), isFalse);
      expect(names.any((n) => n.contains('穿过')), isFalse);
      expect(names.any((n) => n.contains('随后')), isFalse);
    });
  });

  group('Harmonized Reader Chrome & Settings Panel', () {
    test(
      'ReaderChromePalette matches ReaderBg brightness across all themes',
      () {
        final lightScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFFE86A92),
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFFE86A92),
          brightness: Brightness.dark,
        );

        for (final bg in kReaderBgs.take(4)) {
          final p = ReaderChromePalette.from(bg, lightScheme);
          expect(
            p.isDark,
            isFalse,
            reason: '${bg.name} should use light chrome',
          );
          expect(p.surface.computeLuminance(), greaterThan(0.65));
        }
        for (final bg in kReaderBgs.skip(4)) {
          final p = ReaderChromePalette.from(bg, darkScheme);
          expect(p.isDark, isTrue, reason: '${bg.name} should use dark chrome');
          expect(p.surface.computeLuminance(), lessThan(0.15));
        }
      },
    );

    testWidgets('ReaderTopBar and ReaderBottomBar harmonize without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final book = Book(
        id: 'b1',
        title: '雪国',
        author: '川端康成',
        format: BookFormat.txt,
        path: '/tmp/snow.txt',
        chapters: [
          ChapterRef(title: '第一章 穿过县界长长的隧道', charCount: 1200),
          ChapterRef(title: '第二章 驹子', charCount: 1500),
        ],
      );

      var jumped = -1.0;
      await tester.pumpWidget(
        _wrap(
          Stack(
            children: [
              ReaderTopBar(
                visible: true,
                bg: kReaderBgs[0],
                frosted: false,
                book: book,
                chapterIndex: 0,
                offlineProgress: null,
                currentChapterUrl: null,
                annotationCount: 2,
                onBack: () {},
                onShowXray: () {},
                onShowAnnotations: () {},
                onShowChapters: () {},
              ),
              ReaderBottomBar(
                visible: true,
                bg: kReaderBgs[0],
                frosted: false,
                book: book,
                chapterIndex: 0,
                progress: 0.42,
                ttsActive: false,
                onPrevChapter: () {},
                onNextChapter: () {},
                onShowChapters: () {},
                onShowBookmarks: () {},
                onStartTts: () {},
                onShowSettings: () {},
                onJumpProgress: (v) => jumped = v,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('雪国'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(jumped, -1.0);
    });

    testWidgets(
      'ReaderSettingsPanel keeps 左右边距 on 1 crisp line and exposes 仿真 mode',
      (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 800 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        final prefs = AppPrefs();
        await tester.pumpWidget(
          _wrap(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ReaderSettingsPanel(prefs: prefs, compact: true),
            ),
          ),
        );
        await tester.pump();

        final marginText = find.text('左右边距');
        expect(marginText, findsOneWidget);
        final rect = tester.getRect(marginText);
        // Single-line 12.5px text is ~18-22px tall; wrapped 2 lines would be > 32px
        expect(
          rect.height,
          lessThan(28),
          reason: '左右边距 must remain on 1 crisp line without wrapping',
        );

        await tester.tap(find.text('更多'));
        await tester.pump();
        expect(find.text('仿真'), findsOneWidget);

        await tester.tap(find.text('仿真'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(prefs.pageMode, PageTurnMode.simulation);
        expect(tester.takeException(), isNull);
        prefs.dispose();
      },
    );
  });

  group('SimulationTurnView (paper_curl 3D page curl)', () {
    testWidgets('supports tap-to-turn and programmatic next/prev', (
      tester,
    ) async {
      PageCurlView.debugDisableShader = true;
      addTearDown(() => PageCurlView.debugDisableShader = false);

      final simKey = GlobalKey<SimulationTurnViewState>();
      var changedTo = 0;
      var toggledBars = 0;

      await tester.pumpWidget(
        _wrap(
          SimulationTurnView(
            key: simKey,
            itemCount: 3,
            initialPage: 0,
            backdrop: kReaderBgs[0].color,
            itemBuilder: (_, i) => Center(child: Text('第 ${i + 1} 页')),
            onPageChanged: (i) => changedTo = i,
            onSettled: () {},
            onBeyondNext: () {},
            onBeyondPrev: () {},
            onToggleBars: () => toggledBars++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 1 页'), findsOneWidget);

      // Programmatic next page
      simKey.currentState!.animateNext();
      await tester.pumpAndSettle();
      expect(changedTo, 1);
      expect(simKey.currentState!.currentPage, 1);

      // Tap center toggles bars
      final center = tester.getCenter(find.byType(SimulationTurnView));
      await tester.tapAt(center);
      await tester.pump();
      expect(toggledBars, 1);

      // Programmatic prev page
      simKey.currentState!.animatePrev();
      await tester.pumpAndSettle();
      expect(changedTo, 0);
    });
  });

  group('Annotations SQLite persistence, Quote Card, Image Viewer & textPurifier', () {
    test(
      'ReaderAnnotationStore persists highlights & notes in SakuraDatabase',
      () async {
        final db = await SakuraDatabase.open(
          dbPath: ':memory:',
          factory: databaseFactoryFfi,
        );
        addTearDown(db.close);

        final store = ReaderAnnotationStore(database: db);
        final now = DateTime.now().millisecondsSinceEpoch;
        final saved = await store.save(
          ReaderAnnotation(
            id: 'ann_1',
            bookId: 'book_1',
            chapterIndex: 0,
            startOffset: 10,
            endOffset: 30,
            quote: '穿过县界长长的隧道，便是雪国。',
            note: '开篇神来之笔',
            colorIndex: 1,
            kind: 'note',
            createdAt: now,
            updatedAt: now,
          ),
        );

        expect(store.highlightsAndNotes, hasLength(1));
        expect(saved.color, AnnotationColor.apricot);

        // Reload in a fresh store instance from SQLite
        final reloaded = ReaderAnnotationStore(database: db);
        await reloaded.loadForBook('book_1');
        expect(reloaded.highlightsAndNotes, hasLength(1));
        expect(reloaded.forChapter(0).first.note, '开篇神来之笔');
        expect(reloaded.forChapter(0).first.colorIndex, 1);

        await reloaded.remove('ann_1');
        expect(reloaded.highlightsAndNotes, isEmpty);
        expect(await db.countAnnotations(bookId: 'book_1'), 0);
      },
    );

    testWidgets(
      'ReaderAnnotationActionSheet saves highlight & triggers Ask AI callback',
      (tester) async {
        final store = ReaderAnnotationStore();
        String? aiExcerpt;

        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showReaderAnnotationActionSheet(
                    ctx,
                    bookId: 'b1',
                    bookTitle: '雪国',
                    author: '川端康成',
                    chapterIndex: 0,
                    chapterTitle: '第一章',
                    startOffset: 0,
                    endOffset: 15,
                    selectedText: '穿过县界长长的隧道，便是雪国。',
                    store: store,
                    onAskAi: (excerpt) => aiExcerpt = excerpt,
                  ),
                  child: const Text('打开批注'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开批注'));
        await tester.pumpAndSettle();

        expect(find.text('写批注'), findsOneWidget);
        expect(find.text('金句卡片'), findsOneWidget);
        expect(find.text('问小樱 (AI)'), findsOneWidget);

        await tester.tap(find.text('划线'));
        await tester.pumpAndSettle();
        expect(store.highlightsAndNotes, hasLength(1));

        // Open again and tap Ask AI
        await tester.tap(find.text('打开批注'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('问小樱 (AI)'));
        await tester.pumpAndSettle();
        expect(aiExcerpt, '穿过县界长长的隧道，便是雪国。');
      },
    );

    testWidgets('QuoteCardDialog renders editorial card & switches style', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const QuoteCardDialog(
            quote: '夜空下一片白茫茫。',
            note: '极简而深邃的意境',
            bookTitle: '雪国',
            author: '川端康成',
            chapterTitle: '第一章',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('金句书摘卡片'), findsOneWidget);
      expect(find.text('夜空下一片白茫茫。'), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);

      final chip = find.widgetWithText(ChoiceChip, '墨韵');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ReaderImageViewerPage renders InteractiveViewer cleanly', (
      tester,
    ) async {
      // 1x1 transparent PNG
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        _wrap(
          ReaderImageViewerPage(
            imageProvider: MemoryImage(pngBytes),
            caption: '插图一',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('插图一'), findsOneWidget);
    });

    testWidgets('ReaderPage applies optional textPurifier hook before display', (
      tester,
    ) async {
      late Directory tmp;
      late BookStore bookStore;
      late AppPrefs prefs;

      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('sakura_purifier_test');
        final txtFile = File('${tmp.path}/sample.txt');
        await txtFile.writeAsString(
          '第一章\n\n这里是正文内容。【广告请删除】阅读体验非常顺滑。',
          flush: true,
        );
        final dirs = AppDirs(files: tmp.path, cache: tmp.path);
        prefs = AppPrefs(dirsOverride: dirs);
        await prefs.load();
        prefs.setPageMode(PageTurnMode.scroll);
        bookStore = BookStore(dirsOverride: dirs);
        await bookStore.load();
        await bookStore.importFile(txtFile.path);
      });
      final bookId = bookStore.books.first.id;
      await tester.pumpWidget(
        _wrap(
          ReaderPage(
            store: bookStore,
            prefs: prefs,
            bookId: bookId,
            textPurifier: (text, {bookTitle, sourceUrl}) =>
                text.replaceAll('【广告请删除】', ''),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.textContaining('阅读体验非常顺滑').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.textContaining('阅读体验非常顺滑'), findsOneWidget);
      expect(find.textContaining('广告请删除'), findsNothing);

      // Unmount ReaderPage & drain timers so file handles close before cleanup
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      prefs.dispose();
      bookStore.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      });
    });
  });
}
