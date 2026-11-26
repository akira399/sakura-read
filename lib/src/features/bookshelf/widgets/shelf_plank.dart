import 'package:flutter/material.dart';

import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';

/// 实体书架层板：为书籍提供接地落脚点与景深阴影（透光磨砂 / 实体樱木）。
class ShelfPlank extends StatelessWidget {
  const ShelfPlank({super.key, required this.style});

  final ShelfPlankStyle style;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (style) {
      case ShelfPlankStyle.frostedGlass:
        return Container(
          height: 11,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0.04),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.82),
                      const Color(0xFFFFE5EF).withValues(alpha: 0.45),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.90),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.60)
                    : const Color(0xFF62344A).withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
        );
      case ShelfPlankStyle.warmWood:
        return Container(
          height: 12,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      Color(0xFF42332D),
                      Color(0xFF2D221E),
                      Color(0xFF1B1412),
                    ]
                  : const [
                      Color(0xFFEAD4BE),
                      Color(0xFFD6B696),
                      Color(0xFFBA936F),
                    ],
            ),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.65),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.65)
                    : const Color(0xFF54351C).withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
        );
      case ShelfPlankStyle.obiBand:
      case ShelfPlankStyle.minimal:
        return const SizedBox.shrink();
    }
  }
}

/// 为封面包裹右侧 3D 纸张堆叠切口与投影，还原实体精装书立体感。
class BookPageEdgesFrame extends StatelessWidget {
  const BookPageEdgesFrame({
    super.key,
    required this.showEdges,
    required this.radius,
    required this.child,
    this.popOutline = false,
  });

  final bool showEdges;
  final double radius;
  final Widget child;
  final bool popOutline;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sakura = context.sakura;

    if (popOutline) {
      final outline = isDark
          ? const Color(0xFF38BDF8)
          : const Color(0xFF0F172A);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: outline, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
                  : const Color(0xFF0F172A),
              offset: const Offset(3.5, 4.5),
              blurRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1.5),
          child: child,
        ),
      );
    }

    if (!showEdges) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 4,
          bottom: 4,
          right: -4.5,
          width: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isDark
                    ? const [Color(0xFF474252), Color(0xFF312D3A)]
                    : const [
                        Color(0xFFF6F0E5),
                        Color(0xFFDCD1BF),
                        Color(0xFFF4EDE0),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: sakura.coverShadow,
                  blurRadius: 6,
                  offset: const Offset(2, 3),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
