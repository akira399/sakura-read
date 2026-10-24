import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/pet_mood.dart';
import 'pet_overlay.dart' show kPetEggActive;

/// 彩蛋层：全黑锁定界面，正中阴沉脸桌宠 + 台词 + 血字。
///
/// 触发：生气第 4 次及以上按概率进入（见 `PetMood.escalate`）。
/// 出口：**长按 5 秒认错**（或 60 秒后自动放行）——曾经的「只能重启 App」
/// 让用户真的被锁在软件外面（酷安反馈「不让我用软件了」），已废弃。
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

class _EggView extends StatefulWidget {
  const _EggView();

  @override
  State<_EggView> createState() => _EggViewState();
}

class _EggViewState extends State<_EggView> {
  /// 长按多久算「认错」。
  static const Duration holdToRelease = Duration(seconds: 5);

  /// 兜底：无论如何都不会永久锁死。
  static const Duration autoRelease = Duration(seconds: 60);

  Timer? _holdTimer;
  Timer? _autoTimer;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _autoTimer = Timer(autoRelease, _release);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }

  void _release() {
    _holdTimer?.cancel();
    _autoTimer?.cancel();
    if (kPetEggActive.value) kPetEggActive.value = false;
  }

  void _onHoldStart(LongPressStartDetails _) {
    _holdTimer?.cancel();
    setState(() => _holding = true);
    _holdTimer = Timer(holdToRelease, _release);
  }

  void _onHoldEnd() {
    _holdTimer?.cancel();
    if (mounted && _holding) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // 全屏黑幕：吃掉背景手势（避免点穿到下面的书架），但保留自己的长按出口
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onDoubleTap: () {},
        onLongPressStart: _onHoldStart,
        onLongPressEnd: (_) => _onHoldEnd(),
        onLongPressCancel: _onHoldEnd,
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
                    const SizedBox(height: 34),
                    // 出口：长按认错（避免把用户真的锁在软件外面）
                    AnimatedOpacity(
                      opacity: _holding ? 1 : .55,
                      duration: const Duration(milliseconds: 160),
                      child: Column(
                        children: [
                          Text(
                            _holding ? '松手就前功尽弃了…' : '长按 5 秒认错',
                            style: const TextStyle(
                              color: Color(0xFFA98588),
                              fontSize: 12.5,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _holding ? 132 : 92,
                            height: 2,
                            decoration: BoxDecoration(
                              color: _holding
                                  ? const Color(0xFFFF2B45)
                                  : const Color(0xFF4A2226),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
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

/// 彩蛋立绘。
///
/// **故意不加任何"怒气符号"**：情绪由素材本身表达（皱眉 / 瞪眼 / 鼓脸）。
///
/// 历史（为什么不加）：
/// 曾尝试让 AI 画 💢 符号（画歪成六角星），又用代码绘制过三次
/// （贝塞尔路径画成六角星 → 矩形拼接但比例失衡像"医疗十字"），
/// 都无法稳定做出动漫风格的 💢。最终决定**去掉该符号**——
/// 立绘的生气表情已经足够清楚，符号是画蛇添足。
class _RagePet extends StatelessWidget {
  const _RagePet();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 292,
      child: Image.asset(
        'assets/images/pet_rage.png',
        height: 292,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
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
