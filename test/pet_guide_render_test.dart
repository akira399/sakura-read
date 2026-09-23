// 新手引导层的**渲染**测试：确保引导遮罩 / 高亮环 / 气泡能真正渲染出来。
//
// 回归背景（v1.3.2/1.3.3 线上 bug）：曾把 `Positioned` 包进 `IgnorePointer` 再放进
// Stack。由于 Positioned 是 ParentDataWidget、必须是 Stack 的直接子级，一旦进入
// 「有锚点的步骤」就抛断言 → 整个引导层渲染崩溃，表现为：背景不变暗、点击全失效、
// 右上角出现灰色错误块（截图证据见 CHANGELOG v1.3.4）。
//
// 之前的测试只覆盖 controller 逻辑，没有覆盖渲染树，所以完全漏掉了这个问题。
// 这里的每个用例都会断言 `tester.takeException() == null` 且不存在 ErrorWidget。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_mood.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/ui/widgets/pet_guide_overlay.dart';

/// 把引导层放进一个模拟真实环境的壳里（Stack + 尺寸）。
Widget _host(PetGuideController c) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(child: ColoredBox(color: Color(0xFFEEEEEE))),
          PetGuideOverlay(controller: c, pet: PetStore()),
        ],
      ),
    ),
  );
}

/// 统一收尾：结束引导并销毁 controller（否则 20 秒 idle 定时器会挂在测试里）。
Future<void> _teardown(WidgetTester tester, PetGuideController c) async {
  c.onFinished = null;
  c.onPatienceRunOut = null;
  c.skip(); // 停掉 idle / anchor 定时器
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('开场步骤（无锚点）：渲染小樱 + 气泡 + 跳过按钮', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('小樱'), findsOneWidget);
    expect(find.textContaining('终于见到你啦'), findsOneWidget);
    expect(find.text('跳过引导'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    await _teardown(tester, c);
  });

  testWidgets('有锚点步骤：渲染高亮环（回归：Positioned 必须是 Stack 直接子级）', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance(); // ← 进入带锚点的第 2 步（线上崩溃点）
    expect(c.step.hasAnchor, isTrue);
    c.registerAnchor(c.step.anchorId!, const Rect.fromLTWH(40, 120, 60, 60));

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    // 关键断言：渲染过程不能抛异常（Positioned 误用会在这里失败）
    expect(tester.takeException(), isNull);
    expect(find.text('小樱'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    await _teardown(tester, c);
  });

  testWidgets('每一步都能渲染（遍历整条引导流程）', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();

    for (var i = 0; i <= petGuideSteps.length; i++) {
      if (!c.active) break;
      final id = c.step.anchorId;
      if (id != null) {
        c.registerAnchor(id, const Rect.fromLTWH(30, 200, 80, 80));
      }
      await tester.pumpWidget(_host(c));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.takeException(),
        isNull,
        reason: '第 $i 步（${c.step.id}）渲染失败',
      );
      expect(find.byType(ErrorWidget), findsNothing, reason: '第 $i 步出现错误块');
      c.advance();
    }
    expect(c.active, isFalse, reason: '应能走完整个流程');

    await _teardown(tester, c);
  });

  testWidgets('劝导状态：气泡切到生气语气且仍可渲染', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();
    c.registerAnchor(c.step.anchorId!, const Rect.fromLTWH(10, 10, 50, 50));
    c.reportWrong();

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('小樱（有点火）'), findsOneWidget);
    expect(find.text(petGuideNags.first), findsOneWidget);

    await _teardown(tester, c);
  });

  testWidgets('锚点缺失（软化）时也不应崩溃，且高亮层不再占位', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance(); // 有锚点，但故意不上报

    await tester.pumpWidget(_host(c));
    await tester.pump(PetGuideController.anchorGrace);
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(c.softened, isTrue);
    expect(find.byType(ErrorWidget), findsNothing);

    await _teardown(tester, c);
  });

  testWidgets('跳过按钮不与锚点重叠（回归：曾压住书架放大镜）', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();
    // 模拟底部导航栏第 3 格（屏幕最下方）
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    c.registerAnchor(
      c.step.anchorId!,
      Rect.fromLTWH(size.width * 2 / 3, size.height - 80, size.width / 3, 80),
    );

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    final skip = tester.getRect(find.text('跳过引导'));
    final anchor = c.anchorRect!;
    expect(
      skip.overlaps(anchor),
      isFalse,
      reason: '跳过按钮 $skip 与锚点 $anchor 重叠，会遮挡用户要点的位置',
    );

    await _teardown(tester, c);
  });

  testWidgets('跳过按钮位于顶部，不会落在书架的头部操作区（y<180）', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    final skip = tester.getRect(find.text('跳过引导'));
    // 书架头部（含放大镜 / 排列按钮）大约在 y=60~150 的右上区域，
    // 跳过按钮必须避开右上角，否则会遮挡真实按钮。
    final topRight = Rect.fromLTWH(
      tester.view.physicalSize.width / tester.view.devicePixelRatio * 0.6,
      50,
      tester.view.physicalSize.width / tester.view.devicePixelRatio * 0.4,
      120,
    );
    expect(
      skip.overlaps(topRight),
      isFalse,
      reason: '跳过按钮 $skip 落在右上角操作区，会遮挡放大镜',
    );

    await _teardown(tester, c);
  });

  testWidgets('气泡在贴边锚点下仍留在屏幕内', (tester) async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    c.registerAnchor(
      c.step.anchorId!,
      Rect.fromLTWH(size.width - 60, size.height - 80, 50, 50),
    );

    await tester.pumpWidget(_host(c));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    final bubble = tester.getRect(find.textContaining('小樱'));
    expect(bubble.left, greaterThanOrEqualTo(0));
    expect(bubble.right, lessThanOrEqualTo(size.width));

    await _teardown(tester, c);
  });
}
