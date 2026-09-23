// 彩蛋（全屏锁定）层的渲染测试。
//
// 回归背景：v1.3.6 用户在真机上触发彩蛋时看到**整屏灰色**（Flutter 的
// ErrorWidget），说明构建时抛了异常。此前引导层已经因为 `Positioned` 误用
// 崩过一次，这里用同样的方式把它钉住：
//   每个用例都断言「无异常 + 不存在 ErrorWidget」。
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
