import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/pet_store.dart';
import '../../data/prefs.dart';

/// 全局手机陀螺仪/重力光晕覆盖层：随设备倾斜柔和流动，阅读正文时自动隐藏。
class GyroHaloOverlay extends StatefulWidget {
  const GyroHaloOverlay({
    super.key,
    required this.prefs,
    required this.petStore,
  });

  final AppPrefs prefs;
  final PetStore petStore;

  @override
  State<GyroHaloOverlay> createState() => _GyroHaloOverlayState();
}

class _GyroHaloOverlayState extends State<GyroHaloOverlay> {
  static const EventChannel _channel = EventChannel('sakuraread/motion');

  StreamSubscription<dynamic>? _sub;
  Offset _gravity = Offset.zero;

  @override
  void initState() {
    super.initState();
    _syncSensor();
    widget.prefs.addListener(_syncSensor);
    widget.petStore.addListener(_syncSensor);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_syncSensor);
    widget.petStore.removeListener(_syncSensor);
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  void _syncSensor() {
    final shouldListen =
        Platform.isAndroid &&
        Platform.environment['FLUTTER_TEST'] != 'true' &&
        widget.prefs.gyroHaloEnabled &&
        !widget.petStore.readerActive;
    if (shouldListen && _sub == null) {
      try {
        _sub = _channel.receiveBroadcastStream().listen(
          (event) {
            if (!mounted || event is! List || event.length < 2) return;
            final gx = (event[0] as num).toDouble().clamp(-1.0, 1.0);
            final gy = (event[1] as num).toDouble().clamp(-1.0, 1.0);
            if ((gx - _gravity.dx).abs() > 0.008 ||
                (gy - _gravity.dy).abs() > 0.008) {
              setState(() => _gravity = Offset(gx, gy));
            }
          },
          onError: (Object _) {
            _sub?.cancel();
            _sub = null;
          },
          cancelOnError: true,
        );
      } on MissingPluginException {
        _sub = null;
      } catch (_) {
        _sub = null;
      }
    } else if (!shouldListen && _sub != null) {
      _sub?.cancel();
      _sub = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([widget.prefs, widget.petStore]),
      builder: (context, _) {
        if (!widget.prefs.gyroHaloEnabled ||
            widget.petStore.readerActive ||
            reducedMotion) {
          return const SizedBox.shrink();
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final color = Color(widget.prefs.gyroHaloColor);
        final intensity = widget.prefs.gyroHaloIntensity.clamp(0.15, 1.0);
        return IgnorePointer(
          child: RepaintBoundary(
            child: TweenAnimationBuilder<Offset>(
              tween: Tween<Offset>(end: _gravity),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, smoothGravity, _) => CustomPaint(
                painter: _GyroHaloPainter(
                  gravity: smoothGravity,
                  color: color,
                  intensity: intensity,
                  isDark: isDark,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GyroHaloPainter extends CustomPainter {
  const _GyroHaloPainter({
    required this.gravity,
    required this.color,
    required this.intensity,
    required this.isDark,
  });

  final Offset gravity;
  final Color color;
  final double intensity;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // 主光晕随倾斜在屏幕上方至中部柔和游走
    final cx = size.width * (0.5 - gravity.dx * 0.34);
    final cy = size.height * (0.24 + gravity.dy * 0.24);
    final center = Offset(cx, cy);
    final radius = size.longestSide * 0.62;
    final alphaScale = isDark ? 0.58 : 0.92;
    final peakAlpha = (0.30 * intensity * alphaScale).clamp(0.0, 0.36);

    final primaryPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: peakAlpha),
          color.withValues(alpha: peakAlpha * 0.42),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, primaryPaint);

    // 反向边缘余晖，强化玻璃折射与纵深平衡感
    final secondaryCenter = Offset(
      size.width * (0.52 + gravity.dx * 0.26),
      size.height * (0.86 - gravity.dy * 0.14),
    );
    final secondaryRadius = size.longestSide * 0.46;
    final secondaryPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              color.withValues(alpha: peakAlpha * 0.65),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: secondaryCenter, radius: secondaryRadius),
          );
    canvas.drawCircle(secondaryCenter, secondaryRadius, secondaryPaint);
  }

  @override
  bool shouldRepaint(covariant _GyroHaloPainter oldDelegate) =>
      oldDelegate.gravity != gravity ||
      oldDelegate.color != color ||
      oldDelegate.intensity != intensity ||
      oldDelegate.isDark != isDark;
}
