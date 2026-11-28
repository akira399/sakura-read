import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/book_store.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';

/// 打开在线多书源封面搜索面板；选择并下载成功后返回本地封面文件路径，取消返回 null。
Future<String?> showOnlineCoverPickerSheet(
  BuildContext context, {
  required Book book,
  required BookStore bookStore,
  required SourceStore sourceStore,
  required AppPrefs prefs,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OnlineCoverPickerSheet(
      book: book,
      bookStore: bookStore,
      sourceStore: sourceStore,
      prefs: prefs,
    ),
  );
}

class _CoverCandidate {
  _CoverCandidate({
    required this.coverUrl,
    required this.title,
    required this.author,
    required this.sourceName,
    required this.score,
    required this.order,
  });

  final String coverUrl;
  final String title;
  final String author;
  final String sourceName;
  final int score;
  final int order;
}

class _OnlineCoverPickerSheet extends StatefulWidget {
  const _OnlineCoverPickerSheet({
    required this.book,
    required this.bookStore,
    required this.sourceStore,
    required this.prefs,
  });

  final Book book;
  final BookStore bookStore;
  final SourceStore sourceStore;
  final AppPrefs prefs;

  @override
  State<_OnlineCoverPickerSheet> createState() =>
      _OnlineCoverPickerSheetState();
}

class _OnlineCoverPickerSheetState extends State<_OnlineCoverPickerSheet> {
  static const String _coverUa =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/122.0 '
      'Mobile Safari/537.36';

  late final TextEditingController _queryCtrl = TextEditingController(
    text: widget.book.title.trim(),
  );

  OnlineRepo? _repo;
  int _searchSeq = 0;
  bool _searching = false;
  int _doneCount = 0;
  int _totalCount = 0;
  String? _error;
  String? _downloadingUrl;

  final List<_CoverCandidate> _items = <_CoverCandidate>[];
  final Set<String> _seenUrls = <String>{};
  int _orderSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _queryCtrl.text.trim().isNotEmpty) {
        _startSearch();
      }
    });
  }

  @override
  void dispose() {
    _repo?.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _sortCandidates() {
    _items.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return a.order.compareTo(b.order);
    });
  }

  Future<void> _startSearch() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;

    final enabled = widget.sourceStore.enabled;
    if (enabled.isEmpty) {
      setState(() {
        _searching = false;
        _error = '还没有启用的书源，请先在「设置 → 书源管理」导入并启用书源';
      });
      return;
    }

    _repo?.dispose();
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _doneCount = 0;
      _totalCount = enabled.length;
      _error = null;
      _items.clear();
      _seenUrls.clear();
      _orderSeq = 0;
    });

    final repo = _repo = OnlineRepo(
      store: widget.sourceStore,
      concurrency: widget.prefs.searchConcurrency,
      perSourceTimeout: Duration(seconds: widget.prefs.searchTimeout),
    );

    await repo.searchAll(
      query,
      onSourceDone: (res) {
        if (!mounted || seq != _searchSeq) return;
        var added = false;
        for (final sb in res.books) {
          final url = (sb.coverUrl ?? '').trim();
          if (!url.startsWith('http://') && !url.startsWith('https://')) {
            continue;
          }
          if (!_seenUrls.add(url)) continue;
          added = true;
          _items.add(
            _CoverCandidate(
              coverUrl: url,
              title: (sb.name ?? widget.book.title).trim(),
              author: (sb.author ?? '').trim(),
              sourceName: res.source.bookSourceName.trim().isEmpty
                  ? Uri.tryParse(res.source.bookSourceUrl)?.host ?? '书源'
                  : res.source.bookSourceName.trim(),
              score: bookRelevanceScore(sb, query),
              order: _orderSeq++,
            ),
          );
        }
        if (added) _sortCandidates();
        setState(() {
          _doneCount++;
        });
      },
    );

    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
    });
  }

  Future<void> _pickCandidate(_CoverCandidate item) async {
    if (_downloadingUrl != null) return;
    setState(() => _downloadingUrl = item.coverUrl);
    try {
      final resp = await http
          .get(
            Uri.parse(item.coverUrl),
            headers: const {'User-Agent': _coverUa},
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200 || resp.bodyBytes.length < 300) {
        throw StateError('HTTP ${resp.statusCode}');
      }
      await widget.bookStore.coverDir.create(recursive: true);
      final target =
          '${widget.bookStore.coverDir.path}/${widget.book.id}-${DateTime.now().microsecondsSinceEpoch}.img';
      await File(target).writeAsBytes(resp.bodyBytes, flush: false);
      if (!mounted) return;
      Navigator.of(context).pop(target);
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloadingUrl = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这张封面下载失败，请换一张或换个书源封面试试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '在线搜索书源封面',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _searching
                            ? '正在搜索 $_doneCount / $_totalCount 个书源 · 已收集 ${_items.length} 张封面'
                            : '已收集 ${_items.length} 张书源封面，点击直接设为本书封面',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_searching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _startSearch(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '输入书名搜索各书源封面',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _startSearch, child: const Text('搜索')),
              ],
            ),
          ),
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else if (_items.isEmpty && _searching)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在向已启用书源搜集封面…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_search_outlined,
                        size: 42,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '暂时没搜到可用封面图片，可以换个关键词再搜一次',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.56,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final busy = _downloadingUrl == item.coverUrl;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickCandidate(item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  color: scheme.surfaceContainerHighest,
                                  child: Image.network(
                                    item.coverUrl,
                                    headers: const {'User-Agent': _coverUa},
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 4,
                                  right: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.58,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.sourceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (busy)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
