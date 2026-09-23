import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../source/source_store.dart';
import '../theme/app_theme.dart';
import 'reader/reader_page.dart';
import 'source/source_switch_sheet.dart';
import 'widgets/book_cover.dart';
import 'widgets/cute.dart';

/// 书籍详情页：封面 / 信息 / 简介 / 目录。
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.bookId,
  });

  final BookStore store;
  final AppPrefs prefs;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final book = store.byId(bookId);
        if (book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('这本书不在书架里了')),
          );
        }
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(book: book, store: store),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _Actions(
                    book: book,
                    onContinue: () => _openReader(context, book),
                    onSwitchSource: book.format == BookFormat.online
                        ? () => _switchSource(context, book)
                        : null,
                  ),
                ),
              ),
              if (book.intro.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _IntroCard(intro: book.intro),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.format_list_numbered_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '目录 · 共 ${book.chapterCount} 章',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                sliver: SliverList.separated(
                  itemCount: book.chapterCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) => _ChapterTile(
                    book: book,
                    index: index,
                    onTap: () => _openChapter(context, book, index),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openReader(BuildContext context, Book book) {
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

  void _openChapter(BuildContext context, Book book, int index) {
    store.touch(book.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          store: store,
          prefs: prefs,
          bookId: book.id,
          chapterIndex: index,
          charOffset: index == book.safeChapterIndex ? book.charOffset : 0,
        ),
      ),
    );
  }

  /// 在线书换源：自动搜索候选 → 选择 → 切换（保留阅读进度）。
  Future<void> _switchSource(BuildContext context, Book book) async {
    final sourceStore = SourceStore.shared;
    if (sourceStore == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showSourceSwitchSheet(
      context,
      bookStore: store,
      sourceStore: sourceStore,
      book: book,
    );
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('已换源 🎀')));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.book, required this.store});

  final Book book;
  final BookStore store;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        // 背景：封面模糊 + 主题渐变
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: SakuraTheme.headerGradient(context),
            ),
          ),
        ),
        Positioned.fill(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Opacity(
                opacity: .45,
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 240,
                      height: 320,
                      child: BookCover(book: book, radius: 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(8, topPad + 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    height: 156,
                    child: BookCover(book: book, radius: 14),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            book.author.isEmpty ? '佚名' : book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .9),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _chip(book.formatLabel),
                              _chip('${book.chapterCount} 章'),
                              if (book.totalChars > 0)
                                _chip(_charsLabel(book.totalChars)),
                              if (book.finished) _chip('已读完'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _charsLabel(int chars) {
    if (chars >= 10000) {
      return '${(chars / 10000).toStringAsFixed(1)} 万字';
    }
    return '$chars 字';
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .22),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.book,
    required this.onContinue,
    this.onSwitchSource,
  });

  final Book book;
  final VoidCallback onContinue;
  final VoidCallback? onSwitchSource;

  @override
  Widget build(BuildContext context) {
    final started = book.lastReadAt > 0 && !book.finished;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.auto_stories_rounded, size: 20),
            label: Text(
              book.finished
                  ? '重新阅读'
                  : started
                  ? '继续阅读 · 第 ${book.safeChapterIndex + 1} 章'
                  : '开始阅读',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (onSwitchSource != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: onSwitchSource,
            tooltip: '换源',
            icon: Icon(
              Icons.swap_horiz_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(width: 10),
        SoftCard(
          radius: 24,
          padding: const EdgeInsets.all(10),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '进度 ${book.progressLabel}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntroCard extends StatefulWidget {
  const _IntroCard({required this.intro});

  final String intro;

  @override
  State<_IntroCard> createState() => _IntroCardState();
}

class _IntroCardState extends State<_IntroCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.menu_book_rounded, title: '简介'),
          const SizedBox(height: 10),
          Text(
            widget.intro,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: scheme.onSurface.withValues(alpha: .86),
            ),
          ),
          if (widget.intro.length > 90)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.book,
    required this.index,
    required this.onTap,
  });

  final Book book;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chapter = book.chapters[index];
    final isCurrent = index == book.safeChapterIndex && book.lastReadAt > 0;
    final isRead =
        index < book.safeChapterIndex ||
        (index == book.safeChapterIndex && book.finished);
    return Material(
      color: isCurrent ? scheme.primary.withValues(alpha: .12) : scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: isRead
                    ? Icon(Icons.check_rounded, size: 17, color: scheme.primary)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: isCurrent ? scheme.primary : null,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                    fontSize: 14,
                    color: isRead && !isCurrent
                        ? scheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                chapter.charCount > 0 ? '${chapter.charCount} 字' : '',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
