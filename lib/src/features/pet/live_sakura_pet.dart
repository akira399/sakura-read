import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'pet_mood_bus.dart';

/// 将 8 种实时桌宠情绪映射到原本的 `assets/images/pet_*.png` 立绘差分。
String petSpriteForMood(PetLiveMood mood) => switch (mood) {
  PetLiveMood.idle => 'assets/images/pet_chibi.png',
  PetLiveMood.reading => 'assets/images/pet_read.png',
  PetLiveMood.happy => 'assets/images/pet_cheer.png',
  PetLiveMood.shy => 'assets/images/pet_shy.png',
  PetLiveMood.sleepy => 'assets/images/pet_sleep.png',
  PetLiveMood.pouting => 'assets/images/pet_angry.png',
  PetLiveMood.thinking => 'assets/images/pet_curious.png',
  PetLiveMood.speaking => 'assets/images/pet_encourage.png',
};

/// Live Interactive Pet 2.0：完整保留原本的 `assets/images/pet_*.png` 形象与全部立绘美术，
/// 在原图基础上叠加 60/120fps 丝滑呼吸弹性、视线/触控 3D 微倾跟随、差分平滑交叉淡入与环绕粒子动效。
class LiveSakuraPet extends StatefulWidget {
  const LiveSakuraPet({
    super.key,
    this.mood = PetLiveMood.idle,
    this.assetOverride,
    this.size = 76,
    this.lookTarget = Offset.zero,
    this.motionEnabled = true,
    this.showSparkles = false,
    this.peekingSide = 0,
    this.accentColor,
  });

  final PetLiveMood mood;

  /// 可选立绘覆盖（用于 `pet_wave.png` / `pet_dance.png` / `pet_snack.png` / `pet_tea.png` / `pet_stretch.png` 等原版专属动作差分）。
  final String? assetOverride;

  final double size;

  /// 归一化触控/拖拽跟随目标（x, y 均在 -1.0 ~ 1.0）。
  final Offset lookTarget;

  /// 是否启用连续动画（会同时尊重系统的减少动态效果设置）。
  final bool motionEnabled;

  /// 额外爆发飘心/星光（如摸头、投喂、升级瞬间）。
  final bool showSparkles;

  /// 贴边探头方向：-1 = 从左缘探头，1 = 从右缘探头，0 = 正常站姿。
  final int peekingSide;

  /// 可选主题强调色（默认樱绯 `#E86A92`）。
  final Color? accentColor;

  /// 当前实际渲染的原版立绘资源路径。
  String get resolvedAsset => assetOverride ?? petSpriteForMood(mood);

  @override
  State<LiveSakuraPet> createState() => _LiveSakuraPetState();
}

