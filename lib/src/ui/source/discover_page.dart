// 发现页：按书源分类「逛书」，不需要先想好关键词。
//
// 用户反馈（社区最期待的功能之一）：「什么时候能上线那个发现页啊」。
//
// 数据来源：书源的 `exploreUrl` + `ruleExplore` 规则（Legado 兼容）。
// 注意：并非所有书源都配了发现页规则——内置的公版源就没有；因此这里有
// 三重兜底：
//   1. 没有任何源支持 → 明确引导用户去导入带发现页规则的书源；
//   2. 分类下有多个源 → 并发抓取 + 同名合并（与搜索页一致）；
//   3. 单个源失败 → 隔离错误，其它源照常展示。
import 'package:flutter/material.dart';

import '../../data/book_store.dart';
import '../../data/prefs.dart';
import '../../source/models.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';
import '../widgets/cute.dart';
import 'online_book_page.dart';

/// 同名书的多个来源（发现页合并展示）。
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

  /// 可用的分类（来自所有启用书源）。
  List<ExploreCategory> _categories = const [];

  /// 当前选中的分类。
  String? _current;

  bool _loading = false;
  String? _error;
  List<_MergedBook> _books = const [];

  /// 每页条数（发现页按页浏览）。
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _categories = _repo.allExploreCategories();
    if (_categories.isNotEmpty) {
      _current = _categories.first.title;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final category = _current;
    if (category == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _repo.exploreAll(category);
      if (!mounted) return;
      final merged = _merge(results);
      setState(() {
        _books = merged;
        _loading = false;
        _error = merged.isEmpty ? '这个分类暂时没抓到书，换个分类或稍后再试' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  /// 多源结果 → 同名同作者合并（与搜索页一致的用户体验）。
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
    final list = map.values.toList();
    // 来源多的排前面（更可靠）
    list.sort((a, b) => b.variants.length.compareTo(a.variants.length));
    return list.take(_pageSize).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: _categories.isEmpty ? _buildNoExplore() : _buildBody(context),
    );
  }

  /// 没有任何书源支持发现页时的引导。
  Widget _buildNoExplore() {
    return EmptyState(
      icon: Icons.explore_outlined,
      title: '还没有可发现的分类',
      subtitle:
          '发现页需要书源自带「发现规则」（exploreUrl）\n'
          '可在「设置 → 书源管理」导入带发现规则的书源',
      actions: [
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _categories = _repo.allExploreCategories();
              if (_categories.isNotEmpty) {
                _current = _categories.first.title;
              }
            });
            if (_categories.isNotEmpty) _load();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新检测'),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        // 分类选择
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _categories[i];
              return ChoiceChip(
                label: Text(c.title),
                selected: _current == c.title,
                onSelected: (_) {
                  if (_current == c.title) return;
                  setState(() {
                    _current = c.title;
                    _books = const [];
                  });
                  _load();
                },
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '这里暂时是空的',
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
      onTap: () => _open(context, m),
    );
  }

  /// 打开书籍详情（与搜索页同一套逻辑：只保留支持阅读的源）。
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
