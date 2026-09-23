import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 樱花花瓣飘落效果（纯 Canvas 绘制，开销很小）。
class SakuraPetals extends StatefulWidget {
  const SakuraPetals({
    super.key,
    this.count = 14,
    this.child,
    this.opacity = .8,
    this.colors,
  });

  final int count;
  final Widget? child;
  final double opacity;
  final List<Color>? colors;

  @override
  State<SakuraPetals> createState() => _SakuraPetalsState();
}

class _SakuraPetalsState extends State<SakuraPetals>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  late final List<_Petal> _petals = _makePetals();

  List<_Petal> _makePetals() {
    final rnd = math.Random(42);
    return List.generate(
      widget.count,
      (i) => _Petal(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        size: 6 + rnd.nextDouble() * 9,
        speed: .5 + rnd.nextDouble() * .8,
        sway: .4 + rnd.nextDouble(),
        phase: rnd.nextDouble() * math.pi * 2,
        spin: (rnd.nextDouble() - .5) * 2,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        widget.colors ??
        const [Color(0xFFFFB7C5), Color(0xFFFFD1DC), Color(0xFFE8B4FF)];
    return RepaintBoundary(
      child: Stack(
        children: [
          if (widget.child != null) Positioned.fill(child: widget.child!),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _PetalPainter(
                    _petals,
                    _controller.value,
                    colors,
                    widget.opacity,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Petal {
  const _Petal({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.sway,
    required this.phase,
    required this.spin,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double sway;
  final double phase;
  final double spin;
}

class _PetalPainter extends CustomPainter {
  _PetalPainter(this.petals, this.t, this.colors, this.opacity);

  final List<_Petal> petals;
  final double t;
  final List<Color> colors;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < petals.length; i++) {
      final p = petals[i];
      final ty = (p.y + t * p.speed) % 1.0;
      final y = ty * size.height * 1.1 - size.height * .05;
      final x =
          (p.x + math.sin(t * math.pi * 2 * p.sway + p.phase) * .05) *
          size.width;
      final rot = p.phase + t * p.spin * math.pi * 2;
      final alpha =
          opacity * (.55 + .45 * math.sin(t * math.pi * 2 + p.phase).abs());
      paint.color = colors[i % colors.length].withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size * .72,
          height: p.size,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) =>
      old.t != t || old.opacity != opacity;
}
