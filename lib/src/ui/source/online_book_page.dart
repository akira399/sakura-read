// 在线书籍详情页：详情信息 + 多源切换 + 目录 + 加入书架 / 换源 / 开始阅读。
//
// 同一本书可能来自多个书源（搜索页已按书合并）；页内提供来源切换，
// 已在书架的书可直接「换源」（更新书页地址 / 目录并清空旧章节缓存）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/book_store.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../source/models.dart';
import '../../source/online_book_service.dart';
import '../../source/source_store.dart';
import '../reader/reader_page.dart';

/// 同一本书的一个来源变体（书源 + 该源下的搜索结果）。
class OnlineBookVariant {
  const OnlineBookVariant(this.source, this.book);

  final BookSource source;
  final SearchBook book;
}

class OnlineBookPage extends StatefulWidget {
  const OnlineBookPage({
    super.key,
    required this.bookStore,
    required this.prefs,
    required this.variants,
  });

  final BookStore bookStore;
  final AppPrefs prefs;
  final List<OnlineBookVariant> variants;

  @override
  State<OnlineBookPage> createState() => _OnlineBookPageState();
}

class _OnlineBookPageState extends State<OnlineBookPage> {
  static const String _coverUa =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/122.0 '
      'Mobile Safari/537.36';

  final OnlineBookService _service = OnlineBookService();

  int _sel = 0;
  bool _loading = true;
  String? _error;
  OnlineBookInfo? _info;
  List<ChapterRef> _chapters = const [];
  bool _busy = false;

  OnlineBookVariant get _variant => widget.variants[_sel];

  String get _bookUrl => (_variant.book.bookUrl ?? '').trim();

