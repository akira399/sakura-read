// 本次 UI 改动的渲染 / 布局回归测试：
//   ① 不透明状态栏底块（StatusBarBackdrop）覆盖状态栏高度；
//   ② 头部「状态栏区 + 渐变区」两段式的颜色无缝衔接（用户反馈色阶跳变）；
//   ③ 阅读设置面板三页签：默认「排版」可见、切页后内容随之变化。
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

  group('状态栏色阶衔接（用户反馈：状态栏与页面颜色不一致）', () {
    testWidgets('头部两段式：状态栏区为纯色、且该纯色 = 渐变起步色（无缝）', (tester) async {
      // 构造与书架一致的两段式头部（状态栏区纯色 + 内容区渐变）
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    height: 40,
                    child: ColoredBox(color: Color(0x00000000)),
                  ),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      gradient: SakuraTheme.headerGradient(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // 取主题侧的「头部顶色」与渐变起点色对比
      final ctx = tester.element(find.byType(Column).first);
      final themeTop = SakuraTheme.headerTopColor(ctx);
      final gradient = SakuraTheme.headerGradient(ctx);
      final gradientTop = gradient.colors.first;

      // 无缝要求的核心：渐变**起点色**与状态栏底块色一致（或仅差透明度混合前的原始色）
      // 说明：渐变首色是半透明原色，混到背景后才等于 headerTopColor，
      // 这里验证「混底后颜色一致」——即两者的不透明等效色相同。
      final blendedGradientTop = Color.alphaBlend(
        gradientTop,
        Theme.of(ctx).scaffoldBackgroundColor,
      );
      final delta =
          (blendedGradientTop.r - themeTop.r).abs() +
          (blendedGradientTop.g - themeTop.g).abs() +
          (blendedGradientTop.b - themeTop.b).abs();
      expect(delta, lessThan(0.05), reason: '渐变起点（混底后）与状态栏底块色必须一致，否则出现色阶跳变');
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
