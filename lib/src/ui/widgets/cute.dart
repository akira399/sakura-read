import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 樱花 logo（纯 Canvas 绘制）。
class PetalLogo extends StatelessWidget {
  const PetalLogo({super.key, this.size = 64, this.color, this.centerColor});

  final double size;
  final Color? color;
  final Color? centerColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PetalLogoPainter(
          color ?? const Color(0xFFFF8FB6),
          centerColor ?? const Color(0xFFFFE082),
        ),
      ),
    );
  }
}

class _PetalLogoPainter extends CustomPainter {
  _PetalLogoPainter(this.color, this.centerColor);

  final Color color;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final petal = Paint()..color = color;
    final petalLight = Paint()..color = Color.lerp(color, Colors.white, .35)!;
    for (var i = 0; i < 5; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi * 2 / 5);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -r * .52),
          width: r * .62,
          height: r * .92,
        ),
        i.isEven ? petal : petalLight,
      );
      canvas.restore();
    }
    canvas.drawCircle(center, r * .2, Paint()..color = centerColor);
  }

  @override
  bool shouldRepaint(covariant _PetalLogoPainter old) =>
      old.color != color || old.centerColor != centerColor;
}

/// 圆角软卡片（带粉嫩的柔和阴影）。
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    final inner = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFFFFA6C9)).withValues(
              alpha: isDark ? .35 : .18,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: color ?? scheme.surface,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? inner
            : InkWell(onTap: onTap, borderRadius: borderRadius, child: inner),
      ),
    );
  }
}

/// 空状态：圆形渐变图标 + 文案 + 操作按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    this.imageAsset,
    this.illustration,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final IconData icon;

  /// 可选的看板娘插画（有图时优先显示，替代图标圆）。
  final String? imageAsset;

  /// 可选的互动看板娘组件（优先级高于 imageAsset）。
  final Widget? illustration;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (illustration != null)
              illustration!
            else if (imageAsset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  imageAsset!,
                  width: 168,
                  height: 168,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withValues(alpha: .25),
                      scheme.secondary.withValues(alpha: .25),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 46, color: scheme.primary),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 设置页的小节标题。
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }
}
