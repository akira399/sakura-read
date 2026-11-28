import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';
import 'shelf_plank.dart';

/// 书架 2.5 封面网格卡片：支持 3D 纸页切口、轻小说腰封与玻/木层板陈列。
class BookGridCard extends StatelessWidget {
  const BookGridCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onMenu,
    this.compact = false,
    this.coverEmphasized = false,
    this.plankStyle = ShelfPlankStyle.frostedGlass,
    this.visualStyle = VisualStylePreset.sakuraAtelier,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final bool compact;
  final bool coverEmphasized;
  final ShelfPlankStyle plankStyle;
  final VisualStylePreset visualStyle;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final percent = (book.progress * 100).round();

    final showEdges =
        !compact &&
        (plankStyle == ShelfPlankStyle.frostedGlass ||
            plankStyle == ShelfPlankStyle.warmWood);
    final isObi = plankStyle == ShelfPlankStyle.obiBand && !compact;
    final isAnime = visualStyle == VisualStylePreset.animePop;
    final isWashi = visualStyle == VisualStylePreset.kyotoWashi;

    return SakuraPressable(
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      onLongPress: onMenu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Hero(
                  tag: 'book-cover-${book.id}',
                  child: BookPageEdgesFrame(
                    showEdges: showEdges,
                    popOutline: isObi || isAnime,
                    radius: compact ? 10 : (isObi || isAnime ? 10 : 14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCover(
                          book: book,
                          radius: compact ? 10 : (isObi || isAnime ? 9 : 14),
                          elevated: !showEdges && !isObi && !isAnime,
                          showFormatBadge: !compact,
                          showTextOnGenerated: false,
                        ),
                        if (isObi)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accent,
                                    Color.lerp(
                                      accent,
                                      const Color(0xFF38BDF8),
                                      0.45,
                                    )!,
                                  ],
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${book.chapterCount}章 · ${book.finished ? '已读完' : '$percent%'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (book.pinned)
                  Positioned(
                    top: compact ? 5 : 7,
                    left: compact ? 5 : 7,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.push_pin_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            book.title,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: sakura.inkPrimary,
              fontFamily: isWashi ? 'serif' : null,
              fontSize: compact ? 11.5 : 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (!coverEmphasized && !compact) ...[
            const SizedBox(height: 2),
            Text(
              book.author.isEmpty ? '佚名' : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sakura.inkSecondary, fontSize: 11),
            ),
          ],
          SizedBox(height: compact ? 4 : 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: book.progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: sakura.surfaceSubtle,
                    color: isAnime ? const Color(0xFF38BDF8) : accent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                book.finished ? '已读完' : '$percent%',
                style: TextStyle(
                  color: book.finished ? accent : sakura.inkSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