  /// 书架里已有的同一本书（任一来源变体命中即算）。
  Book? get _shelfBook {
    for (final v in widget.variants) {
      final url = (v.book.bookUrl ?? '').trim();
      if (url.isEmpty) continue;
      final b = widget.bookStore.onlineByPath(url);
      if (b != null) return b;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_bookUrl.isEmpty) {
      setState(() {
        _loading = false;
        _error = '这本书缺少详情页地址';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _service.fetchInfo(_variant.source, _bookUrl);
      if (!mounted) return;
      setState(() {
        _info = info;
        _chapters = info.chapters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _switchSource(int index) {
    if (index == _sel || _busy) return;
    setState(() => _sel = index);
    _load();
  }

  // ---------- 书架 / 换源 / 阅读 ----------

  Future<void> _addToShelf({bool silent = false}) async {
    if (_shelfBook != null || _busy) return;
    if (_chapters.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目录为空，不能加入书架（可能是源规则失效）')));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final id = Book.newId();
      String? coverPath;
      final coverUrl = _info?.coverUrl ?? _variant.book.coverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        coverPath = await _downloadCover(coverUrl, id);
      }
      final book = Book(
        id: id,
        title: (_info?.name ?? _variant.book.name ?? '未命名').trim(),
        author: (_info?.author ?? _variant.book.author ?? '').trim(),
        format: BookFormat.online,
        path: _bookUrl,
        sourceUrl: _variant.source.bookSourceUrl,
        coverPath: coverPath,
        generatedCover: coverPath == null,
        intro: (_info?.intro ?? _variant.book.intro ?? '').trim(),
        chapters: _chapters,
      );
      widget.bookStore.addOnline(book);
      if (!mounted) return;
      setState(() {});
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入书架，可以随时接着看啦 🎀')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 已入架但当前选中的是另一个来源 → 换源（保留进度，清空旧缓存）。
  Future<void> _switchShelfSource(Book shelf) async {
    if (_busy) return;
    if (_chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该来源目录为空，无法切换（可能是源规则失效）')));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.bookStore.switchOnlineSource(
        shelf.id,
        path: _bookUrl,
        sourceUrl: _variant.source.bookSourceUrl,
        chapters: _chapters,
        title: _info?.name ?? _variant.book.name,
        author: _info?.author ?? _variant.book.author,
        intro: _info?.intro ?? _variant.book.intro,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换书源：${_variant.source.bookSourceName}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReader(int chapterIndex) async {
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目录为空，无法阅读（可能是源规则失效）')));
      return;
    }
    final shelf = _shelfBook;
    if (shelf == null) {
      await _addToShelf(silent: true);
    } else if (shelf.path != _bookUrl) {
      await _switchShelfSource(shelf);
    }
    final book = widget.bookStore.onlineByPath(_bookUrl);
    if (book == null || !mounted) return;
    widget.bookStore.touch(book.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          store: widget.bookStore,
          prefs: widget.prefs,
          bookId: book.id,
          chapterIndex: chapterIndex,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<String?> _downloadCover(String url, String bookId) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': _coverUa})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200 || resp.bodyBytes.length < 300) return null;
      final dir = widget.bookStore.coverDir;
      await dir.create(recursive: true);
      final ext = url.toLowerCase().contains('.png') ? 'png' : 'jpg';
      final file = File('${dir.path}/$bookId.$ext');
      await file.writeAsBytes(resp.bodyBytes, flush: false);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final name = _info?.name ?? _variant.book.name ?? '未命名';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在读取详情…', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 46,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
              const SizedBox(height: 12),
              Text(
                '读取详情失败\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.6, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    final author = (info?.author ?? _variant.book.author ?? '').trim();
    final kind = (info?.kind ?? _variant.book.kind ?? '').trim();
    final intro = (info?.intro ?? _variant.book.intro ?? '').trim();
    final lastChapter = (info?.lastChapter ?? '').trim();
    final coverUrl = info?.coverUrl ?? _variant.book.coverUrl;

    final shelf = _shelfBook;
    final inShelf = shelf != null && shelf.path == _bookUrl;
    final shelfFromOther = shelf != null && shelf.path != _bookUrl
        ? SourceStore.shared?.byUrl(shelf.sourceUrl ?? '')?.bookSourceName
        : null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(url: coverUrl, title: _variant.book.name ?? ''),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info?.name ?? _variant.book.name ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (author.isNotEmpty) author,
                          if (kind.isNotEmpty) kind,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.variants.length > 1)
                        _sourceChips(scheme)
                      else
                        Text(
                          '来源：${_variant.source.bookSourceName}'
                          '${_chapters.isNotEmpty ? ' · 共 ${_chapters.length} 章' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .85,
                            ),
                          ),
                        ),
                      if (shelfFromOther != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '书架版本来自：$shelfFromOther',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.primary.withValues(alpha: .85),
                          ),
                        ),
                      ],
                      if (lastChapter.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '最新：$lastChapter',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .85,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _leftButton(shelf, inShelf)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _openReader(0),
                              icon: const Icon(
                                Icons.auto_stories_rounded,
                                size: 18,
                              ),
                              label: const Text('开始阅读'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (intro.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
              child: _ExpandableIntro(text: intro),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                Icon(
                  Icons.format_list_bulleted_rounded,
                  size: 17,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  '目录',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (_chapters.isNotEmpty)
                  Text(
                    '${_chapters.length} 章',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_chapters.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              child: Text(
                '目录为空（可能源规则失效或站点改版）',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: _chapters.length,
            itemBuilder: (context, i) {
              final ch = _chapters[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  ch.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                onTap: () => _openReader(i),
              );
            },
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 30)),
      ],
    );
  }

  Widget _sourceChips(ColorScheme scheme) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < widget.variants.length; i++)
          ChoiceChip(
            label: Text(
              widget.variants[i].source.bookSourceName,
              style: const TextStyle(fontSize: 11.5),
            ),
            selected: i == _sel,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => _switchSource(i),
          ),
      ],
    );
  }

  Widget _leftButton(Book? shelf, bool inShelf) {
    if (shelf == null) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : () => _addToShelf(),
        icon: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bookmark_add_outlined, size: 18),
        label: const Text('加入书架'),
      );
    }
    if (inShelf) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('已在书架'),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _switchShelfSource(shelf),
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.swap_horiz_rounded, size: 18),
      label: const Text('切换到此源'),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 96,
      height: 132,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .55),
            scheme.secondary.withValues(alpha: .55),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
    final u = url ?? '';
    if (u.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        u,
        width: 96,
        height: 132,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

/// 简介：默认最多 5 行，点击「展开」查看全文。
class _ExpandableIntro extends StatefulWidget {
  const _ExpandableIntro({required this.text});

  final String text;

  @override
  State<_ExpandableIntro> createState() => _ExpandableIntroState();
}

class _ExpandableIntroState extends State<_ExpandableIntro> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text.trim(),
            maxLines: _expanded ? null : 5,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.7),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? '收起' : '展开全部',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
