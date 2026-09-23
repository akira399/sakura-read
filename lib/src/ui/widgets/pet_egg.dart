import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/pet_mood.dart';

/// 彩蛋层：全黑锁定界面（不可操作），正中只有阴沉脸桌宠 + 台词 + 血字。
///
/// 触发：生气第 4 次及以上按概率进入（见 `PetMood.escalate`）。
/// 退出：只有重启 App。
class PetEggOverlay extends StatelessWidget {
  const PetEggOverlay({super.key, required this.active});

  /// 是否激活（由 `kPetEggActive` 驱动）。
  final ValueListenable<bool> active;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (context, on, _) =>
          on ? const _EggView() : const SizedBox.shrink(),
    );
  }
}

class _EggView extends StatelessWidget {
  const _EggView();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // 全屏黑幕；本层吃掉所有手势 → 整个界面被锁定
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onDoubleTap: () {},
        onLongPress: () {},
        onVerticalDragStart: (_) {},
        onHorizontalDragStart: (_) {},
        child: Material(
          color: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 血色氛围（中心向外压暗，营造压迫感）
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.95,
                    colors: [Color(0x8C3A070C), Color(0xFF000000)],
                  ),
                ),
              ),
              // 四角暗角（把视线压向中间的角色）
              const _Vignette(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Pulse(child: _RagePet()),
                    const SizedBox(height: 26),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF120607),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF5A1A20),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF2B45,
                            ).withValues(alpha: .18),
                            blurRadius: 22,
                          ),
                        ],
                      ),
                      child: const Text(
                        petEggLine,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE8DCDD),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        petEggFooter,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFF2B45),
                          fontSize: 15,
                          height: 1.7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 8),
                            Shadow(color: Color(0xFFFF2B45), blurRadius: 14),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 阴沉脸立绘：在图片上叠一层"上半脸阴影"，强化病娇压迫感
/// （AI 素材的表情不够狠时，用渲染手段补足）。
class _RagePet extends StatelessWidget {
  const _RagePet();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 立绘（略微压暗 + 降饱和，营造阴冷）
          ImageFiltered(
            imageFilter: ui.ImageFilter.matrix(
              Float64List.fromList(<double>[
                0.82, 0, 0, 0, 0, //
                0, 0.72, 0, 0, 0, //
                0, 0, 0.78, 0, 0, //
                0, 0, 0, 1, 0, //
              ]),
            ),
            child: Image.asset(
              'assets/images/pet_rage.png',
              height: 260,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          // 上半脸阴影带（覆盖额头到眼睛区域）
          Positioned(
            top: 38,
            child: Container(
              width: 150,
              height: 62,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF000000).withValues(alpha: .92),
                    const Color(0xFF000000).withValues(alpha: .55),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 四周暗角。
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.75,
            colors: [Color(0x00000000), Color(0xCC000000)],
            stops: [0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 缓慢的呼吸缩放（让静止画面有一丝"活着"的压迫感）。
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
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
      builder: (context, child) => Transform.scale(
        scale: 1 + _c.value * 0.035,
        child: Opacity(opacity: 0.94 + _c.value * 0.06, child: child),
      ),
      child: widget.child,
    );
  }
}
