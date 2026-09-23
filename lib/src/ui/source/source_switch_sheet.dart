// 换源面板：为一本在线书（书架 / 阅读中）重新搜索并切换到新的书源。
//
// 流程：自动用当前书名搜索所有启用书源 → 按相关性排序展示候选
// → 选择后先拉取详情/目录校验，再切换（保留阅读进度，清空旧源章节缓存）。
import 'package:flutter/material.dart';

import '../../data/book_store.dart';
import '../../data/models.dart';
import '../../source/models.dart';
import '../../source/online_book_service.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';

/// 打开换源面板；成功换源返回 true。
Future<bool> showSourceSwitchSheet(
  BuildContext context, {
  required BookStore bookStore,
  required SourceStore sourceStore,
  required Book book,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SourceSwitchSheet(
      bookStore: bookStore,
      sourceStore: sourceStore,
      book: book,
    ),
  );
  return ok == true;
}

class _Candidate {
  _Candidate(this.source, this.book, this.score, this.order);

  final BookSource source;
  final SearchBook book;
  final int score;
  final int order;

  String get name => (book.name ?? '').trim();
  String get author => (book.author ?? '').trim();
  String get url => (book.bookUrl ?? '').trim();
}

class _SourceSwitchSheet extends StatefulWidget {
  const _SourceSwitchSheet({
    required this.bookStore,
    required this.sourceStore,
    required this.book,
  });

  final BookStore bookStore;
  final SourceStore sourceStore;
  final Book book;

  @override
  State<_SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<_SourceSwitchSheet> {
  final OnlineBookService _service = OnlineBookService();

  bool _searching = true;
  String? _error;
  List<_Candidate> _candidates = const [];
  int? _busyIndex;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final enabled = widget.sourceStore.enabled;
      if (enabled.isEmpty) {
        setState(() {
          _searching = false;
          _error = '还没有启用的书源';
        });
        return;
      }
      final repo = OnlineRepo(store: widget.sourceStore);
      final results = await repo.searchAll(widget.book.title);
      if (!mounted) return;

      final all = <_Candidate>[];
      final seen = <String>{};
      var order = 0;
      for (final r in results) {
        if (!r.ok) continue;
        for (final b in r.books) {
          final url = (b.bookUrl ?? '').trim();
          if (url.isEmpty) continue;
          if (!seen.add('${r.source.bookSourceUrl}|$url')) continue;
          all.add(
            _Candidate(
              r.source,
              b,
              bookRelevanceScore(b, widget.book.title),
              order++,
            ),
          );
        }
      }
      all.sort((a, b) {
        final c = b.score.compareTo(a.score);
        if (c != 0) return c;
        return a.order.compareTo(b.order);
      });
      // 只保留与书名 / 作者沾边的候选，避免展示无关书
      final related = [
        for (final c in all)
          if (c.score >= 480) c,
      ];
      final list = related.isNotEmpty ? related : all;
      if (!mounted) return;
      setState(() {
        _searching = false;
        _candidates = list;
        if (list.isEmpty) _error = '没有找到可用的换源结果';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pick(int index) async {
    if (_busyIndex != null) return;
    final cand = _candidates[index];
    setState(() => _busyIndex = index);
    try {
      final info = await _service.fetchInfo(cand.source, cand.url);
      if (info.chapters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('该来源目录为空，无法切换')));
        }
        return;
      }
      await widget.bookStore.switchOnlineSource(
        widget.book.id,
        path: cand.url,
        sourceUrl: cand.source.bookSourceUrl,
        chapters: info.chapters,
        title: info.name ?? cand.name,
        author: info.author ?? cand.author,
        intro: info.intro,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('换源失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentSource = widget.sourceStore
        .byUrl(widget.book.sourceUrl ?? '')
        ?.bookSourceName;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '换源 · ${widget.book.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (currentSource != null)
                    Text(
                      '当前：$currentSource',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildList(context, scheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, ColorScheme scheme) {
    if (_searching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在搜索可用书源…', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      itemCount: _candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final c = _candidates[i];
        final isCurrent = c.url == widget.book.path;
        final busy = _busyIndex == i;
        return Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isCurrent || busy ? null : () => _pick(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name.isEmpty ? '（未命名）' : c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (c.author.isNotEmpty) c.author,
                            c.source.bookSourceName,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (isCurrent)
                    Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
