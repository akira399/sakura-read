// 引导锚点「帧级位置跟踪」回归测试。
//
// 回归背景（用户截图反馈「粉色高亮框飘在屏幕中间、看不到＋」）：
// 从搜索页（键盘弹起）返回书架的那一刻，引导推进到「点「＋」」步骤；
// 锚点在页面回退的瞬间上报了一次坐标（此时「＋」仍停在**被键盘顶起**
// 的位置）。随后键盘收起、「＋」落回右下角，但锚点只在 build / 路由回调
// 时上报位置——而动画期间锚点子树并不重建，于是没有任何机制重新上报，
// 高亮框永久定格在错误位置（y 方向偏差 ≈ 键盘高度）。
//
// 修复：锚点在引导进行期间**逐帧**重报位置（位置未变时 controller 内部
// 去重，不会造成额外重建）。
//
// 本测试用「不重建子树、纯位移动画」复现该场景（与真实的「键盘顶起 FAB」
// 一致：位置变了，但锚点不重建）：
//   - 修复前：动画结束后锚点仍停在初始位置 → 测试失败；
//   - 修复后：动画进行中即开始跟随，结束后停在最终位置。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/ui/widgets/pet_guide_overlay.dart';

/// 一个可编程移动的容器：用 Transform 位移（不改子树、不触发重建）。
class _Mover extends StatefulWidget {
  const _Mover({super.key, required this.child});

  final Widget child;

  @override
  State<_Mover> createState() => _MoverState();
}

class _MoverState extends State<_Mover> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      // 注意：child 为缓存子树 —— 动画期间**不会重建**
      // （这正是真实的「键盘顶起 FAB」场景：位置变了，但锚点不重建）。
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, -240 * c.value), child: child),
      child: widget.child,
    );
  }
}

void main() {
  testWidgets('目标移动（子树不重建）时，锚点位置必须逐帧跟随', (tester) async {
    final ctrl = PetGuideController();
    addTearDown(ctrl.dispose);
    ctrl.start(); // 置 kPetGuideActive = true，锚点才会挂载

    final moverKey = GlobalKey<_MoverState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 100,
                top: 500,
                width: 56,
                height: 56,
                child: _Mover(
                  key: moverKey,
                  child: PetGuideTarget(
                    id: 'moving_target',
                    child: const ColoredBox(color: Color(0xFFFF7EB6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final before = ctrl.rectOf('moving_target');
    expect(before, isNotNull, reason: '锚点应已上报初始位置');
    expect(before!.top, closeTo(500, 1), reason: '初始位置应在上报坐标 (100,500)');

    // 模拟「键盘收起、＋落回」：纯位移，不重建锚点子树
    moverKey.currentState!.c.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final mid = ctrl.rectOf('moving_target');
    expect(
      mid!.top,
      lessThan(before.top - 60),
      reason: '动画进行中锚点就应开始跟随（修复前这里完全不更新）',
    );

    await tester.pump(const Duration(milliseconds: 200)); // 动画完成
    await tester.pump();
    final after = ctrl.rectOf('moving_target');
    expect(
      after!.top,
      closeTo(500 - 240, 1.5),
      reason: '动画结束后锚点必须停在最终位置（修复前会定格在初始位置）',
    );

    // 收尾：停掉引导（清定时器）并卸载
    ctrl.skip();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
