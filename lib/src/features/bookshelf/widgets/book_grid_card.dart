import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';

/// 书架 2.0 封面网格卡片：封面与信息上下分离，绝不互相遮挡。
class BookGridCard extends StatelessWidget {
  const BookGridCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onMenu,
    this.compact = false,
    this.coverEmphasized = false,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final bool compact;
  final bool coverEmphasized;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final percent = (book.progress * 100).round();

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
              children: [
                Hero(
                  tag: 'book-cover-${book.id}',
                  child: BookCover(
                    book: book,
                    radius: compact ? 10 : 14,
                    elevated: true,
                    showFormatBadge: !compact,
                    showTextOnGenerated: false,
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
                    color: accent,
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
