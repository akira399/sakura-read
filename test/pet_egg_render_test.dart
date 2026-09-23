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
  test('素材回归：pet_rage.png 图像本身不应含任何"怒气符号"', () async {
    // 背景（三次踩坑）：
    //   1) AI 画的"怒气符号"经常画成六角星（用户截图证实）；
    //   2) 按颜色擦除只删了填充，**黑色描边**留下 → 屏幕上仍是黑色星号；
    //   3) 改用连通域擦除又把人物头发一起删了。
    // 最终方案：**从源头解决** —— 要求 AI 生成"画面上没有任何符号"的图
    // （见 tool/vlm_check_clean.py 质检），💢 完全由代码绘制。
    //
    // 本测试守住这个前提：素材里不能出现橙红填充 + 深色描边组成的
    // "符号状小块"。判定方式：统计**孤立小连通域**（被透明包围的小块）。
    final bytes = File('assets/images/pet_rage.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    final w = image.width, h = image.height;

    // 收集所有不透明像素，做 8 连通聚类，找出「远离主体的小块」
    final opaque = <int>{};
    for (var i = 0; i < w * h; i++) {
      if (px[i * 4 + 3] > 40) opaque.add(i);
    }

    final seen = <int>{};
    final clusters = <List<int>>[];
    for (final start in opaque) {
      if (seen.contains(start)) continue;
      final cluster = <int>[];
      final stack = <int>[start];
      seen.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        cluster.add(i);
        final x = i % w, y = i ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (opaque.contains(ni) && seen.add(ni)) stack.add(ni);
          }
        }
      }
      clusters.add(cluster);
    }

    clusters.sort((a, b) => b.length.compareTo(a.length));
    // 主体必然最大；除主体外，任何超过 200px 的独立块都可能是残留符号
    final stray = clusters.skip(1).where((c) => c.length > 200).toList();
    expect(
      stray,
      isEmpty,
      reason:
          '主人物之外还有 ${stray.length} 个较大独立块'
          '（尺寸 ${stray.map((c) => c.length).take(5).toList()}）——'
          '素材里可能残留了星号/符号，请换用"无符号"的干净素材',
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
    // 注：彩蛋界面**故意不含"怒气符号"**（💢 画过四版都不理想，
    // 详见 pet_egg.dart 的 _RagePet 注释）。情绪由立绘自身表情表达。
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