class _LiveSakuraPetState extends State<LiveSakuraPet>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _accent;
  late final AnimationController _moodPop;

  Offset _smoothLook = Offset.zero;
  bool _reduceMotion = false;

  bool get _animate => widget.motionEnabled && !_reduceMotion;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _accent = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _moodPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1.0,
    );
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant LiveSakuraPet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motionEnabled != widget.motionEnabled) {
      _syncControllers();
    }
    if ((oldWidget.mood != widget.mood ||
            oldWidget.assetOverride != widget.assetOverride) &&
        _animate) {
      _moodPop.forward(from: 0.0);
    }
    final target = Offset(
      widget.lookTarget.dx.clamp(-1.0, 1.0),
      widget.lookTarget.dy.clamp(-1.0, 1.0),
    );
    _smoothLook = Offset.lerp(_smoothLook, target, 0.45) ?? target;
  }

  void _syncControllers() {
    if (_animate) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
      if (!_accent.isAnimating) _accent.repeat();
    } else {
      _breath.stop();
      _accent.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _accent.dispose();
    _moodPop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      _syncControllers();
    }
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final target = Offset(
      widget.lookTarget.dx.clamp(-1.0, 1.0),
      widget.lookTarget.dy.clamp(-1.0, 1.0),
    );
    final asset = widget.resolvedAsset;
    final cachePx = (widget.size * 3).round().clamp(128, 512);
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';

    // 原版立绘 + 轮廓柔和阴影（保持原本的美术质感与剪影立体感）
    final spriteStack = AnimatedSwitcher(
      duration: Duration(milliseconds: _animate && !isTest ? 260 : 0),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      child: Stack(
        key: ValueKey<String>(asset),
        fit: StackFit.expand,
        children: [
          if (!isTest)
            Transform.translate(
              offset: const Offset(0, 3),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.13),
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    asset,
                    cacheHeight: cachePx,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          Image.asset(
            asset,
            cacheHeight: isTest ? null : cachePx,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ],
      ),
    );

    final animatedPet = RepaintBoundary(
      child: ColoredBox(
        color: Colors.transparent,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breath, _accent, _moodPop]),
            builder: (context, child) {
              _smoothLook = Offset.lerp(_smoothLook, target, 0.25) ?? target;
              final breathT = _animate ? _breath.value : 0.0;
              final breathWave = 1.0 - math.cos(breathT * math.pi); // 0..2
              final floatY = _animate ? -breathWave * 1.8 : 0.0;
              final scaleX = _animate ? 1.0 - (breathT - 0.5) * 0.018 : 1.0;
              final scaleY = _animate ? 1.0 + (breathT - 0.5) * 0.024 : 1.0;
              final pop = _animate
                  ? 1.0 + math.sin(_moodPop.value * math.pi) * 0.065
                  : 1.0;

              final peekShiftX = _animate && widget.peekingSide != 0
                  ? -widget.peekingSide * (breathWave * 1.8)
                  : 0.0;
              final tiltAngle =
                  (_smoothLook.dx * 0.08) +
                  (widget.peekingSide * -0.36) +
                  (widget.mood == PetLiveMood.thinking ? 0.05 : 0.0) +
                  (widget.mood == PetLiveMood.shy ? -0.04 : 0.0);

              final pivot = widget.peekingSide == 0
                  ? Alignment.bottomCenter
                  : Alignment(widget.peekingSide < 0 ? -0.9 : 0.9, 0.35);

              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..translateByDouble(
                  _smoothLook.dx * 2.2 + peekShiftX,
                  floatY + _smoothLook.dy * 1.5,
                  0,
                  1,
                )
                ..rotateZ(tiltAngle)
                ..rotateY(_smoothLook.dx * 0.12)
                ..rotateX(-_smoothLook.dy * 0.08)
                ..scaleByDouble(scaleX * pop, scaleY * pop, 1, 1);

              return Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Transform(alignment: pivot, transform: matrix, child: child),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PetAuraParticlesPainter(
                        mood: widget.mood,
                        phase: _animate ? _accent.value : 0.35,
                        showSparkles: widget.showSparkles,
                        peekingSide: widget.peekingSide,
                        accentColor: accent,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: spriteStack,
          ),
        ),
      ),
    );

    if (!_animate ||
        !widget.showSparkles ||
        Platform.environment['FLUTTER_TEST'] == 'true') {
      return animatedPet;
    }
    return animatedPet.animate().scale(
      begin: const Offset(0.96, 0.96),
      end: const Offset(1.04, 1.04),
      duration: 240.ms,
      curve: Curves.easeOutBack,
    );
  }
}

/// 环绕原版立绘四周的轻盈情绪粒子（爱心 / 星光 / 思考气泡 / Zzz），绝不遮挡人物面部。
class _PetAuraParticlesPainter extends CustomPainter {
  const _PetAuraParticlesPainter({
    required this.mood,
    required this.phase,
    required this.showSparkles,
    required this.peekingSide,
    required this.accentColor,
  });

  final PetLiveMood mood;
  final double phase;
  final bool showSparkles;
  final int peekingSide;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100.0;
    canvas.save();
    canvas.scale(s, s);

