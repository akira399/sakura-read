import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/pet_guide.dart';
import '../../data/pet_store.dart';
import 'pet_overlay.dart';

/// 桌宠新手引导的宿主：决定何时开始引导，并把结果写回设置。
///
/// - 只在「主机就绪（开屏结束 + 权限通过）」且未看过引导时启动一次；
/// - 引导中把桌宠隐藏（由引导层自己摆位，避免两个小樱）；
/// - 用户第 6 次不听话 → 触发全黑锁定彩蛋。
class PetGuideHost extends StatefulWidget {
  const PetGuideHost({
    super.key,
    required this.pet,
    required this.hostReady,
    required this.seen,
    required this.onSeen,
    this.enabled = true,
  });

  final PetStore pet;

  /// 是否可以开始引导（开屏结束 + 权限就绪）。
  final ValueListenable<bool> hostReady;

  /// 是否已经看过引导。
  final bool seen;

  /// 标记「已看过」。
  final VoidCallback onSeen;

  /// 是否允许开始引导（首次启动需先同意使用条款）。
  final bool enabled;

  @override
  State<PetGuideHost> createState() => _PetGuideHostState();
}

class _PetGuideHostState extends State<PetGuideHost> {
  late final PetGuideController _c = PetGuideController(
    onFinished: _onFinished,
    onPatienceRunOut: _onPatienceRunOut,
  );
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.hostReady.addListener(_maybeStart);
    kPetGuideReplay.addListener(_onReplayRequest);
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant PetGuideHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _maybeStart();
    // 「已看过」被重新打开（如同意条款时重置 guideSeen）：也允许开始，
    // 保证无论两个标记的更新次序如何，引导都能及时出现。
    if (!widget.seen && oldWidget.seen) _maybeStart();
  }

  @override
  void dispose() {
    widget.hostReady.removeListener(_maybeStart);
    kPetGuideReplay.removeListener(_onReplayRequest);
    _c.dispose();
    super.dispose();
  }

  void _maybeStart() {
    if (_started || !mounted) return;
    if (!widget.enabled) return; // 未同意首启条款：先不打扰
    if (!widget.hostReady.value) return;
    if (widget.seen && !_forceShow) return;
    _started = true;
    _c.start();
  }

  /// 测试 / 调试用开关（正常流程始终为 false）。
  final bool _forceShow = false;

  /// 设置页点了「重看新手引导」：绕过「已看过」限制，再播一遍。
  void _onReplayRequest() {
    if (!mounted || _c.active) return;
    if (!widget.enabled || !widget.hostReady.value) return;
    _started = true;
    _c.start();
  }

  void _onFinished() => widget.onSeen();

  void _onPatienceRunOut() {
    // 不耐烦了 → 直接锁屏（与生气彩蛋共用黑屏界面）
    _enterEgg();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (!_c.active) return const SizedBox.shrink();
        return PetGuideOverlay(controller: _c, pet: widget.pet);
      },
    );
  }
}

/// 进入全黑锁定彩蛋（引导耐心耗尽）。
void _enterEgg() {
  kPetEggActive.value = true;
}

/// 引导用的路由观察者。
///
/// 作用：让锚点知道自己**是否被新页面盖住**（push）或**重新露出**（pop）。
/// 有了它，引导就能安全地跨页面进行，例如：
///   点放大镜 →（跳到搜索页）→ 点返回 →（回书架）→ 点「＋」
/// 关键在于：搜索页盖住书架时，书架的锚点必须**撤销上报**，否则引导会指向
/// 一个"看不见的位置"（曾经踩过的坑，见 CHANGELOG v1.3.6）。
final RouteObserver<ModalRoute<void>> guideRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// 引导层：聚光灯 + 小樱指引气泡 + 跳过。
///
/// 实现要点：遮罩由「目标矩形之外的四块」组成，因此目标区域的手势会
/// 穿透到真实控件上——用户点的是真按钮，不是模拟点击。
class PetGuideOverlay extends StatelessWidget {
  const PetGuideOverlay({
    super.key,
    required this.controller,
    required this.pet,
  });

  final PetGuideController controller;
  final PetStore pet;

