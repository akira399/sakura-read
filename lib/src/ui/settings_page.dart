import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/pet_store.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../source/source_store.dart';
import '../util/format.dart';
import 'reader/reader_page.dart';
import 'reader/reader_settings_panel.dart';
import 'source/source_manager_page.dart';
import 'stats_page.dart';
import 'widgets/cute.dart';
import 'widgets/pet_overlay.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.sourceStore,
    required this.statsStore,
  });

  final BookStore store;
  final AppPrefs prefs;
  final SourceStore sourceStore;
  final StatsStore statsStore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await widget.store.cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = size);
  }

  /// 快速切换日间 / 夜间模式（阅读背景与全局主题同步；设置页悬浮按钮）。
  void _toggleTheme() {
    final prefs = widget.prefs;
    final effectiveDark = switch (prefs.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      _ => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    prefs.setNightMode(!effectiveDark);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.prefs,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          floatingActionButton: FloatingActionButton.small(
            // 与书架的 FAB 区分（两者同时在 IndexedStack 中存活，避免 Hero tag 冲突）
            heroTag: 'settings-theme-fab',
            onPressed: _toggleTheme,
            tooltip: isDark ? '切换到浅色模式' : '切换到深色模式',
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 18,
              16,
              100,
            ),
            children: [
              _title(context),
              const SizedBox(height: 16),
              _appearanceCard(context),
              const SizedBox(height: 14),
              _readingCard(context),
              const SizedBox(height: 14),
              _petCard(context),
              const SizedBox(height: 14),
              _statsCard(context),
              const SizedBox(height: 14),
              _sourceCard(context),
              const SizedBox(height: 14),
              _storageCard(context),
              const SizedBox(height: 14),
              _aboutCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _title(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const PetalLogo(size: 42),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设置',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              '把阅读体验调成你喜欢的样子',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _appearanceCard(BuildContext context) {
    final prefs = widget.prefs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.palette_rounded, title: '外观'),
          const SizedBox(height: 14),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {prefs.themeMode},
            onSelectionChanged: (s) => prefs.setThemeMode(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          const Text(
            '主题色',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < AppPrefs.accents.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: () => prefs.setAccentIndex(i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppPrefs.accents[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: prefs.accentIndex == i
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppPrefs.accents[i].withValues(alpha: .45),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: prefs.accentIndex == i
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readingCard(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.menu_book_rounded, title: '阅读偏好'),
          const SizedBox(height: 6),
          Text(
            '也可以在阅读界面点击屏幕中间，随时调整',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          ReaderSettingsPanel(prefs: widget.prefs, petStore: PetStore.shared),
        ],
      ),
    );
  }

  Widget _petCard(BuildContext context) {
    final pet = PetStore.shared;
    if (pet == null) return const SizedBox.shrink();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.pets_rounded, title: '看板娘'),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: pet,
            builder: (_, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 42,
                height: 42,
                child: Image.asset(
                  'assets/images/pet_chibi.png',
                  fit: BoxFit.contain,
                ),
              ),
              title: Text(
                '亲密度 Lv.${pet.level}「${pet.levelName}」',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '已互动 ${pet.interactions} 次 · 点心 '
                '${kPetFoods.map((f) => pet.foodCount(f.id)).fold<int>(0, (a, b) => a + b)} 份',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showPetPanel(context, pet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard(BuildContext context) {
    final bookmarkStore = BookmarkStore.shared;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.insights_rounded, title: '阅读记录'),
          const SizedBox(height: 6),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('阅读统计', style: TextStyle(fontSize: 14)),
            subtitle: AnimatedBuilder(
              animation: widget.statsStore,
              builder: (_, _) => Text(
                '累计 ${formatDuration(widget.statsStore.totalSeconds)} · '
                '连续 ${widget.statsStore.streak} 天 · '
                '读完 ${widget.statsStore.finishedBooks} 本',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StatsPage(statsStore: widget.statsStore),
              ),
            ),
          ),
          if (bookmarkStore != null)
            AnimatedBuilder(
              animation: bookmarkStore,
              builder: (_, _) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmark_border_rounded),
                title: const Text('我的书签', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  bookmarkStore.count == 0
                      ? '阅读时点底栏「书签」收藏精彩段落'
                      : '共 ${bookmarkStore.count} 条书签',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showBookmarks(context, bookmarkStore),
              ),
            ),
        ],
      ),
    );
  }

  /// 全量书签列表（跨书查看，点击删除）。
  void _showBookmarks(BuildContext context, BookmarkStore store) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.62,
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final items = store.items;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_border_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '全部书签 · 共 ${items.length} 条',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                              '还没有书签，去阅读界面收藏吧～',
                              style: TextStyle(fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final b = items[index];
                              final book = widget.store.byId(b.bookId);
                              final title = book == null
                                  ? '（已删除的书）'
                                  : book.title;
                              return ListTile(
                                dense: true,
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${b.chapterTitle.isEmpty ? '第 ${b.chapterIndex + 1} 章' : b.chapterTitle}'
                                  '${b.excerpt.isEmpty ? '' : '\n${b.excerpt}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  tooltip: '删除',
                                  onPressed: () => store.remove(b.id),
                                ),
                                onTap: book == null
                                    ? null
                                    : () {
                                        Navigator.of(sheetContext).pop();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ReaderPage(
                                              store: widget.store,
                                              prefs: widget.prefs,
                                              bookId: b.bookId,
                                              chapterIndex: b.chapterIndex,
                                              charOffset: b.charOffset,
                                            ),
                                          ),
                                        );
                                      },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sourceCard(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.cloud_outlined, title: '书源'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_rounded),
            title: const Text('书源管理', style: TextStyle(fontSize: 14)),
            subtitle: AnimatedBuilder(
              animation: widget.sourceStore,
              builder: (_, _) => Text(
                widget.sourceStore.isEmpty
                    ? '导入「阅读 3.0」格式的书源，搜遍全网小说'
                    : '共 ${widget.sourceStore.sources.length} 个 · '
                          '已启用 ${widget.sourceStore.enabledCount} 个',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SourceManagerPage(store: widget.sourceStore),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageCard(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.cleaning_services_rounded,
            title: '存储',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_snippet_rounded),
            title: const Text('EPUB 章节缓存', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              _cacheBytes == null ? '计算中…' : formatBytes(_cacheBytes!),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await widget.store.clearCache();
              await _loadCacheSize();
              if (!mounted) return;
              messenger.showSnackBar(const SnackBar(content: Text('缓存已清空')));
            },
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('清除缓存'),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Image.asset(
              'assets/images/pet_wave.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '樱读',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'v1.3.1 · 本地 + 在线小说阅读器',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(
            '二次元风格的阅读器\n本地 TXT / EPUB + 书源在线搜书 · 看书 · 一键换源',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '用 Flutter 构建 · 由 Operit 制作',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
