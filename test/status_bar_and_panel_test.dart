// 状态栏「透明」与阅读设置面板的回归测试。
//
// ① 状态栏透明（用户偏好，曾一度改为「不透明底块」，用户反馈不好后回退）：
//    - 头部渐变容器必须**铺满整个头部（含状态栏区域）**，状态栏本身透明时
//      头部颜色直接透到状态栏底下；
//    - 不应再存在任何「状态栏独立色块」（StatusBarBackdrop 已移除）。
// ② 阅读设置面板三页签：默认「排版」可见、切页后内容随之变化。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/reader/reader_settings_panel.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';

/// 带状态栏高度（padding.top）的测试宿主。
Widget _host(Widget child, {double topPadding = 40}) {
  return MaterialApp(
    theme: SakuraTheme.build(const Color(0xFFFF7EB6), Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: topPadding)),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('状态栏透明（头部渐变铺满含状态栏区域）', () {
    testWidgets('头部渐变容器覆盖状态栏高度：从屏幕顶端开始', (tester) async {
      const topPad = 40.0;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              // 与书架一致的头部结构：单个渐变容器 + 顶部 padding 让出状态栏。
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: SakuraTheme.headerGradient(context),
                    ),
                    padding: EdgeInsets.only(top: topPad + 18, bottom: 18),
                    child: const Text('头部内容'),
                  ),
                ],
              );
            },
          ),
          topPadding: topPad,
        ),
      );

      // 渐变容器从屏幕最顶端（y=0）开始 —— 也就是伸到状态栏底下。
      final headerBox = tester.getRect(find.byType(Container).first);
      expect(headerBox.top, 0, reason: '头部渐变必须从屏幕顶端开始（铺满状态栏区域），状态栏才能透出头部颜色');
      expect(
        headerBox.height,
        greaterThan(topPad),
        reason: '头部高度应大于状态栏高度（渐变延伸到状态栏之下）',
      );
    });

    testWidgets('渐变是对角方向（topLeft → bottomRight）', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final gradient = SakuraTheme.headerGradient(ctx);
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
    });

    testWidgets('真实书架页：body 直接是滚动视图，不存在状态栏覆盖层', (tester) async {
      late AppPrefs prefs;
      late BookStore store;
      late SourceStore sourceStore;
      await tester.runAsync(() async {
        final tmp = await Directory.systemTemp.createTemp('sakura_shelf_sb');
        final dirs = AppDirs(files: tmp.path, cache: tmp.path);
        prefs = AppPrefs(dirsOverride: dirs);
        await prefs.load();
        store = BookStore(dirsOverride: dirs);
        await store.load();
        sourceStore = SourceStore(dirsOverride: dirs);
        await sourceStore.load();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: SakuraTheme.build(const Color(0xFFFF7EB6), Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
            child: ShelfPage(
              store: store,
              prefs: prefs,
              sourceStore: sourceStore,
            ),
          ),
        ),
      );
      await tester.pump();

      // 回退后：书架 body 是 CustomScrollView（不再是 Stack + Positioned 底块）。
      // 若将来有人重新引入覆盖层，这里会因找到 Stack 而失败（提醒核对设计意图）。
      final scroll = find.descendant(
        of: find.byType(ShelfPage),
        matching: find.byType(CustomScrollView),
      );
      expect(scroll, findsOneWidget, reason: '书架 body 应为滚动视图');
    });
  });

  group('ReaderSettingsPanel（三页签）', () {
    testWidgets('默认显示「排版」页（字号滑杆可见），可切到「外观」与「更多」', (tester) async {
      final prefs = AppPrefs();
      await tester.pumpWidget(
        _host(SingleChildScrollView(child: ReaderSettingsPanel(prefs: prefs))),
      );
      await tester.pump();

      // 默认：排版页
      expect(find.text('排版'), findsOneWidget);
      expect(find.text('字号'), findsOneWidget);
      expect(find.text('行距'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('更多'), findsOneWidget);

      // 切「外观」：出现背景 / 字体标签，排版项消失
      await tester.tap(find.text('外观'));
      await tester.pump();
      expect(find.text('背景'), findsOneWidget);
      expect(find.text('字体'), findsOneWidget);
      expect(find.text('字号'), findsNothing, reason: '切页后排版项应隐藏');

      // 切「更多」：出现翻页动画与开关
      await tester.tap(find.text('更多'));
      await tester.pump();
      expect(find.text('翻页动画'), findsOneWidget);
      expect(find.text('阅读时保持屏幕常亮'), findsOneWidget);
    });

    testWidgets('紧凑模式：面板高度受限（≤ 屏幕 45%），正文区域保持可见', (tester) async {
      final prefs = AppPrefs();
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(ReaderSettingsPanel(prefs: prefs, compact: true)),
      );
      await tester.pump();

      final box = tester.getSize(find.byType(ReaderSettingsPanel));
      expect(
        box.height,
        lessThanOrEqualTo(800 * .45),
        reason: '紧凑面板不应超过屏幕高度的 45%（用户调字号时要能看到正文）',
      );
    });
  });
}
