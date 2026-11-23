import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';

/// 书架 2.0 列表视图条目：统一卡片描边、书脊缩略图与进度条。
class BookListTile extends StatelessWidget {
  const BookListTile({
    super.key,
    required this.book,
    required this.subtitle,
    required this.onOpen,
    required this.onMenu,
  });

  final Book book;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final percent = (book.progress * 100).round();

    return SakuraPressable(
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      onLongPress: onMenu,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sakura.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sakura.hairline),
        ),
        child: Row(
          children: [
            Hero(
              tag: 'book-cover-${book.id}',
              child: SizedBox(
                width: 48,
                height: 68,
                child: BookCover(
                  book: book,
                  radius: 9,
                  elevated: true,
                  showFormatBadge: false,
                  showTextOnGenerated: false,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (book.pinned) ...[
                        Icon(Icons.push_pin_rounded, size: 13, color: accent),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: sakura.inkPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: sakura.surfaceSubtle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          book.formatLabel,
                          style: TextStyle(
                            color: sakura.inkSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sakura.inkSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: book.progress.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: sakura.surfaceSubtle,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        book.finished ? '已读完' : '$percent%',
                        style: TextStyle(
                          color: book.finished ? accent : sakura.inkSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onMenu,
              icon: Icon(Icons.more_vert_rounded, color: sakura.inkSecondary),
              tooltip: '更多操作',
            ),
          ],
        ),
      ),
    );
  }
}