  static const _nagFaces = [
    'assets/images/pet_chibi.png',
    'assets/images/pet_chibi.png',
    'assets/images/pet_wave.png',
    'assets/images/pet_rage.png',
    'assets/images/pet_rage.png',
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final full = Offset.zero & media.size;
    final step = controller.step;
    final target = controller.anchorRect?.inflate(10);

    // ── 让路原则（功能要符合直觉，绝不把页面堵死）──
    // 1) 面板打开期间（hideWhileOpen）：完全收起，用户自由操作面板；
    // 2) 需要目标但目标暂不可见、也未"软化"：收起等待（目标出现即恢复；
    //    目标随页面消失则由 onAnchorCovered / onAnchorGone 接管推进）——
    //    之前这里会铺**全屏遮罩**去堵一个看不见的目标，把页面整个堵死；
    // 3) 自由参观（freeRoam）：只高亮 + 旁白，不铺遮罩、不计"不听话"。
    if (controller.suppressed) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    final needsTarget = step.hasAnchor;
    if (needsTarget &&
        target == null &&
        !controller.softened &&
        !step.freeRoam) {
      return const Positioned.fill(child: SizedBox.shrink());
    }

    // 遮罩：freeRoam 不铺；目标缺失（已软化）铺全屏（点任意处继续）；
    // 正常情况铺四块、给目标留孔（手势穿透到真实控件）。
    final List<Widget> barriers;
    if (step.freeRoam) {
      barriers = const [];
    } else if (target == null) {
      barriers = [_Barrier(rect: full, onTap: _onBarrierTap)];
    } else {
      barriers = [
        _Barrier(
          rect: Rect.fromLTRB(0, 0, full.width, target.top),
          onTap: _onBarrierTap,
        ),
        _Barrier(
          rect: Rect.fromLTRB(0, target.bottom, full.width, full.height),
          onTap: _onBarrierTap,
        ),
        _Barrier(
          rect: Rect.fromLTRB(0, target.top, target.left, target.bottom),
          onTap: _onBarrierTap,
        ),
        _Barrier(
          rect: Rect.fromLTRB(
            target.right,
            target.top,
            full.width,
            target.bottom,
          ),
          onTap: _onBarrierTap,
        ),
      ];
    }

    return Positioned.fill(
      // 必须包一层 Material：引导层挂在 MaterialApp 之上，
      // 若直接放裸 Text，会继承 MaterialApp 最外层的调试用 DefaultTextStyle
      // （红字 + 黄色双下划线），气泡文案下方就会出现"双黄线"。
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            ...barriers,
            if (target != null)
              // 目标高亮环（不吃手势）
              // 注意：Positioned 是 ParentDataWidget，必须是 Stack 的**直接子级**；
              // 所以 IgnorePointer 要放在 Positioned 里面（顺序反过来会抛断言，
              // 导致整个引导层渲染崩溃 —— 见 pet_guide_render_test 回归用例）。
              Positioned.fromRect(
                rect: target,
                child: const IgnorePointer(child: _SpotlightRing()),
              ),
            // ---- 小樱 + 气泡 ----
            _Bubble(
              target: target,
              full: full,
              text: controller.nagLine ?? controller.step.text,
              hint: controller.step.hasAnchor
                  ? (controller.nagLine == null ? controller.step.hint : '……')
                  : controller.step.hint,
              nagging: controller.nagLine != null,
              face:
                  _nagFaces[math.min(
                    controller.nagCount,
                    _nagFaces.length - 1,
                  )],
            ),
            // ---- 跳过按钮 ----
            // 放在**顶部居中**：右上角会和书架的放大镜/排列按钮重叠，
            // 容易造成误点与视觉遮挡（见 CHANGELOG v1.3.5）。
            Positioned(
              top: media.padding.top + 8,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: TextButton.icon(
                  onPressed: controller.skip,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .58),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.fast_forward_rounded, size: 17),
                  label: const Text(
                    '跳过引导',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onBarrierTap() {
    // 无目标步骤 / 目标已"软化"（锚点缺失）：点任意处都算继续；
    // 有目标步骤：点到非目标处 → 记一次"不听话"（劝导）。
    if (controller.step.hasAnchor && controller.anchorRect != null) {
      controller.reportWrong();
    } else {
      controller.advance();
    }
  }
}

class _Barrier extends StatelessWidget {
  const _Barrier({required this.rect, required this.onTap});

  final Rect rect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const ColoredBox(color: Color(0x99000000)),
      ),
    );
  }
}

/// 目标高亮：呼吸的粉色描边。
class _SpotlightRing extends StatefulWidget {
  const _SpotlightRing();

  @override
  State<_SpotlightRing> createState() => _SpotlightRingState();
}

