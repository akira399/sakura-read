import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';

/// 从当前在读书籍派生柔和氛围色板（与 `GeneratedCover` 保持一致）。
List<Color> coverAuraPaletteFor(
  Book? book, {
  required bool isDark,
  required Color fallbackAccent,
}) {
  if (book == null) {
    return isDark
        ? [
            fallbackAccent.withValues(alpha: 0.28),
            const Color(0xFF3E2D5C).withValues(alpha: 0.34),
            const Color(0xFF282038).withValues(alpha: 0.22),
          ]
        : [
            fallbackAccent.withValues(alpha: 0.22),
            const Color(0xFFA799EF).withValues(alpha: 0.20),
            const Color(0xFFFFD8E6).withValues(alpha: 0.26),
          ];
  }
  var hash = 0;
  for (final unit in book.title.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  const lightSets = [
    [Color(0xFF88B8FA), Color(0xFFB5A7F5), Color(0xFFF7BED5)],
    [Color(0xFFF59EC0), Color(0xFFB39FF7), Color(0xFFFFD8C4)],
    [Color(0xFF84D1BE), Color(0xFF93CAF2), Color(0xFFF7C0D6)],
    [Color(0xFFF4B3C8), Color(0xFFCBB1F7), Color(0xFFF9DEC4)],
    [Color(0xFF9FB0F8), Color(0xFFD9AEF6), Color(0xFFF8BFD7)],
    [Color(0xFFF2A4C2), Color(0xFFF7D4BC), Color(0xFFB3A9F2)],
  ];
  const darkSets = [
    [Color(0xFF274A82), Color(0xFF3A306E), Color(0xFF5A2E54)],
    [Color(0xFF5D2643), Color(0xFF3A296B), Color(0xFF59382C)],
    [Color(0xFF1F5450), Color(0xFF234A6B), Color(0xFF4F2C4A)],
    [Color(0xFF613626), Color(0xFF582942), Color(0xFF5E4724)],
    [Color(0xFF2C3B75), Color(0xFF4D2B6A), Color(0xFF5C2D49)],
    [Color(0xFF5A2B45), Color(0xFF5B4324), Color(0xFF3B2E66)],
  ];
  final set = (isDark ? darkSets : lightSets)[hash % lightSets.length];
  return [
    set[0].withValues(alpha: isDark ? 0.28 : 0.16),
    set[1].withValues(alpha: isDark ? 0.24 : 0.14),
    set[2].withValues(alpha: isDark ? 0.20 : 0.16),
  ];
}

/// 书架 2.5 动态氛围背景：
/// - 封面取色流体极光 + 昼夜窗格柔光（`ambientCoverAura`）
/// - 和纸微粒肌理（`sakuraAtelier` / `kyotoWashi`）或轻漫半调网点（`animePop`）
/// - 微风樱花花瓣（`shelfSakuraPetals`，30fps 节流，不重建子树）
class ShelfBackdrop extends StatefulWidget {
  const ShelfBackdrop({
    super.key,
    required this.visualStyle,
    required this.ambientAura,
    required this.showPetals,
    required this.activeBook,
    required this.child,
  });

  final VisualStylePreset visualStyle;
  final bool ambientAura;
  final bool showPetals;
  final Book? activeBook;
  final Widget child;

  @override
  State<ShelfBackdrop> createState() => _ShelfBackdropState();
}

class _ShelfBackdropState extends State<ShelfBackdrop>
    with SingleTickerProviderStateMixin {
  static const Duration _frameStep = Duration(milliseconds: 33);
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Duration _lastPaint = Duration.zero;
  bool _reducedMotion = false;

  late final List<_BackdropPetal> _petals = _makePetals();

  List<_BackdropPetal> _makePetals() {
    final rnd = math.Random(2026);
    return List.generate(
      11,
      (_) => _BackdropPetal(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        size: 5 + rnd.nextDouble() * 6,
        speed: 0.45 + rnd.nextDouble() * 0.65,
        sway: 0.4 + rnd.nextDouble() * 0.8,
        phase: rnd.nextDouble() * math.pi * 2,
        spin: (rnd.nextDouble() - 0.5) * 1.8,
      ),
    );
  }

  bool get _needsAnimation =>
      !_reducedMotion &&
      (widget.ambientAura ||
          (widget.showPetals &&
              widget.visualStyle != VisualStylePreset.animePop));

  void _syncTicker() {
    if (_needsAnimation) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ShelfBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastPaint < _frameStep) return;
    _lastPaint = elapsed;
    _phase.value = elapsed.inMilliseconds / 1000.0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final baseBg = switch (widget.visualStyle) {
      VisualStylePreset.sakuraAtelier =>
        isDark ? const Color(0xFF14101B) : const Color(0xFFFFFAF9),
      VisualStylePreset.liquidGlass =>
        isDark ? const Color(0xFF0E0C16) : const Color(0xFFF8F6FC),
      VisualStylePreset.kyotoWashi =>
        isDark ? const Color(0xFF1A1513) : const Color(0xFFF9F2E8),
      VisualStylePreset.animePop =>
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF3F8FF),
    };
    final palette = coverAuraPaletteFor(
      widget.activeBook,
      isDark: isDark,
      fallbackAccent: accent,
    );

    return ColoredBox(
      color: baseBg,
      child: CustomPaint(
        painter: _ShelfAtmospherePainter(
          phase: _phase,
          visualStyle: widget.visualStyle,
          ambientAura: widget.ambientAura,
          showPetals:
              widget.showPetals &&
              widget.visualStyle != VisualStylePreset.animePop,
          isDark: isDark,
          palette: palette,
          hairline: sakura.hairline,
          petals: _petals,
        ),
        child: widget.child,
      ),
    );
  }
}

