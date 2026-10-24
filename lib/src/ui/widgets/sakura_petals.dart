import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

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
  static const Duration _cycle = Duration(seconds: 14);

  /// 花瓣是背景装饰：30fps 已经足够顺滑，但能把「整屏重绘 + 底部毛玻璃重新
  /// 模糊」的开销直接砍半——手机上这段是书架/设置页掉帧的大头。
  static const Duration _frameStep = Duration(milliseconds: 33);

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  Duration _lastPaint = Duration.zero;
  bool _reducedMotion = false;

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
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统「移除动画 / 减少动态效果」：花瓣保持静止，不再产生逐帧重绘。
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      if (reduced) {
        _phase.value = .35;
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (_reducedMotion) return;
    if (elapsed - _lastPaint < _frameStep) return;
    _lastPaint = elapsed;
    _phase.value =
        (elapsed.inMicroseconds % _cycle.inMicroseconds) /
        _cycle.inMicroseconds;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        widget.colors ??
        const [Color(0xFFFFB7C5), Color(0xFFFFD1DC), Color(0xFFE8B4FF)];
    // 注意：RepaintBoundary 只能包住花瓣这一层。
    // 早先把整棵树（含页面内容）包进同一个 boundary，花瓣每帧重绘都会连带
    // 把整个页面重新光栅化一遍，书架/设置页因此掉帧明显。
    return Stack(
      children: [
        if (widget.child != null) Positioned.fill(child: widget.child!),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _phase,
                builder: (context, phase, _) => CustomPaint(
                  // 花瓣一直在动：声明 willChange 让光栅缓存不被反复失效。
                  painter: _PetalPainter(
                    _petals,
                    phase,
                    colors,
                    widget.opacity,
                  ),
                  willChange: true,
                ),
              ),
            ),
          ),
        ),
      ],
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