    if (peekingSide != 0) {
      _drawEdgeGripPaws(canvas, peekingSide);
    }

    if (showSparkles || mood == PetLiveMood.happy || mood == PetLiveMood.shy) {
      const anchors = [Offset(14, 24), Offset(86, 22), Offset(20, 10)];
      for (var i = 0; i < anchors.length; i++) {
        final local = (phase + i * 0.33) % 1.0;
        final base = anchors[i];
        final x = base.dx + math.sin(local * math.pi * 2) * 2.6;
        final y = base.dy - local * 13.0;
        final alpha = math.sin(local * math.pi).clamp(0.0, 1.0);
        _drawHeart(
          canvas,
          Offset(x, y),
          3.5 - i * 0.35,
          accentColor.withValues(alpha: alpha * 0.92),
        );
      }
    }

    if (mood == PetLiveMood.thinking) {
      for (var i = 0; i < 3; i++) {
        final pulse = 0.5 + 0.5 * math.sin((phase * 2 * math.pi) - i * 0.9);
        canvas.drawCircle(
          Offset(80.0 + i * 5.0, 20.0 - i * 4.2),
          1.5 + i * 0.55,
          Paint()..color = accentColor.withValues(alpha: 0.45 + pulse * 0.5),
        );
      }
    }

    if (mood == PetLiveMood.speaking) {
      for (var i = 0; i < 2; i++) {
        final local = (phase + i * 0.5) % 1.0;
        final alpha = math.sin(local * math.pi).clamp(0.0, 1.0);
        _drawSparkle(
          canvas,
          Offset(84 + i * 6.0, 28 - local * 14),
          3.4,
          accentColor.withValues(alpha: alpha * 0.9),
        );
      }
    }

    if (mood == PetLiveMood.sleepy) {
      final alpha = math.sin(phase * math.pi).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF8B7EB8).withValues(alpha: alpha * 0.88);
      final ox = 78.0 + phase * 6.0;
      final oy = 22.0 - phase * 11.0;
      final zPath = Path()
        ..moveTo(ox, oy)
        ..lineTo(ox + 5.5, oy)
        ..lineTo(ox, oy + 5.5)
        ..lineTo(ox + 5.5, oy + 5.5);
      canvas.drawPath(zPath, paint);
    }

    canvas.restore();
  }

  void _drawEdgeGripPaws(Canvas canvas, int side) {
    final fill = Paint()..color = const Color(0xFFFFE4D6);
    final stroke = Paint()
      ..color = const Color(0xFF8A5A5A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final edgeX = side < 0 ? 44.0 : 56.0;
    final dxDir = side < 0 ? 1.0 : -1.0;
    for (final y in const [40.0, 56.0]) {
      final paw = Rect.fromCenter(
        center: Offset(edgeX + dxDir * 4.5, y),
        width: 11.5,
        height: 8.5,
      );
      canvas.drawOval(paw, fill);
      canvas.drawOval(paw, stroke);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double r, Color color) {
    final p = Path()
      ..moveTo(center.dx, center.dy + r * 0.9)
      ..cubicTo(
        center.dx - r * 1.4,
        center.dy - r * 0.1,
        center.dx - r * 0.8,
        center.dy - r * 1.2,
        center.dx,
        center.dy - r * 0.35,
      )
      ..cubicTo(
        center.dx + r * 0.8,
        center.dy - r * 1.2,
        center.dx + r * 1.4,
        center.dy - r * 0.1,
        center.dx,
        center.dy + r * 0.9,
      )
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PetAuraParticlesPainter oldDelegate) =>
      oldDelegate.mood != mood ||
      oldDelegate.phase != phase ||
      oldDelegate.showSparkles != showSparkles ||
      oldDelegate.peekingSide != peekingSide ||
      oldDelegate.accentColor != accentColor;
}
