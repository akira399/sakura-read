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
/// 为什么用代码画而不是用素材里的：
/// AI 画的"怒气符号"经常画歪（画成星号 ❋ 或六角星 ✳），反而破坏表情。
/// 直接用代码精确绘制四臂十字（每臂端头带小圆帽），保证效果可控。
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
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    // 垂直臂比水平臂略长（经典 💢 比例）
    const armV = 28.0;
    const armH = 24.0;
    const t = 6.5; // 臂粗的一半
    const r = 4.5; // 端头圆帽半径

    final paint = Paint()
      ..color =
          const Color(0xFFD22B2B) // 经典动漫怒红
      ..style = PaintingStyle.fill;

    // 底层阴影（暗红）——让符号在浅色背景下也能看清
    final shadow = Paint()
      ..color = const Color(0xFF3A070C).withValues(alpha: .55)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (final p in [shadow, paint]) {
      final path = Path()
        // ── 垂直上臂 ──
        ..moveTo(cx - t, cy - armV + r)
        ..quadraticBezierTo(cx - t, cy - armV, cx, cy - armV)
        ..quadraticBezierTo(cx + t, cy - armV, cx + t, cy - armV + r)
        ..lineTo(cx + t, cy - t)
        // ── 水平右臂 ──
        ..lineTo(cx + armH - r, cy - t)
        ..quadraticBezierTo(cx + armH, cy - t, cx + armH, cy)
        ..quadraticBezierTo(cx + armH, cy + t, cx + armH - r, cy + t)
        ..lineTo(cx + t, cy + t)
        // ── 垂直下臂 ──
        ..lineTo(cx + t, cy + armV - r)
        ..quadraticBezierTo(cx + t, cy + armV, cx, cy + armV)
        ..quadraticBezierTo(cx - t, cy + armV, cx - t, cy + armV - r)
        ..lineTo(cx - t, cy + t)
        // ── 水平左臂 ──
        ..lineTo(cx - armH + r, cy + t)
        ..quadraticBezierTo(cx - armH, cy + t, cx - armH, cy)
        ..quadraticBezierTo(cx - armH, cy - t, cx - armH + r, cy - t)
        ..lineTo(cx - t, cy - t)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_AngerMarkPainter oldDelegate) => false;
}

/// 彩蛋立绘：直接使用「生气差分」原图表达情绪。
///
/// 为什么不做滤镜加工：
/// 之前试过在图片上叠「上半脸黑色阴影带」+ 降饱和来硬凑压迫感，
/// 结果是一条生硬的黑条压在脸上，既不像阴影也很难看（用户明确反馈）。
/// 正确做法是让**素材本身**表达情绪（皱眉 / 鼓脸），
/// 渲染层只做轻微的氛围烘托（背景血色光晕 + 呼吸缩放）。
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
