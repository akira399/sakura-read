import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/models.dart';
import '../data/offline_downloader.dart';
import '../data/prefs.dart';
import '../source/source_store.dart';
import '../theme/app_theme.dart';
import 'reader/reader_page.dart';
import 'source/source_switch_sheet.dart';
import 'widgets/book_cover.dart';
import 'widgets/cute.dart';

/// 书籍详情页：封面 / 信息 / 简介 / 目录 / 离线缓存。
class BookDetailPage extends StatefulWidget {
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
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  /// 离线下载器（一次一个任务）。
  final OfflineDownloader _downloader = OfflineDownloader();

  /// 当前下载进度（null = 没在下载）。
  OfflineDownloadProgress? _progress;

  /// 已缓存章节数（进度展示用）。
  int? _cachedCount;

  BookStore get store => widget.store;

  Book? get _book => store.byId(widget.bookId);

  @override
  void initState() {
    super.initState();
    _refreshCachedCount();
  }

  Future<void> _refreshCachedCount() async {
    final n = await store.cachedChapterCount(widget.bookId);
    if (mounted) setState(() => _cachedCount = n);
  }

  /// 缓存整本（在线书）：逐章抓取并落盘，可随时取消。
  Future<void> _downloadAll() async {
    final book = _book;
    if (book == null) return;
    if (_downloader.running) return;
    final messenger = ScaffoldMessenger.of(context);

    // 从「已缓存的下一章」开始，避免重复抓（重跑只补缺的）
    final cached = await store.cachedChapterCount(book.id);
    if (!mounted) return;
    setState(() {
      _progress = OfflineDownloadProgress(
        done: 0,
        total: book.chapterCount - cached,
        failed: 0,
        currentChapter: cached,
        finished: false,
        cancelled: false,
      );
    });

    final result = await _downloader.download(
      book,
      store,
      from: 0,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() => _progress = null);
    await _refreshCachedCount();
    if (!mounted) return;

    final ok = book.chapterCount - result.failed;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.cancelled
              ? '已暂停（已缓存 $ok 章，下次可继续）'
              : result.failed == 0
              ? '整本已缓存，断网也能读啦 🎀'
              : '已缓存 $ok 章，${result.failed} 章失败（可重试）',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 清空本书缓存。
  Future<void> _clearCache() async {
    await store.clearBookCache(widget.bookId);
    await _refreshCachedCount();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除本书缓存')));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final book = store.byId(widget.bookId);
        if (book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('这本书不在书架里了')),
          );
        }
        final isOnline = book.format == BookFormat.online;
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
                    onSwitchSource: isOnline
                        ? () => _switchSource(context, book)
                        : null,
                    onDownload: isOnline && !_downloader.running
                        ? _downloadAll
                        : null,
                  ),
                ),
              ),
              // 离线缓存状态 / 下载进度（仅在线书）
              if (isOnline)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _OfflineCard(
                      book: book,
                      cachedCount: _cachedCount,
                      progress: _progress,
                      onDownload: _downloadAll,
                      onCancel: _downloader.cancel,
                      onClear: _clearCache,
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
          prefs: widget.prefs,
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
          prefs: widget.prefs,
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
    // 头部即渐变容器本身：渐变铺满整个头部（含状态栏区域），状态栏透明 →
    // 头部颜色直接透到状态栏底下（用户偏好这种透明观感）。
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
    this.onDownload,
  });

  final Book book;
  final VoidCallback onContinue;
  final VoidCallback? onSwitchSource;

  /// 「缓存整本」入口（仅在线书提供）。
  final VoidCallback? onDownload;

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
        // 用户反馈「不支持离线缓存」：提供「缓存整本」入口（在线书）
        if (onDownload != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: onDownload,
            tooltip: '缓存整本（离线可读）',
            icon: Icon(
              Icons.download_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
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

/// 离线缓存卡片（仅在线书）：显示已缓存章节 / 下载进度 / 操作按钮。
///
/// 用户反馈「不支持离线缓存」：这里让用户能把整本提前下好，
/// 之后地铁 / 飞机上断网也能接着读。
class _OfflineCard extends StatelessWidget {
  const _OfflineCard({
    required this.book,
    required this.cachedCount,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onClear,
  });

  final Book book;

  /// 已缓存章节数（null = 还在统计）。
  final int? cachedCount;

  /// 下载进度（null = 空闲）。
  final OfflineDownloadProgress? progress;

  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = book.chapterCount;
    final cached = cachedCount ?? 0;
    final p = progress;
    final downloading = p != null;

    return SoftCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_download_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                '离线缓存',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                cachedCount == null ? '统计中…' : '已缓存 $cached / $total 章',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: p.fraction, minHeight: 7),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正在缓存第 ${p.currentChapter + 1} 章 · '
                    '${p.done}/${p.total}'
                    '${p.failed > 0 ? '（${p.failed} 章失败）' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('暂停', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ] else ...[
            Text(
              cached >= total && total > 0
                  ? '整本已缓存，断网也能读啦～'
                  : '提前缓存整本，没网时也能接着看',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onDownload,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 17),
                  label: Text(
                    cached > 0 && cached < total ? '继续缓存' : '缓存整本',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                if (cached > 0) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('清除缓存', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
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
