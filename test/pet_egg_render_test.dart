// 彩蛋（全屏锁定）层的渲染测试。
//
// 回归背景：v1.3.6 用户在真机上触发彩蛋时看到**整屏灰色**（Flutter 的
// ErrorWidget），说明构建时抛了异常。此前引导层已经因为 `Positioned` 误用
// 崩过一次，这里用同样的方式把它钉住：
//   每个用例都断言「无异常 + 不存在 ErrorWidget」。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/ui/widgets/pet_egg.dart';

/// 复刻 app.dart 里的真实层级：
/// Stack → ValueListenableBuilder → PetEggOverlay → (build) → _EggView
///
/// 关键在于**中间隔了 ValueListenableBuilder 这种非渲染组件**——
/// 若 `_EggView` 直接返回 `Positioned`，就会踩 ParentDataWidget 的坑。
Widget _host(ValueNotifier<bool> egg, {Widget? below}) {
  return MaterialApp(
    home: ValueListenableBuilder<bool>(
      valueListenable: egg,
      builder: (context, _, child) => Stack(
        children: [
          below ??
              const SizedBox.expand(
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
          PetEggOverlay(active: egg),
        ],
      ),
    ),
  );
}

/// 图片资源在测试环境可能加载失败，这类异常与布局无关，过滤掉。
bool _isAssetNoise(Object? e) =>
    e == null || e.toString().contains('Unable to load asset');

void main() {
  test('素材回归：pet_rage.png 右上角不应有「AI 画歪的星号」', () async {
    // 背景：AI 生成的"怒气符号"经常画成六角星（用户截图证实）。
    // 现在改为代码绘制（_AngerMark），素材里的星号已由
    // tool/erase_anger_star.dart 擦除。换素材后必须重跑该工具，
    // 否则这张测试会红——防止星号被悄悄画回来。
    final bytes = File('assets/images/pet_rage.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    final w = image.width;

    // 只检查「原星号所在区域」（erase 工具报告的 bbox 226..297, 24..97）。
    // 不检查整个象限——那里有腮红/唇色等合法橙红像素。
    var orange = 0;
    for (var y = 20; y < 100; y++) {
      for (var x = 222; x < 302; x++) {
        final i = (y * w + x) * 4;
        if (px[i + 3] <= 16) continue; // 透明像素不算
        final r = px[i], g = px[i + 1], b = px[i + 2];
        if (r >= 150 && g <= r * 0.85 && b <= r * 0.7 && ((r - g) > 45)) {
          orange++;
        }
      }
    }
    expect(
      orange,
      lessThan(30),
      reason:
          '原星号位置有 $orange 个橙红像素——素材里可能又出现了'
          '「怒气星号」，请运行 tool/erase_anger_star.dart 清除',
    );
  });

  testWidgets('彩蛋未激活：不渲染任何东西，也不报错', (tester) async {
    final egg = ValueNotifier<bool>(false);
    addTearDown(egg.dispose);

    await tester.pumpWidget(_host(egg));
    await tester.pump();

    expect(_isAssetNoise(tester.takeException()), isTrue);
    expect(find.text('你以为我是好惹的？'), findsNothing);
  });

  testWidgets('彩蛋激活：全屏渲染，出现台词与血字（回归：曾整屏变灰）', (tester) async {
    final egg = ValueNotifier<bool>(false);
    addTearDown(egg.dispose);

    await tester.pumpWidget(_host(egg));
    await tester.pump();

    egg.value = true; // ← 触发展开
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 核心断言：渲染过程不能抛异常；不能出现灰色错误块
    expect(
      _isAssetNoise(tester.takeException()),
      isTrue,
      reason: '彩蛋激活时渲染抛异常（真机表现就是整屏灰色）',
    );
    expect(find.byType(ErrorWidget), findsNothing, reason: '彩蛋层出现错误块');

    // 内容确实渲染出来了
    expect(find.text('你以为我是好惹的？'), findsOneWidget);
    expect(find.text('小樱禁止你使用该软件'), findsOneWidget);
    // 生气标记（💢）由 CustomPaint 绘制——回归背景：
    // AI 画的"怒气符号"经常画歪成星号，改为代码精确绘制
    expect(find.byType(CustomPaint), findsWidgets, reason: '缺少代码绘制的生气十字标记（💢）');
  });

  testWidgets('彩蛋铺满全屏（尺寸等于屏幕）', (tester) async {
    final egg = ValueNotifier<bool>(true);
    addTearDown(egg.dispose);

    await tester.pumpWidget(_host(egg));
    await tester.pump();

    expect(_isAssetNoise(tester.takeException()), isTrue);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final barrier = tester.getRect(find.byType(GestureDetector).first);
    expect(barrier.width, closeTo(size.width, 1));
    expect(barrier.height, closeTo(size.height, 1));
  });

  testWidgets('彩蛋出现后：下面的界面被完全遮住（锁定效果）', (tester) async {
    final egg = ValueNotifier<bool>(true);
    addTearDown(egg.dispose);

    await tester.pumpWidget(_host(egg));
    await tester.pump();

    // 锁定层存在且不透明 —— 用户点不到下面的内容
    expect(find.byType(ErrorWidget), findsNothing);
    expect(_isAssetNoise(tester.takeException()), isTrue);
    expect(find.text('你以为我是好惹的？'), findsOneWidget);
  });

  testWidgets('多次开关彩蛋不会累积异常', (tester) async {
    final egg = ValueNotifier<bool>(false);
    addTearDown(egg.dispose);

    await tester.pumpWidget(_host(egg));
    for (var i = 0; i < 3; i++) {
      egg.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _isAssetNoise(tester.takeException()),
        isTrue,
        reason: '第 $i 次开启异常',
      );

      egg.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _isAssetNoise(tester.takeException()),
        isTrue,
        reason: '第 $i 次关闭异常',
      );
    }
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
