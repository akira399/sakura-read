import 'package:flutter/material.dart';

import '../../../core/icons/sakura_icons.dart';
import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_layout.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/pet_guide_overlay.dart';
import 'shelf_backdrop.dart';

/// 书架 2.5 风格自适应头栏：延伸至透明状态栏底下，全面使用自绘双色图标。
class ShelfHeader extends StatelessWidget {
  const ShelfHeader({
    super.key,
    required this.greeting,
    required this.bookCount,
    required this.onAiTap,
    required this.onSearchTap,
    required this.onArrangeTap,
    required this.onManageTap,
    this.visualStyle = VisualStylePreset.sakuraAtelier,
    this.activeBook,
  });

  final String greeting;
  final int bookCount;
  final VoidCallback onAiTap;
  final VoidCallback onSearchTap;
  final VoidCallback onArrangeTap;
  final VoidCallback onManageTap;
  final VisualStylePreset visualStyle;
  final Book? activeBook;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.paddingOf(context).top;

    if (visualStyle == VisualStylePreset.animePop) {
      return _AnimePopHeader(
        topPad: topPad,
        bookCount: bookCount,
        isDark: isDark,
        onAiTap: onAiTap,
        onSearchTap: onSearchTap,
        onArrangeTap: onArrangeTap,
        onManageTap: onManageTap,
      );
    }

    final isWashi = visualStyle == VisualStylePreset.kyotoWashi;
    final isLiquid = visualStyle == VisualStylePreset.liquidGlass;
    final accent = Theme.of(context).colorScheme.primary;
    final aura = coverAuraPaletteFor(
      activeBook,
      isDark: isDark,
      fallbackAccent: accent,
    );