class _BackdropPetal {
  const _BackdropPetal({
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

class _ShelfAtmospherePainter extends CustomPainter {
  _ShelfAtmospherePainter({
    required this.phase,
    required this.visualStyle,
    required this.ambientAura,
    required this.showPetals,
    required this.isDark,
    required this.palette,
    required this.hairline,
    required this.petals,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final VisualStylePreset visualStyle;
  final bool ambientAura;
  final bool showPetals;
  final bool isDark;
  final List<Color> palette;
  final Color hairline;
  final List<_BackdropPetal> petals;

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;

    // 1. 封面取色流体极光 + 昼夜窗格柔光
    if (ambientAura && size.width > 0 && size.height > 0) {
      final blobs = [
        (
          Offset(
            size.width * (0.24 + 0.10 * math.sin(t * 0.45)),
            size.height * (0.12 + 0.03 * math.cos(t * 0.35)),
          ),
          size.width * 0.72,
          palette[0],
        ),
        (
          Offset(
            size.width * (0.80 + 0.08 * math.cos(t * 0.35)),
            size.height * (0.20 + 0.04 * math.sin(t * 0.50)),
          ),
          size.width * 0.62,
          palette[1],
        ),
        (
          Offset(
            size.width * (0.48 + 0.12 * math.sin(t * 0.28)),
            size.height * 0.85,
          ),
          size.width * 0.60,
          palette[2],
        ),
      ];
      for (final (center, radius, color) in blobs) {
        final rect = Rect.fromCircle(center: center, radius: radius);
        final paint = Paint()
          ..shader = RadialGradient(
            stops: const [0.0, 0.48, 1.0],
            colors: [
              color,
              color.withValues(alpha: color.a * 0.36),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect);
        canvas.drawCircle(center, radius, paint);
      }

      // 京都和纸 / 混搭旗舰：斜照窗格日照光斑（从顶栏自然衔接向下散开）
      if (visualStyle == VisualStylePreset.sakuraAtelier ||
          visualStyle == VisualStylePreset.kyotoWashi) {
        final sunColor = isDark
            ? const Color(0xFFFFCA8C).withValues(alpha: 0.045)
            : const Color(0xFFFFE4DC).withValues(alpha: 0.24);
        for (var i = 0; i < 3; i++) {
          final cx = 64.0 + i * 96 + math.sin(t * 0.6 + i) * 8;
          final cy = 44.0 + i * 34;
          const r = 156.0;
          final p = Paint()
            ..shader = RadialGradient(
              stops: const [0.0, 0.5, 1.0],
              colors: [
                sunColor,
                sunColor.withValues(alpha: sunColor.a * 0.35),
                sunColor.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
          canvas.drawCircle(Offset(cx, cy), r, p);
        }
      }
    }

    // 2. 材质底纹：轻漫半调网点 vs 和纸点阵肌理
    if (visualStyle == VisualStylePreset.animePop) {
      final dotPaint = Paint()
        ..color = (isDark ? const Color(0xFF60A5FA) : const Color(0xFF3898EC))
            .withValues(alpha: isDark ? 0.10 : 0.11);
      const step = 16.0;
      for (var y = 12.0; y < size.height; y += step) {
        for (var x = 12.0; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
        }
      }
    } else if (visualStyle == VisualStylePreset.sakuraAtelier ||
        visualStyle == VisualStylePreset.kyotoWashi) {
      final grainPaint = Paint()
        ..color = (isDark ? Colors.white : const Color(0xFF7B604E)).withValues(
          alpha: isDark ? 0.02 : 0.024,
        );
      const step = 22.0;
      for (var y = 10.0; y < size.height; y += step) {
        final offsetX = ((y ~/ step) % 2) * 11.0;
        for (var x = 10.0 + offsetX; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 0.9, grainPaint);
        }
      }
    }

    // 3. 轻柔樱花花瓣
    if (showPetals && size.width > 0 && size.height > 0) {
      final petalColor = isDark
          ? const Color(0xFFFFB2CE).withValues(alpha: 0.34)
          : const Color(0xFFF486AC).withValues(alpha: 0.38);
      final petalPaint = Paint()..color = petalColor;
      for (final p in petals) {
        final progressY = (p.y + (t * p.speed * 0.055)) % 1.0;
        final driftX =
            (p.x + t * p.speed * 0.02 + math.sin(t * p.sway + p.phase) * 0.04) %
            1.0;
        final px = driftX * size.width;
        final py = progressY * size.height;
        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(p.phase + t * p.spin);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.58,
          ),
          petalPaint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShelfAtmospherePainter oldDelegate) =>
      oldDelegate.visualStyle != visualStyle ||
      oldDelegate.ambientAura != ambientAura ||
      oldDelegate.showPetals != showPetals ||
      oldDelegate.isDark != isDark ||
      oldDelegate.palette != palette;
}
