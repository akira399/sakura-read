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

/// 生气标记（💢）：动漫风格四臂十字。
///
/// 为什么用代码画而不是素材：
/// AI 画的"怒气符号"经常画歪（六角星/星号）。
/// 为什么不用复杂 Path：
/// 之前用 quadraticBezierTo 手写十字轮廓，控制点算错画成了六角星（用户截图证实）。
/// 这里改用「矩形 + 圆形」最简单的图元拼十字——形状 100% 可控，绝不会画歪。
class _AngerMark extends StatelessWidget {
  const _AngerMark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(44, 44), painter: _AngerMarkPainter());
  }
}

class _AngerMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..color = const Color(0xFFD22B2B);

    // ── 十字：两条矩形（竖臂比横臂略长，经典 💢 比例） ──
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 13, height: 52),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: 44, height: 13),
      paint,
    );

    // ── 臂端圆帽（让十字末端圆润） ──
    const tipR = 7.5;
    canvas.drawCircle(Offset(cx, cy - 25), tipR, paint);
    canvas.drawCircle(Offset(cx, cy + 25), tipR, paint);
    canvas.drawCircle(Offset(cx - 21, cy), tipR, paint);
    canvas.drawCircle(Offset(cx + 21, cy), tipR, paint);

    // 中心小圆（交点更饱满）
    canvas.drawCircle(Offset(cx, cy), 8, paint);
  }

  @override
  bool shouldRepaint(_AngerMarkPainter oldDelegate) => false;
}

/// 彩蛋立绘：直接使用「生气差分」原图表达情绪。
///
/// 之前用「上半脸黑色阴影带」+ 降饱和硬凑压迫感，结果是生硬黑条压在脸上，
/// 很难看（用户明确反馈）。正确做法：情绪由**素材本身**表达（皱眉/鼓脸），
/// 渲染层只做轻微氛围烘托（背景血色光晕 + 呼吸缩放）。
class _RagePet extends StatelessWidget {
  const _RagePet();

  @override
  Widget build(BuildContext context) {
    // 立绘原始比例 319x512，height=292 时显示宽度 ≈ 182，
    // Align(bottomCenter) 后立绘左边缘在 x≈55。
    // 💢 位置 = 原图星号中心 (261,60) 按 0.571 缩放 + 立绘偏移 → (204, 34)
    // （原星号已由 tool/erase_anger_star.dart 从素材中擦除）
    return SizedBox(
      height: 292,
      width: 292,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/images/pet_rage.png',
              height: 292,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          // 💢 生气十字标记（贴着头部右上，替换 AI 画歪的"星号"）
          const Positioned(left: 182, top: 12, child: _AngerMark()),
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
