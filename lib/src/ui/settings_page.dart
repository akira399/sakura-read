import 'package:flutter/material.dart';

import '../core/icons/sakura_icons.dart';
import '../core/motion/sakura_motion.dart';
import '../core/theme/sakura_layout.dart';
import '../core/theme/sakura_tokens.dart';
import '../data/book_store.dart';
import '../data/pet_store.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../data/tts_voice_catalog.dart';
import '../data/tts_voice_store.dart';
import '../features/book_source/replace_rule_store.dart';
import '../features/book_source/replace_rules_page.dart';
import '../features/settings/appearance_studio_page.dart';
import '../features/settings/reading_defaults_page.dart';
import '../features/settings/system_about_page.dart';
import '../features/settings/tts_settings_page.dart';
import '../source/source_store.dart';
import '../util/format.dart';
import 'ai_chat_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'legado_import_page.dart';
import 'reader/reader_page.dart';
import 'source/source_manager_page.dart';
import 'stats_page.dart';
import 'widgets/pet_overlay.dart';

/// 设置 2.5 主控台（清爽分组枢纽 + 小樱伴读名片 + 全风格联动）。
///
/// 摒弃旧版冗长堆叠开关列表与悬浮遮挡球：
/// - 顶部独立安全区顶栏内置「日间 / 夜间」一键切换胶囊，绝不与状态栏重叠；
/// - 顶部保留原版小樱桌宠立绘的「伴读名片」入口；
/// - 4 组轻盈分类条目直达所有深度设置页与功能面板。
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
  void _push(Widget page) {
    Navigator.of(context)
        .push(SakuraPageRoute(slideHorizontal: true, builder: (_) => page));
  }

  String _pageModeLabel(PageTurnMode mode) => switch (mode) {
    PageTurnMode.slide => '平滑滑动',
    PageTurnMode.cover => '覆盖翻页',
    PageTurnMode.fade => '淡入淡出',
    PageTurnMode.simulation => '拟真卷页',
    PageTurnMode.scroll => '上下滚动',
  };

  String _aiSummary(AppPrefs prefs) {
    if (!prefs.aiConfigured) return '尚未配置模型或密钥 · 点此接入';
    if (prefs.aiUseLocalModel) {
      final local = prefs.aiLocalModelId.trim();
      return local.isEmpty ? '已启用本地离线模型' : '本地模型：$local';
    }
    final model = prefs.aiModel.trim();
    return model.isEmpty ? '已配置云端模型 · 可随时对话' : '当前模型：$model';
  }

  String _ttsSummary(AppPrefs prefs) {
    final pack = ttsVoicePackById(prefs.ttsVoicePack) ?? builtinVoicePack;
    final role = prefs.ttsRolePlay ? ' · AI 分角色开启' : '';
    return '音色「${pack.name}」$role';
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      widget.prefs,
      widget.store,
      widget.sourceStore,
      widget.statsStore,
      TtsVoiceStore.instance,
      ReplaceRuleStore.shared,
      if (PetStore.shared != null) PetStore.shared!,
      if (BookmarkStore.shared != null) BookmarkStore.shared!,
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final sakura = context.sakura;
        final scheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final preset = widget.prefs.visualStyle;
        final pet = PetStore.shared;
        final bookmarks = BookmarkStore.shared;

        final topTint = switch (preset) {
          VisualStylePreset.sakuraAtelier => scheme.primary.withAlpha(
            isDark ? 28 : 22,
          ),
          VisualStylePreset.liquidGlass => Color.lerp(
            scheme.primary,
            const Color(0xFF7CA7D9),
            0.4,
          )!.withAlpha(isDark ? 26 : 18),
          VisualStylePreset.kyotoWashi => const Color(
            0xFFD9B282,
          ).withAlpha(isDark ? 22 : 24),
          VisualStylePreset.animePop => scheme.primary.withAlpha(
            isDark ? 24 : 14,
          ),
        };

        final bottomPad = MediaQuery.paddingOf(context).bottom + 104;
        final isWide = SakuraLayout.isWide(context);
        final hInsets = SakuraLayout.horizontalInsets(context);

        final heroCard = _MascotProfileHeroCard(
          pet: pet,
          statsStore: widget.statsStore,
          bookCount: widget.store.books.length,
          preset: preset,
          onOpenPanel: pet == null ? null : () => showPetPanel(context, pet),
          onOpenQuickSheet: () => _showPetControlsSheet(context),
        );

        final visualSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              title: '书房视觉与排版',
              caption: '视觉预设 · 默认排版 · 离线听书',
            ),
            const SizedBox(height: 8),
            _SettingsGroupCard(
              preset: preset,
              children: [
                _SettingsNavRow(
                  glyph: SakuraGlyph.appearance,
                  badgeColor: scheme.primary,
                  title: '书房风格与外观',
                  subtitle:
                      '${preset.shortLabel} · ${widget.prefs.shelfPlankStyle.shortLabel}',
                  onTap: () => _push(AppearanceStudioPage(prefs: widget.prefs)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.typography,
                  badgeColor: const Color(0xFF7B61FF),
                  title: '阅读默认排版',
                  subtitle:
                      '${widget.prefs.fontSize.toInt()}pt · 行距 ${widget.prefs.lineHeight.toStringAsFixed(1)} · ${_pageModeLabel(widget.prefs.pageMode)}',
                  onTap: () => _push(ReadingDefaultsPage(prefs: widget.prefs)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.audio,
                  badgeColor: const Color(0xFF2B8A7E),
                  title: '听书与离线语音',
                  subtitle: _ttsSummary(widget.prefs),
                  onTap: () => _push(TtsSettingsPage(prefs: widget.prefs)),
                ),
              ],
            ),
          ],
        );

        final companionSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              title: '小樱与 AI 伴读',
              caption: '桌面伴读宠物 · AI 模型 · 对话手账',
            ),
            const SizedBox(height: 8),
            _SettingsGroupCard(
              preset: preset,
              children: [
                _SettingsNavRow(
                  glyph: SakuraGlyph.mascot,
                  badgeColor: const Color(0xFFE05D7C),
                  title: '小樱桌宠与看板娘',
                  subtitle: pet == null
                      ? '开屏动画${widget.prefs.showSplashAnimation ? '开启' : '关闭'}'
                      : pet.enabled
                      ? '已启用 · Lv.${pet.level} ${pet.levelName}'
                      : '桌宠已收起 · 点此唤醒',
                  onTap: () => _showPetControlsSheet(context),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.aiCompanion,
                  badgeColor: const Color(0xFF5A6EE8),
                  title: 'AI 模型与提示词',
                  subtitle: _aiSummary(widget.prefs),
                  onTap: () => _push(AiSettingsPage(prefs: widget.prefs)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.aiCompanion,
                  badgeColor: const Color(0xFF9E4784),
                  title: 'AI 书伴对话',
                  subtitle: '全库检索 · 角色访谈 · 防剧透记忆',
                  onTap: () => _push(
                    AiChatPage(
                      store: widget.store,
                      prefs: widget.prefs,
                      statsStore: widget.statsStore,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

        final sourceSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              title: '书源与阅读记录',
              caption: 'Legado 书源 · 净化规则 · 统计与书签',
            ),
            const SizedBox(height: 8),
            _SettingsGroupCard(
              preset: preset,
              children: [
                _SettingsNavRow(
                  glyph: SakuraGlyph.sources,
                  badgeColor: const Color(0xFFD97736),
                  title: '书源管理与 AI 写源',
                  subtitle:
                      '已启用 ${widget.sourceStore.enabledCount} / ${widget.sourceStore.sources.length} 条兼容书源',
                  onTap: () =>
                      _push(SourceManagerPage(store: widget.sourceStore)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.purify,
                  badgeColor: const Color(0xFF3E8E7E),
                  title: '正文净化规则',
                  subtitle:
                      '已启用 ${ReplaceRuleStore.shared.enabledCount} / ${ReplaceRuleStore.shared.rules.length} 条替换规则',
                  onTap: () => _push(const ReplaceRulesPage()),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.typography,
                  badgeColor: const Color(0xFF4F7CAC),
                  title: '阅读统计与周报',
                  subtitle:
                      '累计 ${widget.statsStore.readDays} 天 · 连续 ${widget.statsStore.streak} 天 · 完本 ${widget.statsStore.finishedBooks}',
                  onTap: () => _push(StatsPage(statsStore: widget.statsStore)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.about,
                  badgeColor: const Color(0xFFC25970),
                  title: '书签与批注',
                  subtitle: '共保存 ${bookmarks?.count ?? 0} 条阅读书签与摘录',
                  onTap: () => _showBookmarks(context, bookmarks),
                ),
              ],
            ),
          ],
        );

        final systemSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              title: '数据与系统',
              caption: '备份恢复 · 阅读 3.0 迁移 · 性能与关于',
            ),
            const SizedBox(height: 8),
            _SettingsGroupCard(
              preset: preset,
              children: [
                _SettingsNavRow(
                  glyph: SakuraGlyph.backup,
                  badgeColor: const Color(0xFF3B7A9E),
                  title: '备份与 WebDAV 同步',
                  subtitle: '本地快照导出 / 云端恢复设置与进度',
                  onTap: () => _push(BackupPage(prefs: widget.prefs)),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.sources,
                  badgeColor: const Color(0xFF8C6239),
                  title: '阅读 3.0 数据迁移',
                  subtitle: '导入 Legado 书架、书源、书签与阅读记录',
                  onTap: () => _push(
                    LegadoImportPage(
                      prefs: widget.prefs,
                      shelf: widget.store,
                      sources: widget.sourceStore,
                    ),
                  ),
                ),
                _SettingsNavRow(
                  glyph: SakuraGlyph.performance,
                  badgeColor: const Color(0xFF6B5B95),
                  title: '性能、存储与关于',
                  subtitle:
                      '并发 ${widget.prefs.searchConcurrency} · 高刷${widget.prefs.highRefreshRate ? '开启' : '关闭'}',
                  onTap: () => _push(
                    SystemAboutPage(prefs: widget.prefs, store: widget.store),
                  ),
                ),
              ],
            ),
          ],
        );

        return Scaffold(
          backgroundColor: sakura.canvas,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(topTint, sakura.canvas),
                  sakura.canvas,
                ],
                stops: const [0.0, 0.36],
              ),
            ),
            child: Column(
              children: [
                _SettingsTopHeader(
                  prefs: widget.prefs,
                  isDark: isDark,
                  preset: preset,
                  onToggleTheme: () {
                    widget.prefs.setThemeMode(
                      isDark ? ThemeMode.light : ThemeMode.dark,
                    );
                  },
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      hInsets.left,
                      8,
                      hInsets.right,
                      bottomPad,
                    ),
                    children: [
                      if (isWide)
                        Center(
                          heightFactor: 1.0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: SakuraLayout.contentMaxWidth,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      heroCard,
                                      const SizedBox(height: 18),
                                      visualSection,
                                      const SizedBox(height: 18),
                                      companionSection,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      sourceSection,
                                      const SizedBox(height: 18),
                                      systemSection,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        heroCard,
                        const SizedBox(height: 18),
                        visualSection,
                        const SizedBox(height: 18),
                        companionSection,
                        const SizedBox(height: 18),
                        sourceSection,
                        const SizedBox(height: 18),
                        systemSection,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPetControlsSheet(BuildContext context) async {
    final pet = PetStore.shared;
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: sakura.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return AnimatedBuilder(
          animation: Listenable.merge([widget.prefs, ?pet]),
          builder: (sheetCtx, _) {
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: sakura.accentSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Image.asset(
                                'assets/images/pet_read.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '小樱桌宠与看板娘',
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    pet == null
                                        ? '原版立绘伴读设定'
                                        : 'Lv.${pet.level} ${pet.levelName} · 好感度 ${pet.affinity}',
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: sakura.inkSecondary),
                                  ),
                                ],
                              ),
                            ),
                            if (pet != null)
                              FilledButton.tonal(
                                onPressed: () {
                                  Navigator.of(sheetCtx).pop();
                                  showPetPanel(context, pet);
                                },
                                child: const Text('互动面板'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (pet != null) ...[
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: scheme.primary,
                            title: const Text('启用桌面小樱'),
                            subtitle: const Text('在书架与各页面边缘贴靠陪伴'),
                            value: pet.enabled,
                            onChanged: pet.setEnabled,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: scheme.primary,
                            title: const Text('阅读器内伴读'),
                            subtitle: const Text('看书时记录时长并适时陪伴'),
                            value: pet.showPetInReader,
                            onChanged: pet.setShowPetInReader,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: scheme.primary,
                            title: const Text('呼吸与拖拽微动效'),
                            subtitle: const Text('关闭后保持静态展示以节省电量'),
                            value: pet.motionEnabled,
                            onChanged: pet.setMotionEnabled,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeTrackColor: scheme.primary,
                            title: const Text('静默模式'),
                            subtitle: const Text('暂停主动冒泡气泡提醒'),
                            value: pet.quiet,
                            onChanged: pet.setQuiet,
                          ),
                        ],
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          activeTrackColor: scheme.primary,
                          title: const Text('启动看板娘开屏动画'),
                          subtitle: const Text('保留原版看板娘启动画卷'),
                          value: widget.prefs.showSplashAnimation,
                          onChanged: widget.prefs.setShowSplashAnimation,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showBookmarks(
    BuildContext context,
    BookmarkStore? store,
  ) async {
    final sakura = context.sakura;
    if (store == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('书签服务尚未初始化')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sakura.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return AnimatedBuilder(
          animation: store,
          builder: (sheetCtx, _) {
            final items = store.items.reversed.toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (_, controller) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SakuraIcon(
                            glyph: SakuraGlyph.about,
                            size: 36,
                            color: sakura.inkSecondary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '还没有保存书签或笔记',
                            style: TextStyle(color: sakura.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            '全部书签与批注 (${items.length})',
                            style: Theme.of(sheetCtx).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final b = items[i];
                          final book = widget.store.byId(b.bookId);
                          final bookTitle = book?.title ?? '已移除书籍';
                          return Material(
                            color: sakura.surfaceSubtle,
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              title: Text(
                                '$bookTitle · ${b.chapterTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${b.excerpt}\n${timeAgo(b.createdAt)}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: sakura.inkSecondary,
                                  ),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                tooltip: '删除书签',
                                onPressed: () => store.remove(b.id),
                              ),
                              onTap: book == null
                                  ? null
                                  : () {
                                      Navigator.of(sheetCtx).pop();
                                      _push(
                                        ReaderPage(
                                          store: widget.store,
                                          prefs: widget.prefs,
                                          bookId: book.id,
                                          chapterIndex: b.chapterIndex,
                                          charOffset: b.charOffset,
                                        ),
                                      );
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SettingsTopHeader extends StatelessWidget {
  const _SettingsTopHeader({
    required this.prefs,
    required this.isDark,
    required this.preset,
    required this.onToggleTheme,
  });

  final AppPrefs prefs;
  final bool isDark;
  final VisualStylePreset preset;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    final isPop = preset == VisualStylePreset.animePop;

    final hInsets = SakuraLayout.horizontalInsets(context, min: 20);
    final shortLandscape = SakuraLayout.isShortLandscape(context);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          hInsets.left,
          shortLandscape ? 8 : 12,
          hInsets.right < 16 ? 16 : hInsets.right,
          shortLandscape ? 6 : 10,
        ),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SakuraLayout.contentMaxWidth,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '书房设置',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: sakura.inkPrimary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '当前风格：${preset.shortLabel}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: sakura.inkSecondary),
                      ),
                    ],
                  ),
                ),
                SakuraPressable(
                  onTap: onToggleTheme,
                  child: Semantics(
                    button: true,
                    label: isDark ? '切换日间模式' : '切换夜间模式',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sakura.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isPop ? sakura.inkPrimary : sakura.hairline,
                          width: isPop ? 1.5 : 1,
                        ),
                        boxShadow: isPop
                            ? [
                                BoxShadow(
                                  color: sakura.inkPrimary.withAlpha(38),
                                  offset: const Offset(2, 2),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: sakura.coverShadow.withAlpha(18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDark
                                ? Icons.wb_sunny_rounded
                                : Icons.nights_stay_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isDark ? '日间' : '夜间',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: sakura.inkPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotProfileHeroCard extends StatelessWidget {
  const _MascotProfileHeroCard({
    required this.pet,
    required this.statsStore,
    required this.bookCount,
    required this.preset,
    required this.onOpenPanel,
    required this.onOpenQuickSheet,
  });

  final PetStore? pet;
  final StatsStore statsStore;
  final int bookCount;
  final VisualStylePreset preset;
  final VoidCallback? onOpenPanel;
  final VoidCallback onOpenQuickSheet;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    final isPop = preset == VisualStylePreset.animePop;
    final petStore = pet;

    final levelTitle = petStore == null
        ? '小樱书屋手账'
        : 'Lv.${petStore.level} · ${petStore.levelName}';
    final statusSub = petStore == null
        ? '今天也和小樱一起安静读书吧'
        : petStore.enabled
        ? '好感度 ${petStore.affinity} · 互动 ${petStore.interactions} 次'
        : '桌宠当前休眠中 · 点右下按钮唤醒';

    return SakuraPressable(
      onTap: onOpenPanel ?? onOpenQuickSheet,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sakura.card,
          borderRadius: BorderRadius.circular(isPop ? 18 : 22),
          border: Border.all(
            color: isPop ? sakura.inkPrimary : sakura.hairline,
            width: isPop ? 1.8 : 1,
          ),
          boxShadow: isPop
              ? [
                  BoxShadow(
                    color: sakura.inkPrimary.withAlpha(46),
                    offset: const Offset(3, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: sakura.coverShadow.withAlpha(24),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [sakura.accentSoft, sakura.surfaceSubtle],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.primary.withAlpha(55)),
                  ),
                  child: Image.asset(
                    'assets/images/pet_read.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              levelTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: sakura.inkPrimary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: sakura.inkSecondary),
                      ),
                      if (petStore != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: petStore.levelProgress.clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: sakura.surfaceSubtle,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onOpenPanel != null) ...[
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: onOpenPanel,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('互动面板'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroStatChip(
                    label: '累计阅读',
                    value: formatDuration(statsStore.totalSeconds),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStatChip(
                    label: '连续坚持',
                    value: '${statsStore.streak} 天',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroStatChip(label: '书架藏书', value: '$bookCount 本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: sakura.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: sakura.inkSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: sakura.inkPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: sakura.inkPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 11.5, color: sakura.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.preset, required this.children});

  final VisualStylePreset preset;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final isPop = preset == VisualStylePreset.animePop;
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i != children.length - 1) {
        divided.add(
          Divider(
            height: 1,
            indent: 66,
            endIndent: 16,
            color: sakura.hairline.withAlpha(140),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: sakura.card,
        borderRadius: BorderRadius.circular(isPop ? 16 : 20),
        border: Border.all(
          color: isPop ? sakura.inkPrimary : sakura.hairline,
          width: isPop ? 1.6 : 1,
        ),
        boxShadow: isPop
            ? [
                BoxShadow(
                  color: sakura.inkPrimary.withAlpha(36),
                  offset: const Offset(3, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: sakura.coverShadow.withAlpha(16),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isPop ? 14.5 : 19),
        child: Column(mainAxisSize: MainAxisSize.min, children: divided),
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.glyph,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final SakuraGlyph glyph;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              SakuraIconBadge(
                glyph: glyph,
                color: badgeColor,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: sakura.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12.2,
                        color: sakura.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: sakura.inkSecondary.withAlpha(170),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
