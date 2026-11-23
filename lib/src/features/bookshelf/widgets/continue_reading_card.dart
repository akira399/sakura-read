import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';

/// 书架顶部「继续阅读」聚焦卡片：一键直达最近阅读位置。
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    required this.book,
    required this.onContinue,
    required this.onOpenDetail,
  });

  final Book book;
  final VoidCallback onContinue;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final percent = (book.progress * 100).round();
    final chapterTitle = book.chapter?.title.trim() ?? '';
    final subtitle = chapterTitle.isNotEmpty
        ? chapterTitle
        : (book.author.isNotEmpty ? book.author : '准备继续阅读');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(20),
        onTap: onContinue,
        onLongPress: onOpenDetail,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sakura.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sakura.hairline),
            boxShadow: [
              BoxShadow(
                color: sakura.coverShadow.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                height: 84,
                child: BookCover(
                  book: book,
                  radius: 11,
                  elevated: true,
                  showFormatBadge: false,
                  showTextOnGenerated: false,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: sakura.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '继续阅读',
                            style: TextStyle(
                              color: accent,
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
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sakura.inkPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sakura.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
