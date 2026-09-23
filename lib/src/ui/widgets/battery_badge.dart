import 'package:flutter/material.dart';

/// 阅读页页脚电量徽章：迷你电池图标 + 百分比。
///
/// [level] 为 null 时整个徽章不显示（例如读取失败）。
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({
    super.key,
    required this.level,
    required this.charging,
    required this.color,
  });

  /// 电量百分比 0-100。
  final int? level;

  /// 是否正在充电（充电时填充色变绿）。
  final bool charging;

  /// 线条与文字颜色（一般与页脚文字同色）。
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = level;
    if (value == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 17,
          height: 10,
          child: CustomPaint(
            painter: _BatteryPainter(
              ratio: (value / 100).clamp(0.0, 1.0).toDouble(),
              color: color,
              charging: charging,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('$value%', style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({
    required this.ratio,
    required this.color,
    required this.charging,
  });

  final double ratio;
  final Color color;
  final bool charging;

  static const Color _chargingGreen = Color(0xFF67C23A);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 4.5, size.height - 1),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(body, outline);
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width - 2.4,
        size.height * 0.3,
        1.4,
        size.height * 0.4,
      ),
      const Radius.circular(0.7),
    );
    canvas.drawRRect(cap, Paint()..color = color);
    if (ratio > 0.02) {
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5, 1.5, (size.width - 6) * ratio, size.height - 3),
        const Radius.circular(1.2),
      );
      canvas.drawRRect(
        fill,
        Paint()..color = charging ? _chargingGreen : color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.color != color ||
      oldDelegate.charging != charging;
}
