// 发现页：按书源分类浏览书单。
//
// 结构（与 Legado 一致）：
//   顶部「书源」下拉 → 选中源后显示该源的分类标签 → 点分类展示书单
//
// 为什么不是「跨源共享分类名」：实测 1093 个书源里，各家的分类名完全不同
// （七猫叫「男生 / 都市人生」，PO18 叫「都市 / 浓情」），按分类名跨源匹配
// 永远匹配不到 —— 首版就是这么写错的（用户反馈「发现页什么都没有」）。
//
// exploreUrl 支持三种写法（实测分布）：
//   行格式 `标题::地址`（316 个）、JSON 数组（318 个）、JS 脚本（168 个，不支持）
import 'package:flutter/material.dart';

import '../../data/book_store.dart';
import '../../data/prefs.dart';
import '../../source/models.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';
import '../widgets/cute.dart';
import 'online_book_page.dart';

/// 同名书的多个来源。
class _MergedBook {
  _MergedBook(this.title, this.author);

  final String title;
  final String author;
  final List<(BookSource, SearchBook)> variants = [];

  SearchBook get lead => variants.first.$2;
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.bookStore,
    required this.prefs,
    required this.sourceStore,
  });

  final BookStore bookStore;
  final AppPrefs prefs;
  final SourceStore sourceStore;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  late final OnlineRepo _repo = OnlineRepo(store: widget.sourceStore);

  /// 支持发现页的书源。
  List<BookSource> _sources = const [];

  /// 当前选中的书源。
  BookSource? _source;

  /// 当前源的分类。
  List<ExploreCategory> _categories = const [];

  /// 当前选中的分类。
  ExploreCategory? _category;

  bool _loading = false;
  String? _error;
  List<_MergedBook> _books = const [];

  /// 统计信息（无可用源时提示用）。
  ({int capable, int total, int jsOnly})? _stats;

  @override
  void initState() {
    super.initState();
    // 书源在别的页面被导入 / 启用 / 删除时（本页常驻 IndexedStack），
    // 及时刷新可用源列表，避免用户导入后回到发现页仍是空的。
    widget.sourceStore.addListener(_onStoreChanged);
    _reloadSources(autoSelect: true);
  }

  @override
  void dispose() {
    widget.sourceStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    final list = _repo.exploreCapableSources();
    final keep = _source;
    final keepAlive =
        keep != null && list.any((s) => s.bookSourceUrl == keep.bookSourceUrl);
    setState(() {
      _sources = list;
      _stats = _repo.exploreStats();
      if (keepAlive) return;
      _books = const [];
      _error = null;
      if (list.isEmpty) {
        _source = null;
        _categories = const [];
        _category = null;
        return;
      }
      _source = list.first;
      _categories = OnlineRepo.parseExploreCategories(list.first);
      _category = _categories.isEmpty ? null : _categories.first;
    });
    if (!keepAlive && _category != null) _load();
  }

  /// 重新枚举支持发现页的书源。
  void _reloadSources({bool autoSelect = false}) {
    final list = _repo.exploreCapableSources();
    setState(() {
      _sources = list;
      _stats = _repo.exploreStats();
      if (list.isNotEmpty && (_source == null || autoSelect)) {
        _source = list.first;
        _categories = OnlineRepo.parseExploreCategories(list.first);
        _category = _categories.isNotEmpty ? _categories.first : null;
      }
    });
    if (_category != null) _load();
  }

  /// 切换书源。
  void _selectSource(BookSource s) {
    setState(() {
      _source = s;
      _categories = OnlineRepo.parseExploreCategories(s);
      _category = _categories.isNotEmpty ? _categories.first : null;
      _books = const [];
      _error = null;
    });
    if (_category != null) _load();
  }

  /// 切换分类。
  void _selectCategory(ExploreCategory c) {
    if (_category?.title == c.title) return;
    setState(() {
      _category = c;
      _books = const [];
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    final category = _category;
    if (source == null || category == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.exploreSource(source, category);
    if (!mounted) return;
    final merged = _merge([result]);
    setState(() {
      _loading = false;
      _books = merged;
      if (result.error != null) {
        _error = '抓取失败：${result.error}';
      } else if (merged.isEmpty) {
        _error = '这个分类没有解析到书单（该源可能改版或规则不兼容）';
      }
    });
  }

  /// 多源结果 → 同名同作者合并。
  List<_MergedBook> _merge(List<SourceExploreResult> results) {
    final map = <String, _MergedBook>{};
    for (final r in results) {
      for (final b in r.books) {
        final name = b.name ?? '';
        if (name.isEmpty) continue;
        final key = '$name::${b.author ?? ''}'.toLowerCase();
        final m = map.putIfAbsent(key, () => _MergedBook(name, b.author ?? ''));
        m.variants.add((r.source, b));
      }
    }
    return map.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.isEmpty) return _buildEmpty();
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          IconButton(
            onPressed: () => _reloadSources(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新检测书源',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSourceSelector(),
          if (_categories.isNotEmpty) _buildCategoryBar(),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  /// 空状态：没有任何书源支持发现页。
  Widget _buildEmpty() {
    final s = _stats;
    final js = s?.jsOnly ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: EmptyState(
        icon: Icons.explore_outlined,
        title: '没有可用的发现页书源',
        subtitle:
            '共启用 ${s?.total ?? 0} 个书源，其中没有一个能被静态解析\n'
            '${js > 0 ? '（另有 $js 个书源使用 JS 脚本生成分类，暂不支持）\n' : ''}'
            '\n'
            '发现页需要书源里的 exploreUrl 是「行格式」或「JSON 数组」：\n'
            '· 行格式：玄幻::https://站点/list/{{page}}.html\n'
            '· JSON：[{"title":"玄幻","url":"https://..."}]\n'
            '\n'
            '可在「设置 → 书源管理」导入带此类规则的书源',
        actions: [
          FilledButton.icon(
            onPressed: () => _reloadSources(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新检测'),
          ),
        ],
      ),
    );
  }

  /// 书源选择行。
  Widget _buildSourceSelector() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.source_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<BookSource>(
                value: _source,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final s in _sources)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.bookSourceName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _selectSource(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_sources.length} 个可用',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          // 用户反馈「希望能支持 js 格式的书源」：JS 引擎暂未内置，
          // 这里明确告诉用户有多少个源因此用不了，避免以为是导入失败。
          if ((_stats?.jsOnly ?? 0) > 0) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: '这些书源的发现地址是 JS 脚本（@js / <js>），当前版本还不支持执行',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'JS 源 ${_stats!.jsOnly}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 分类标签条。
  Widget _buildCategoryBar() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = _categories[i];
          return ChoiceChip(
            label: Text(c.title),
            selected: _category?.title == c.title,
            onSelected: (_) => _selectCategory(c),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '没有拿到书单',
        subtitle: error,
        actions: [
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _books.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) => _buildTile(context, _books[i]),
      ),
    );
  }

  Widget _buildTile(BuildContext context, _MergedBook m) {
    final scheme = Theme.of(context).colorScheme;
    final b = m.lead;
    final sources = m.variants
        .map((v) => v.$1.bookSourceName)
        .toSet()
        .join(' / ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      onTap: () => _open(context, m),
    );
  }

  /// 打开书籍详情。
  void _open(BuildContext context, _MergedBook m) {
    final readable = <OnlineBookVariant>[];
    for (final (source, book) in m.variants) {
      if (source.bookInfoRule != null || source.tocRule != null) {
        readable.add(OnlineBookVariant(source, book));
      }
    }
    if (readable.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该书来源暂不支持在线阅读（缺少详情/目录规则）')));
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