class _SpotlightRingState extends State<_SpotlightRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Color.lerp(
              const Color(0xFFFF7EB6),
              const Color(0xFFFFF3F8),
              _c.value,
            )!,
            width: 2.4 + _c.value * 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFFFF7EB6,
              ).withValues(alpha: .25 + _c.value * .25),
              blurRadius: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// 小樱说话的气泡 + 立绘，自动避开目标区域。
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.target,
    required this.full,
    required this.text,
    required this.hint,
    required this.nagging,
    required this.face,
  });

  final Rect? target;
  final Rect full;
  final String text;
  final String? hint;
  final bool nagging;
  final String face;

  @override
  Widget build(BuildContext context) {
    final below = target == null || target!.center.dy < full.height * 0.55;
    final t = target;
    final bubble = _bubbleBox(context);
    final petBox = SizedBox(
      height: 132,
      child: Image.asset(face, fit: BoxFit.contain),
    );

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      children: below
          ? [petBox, const SizedBox(height: 8), bubble]
          : [bubble, const SizedBox(height: 8), petBox],
    );

    // 水平：尽量对齐目标中心，并夹在屏幕内
    final width = 300.0;
    var left = t == null ? (full.width - width) / 2 : t.center.dx - width / 2;
    left = left.clamp(12.0, math.max(12.0, full.width - width - 12));

    // 垂直
    double? top;
    double? bottom;
    if (below) {
      top = t == null ? full.height * 0.26 : t.bottom + 16;
      // 目标太靠下时改为贴底部上方
      if (top > full.height * 0.42) top = null;
      if (top == null) bottom = 24;
    } else {
      bottom = full.height - t!.top + 16;
    }

    return Positioned(
      left: left,
      top: top,
      bottom: bottom,
      width: width,
      child: IgnorePointer(
        // 气泡自身**不吃手势**：点击穿透到下面的遮罩，走统一逻辑
        // （无目标步骤 → 继续；有目标步骤 → 记"点错地方"）。
        // 之前这里是 false，气泡把点击吞掉却什么都不做——
        // 用户点"点一下继续"的对话框毫无反应（曾被反馈"不符合直觉"）。
        ignoring: true,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey('$text|$hint|$face'),
            child: column,
          ),
        ),
      ),
    );
  }

  Widget _bubbleBox(BuildContext context) {
    final accent = nagging ? const Color(0xFFFF4D6A) : const Color(0xFFFF7EB6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                nagging
                    ? Icons.sentiment_very_dissatisfied_rounded
                    : Icons.favorite_rounded,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                nagging ? '小樱（有点火）' : '小樱',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: Color(0xFF33202A),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                hint!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 锚点上报：把控件在屏幕上的真实位置告诉引导控制器。
///
/// 用 [Listener]（不消费手势）在目标被按下时推进引导，因此用户点到的
/// 始终是真实控件本身。
class PetGuideAnchor extends StatefulWidget {
  const PetGuideAnchor({
    super.key,
    required this.id,
    required this.controller,
    required this.child,
    this.rectOf,
  });

  final String id;
  final PetGuideController controller;
  final Widget child;

  /// 自定义上报矩形（默认整个子控件）；用于「只标底部栏的第三格」这类场景。
  final Rect Function(Size size)? rectOf;

  @override
  State<PetGuideAnchor> createState() => _PetGuideAnchorState();
}

class _PetGuideAnchorState extends State<PetGuideAnchor> with RouteAware {
  final GlobalKey _key = GlobalKey();

  /// 当前是否被其它页面盖住（盖住时不上报锚点，避免高亮框飘在看不见的位置）。
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeRoute();
      _report();
    });
  }

  /// 订阅路由事件（进入 / 返回本页时更新遮挡状态）。
  void _subscribeRoute() {
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      guideRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // 本页被新页面 / 弹出面板盖住（如点放大镜进入搜索页）
    // 注意：面板步骤的"收起"由 onTargetTapped 驱动（点击即收起），
    // 这里只处理锚点位置的注销。
    _covered = true;
    widget.controller.unregisterAnchor(widget.id);
    if (mounted) setState(() {});
  }

  @override
  void didPopNext() {
    // 上层页面 / 面板退出，本页重新露出（如从搜索页返回、关掉导入面板）
    _covered = false;
    if (mounted) {
      setState(() {});
      _report();
    }
    widget.controller.onAnchorRevealed(widget.id);
  }

  @override
  void dispose() {
    guideRouteObserver.unsubscribe(this);
    widget.controller.unregisterAnchor(widget.id);
    // 目标控件被销毁（所在页面关闭）→ 若引导正指着它，视为完成。
    // 典型场景：要你点搜索页返回箭头，你却用了系统返回键。
    widget.controller.onAnchorGone(widget.id);
    super.dispose();
  }

  void _report() {
    if (!mounted || _covered) return;
    final ctx = _key.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = widget.rectOf?.call(box.size) ?? (Offset.zero & box.size);
    widget.controller.registerAnchor(widget.id, rect.shift(origin));
  }

  @override
  Widget build(BuildContext context) {
    if (!_covered) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
    return Listener(
      // 判定必须在点击当下做（controller 内部读取当前步骤）。
      // 之前在 build 里缓存 isCurrent，引导推进时锚点组件不重建 →
      // 缓存过期，用户点对了却被漏判（曾造成"点了放大镜却卡在原地"）。
      onPointerDown: (_) => widget.controller.onTargetTapped(widget.id),
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}

/// 便捷锚点：只在引导进行中才挂 [PetGuideAnchor]（其余时候零开销）。
///
/// 用法：把要指引的控件包一层即可，例如
/// `PetGuideTarget(id: 'shelf_search', child: IconButton(...))`。
class PetGuideTarget extends StatelessWidget {
  const PetGuideTarget({
    super.key,
    required this.id,
    required this.child,
    this.rectOf,
  });

  final String id;
  final Widget child;

  /// 自定义上报矩形（默认整个子控件）。
  final Rect Function(Size size)? rectOf;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: kPetGuideActive,
      builder: (context, active, _) {
        final c = PetGuideController.current;
        if (!active || c == null) return child;
        return PetGuideAnchor(
          id: id,
          controller: c,
          rectOf: rectOf,
          child: child,
        );
      },
    );
  }
}
