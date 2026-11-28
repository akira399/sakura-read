import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';
import 'shelf_plank.dart';

/// 书架顶部「案头在读」聚焦卡片：
/// - 3D 书脊与纸页厚度框；
/// - 可选垂坠丝绸书签带 + 可点击盖章的朱红「桜読蔵書」印章；
/// - 适配 4 套视觉风格预设。
class ContinueReadingCard extends StatefulWidget {
  const ContinueReadingCard({
    super.key,
    required this.book,
    required this.onContinue,
    required this.onOpenDetail,
    this.visualStyle = VisualStylePreset.sakuraAtelier,
    this.plankStyle = ShelfPlankStyle.frostedGlass,
    this.silkBookmarkAndStamp = true,
    this.compact = false,
    this.margin,
  });

  final Book book;
  final VoidCallback onContinue;
  final VoidCallback onOpenDetail;
  final VisualStylePreset visualStyle;
  final ShelfPlankStyle plankStyle;
  final bool silkBookmarkAndStamp;
  final bool compact;
  final EdgeInsetsGeometry? margin;

  @override
  State<ContinueReadingCard> createState() => _ContinueReadingCardState();
}

class _ContinueReadingCardState extends State<ContinueReadingCard>
    with TickerProviderStateMixin {
  late final AnimationController _ribbonCtrl;
  late final AnimationController _stampCtrl;
  bool _stamped = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _ribbonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _stampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!_reducedMotion && widget.silkBookmarkAndStamp) {
      if (!_ribbonCtrl.isAnimating) _ribbonCtrl.repeat(reverse: true);
    } else {
      _ribbonCtrl.stop();
    }
  }

  @override
  void didUpdateWidget(covariant ContinueReadingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      _stamped = false;
      _stampCtrl.value = 0;
    }
    if (!_reducedMotion && widget.silkBookmarkAndStamp) {
      if (!_ribbonCtrl.isAnimating) _ribbonCtrl.repeat(reverse: true);
    } else {
      _ribbonCtrl.stop();
    }
  }

  @override
  void dispose() {
    _ribbonCtrl.dispose();
    _stampCtrl.dispose();
    super.dispose();
  }

  void _triggerStamp() {
    setState(() => _stamped = true);
    if (_reducedMotion) {
      _stampCtrl.value = 1;
    } else {
      _stampCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final book = widget.book;
    final percent = (book.progress * 100).round();
    final chapterTitle = book.chapter?.title.trim() ?? '';
    final subtitle = chapterTitle.isNotEmpty
        ? chapterTitle
        : (book.author.isNotEmpty ? book.author : '准备继续阅读');

    final isAnime = widget.visualStyle == VisualStylePreset.animePop;
    final isWashi = widget.visualStyle == VisualStylePreset.kyotoWashi;
    final isLiquid = widget.visualStyle == VisualStylePreset.liquidGlass;
    final showEdges =
        widget.plankStyle == ShelfPlankStyle.frostedGlass ||
        widget.plankStyle == ShelfPlankStyle.warmWood;
    final outlineColor = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0F172A);

    final cardDecoration = isAnime
        ? BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: outlineColor, width: 1.8),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
                    : outlineColor,
                offset: const Offset(4, 4),
              ),
            ],
          )
        : BoxDecoration(
            color: isLiquid
                ? sakura.card.withValues(alpha: isDark ? 0.62 : 0.72)
                : isWashi
                ? (isDark
                      ? const Color(0xFF28201C).withValues(alpha: 0.90)
                      : const Color(0xFFFFFBF4).withValues(alpha: 0.92))
                : sakura.card.withValues(alpha: isDark ? 0.78 : 0.86),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isLiquid
                  ? sakura.glassBorder
                  : isWashi
                  ? (isDark
                        ? const Color(0xFFE0B994).withValues(alpha: 0.22)
                        : const Color(0xFF88664C).withValues(alpha: 0.22))
                  : sakura.hairline,
            ),
            boxShadow: [
              BoxShadow(
                color: sakura.coverShadow.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          );

    return Padding(
      padding: widget.margin ?? const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(isAnime ? 16 : 22),
        onTap: widget.onContinue,
        onLongPress: widget.onOpenDetail,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(widget.compact ? 11 : 14),
              decoration: cardDecoration,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: widget.compact ? 54 : 64,
                    height: widget.compact ? 78 : 92,
                    child: BookPageEdgesFrame(
                      showEdges: showEdges,
                      popOutline: isAnime,
                      radius: isAnime ? 9 : 11,
                      child: BookCover(
                        book: book,
                        radius: isAnime ? 8 : 11,
                        elevated: !showEdges && !isAnime,
                        showFormatBadge: false,
                        showTextOnGenerated: false,
                      ),
                    ),
                  ),
                  SizedBox(width: widget.compact ? 12 : 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: isAnime
                                    ? const Color(0xFFEC4899)
                                    : sakura.accentSoft,
                                borderRadius: BorderRadius.circular(
                                  isAnime ? 6 : 999,
                                ),
                              ),
                              child: Text(
                                '继续阅读',
                                style: TextStyle(
                                  color: isAnime ? Colors.white : accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              book.formatLabel,
                              style: TextStyle(
                                color: sakura.inkSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.silkBookmarkAndStamp &&
                                !isAnime &&
                                !_stamped) ...[
                              const Spacer(),
                              GestureDetector(
                                onTap: _triggerStamp,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFFC93B4B)
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: const Text(
                                    '盖蔵書印',
                                    style: TextStyle(
                                      color: Color(0xFFC93B4B),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: widget.compact ? 4 : 6),
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sakura.inkPrimary,
                            fontFamily: isWashi ? 'serif' : null,
                            fontSize: widget.compact ? 14.5 : 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: widget.compact ? 2 : 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sakura.inkSecondary,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: widget.compact ? 6 : 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: book.progress.clamp(0.0, 1.0),
                                  minHeight: 4.5,
                                  backgroundColor: sakura.surfaceSubtle,
                                  color: isAnime
                                      ? const Color(0xFF38BDF8)
                                      : isWashi
                                      ? const Color(0xFFC93B4B)
                                      : accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$percent%',
                              style: TextStyle(
                                color: sakura.inkSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: isAnime
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent,
                                Color.lerp(
                                  accent,
                                  const Color(0xFF9D8CFF),
                                  0.35,
                                )!,
                              ],
                            ),
                      color: isAnime ? const Color(0xFF38BDF8) : null,
                      shape: BoxShape.circle,
                      border: isAnime
                          ? Border.all(color: outlineColor, width: 1.5)
                          : null,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: isAnime ? const Color(0xFF0F172A) : Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            // 垂坠丝绸书签带
            if (widget.silkBookmarkAndStamp && !isAnime)
              Positioned(
                right: 22,
                top: -3,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _ribbonCtrl,
                    builder: (context, child) {
                      final angle =
                          math.sin(_ribbonCtrl.value * math.pi * 2) * 0.045;
                      return Transform.rotate(
                        alignment: Alignment.topCenter,
                        angle: angle,
                        child: child,
                      );
                    },
                    child: ClipPath(
                      clipper: _BookmarkRibbonClipper(),
                      child: Container(
                        width: 13,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isWashi
                                ? const [Color(0xFFC93B4B), Color(0xFF97202F)]
                                : [
                                    accent,
                                    Color.lerp(
                                      accent,
                                      const Color(0xFF97202F),
                                      0.35,
                                    )!,
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 朱红「桜読蔵書」盖章落印动效
            if (widget.silkBookmarkAndStamp && _stamped)
              Positioned(
                right: 60,
                bottom: 8,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _stampCtrl,
                    builder: (context, child) {
                      final t = Curves.easeOutBack.transform(
                        _stampCtrl.value.clamp(0.0, 1.0),
                      );
                      final scale = 1.9 - 0.9 * t;
                      return Opacity(
                        opacity: _stampCtrl.value.clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: -0.15,
                          child: Transform.scale(scale: scale, child: child),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F6).withValues(alpha: 0.72),
                        border: Border.all(
                          color: const Color(0xFFC93B4B),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '桜読\n蔵書',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFC93B4B),
                          fontFamily: 'serif',
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkRibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.76)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
