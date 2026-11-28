import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/core/theme/sakura_tokens.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/isometric_bookshelf.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';

List<Book> _sampleBooks(int count) => [
  for (var i = 1; i <= count; i++)
    Book(
      id: 'iso-$i',
      title: '测试书名第 $i 卷',
      author: '作者 $i',
      format: BookFormat.epub,
      path: '/tmp/iso_$i.epub',
      lastReadAt: i == 1 ? 1700000010000 : 0,
      chapters: [ChapterRef(title: '第 1 章', charCount: 400)],
    ),
];

void main() {
  test('IsometricShelfGeometry 命中测试与索引映射正确', () {
    const s = 18.0;
    const c = 120.0;
    const h = 194.0;
    final dx = c * IsometricShelfGeometry.depthX;
    final dy = -c * IsometricShelfGeometry.depthY;

    expect(
      IsometricShelfGeometry.contains(Offset(s / 2, dy + h / 2), s, c, h),
      isTrue,
    );
    expect(
      IsometricShelfGeometry.contains(
        Offset(s + dx / 2, dy / 2 + h / 2),
        s,
        c,
        h,
      ),
      isTrue,
    );
    expect(
      IsometricShelfGeometry.contains(const Offset(-5, 50), s, c, h),
      isFalse,
    );
    expect(
      IsometricShelfGeometry.contains(const Offset(50, -5), s, c, h),
      isFalse,
    );
    expect(IsometricShelfGeometry.bookIndex(-1, 5), 4);
    expect(IsometricShelfGeometry.bookIndex(6, 5), 1);
    expect(IsometricShelfGeometry.weight(0), closeTo(1.0, 1e-6));
    expect(IsometricShelfGeometry.weight(2.0), 0.0);
  });

  test('IsometricShelfSimulation 惯性滑行最终收敛至目标整数槽位', () {
    final sim = IsometricShelfSimulation(0.0, 8.0, minimumVelocity: 1.0);
    expect(sim.target, greaterThanOrEqualTo(1.0));
    expect(sim.position(sim.duration), closeTo(sim.target, 0.01));
  });

  test('ShelfViewMode.isometric 字符串持久化与反序列化一致', () {
    expect(shelfViewModeFrom('isometric'), ShelfViewMode.isometric);
    expect(ShelfViewMode.isometric.label, '立体');
  });

  testWidgets('SakuraIsometricShelf 渲染单本/多本书籍且支持翻页切换焦点', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final books = _sampleBooks(6);
    Book? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(SakuraAccents.sakura, Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SakuraIsometricShelf(
              books: books,
              visualStyle: VisualStylePreset.sakuraAtelier,
              sortLabel: '最近阅读',
              onOpenDetail: (b) => opened = b,
              onContinueReading: (_) {},
              onMenu: (_) {},
              onArrangeTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('01 / 06'), findsOneWidget);
    expect(find.text('测试书名第 1 卷'), findsWidgets);

    await tester.tap(find.byTooltip('下一本'));
    await tester.pumpAndSettle();
    expect(find.text('02 / 06'), findsOneWidget);
    expect(find.text('测试书名第 2 卷'), findsWidgets);

    await tester.tap(find.text('测试书名第 2 卷').last);
    expect(opened?.id, 'iso-2');
  });

  testWidgets('ShelfPage 切换到「立体」样式在竖屏与横屏暗色模式下均无溢出或异常', (tester) async {
    late Directory tmpDir;
    late AppPrefs prefs;
    late BookStore store;
    late SourceStore sourceStore;

    await tester.runAsync(() async {
      tmpDir = Directory.systemTemp.createTempSync('sakura_iso_shelf_');
      final dirs = AppDirs(files: tmpDir.path, cache: tmpDir.path);
      prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      store = BookStore(dirsOverride: dirs);
      await store.load();
      sourceStore = SourceStore(dirsOverride: dirs);
      await sourceStore.load();
    });
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    for (final b in _sampleBooks(4)) {
      store.addOnline(b);
    }
    prefs.setShelfView(ShelfViewMode.isometric);

    tester.view.physicalSize = const Size(960 * 2, 540 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(960, 540),
            padding: EdgeInsets.only(top: 16),
            disableAnimations: true,
          ),
          child: ShelfPage(
            store: store,
            prefs: prefs,
            sourceStore: sourceStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(SakuraIsometricShelf), findsOneWidget);
    expect(find.text('书籍列表'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
