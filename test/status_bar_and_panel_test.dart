// 本次 UI 改动的渲染 / 布局回归测试：
//   ① 不透明状态栏底块（StatusBarBackdrop）覆盖状态栏高度；
//   ② 阅读设置面板三页签：默认「排版」可见、切页后内容随之变化。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/reader/reader_settings_panel.dart';
import 'package:sakura_read/src/ui/widgets/status_bar_backdrop.dart';

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
  group('StatusBarBackdrop（不透明状态栏底块）', () {
    testWidgets('高度等于状态栏高度、颜色为不透明色', (tester) async {
      await tester.pumpWidget(
        _host(
          const Stack(
            children: [
              SizedBox.expand(),
              Positioned(top: 0, left: 0, right: 0, child: StatusBarBackdrop()),
            ],
          ),
        ),
      );

      final box = tester.getSize(find.byType(StatusBarBackdrop));
      expect(box.height, 40, reason: '底块高度应等于状态栏 padding.top');

      final colored = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(StatusBarBackdrop),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(colored.color.a, 1.0, reason: '必须是完全不透明色（а = 1.0）');
    });

    testWidgets('状态栏高度为 0 时不占位（不干扰布局）', (tester) async {
      await tester.pumpWidget(_host(const StatusBarBackdrop(), topPadding: 0));
      expect(find.byType(SizedBox), findsWidgets);
      final box = tester.getSize(find.byType(StatusBarBackdrop));
      expect(box, Size.zero);
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
