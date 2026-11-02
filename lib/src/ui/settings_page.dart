import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/display_service.dart';
import '../app_info.dart';
import '../data/book_store.dart';
import '../data/pet_guide.dart';
import '../data/pet_store.dart';
import '../data/prefs.dart';
import '../data/tts_voice_catalog.dart';
import '../data/tts_voice_store.dart';
import '../data/stats_store.dart';
import '../platform/native_bridge.dart';
import '../platform/tts_service.dart';
import '../platform/url_launcher.dart';
import '../platform/update_service.dart';
import '../source/source_store.dart';
import '../util/format.dart';
import 'ai_chat_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'legado_import_page.dart';
import 'reader/reader_page.dart';
import 'reader/reader_settings_panel.dart';
import 'source/source_manager_page.dart';
import 'stats_page.dart';
import 'update_dialog.dart';
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

  /// 手动检查更新进行中（按钮转圈、避免重复点击）。
  bool _checkingUpdate = false;

  /// 设备上可用的朗读引擎（懒加载）。
  List<String>? _ttsEngines;

  /// 当前引擎的音色名列表（null = 还没加载）。
  List<String>? _ttsVoices;

  /// 音色加载中。
  bool _ttsVoicesLoading = false;

  /// 朗读引擎探测中。
  bool _ttsProbing = false;

  /// 上一次朗读自检结果（null = 未测过）。
  String? _ttsProbeResult;
  bool _ttsProbeOk = false;

  @override
  void initState() {
    super.initState();
    unawaited(TtsVoiceStore.instance.refresh());
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

  /// 「语音包」区块：内置音色 + 可下载的语音包，多说话人的还能挑音色。
  ///
  /// 用户反馈「语音模型应该是选择下载的，不是打在包里」——所以除了随包的
  /// 超文，其余都是点了才下载、可单独删除。
  Widget _voicePackSection(BuildContext context, ColorScheme scheme) {
    final store = TtsVoiceStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final currentId = widget.prefs.ttsVoicePack;
        final current = ttsVoicePackById(currentId) ?? builtinVoicePack;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '语音包',
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '内置只有一个音色，想要男声 / 女声自己下载',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final pack in ttsVoiceCatalog)
              _voicePackTile(context, scheme, store, pack, currentId),
            if (current.isMultiSpeaker) ...[
              const SizedBox(height: 10),
              Text(
                '音色（共 ${current.speakerCount} 个说话人，先挑几个常用的）',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final preset in current.presets)
                    ChoiceChip(
                      label: Text(
                        preset.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: widget.prefs.ttsVoiceSid == preset.sid,
                      onSelected: (_) {
                        widget.prefs.setTtsVoiceSid(preset.sid);
                        unawaited(
                          TtsService.instance.setVoicePack(
                            current.id,
                            preset.sid,
                          ),
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _voicePackTile(
    BuildContext context,
    ColorScheme scheme,
    TtsVoiceStore store,
    TtsVoicePack pack,
    String currentId,
  ) {
    final installed = store.isInstalled(pack.id);
    final downloading = store.isDownloading(pack.id);
    final active = currentId == pack.id;
    final error = store.errorOf(pack.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: active
            ? Border.all(color: scheme.primary.withValues(alpha: 0.55))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          pack.bundled
                              ? '内置'
                              : '${pack.sizeMb.toStringAsFixed(0)} MB',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pack.tagline,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (downloading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: store.progressOf(pack.id) == 0
                        ? null
                        : store.progressOf(pack.id),
                  ),
                )
              else if (installed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!active)
                      TextButton(
                        onPressed: () => _selectVoicePack(pack),
                        child: const Text('使用', style: TextStyle(fontSize: 12)),
                      ),
                    if (!pack.bundled)
                      IconButton(
                        tooltip: '删除这个语音包',
                        onPressed: store.downloadingId == null
                            ? () async {
                                await store.remove(pack.id);
                                if (widget.prefs.ttsVoicePack == pack.id) {
                                  widget.prefs.setTtsVoicePack(
                                    builtinVoicePack.id,
                                  );
                                  widget.prefs.setTtsVoiceSid(0);
                                  unawaited(
                                    TtsService.instance.setVoicePack(
                                      builtinVoicePack.id,
                                      0,
                                    ),
                                  );
                                }
                                if (mounted) setState(() {});
                              }
                            : null,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                  ],
                )
              else
                FilledButton.tonal(
                  onPressed: store.downloadingId == null
                      ? () => _downloadVoicePack(pack)
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('下载', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: store.progressOf(pack.id) == 0
                  ? null
                  : store.progressOf(pack.id),
              minHeight: 4,
            ),
            const SizedBox(height: 4),
            Text(
              store.progressOf(pack.id) >= 0.99
                  ? '下载完成，正在解压…'
                  : '下载中 ${(store.progressOf(pack.id) * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error, style: TextStyle(fontSize: 11.5, color: scheme.error)),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadVoicePack(TtsVoicePack pack) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await TtsVoiceStore.instance.install(pack);
    if (!mounted) return;
    if (ok) {
      await _selectVoicePack(pack);
      messenger.showSnackBar(SnackBar(content: Text('「${pack.name}」装好了，已切换')));
    } else {
      setState(() {});
    }
  }

  Future<void> _selectVoicePack(TtsVoicePack pack) async {
    widget.prefs.setTtsVoicePack(pack.id);
    widget.prefs.setTtsVoiceSid(pack.defaultSid);
    await TtsService.instance.setVoicePack(pack.id, pack.defaultSid);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.prefs,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          // 与书架同一个坑：底栏 extendBody 盖住正文，默认 FAB 会压在「设置」格上。
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 96),
            child: FloatingActionButton.small(
              // 与书架的 FAB 区分（两者同时在 IndexedStack 中存活，避免 Hero tag 冲突）
              heroTag: 'settings-theme-fab',
              onPressed: _toggleTheme,
              tooltip: isDark ? '切换到浅色模式' : '切换到深色模式',
              child: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              ),
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
              _ttsCard(context),
              const SizedBox(height: 14),
              _petCard(context),
              const SizedBox(height: 14),
              _performanceCard(context),
              const SizedBox(height: 14),
              _statsCard(context),
              const SizedBox(height: 14),
              _aiCard(context),
              const SizedBox(height: 14),
              _sourceCard(context),
              const SizedBox(height: 14),
              _storageCard(context),
              const SizedBox(height: 14),
              _dataCard(context),
              const SizedBox(height: 14),
              _helpCard(context),
              const SizedBox(height: 14),
              _updateCard(context),
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
          const SizedBox(height: 6),
          // 用户反馈「调来调去都没有磨砂」：以前只有半透明蒙层，没有真模糊
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.frostedGlass,
            onChanged: prefs.setFrostedGlass,
            secondary: const Icon(Icons.blur_on_rounded),
            title: const Text('磨砂玻璃', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '阅读页顶栏 / 底栏用实时模糊，透出下面的正文；低端机上会略耗电',
              style: TextStyle(fontSize: 12),
            ),
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
          AnimatedBuilder(
            animation: pet,
            builder: (_, _) => SwitchListTile(
              title: const Text('显示桌宠'),
              subtitle: const Text('可完全关闭；不会锁屏或强制互动'),
              value: pet.enabled,
              onChanged: pet.setEnabled,
            ),
          ),
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

  Widget _aiCard(BuildContext context) {
    final prefs = widget.prefs;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.auto_awesome_rounded, title: 'AI 助手'),
          const SizedBox(height: 6),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: const AssetImage('assets/images/pet_wave.png'),
            ),
            title: const Text('小樱 AI 助手', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              prefs.aiConfigured
                  ? '已配置 · ${prefs.aiModel}${prefs.aiIncludeReading ? ' · 可读取阅读数据' : ''}'
                  : '还没配置接口，点右侧设置',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AiSettingsPage(prefs: prefs)),
              ),
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: 'AI 设置',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AiChatPage(
                  store: widget.store,
                  prefs: prefs,
                  statsStore: widget.statsStore,
                ),
              ),
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
          // 用户反馈：「书源搜索能不能设置线程，搜索太慢了」——并发数可调
          AnimatedBuilder(
            animation: widget.prefs,
            builder: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed_rounded),
                  title: const Text('搜索并发数', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '同时搜索 ${widget.prefs.searchConcurrency} 个书源 · '
                    '调大更快，弱网时容易失败',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Slider(
                  value: widget.prefs.searchConcurrency.clamp(1, 32).toDouble(),
                  min: 1,
                  max: 32,
                  divisions: 31,
                  label: '${widget.prefs.searchConcurrency} 个',
                  onChanged: (v) =>
                      widget.prefs.setSearchConcurrency(v.round()),
                ),
                // 用户反馈「并发数改无上限可让用户选择」：滑杆到 32 之后
                // 还能手填，最大 32（再多也只会被系统网络栈拖死）。
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _customConcurrency(context),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('自定义（最多 32）'),
                  ),
                ),
              ],
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

  /// 用户反馈：「后期考不考虑添加 WebDAV 或其他备份功能」「能把阅读的数据导进来吗」
  Widget _dataCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.inventory_2_rounded, title: '数据'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_rounded),
            title: const Text('备份与恢复', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              widget.prefs.lastBackupAt.isEmpty
                  ? '本地 zip 备份，也可以传到 WebDAV'
                  : '上次备份：${widget.prefs.lastBackupAt.replaceFirst('T', ' ').split('.').first}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BackupPage(prefs: widget.prefs),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.move_to_inbox_rounded),
            title: const Text('从「阅读」导入', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '读取「阅读 3.0」的备份文件，把书架搬过来',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LegadoImportPage(
                  prefs: widget.prefs,
                  shelf: widget.store,
                  sources: widget.sourceStore,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpCard(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.school_rounded, title: '帮助'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.replay_rounded),
            title: const Text('重看新手引导', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '小樱再带你走一遍搜书、导入等功能',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _replayGuide,
          ),
        ],
      ),
    );
  }

  /// 重看新手引导：先切回书架（主界面监听该信号），再请求引导层重播。
  ///
  /// 引导按设计只在首次启动自动出现一次；这是用户**主动重看**的入口，
  /// 处理旧版本「已看过」标记导致升级后见不到引导的困惑。
  void _replayGuide() {
    final already = kPetGuideActive.value;
    petGuideRequestReplay();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(already ? '小樱正在给你带路呢～' : '小樱马上就来找你～'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 朗读卡片：引擎选择 + 自检。
  ///
  /// 用户反馈「一加15 自带语音引擎，用不了朗读」：国产 ROM 的引擎有时
  /// 不会被系统选为默认，需要能让用户**手动指定**并当场验证。
  Widget _ttsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tts = TtsService.instance;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.record_voice_over_rounded,
            title: '朗读',
          ),
          const SizedBox(height: 4),
          Text(
            '没声音？换一个语音引擎试试；系统没有引擎也能用「内置离线语音」',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // 引擎选择
          AnimatedBuilder(
            animation: tts,
            builder: (_, _) {
              final engines = _ttsEngines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (engines == null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.memory_rounded, size: 20),
                      title: const Text('语音引擎', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        _ttsProbing ? '正在检测…' : '点击检测设备上的语音引擎',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: _ttsProbing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: _ttsProbing ? null : _probeTtsEngines,
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: DropdownButtonFormField<String>(
                        initialValue: widget.prefs.ttsEngine,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '语音引擎',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('系统默认（推荐）'),
                          ),
                          // 内置离线语音：系统没引擎时的兜底，永远可选
                          const DropdownMenuItem(
                            value: TtsService.builtinEngineId,
                            child: Text('内置离线语音（无需安装）'),
                          ),
                          for (final e in engines)
                            DropdownMenuItem(
                              value: e,
                              child: Text(
                                _shortEngineName(e),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => _changeTtsEngine(v ?? ''),
                      ),
                    ),
                    if (engines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '这台设备没检测到系统语音引擎，可以直接用上面的「内置离线语音」；'
                                '想用系统音色就点下面的按钮去安装。',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  // 音色（男声 / 女声）：系统引擎的 voices 列表
                  if (engines != null &&
                      engines.isNotEmpty &&
                      widget.prefs.ttsEngine != TtsService.builtinEngineId) ...[
                    const SizedBox(height: 8),
                    if (_ttsVoices == null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.record_voice_over, size: 20),
                        title: const Text(
                          '音色（男声 / 女声）',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          '点「检测引擎」后就能选这台手机里的音色',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: _ttsVoicesLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: _ttsVoicesLoading ? null : _loadTtsVoices,
                      )
                    else if (_ttsVoices!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '这个引擎没提供音色列表，只能用默认声音。',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            _ttsVoices!.contains(widget.prefs.ttsVoice)
                            ? widget.prefs.ttsVoice
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '音色（男声 / 女声）',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('引擎默认音色'),
                          ),
                          for (final v in _ttsVoices!)
                            DropdownMenuItem(
                              value: v,
                              child: Text(v, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) async {
                          widget.prefs.setTtsVoice(v ?? '');
                          final ok = await tts.setPreferredVoice(v ?? '');
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? '音色已切换，点「测试朗读」听听看' : '这个音色暂时用不了，先保持默认',
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                  // 音色风格：内置离线语音只有一种声音，用音调模拟男女声
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_voicePackSection(context, scheme)],
                    ),
                  ),
                  // AI 分角色朗读：本地规则区分旁白 / 对白，不联网
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.prefs.ttsRolePlay,
                    onChanged: widget.prefs.setTtsRolePlay,
                    secondary: const Icon(Icons.theater_comedy_rounded),
                    title: const Text(
                      'AI 分角色朗读',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '旁白和对白用不同音调，同一角色保持一致；完全本地，不花 token',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_ttsProbeResult != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _ttsProbeOk
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: _ttsProbeOk ? scheme.primary : scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _ttsProbeResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _ttsProbeOk
                                  ? scheme.onSurfaceVariant
                                  : scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _ttsProbing ? null : _probeTtsEngines,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('检测引擎'),
              ),
              FilledButton.icon(
                onPressed: _ttsProbing ? null : _testTts,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('测试朗读'),
              ),
              if (_ttsEngines != null && _ttsEngines!.isEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await NativeBridge.openTtsSettings();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('没能打开系统语音设置，请手动到「设置 → 无障碍 → 语音合成」查看'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('去装系统语音'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 加载当前引擎的音色列表（男声 / 女声）。
  Future<void> _loadTtsVoices() async {
    if (_ttsVoicesLoading) return;
    setState(() => _ttsVoicesLoading = true);
    try {
      final tts = TtsService.instance;
      await tts.ensureReady();
      final list = await tts.voices();
      if (!mounted) return;
      setState(() => _ttsVoices = list);
    } finally {
      if (mounted) setState(() => _ttsVoicesLoading = false);
    }
  }

  /// 自定义并发数（1~32）。
  Future<void> _customConcurrency(BuildContext context) async {
    final controller = TextEditingController(
      text: '${widget.prefs.searchConcurrency}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义并发数'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '同时搜索的书源个数',
            helperText: '1 ~ 32；太多容易被书源站限流',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(v);
            },
            child: const Text('好'),
          ),
        ],
      ),
    );
    if (value == null) return;
    widget.prefs.setSearchConcurrency(value.clamp(1, 32));
  }

  /// 引擎包名 → 友好短名（如 `com.iflytek.tts` → `iflytek`）。
  String _shortEngineName(String pkg) {
    final parts = pkg.split('.');
    if (parts.length >= 2) return '${parts[parts.length - 2]} · $pkg';
    return pkg;
  }

  /// 检测设备上可用的朗读引擎。
  Future<void> _probeTtsEngines() async {
    setState(() {
      _ttsProbing = true;
      _ttsProbeResult = null;
    });
    final tts = TtsService.instance;
    final list = await tts.engines();
    if (!mounted) return;
    // 把用户已选引擎同步给服务（首次进入设置页时）
    await tts.setPreferredEngine(widget.prefs.ttsEngine);
    if (!mounted) return;
    // 引擎列表出来后顺手把音色也读一次，省得用户再点一次（男声 / 女声）
    final voices = list.isEmpty ? const <String>[] : await tts.voices();
    if (!mounted) return;
    setState(() {
      _ttsEngines = list;
      _ttsVoices = voices;
      _ttsProbing = false;
      _ttsProbeResult = list.isEmpty
          ? '没有系统语音引擎，可以改用上面的「内置离线语音」'
          : '检测到 ${list.length} 个引擎';
      // 系统引擎为空不算失败：内置离线语音能兜住
      _ttsProbeOk = true;
    });
  }

  /// 切换引擎并重新初始化。
  Future<void> _changeTtsEngine(String engine) async {
    final tts = TtsService.instance;
    widget.prefs.setTtsEngine(engine);
    await tts.setPreferredEngine(engine);
    if (!mounted) return;
    setState(() {
      _ttsProbeResult = engine == TtsService.builtinEngineId
          ? '已切到内置离线语音（首次使用会释放语音模型，约需几秒）'
          : '已切换引擎，点「测试朗读」验证';
      _ttsProbeOk = true;
    });
  }

  /// 自检：真正初始化一次 TTS 并试播一小段。
  Future<void> _testTts() async {
    final tts = TtsService.instance;
    setState(() {
      _ttsProbing = true;
      _ttsProbeResult = null;
    });
    await tts.setPreferredEngine(widget.prefs.ttsEngine);
    final ok = await tts.reinit();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _ttsProbing = false;
        _ttsProbeOk = false;
        _ttsProbeResult = tts.lastError ?? '初始化失败，试试换一个引擎';
      });
      return;
    }
    // 试播一句中文，确认真的能出声（有些引擎初始化成功但中文缺失）
    await tts.start(['樱读朗读测试，听到这句话说明朗读正常。'], from: 0);
    if (!mounted) return;
    setState(() {
      _ttsProbing = false;
      _ttsProbeOk = true;
      _ttsProbeResult = tts.usingOffline
          ? '正在用内置离线语音播放…能听到声音就说明可用'
          : '正在播放测试语音…能听到声音就说明可用';
    });
  }

  /// 性能：帧率浮层开关（排查「卡」的时候最直接）。
  Widget _performanceCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.speed_rounded, title: '性能'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.monitor_heart_outlined),
            title: const Text('显示帧率', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '在屏幕上方叠加实时帧率与每帧耗时（排查卡顿用）',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            value: widget.prefs.showPerformanceOverlay,
            onChanged: (v) => widget.prefs.setShowPerformanceOverlay(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.slow_motion_video_rounded),
            title: const Text('高刷新率', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '有 120Hz 屏幕时按最高刷新率出帧，而不是固定 60Hz；关掉更省电',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            value: widget.prefs.highRefreshRate,
            onChanged: (v) {
              widget.prefs.setHighRefreshRate(v);
              DisplayService.setHighRefresh(v);
            },
          ),
        ],
      ),
    );
  }

  /// 更新卡片：手动检查更新 + 启动自动检查开关。
  Widget _updateCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.system_update_rounded, title: '检查更新'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('检查新版本', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '当前版本 v${AppInfo.version}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: _checkingUpdate ? null : _checkUpdate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.schedule_rounded),
            title: const Text('启动时自动检查更新', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '有新版时弹出更新公告（默认通过国内镜像下载）',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            value: widget.prefs.autoCheckUpdate,
            onChanged: (v) => widget.prefs.setAutoCheckUpdate(v),
          ),
        ],
      ),
    );
  }

  /// 手动检查更新（无论是否「以后再说」都会展示结果）。
  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        await showUpdateDialog(
          context,
          info: result.info!,
          isAuto: false,
          prefs: widget.prefs,
        );
        // 手动检查不记「以后再说」，也不清除已记版本
        break;
      case UpdateCheckStatus.upToDate:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已经是最新版本啦～'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case UpdateCheckStatus.failed:
        messenger.showSnackBar(
          SnackBar(
            content: const Text('检查更新失败，请稍后重试（网络繁忙）'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '重试', onPressed: _checkUpdate),
          ),
        );
        break;
    }
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
            'v${AppInfo.version} · 本地 + 在线小说阅读器',
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
          const SizedBox(height: 14),
          // 开源信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    const Text(
                      '开源信息',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _aboutRow(context, '作者', AppInfo.author),
                _aboutRow(context, '许可证', AppInfo.license),
                _aboutRow(
                  context,
                  '项目主页',
                  'github.com/akira399/sakura-read',
                  onTap: () async {
                    final ok = await launchUrlString(AppInfo.repo);
                    if (!context.mounted || ok) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('没有找到可用的浏览器'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '声明：本软件是阅读工具，不提供、不分发任何书籍内容；\n'
            '通过书源获取的正文来自第三方网站，版权归原作者所有。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.7,
              color: scheme.onSurfaceVariant.withValues(alpha: .8),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '用 Flutter 构建 · Made by ${AppInfo.author}',
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

  /// 关于卡里的一行「键 - 值」（值可按需点击）。
  Widget _aboutRow(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final valueStyle = TextStyle(
      fontSize: 11.5,
      color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
      decoration: onTap == null ? null : TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: .5),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant.withValues(alpha: .75),
              ),
            ),
          ),
          Expanded(
            child: onTap == null
                ? Text(value, style: valueStyle)
                : GestureDetector(
                    onTap: onTap,
                    child: Text(value, style: valueStyle),
                  ),
          ),
        ],
      ),
    );
  }
}
