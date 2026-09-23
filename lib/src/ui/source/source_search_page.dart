// 在线搜索：一次输入，多源并发搜索；同书多源自动合并展示，详情页可切换来源。
import 'package:flutter/material.dart';

import '../../data/book_store.dart';
import '../../data/prefs.dart';
import '../../source/models.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';
import '../widgets/kanban_mascot.dart';
import 'online_book_page.dart';

class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({
    super.key,
    required this.store,
    required this.bookStore,
    required this.prefs,
    this.initialQuery,
  });

  final SourceStore store;
  final BookStore bookStore;
  final AppPrefs prefs;

  /// 打开时预填并自动搜索的关键词（从书架搜索携带过来）。
  final String? initialQuery;

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

/// 合并后的「一本书」：同名同作者的结果聚合，保存各来源变体（保持书源顺序）。
class _MergedBook {
  final List<OnlineBookVariant> variants = [];

  /// 与搜索关键词的相关性（取各变体最高分），用于排序。
  int rank = 0;

  /// 首次出现顺序（稳定排序的兜底键）。
  int order = 0;

  SearchBook get lead => variants.first.book;

  String get title => (lead.name ?? '（未命名）').trim();

  String get author => (lead.author ?? '').trim();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final TextEditingController _controller = TextEditingController();
  OnlineRepo? _repo;

  List<BookSource> _active = const [];
  final Map<String, SourceSearchResult> _results = {};
  bool _searching = false;
  int _searchSeq = 0;

  /// 当前搜索关键词（用于结果相关性排序）。
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
      // 首帧后再发起搜索（避免 initState 阶段用到 context 弹提示）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final key = _controller.text.trim();
    if (key.isEmpty || _searching) return;

    final enabled = widget.store.enabled;
    if (enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有启用的书源，请先在「设置 → 书源管理」导入')),
      );
      return;
    }

    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _active = enabled;
      _keyword = key;
      _results.clear();
    });

    final repo = _repo ??= OnlineRepo(store: widget.store);
    await repo.searchAll(
      key,
      onSourceDone: (r) {
        if (!mounted || seq != _searchSeq) return;
        setState(() => _results[r.source.bookSourceUrl] = r);
      },
    );
    if (!mounted || seq != _searchSeq) return;
    setState(() => _searching = false);
  }

  /// 跨源合并：同名 + 同作者视为同一本书（保持书源顺序与首次出现顺序）。
  List<_MergedBook> _merged() {
    final groups = <String, _MergedBook>{};
    final order = <String>[];
    final seen = <String>{};
    for (final s in _active) {
      final r = _results[s.bookSourceUrl];
      if (r == null) continue;
      for (final b in r.books) {
        final url = (b.bookUrl ?? '').trim();
        if (url.isEmpty) continue;
        if (!seen.add('${s.bookSourceUrl}|$url')) continue;
        final key = bookMergeKey(b);
        final g = groups.putIfAbsent(key, () {
          order.add(key);
          return _MergedBook();
        });
        g.variants.add(OnlineBookVariant(r.source, b));
      }
    }
    // 相关性排序：完全匹配的书名排前；同分按来源数；再同分保持首次出现顺序。
    final list = <_MergedBook>[];
    for (final k in order) {
      final g = groups[k]!;
      g.order = list.length;
      var best = 0;
      for (final v in g.variants) {
        final s = bookRelevanceScore(v.book, _keyword);
        if (s > best) best = s;
      }
      g.rank = best;
      list.add(g);
    }
    list.sort((a, b) {
      final c = b.rank.compareTo(a.rank);
      if (c != 0) return c;
      final c2 = b.variants.length.compareTo(a.variants.length);
      if (c2 != 0) return c2;
      return a.order.compareTo(b.order);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _start(),
          decoration: const InputDecoration(
            hintText: '搜索书名 / 作者',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _searching ? null : _start,
            icon: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_active.isEmpty) {
      return _IdleView(
        hasSources: !widget.store.isEmpty,
        onHintTap: () => _controller.text.isEmpty ? null : _start(),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final merged = _merged();
    var rawCount = 0;
    var doneCount = 0;
    final failures = <SourceSearchResult>[];
    for (final s in _active) {
      final r = _results[s.bookSourceUrl];
      if (r == null) continue;
      doneCount++;
      rawCount += r.books.length;
      if (!r.ok) failures.add(r);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            _searching
                ? '已完成 $doneCount / ${_active.length} 个书源 · 已找到 ${merged.length} 本'
                : '搜索完成：${merged.length} 本（原始 $rawCount 条 · $doneCount 个书源）',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        if (failures.isNotEmpty) _failuresNotice(context, failures),
        if (!_searching && merged.isEmpty && doneCount == _active.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
            child: Text(
              '没有找到结果',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        for (final m in merged) _mergedTile(context, m),
      ],
    );
  }

  Widget _failuresNotice(
    BuildContext context,
    List<SourceSearchResult> failures,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Material(
        color: scheme.errorContainer.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('书源错误'),
              content: SingleChildScrollView(
                child: Text(
                  failures
                      .map((r) => '${r.source.bookSourceName}：${r.error}')
                      .join('\n\n'),
                  style: const TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 15,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${failures.length} 个书源搜索失败（点击查看）',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mergedTile(BuildContext context, _MergedBook m) {
    final scheme = Theme.of(context).colorScheme;
    final b = m.lead;
    final sources = m.variants
        .map((v) => v.source.bookSourceName)
        .toSet()
        .join(' / ');
    return ListTile(
      leading: _cover(context, b.coverUrl),
      title: Text(
        m.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (m.author.isNotEmpty) m.author,
              if (m.variants.length > 1) '${m.variants.length} 个来源',
              if ((b.latestChapterTitle ?? '').isNotEmpty)
                '最新：${b.latestChapterTitle}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 1),
          Text(
            sources,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () => _openMerged(context, m),
    );
  }

  void _openMerged(BuildContext context, _MergedBook m) {
    final readable = [
      for (final v in m.variants)
        if (v.source.bookInfoRule != null || v.source.tocRule != null) v,
    ];
    if (readable.isEmpty) {
      _showUnsupportedSheet(context, m);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineBookPage(
          bookStore: widget.bookStore,
          prefs: widget.prefs,
          variants: readable,
        ),
      ),
    );
  }

  void _showUnsupportedSheet(BuildContext context, _MergedBook m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (m.author.isNotEmpty) m.author,
                  '来源：${m.variants.map((v) => v.source.bookSourceName).toSet().join(' / ')}',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '该来源暂不支持在线阅读（缺少详情/目录规则）\n'
                      '可在「设置 → 书源管理」导入更完整的书源',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, String? url) {
    final placeholder = Container(
      width: 42,
      height: 58,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.menu_book_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .7),
      ),
    );
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 42,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.hasSources, this.onHintTap});

  final bool hasSources;
  final VoidCallback? onHintTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KanbanMascot(size: 150),
            const SizedBox(height: 16),
            Text(
              hasSources ? '输入关键词，一次搜索所有书源' : '先去「设置 → 书源管理」导入书源吧',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
