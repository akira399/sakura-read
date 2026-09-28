import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../util/format.dart';
import 'reader/reader_page.dart';
import 'stats_page.dart';
import 'widgets/book_cover.dart';
import 'widgets/cute.dart';

class RecentPage extends StatelessWidget {
  const RecentPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.statsStore,
  });

  final BookStore store;
  final AppPrefs prefs;
  final StatsStore statsStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final recents = store.books.where((b) => b.lastReadAt > 0).toList()
          ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(context, recents.length)),
              if (recents.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.history_rounded,
                    title: '还没有阅读记录',
                    subtitle: '去书架翻开一本小说吧～',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: recents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _RecentTile(
                      book: recents[index],
                      store: store,
                      prefs: prefs,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 18,
        20,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                '最近阅读',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: '阅读记录',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StatsPage(statsStore: statsStore),
                  ),
                ),
                icon: const Icon(Icons.insights_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count > 0 ? '继续上次的故事 · 共 $count 条记录' : '你的阅读足迹会出现在这里',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.book,
    required this.store,
    required this.prefs,
  });

  final Book book;
  final BookStore store;
  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: () => _open(context),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 72,
            child: BookCover(book: book, radius: 10),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _subtitle(),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 34),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    final chapter = book.chapter;
    if (chapter != null) {
      parts.add('第 ${book.safeChapterIndex + 1} 章 · ${chapter.title}');
    }
    parts.add('已读 ${book.progressLabel}');
    parts.add(timeAgo(book.lastReadAt));
    return parts.join(' · ');
  }

  void _open(BuildContext context) {
    store.touch(book.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          store: store,
          prefs: prefs,
          bookId: book.id,
          chapterIndex: book.safeChapterIndex,
          charOffset: book.charOffset,
        ),
      ),
    );
  }
}