    final decoration = isWashi
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xFF211A17).withValues(alpha: 0.72),
                      const Color(0xFF211A17).withValues(alpha: 0.0),
                    ]
                  : [
                      const Color(0xFFF5EBD9).withValues(alpha: 0.78),
                      const Color(0xFFF5EBD9).withValues(alpha: 0.0),
                    ],
            ),
          )
        : isLiquid
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                aura[0].withValues(alpha: isDark ? 0.22 : 0.14),
                aura[1].withValues(alpha: 0.0),
              ],
            ),
          )
        : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.58, 1.0],
              colors: [
                Color.lerp(
                  sakura.canvas,
                  accent,
                  isDark ? 0.14 : 0.07,
                )!.withValues(alpha: isDark ? 0.88 : 0.84),
                Color.lerp(
                  sakura.canvas,
                  accent,
                  isDark ? 0.06 : 0.03,
                )!.withValues(alpha: isDark ? 0.36 : 0.32),
                sakura.canvas.withValues(alpha: 0.0),
              ],
            ),
          );

    final hInsets = SakuraLayout.horizontalInsets(context, min: 18);
    final compactV =
        SakuraLayout.isShortLandscape(context) ||
        SakuraLayout.isLandscape(context);

    return Container(
      decoration: decoration,
      padding: EdgeInsets.fromLTRB(
        hInsets.left,
        topPad + (compactV ? 8 : 12),
        hInsets.right < 18 ? 14 : hInsets.right,
        compactV ? 8 : 14,
      ),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: SakuraLayout.contentMaxWidth,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isWashi
                        ? const [Color(0xFFD66C76), Color(0xFFD6B696)]
                        : [accent, sakura.inkSecondary.withValues(alpha: 0.35)],
                  ),
                ),
                child: ClipOval(
                  child: ColoredBox(
                    color: sakura.card,
                    child: Image.asset(
                      'assets/images/pet_read.png',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.15),
                      cacheWidth: 168,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isWashi ? '桜読 · 書房' : '樱读',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: sakura.inkPrimary,
                                  fontSize: isWashi ? 19 : 21,
                                  fontFamily: isWashi ? 'serif' : null,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  height: 1.15,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isLiquid
                                ? const Color(0xFFD4A359)
                                      .withValues(alpha: 0.16)
                                : sakura.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: isLiquid
                                ? Border.all(
                                    color: const Color(0xFFD4A359)
                                        .withValues(alpha: 0.45),
                                    width: 0.7,
                                  )
                                : null,
                          ),
                          child: Text(
                            isLiquid ? '✦ 流光' : (isWashi ? '和紙' : '桜書房'),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isLiquid
                                  ? (isDark
                                        ? const Color(0xFFF3CF8A)
                                        : const Color(0xFF9C6D24))
                                  : accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$greeting · $bookCount 本藏书',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sakura.inkSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _HeaderIconButton(
                glyph: SakuraGlyph.aiCompanion,
                tooltip: 'AI 助手',
                onTap: onAiTap,
                accentTint: true,
              ),
              const SizedBox(width: 6),
              PetGuideTarget(
                id: 'shelf_search',
                child: _HeaderIconButton(
                  glyph: SakuraGlyph.search,
                  tooltip: '搜索',
                  onTap: onSearchTap,
                ),
              ),
              const SizedBox(width: 6),
              _HeaderIconButton(
                glyph: SakuraGlyph.arrange,
                tooltip: '排列方式',
                onTap: onArrangeTap,
              ),
              const SizedBox(width: 6),
              _HeaderIconButton(
                glyph: SakuraGlyph.manage,
                tooltip: '批量管理',
                onTap: onManageTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimePopHeader extends StatelessWidget {
  const _AnimePopHeader({
    required this.topPad,
    required this.bookCount,
    required this.isDark,
    required this.onAiTap,
    required this.onSearchTap,
    required this.onArrangeTap,
    required this.onManageTap,
  });

  final double topPad;
  final int bookCount;
  final bool isDark;
  final VoidCallback onAiTap;
  final VoidCallback onSearchTap;
  final VoidCallback onArrangeTap;
  final VoidCallback onManageTap;

  @override
  Widget build(BuildContext context) {
    final borderCol = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0F172A);
    final hInsets = SakuraLayout.horizontalInsets(context, min: 18);
    final compactV =
        SakuraLayout.isShortLandscape(context) ||
        SakuraLayout.isLandscape(context);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: _DiagonalHeaderClipper(),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF1E3A5F), Color(0xFF4C1D95)]
                      : const [Color(0xFF38BDF8), Color(0xFFF472B6)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            hInsets.left,
            topPad + (compactV ? 8 : 12),
            hInsets.right < 18 ? 14 : hInsets.right,
            compactV ? 14 : 22,
          ),
          child: Center(
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: SakuraLayout.contentMaxWidth,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9.5),
                      child: Image.asset(
                        'assets/images/pet_read.png',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.15),
                        cacheWidth: 168,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SAKURA READ // VOL.2',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                '桜読・蔵書',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE047),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  width: 1.0,
                                ),
                              ),
                              child: Text(
                                '$bookCount 卷',
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _AnimeBtn(
                    glyph: SakuraGlyph.aiCompanion,
                    tooltip: 'AI 助手',
                    borderCol: borderCol,
                    onTap: onAiTap,
                  ),
                  const SizedBox(width: 5),
                  PetGuideTarget(
                    id: 'shelf_search',
                    child: _AnimeBtn(
                      glyph: SakuraGlyph.search,
                      tooltip: '搜索',
                      borderCol: borderCol,
                      onTap: onSearchTap,
                    ),
                  ),
                  const SizedBox(width: 5),
                  _AnimeBtn(
                    glyph: SakuraGlyph.arrange,
                    tooltip: '排列方式',
                    borderCol: borderCol,
                    onTap: onArrangeTap,
                  ),
                  const SizedBox(width: 5),
                  _AnimeBtn(
                    glyph: SakuraGlyph.manage,
                    tooltip: '批量管理',
                    borderCol: borderCol,
                    onTap: onManageTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagonalHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height - 14)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _AnimeBtn extends StatelessWidget {
  const _AnimeBtn({
    required this.glyph,
    required this.tooltip,
    required this.borderCol,
    required this.onTap,
  });

  final SakuraGlyph glyph;
  final String tooltip;
  final Color borderCol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SakuraIcon(
            glyph: glyph,
            color: const Color(0xFF0F172A),
            accent: const Color(0xFFEC4899),
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.accentTint = false,
  });

  final SakuraGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;
  final bool accentTint;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentTint
                ? sakura.accentSoft
                : sakura.card.withValues(alpha: 0.80),
            border: Border.all(
              color: accentTint
                  ? accent.withValues(alpha: 0.30)
                  : sakura.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: SakuraIcon(
            glyph: glyph,
            size: 18,
            color: accentTint ? accent : sakura.inkPrimary,
            accent: accent,
          ),
        ),
      ),
    );
  }
}
