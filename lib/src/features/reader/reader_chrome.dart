import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/offline_downloader.dart';
import '../../data/prefs.dart';

/// 阅读器顶栏 / 底栏协调色板：完全跟随当前阅读纸色 [ReaderBg]。
///
/// 消除旧版「浅色顶栏 + 漆黑底栏」的视觉割裂：
/// - 日间纸色（纸白 / 米黄 / 护眼绿 / 浅灰）：暖白或浅纸色半透明磨砂 + 细描边；
/// - 夜间纸色（夜间 / 纯黑）：深炭墨半透明磨砂 + 柔白发丝描边。
@immutable
class ReaderChromePalette {
  const ReaderChromePalette({
    required this.isDark,
    required this.surface,
    required this.frostedSurface,
    required this.foreground,
    required this.secondary,
    required this.disabled,
    required this.border,
    required this.shadow,
    required this.accent,
    required this.sliderInactive,
    required this.pillFill,
  });

  final bool isDark;
  final Color surface;
  final Color frostedSurface;
  final Color foreground;
  final Color secondary;
  final Color disabled;
  final Color border;
  final Color shadow;
  final Color accent;
  final Color sliderInactive;
  final Color pillFill;

  factory ReaderChromePalette.from(ReaderBg bg, ColorScheme scheme) {
    final isDark =
        ThemeData.estimateBrightnessForColor(bg.color) == Brightness.dark;
    if (isDark) {
      final base = Color.lerp(bg.color, const Color(0xFF1F212B), 0.68)!;
      return ReaderChromePalette(
        isDark: true,
        surface: base.withValues(alpha: 0.96),
        frostedSurface: base.withValues(alpha: 0.80),
        foreground: const Color(0xFFECEEF4),
        secondary: const Color(0xFFA6ACBA),
        disabled: const Color(0x52A6ACBA),
        border: Colors.white.withValues(alpha: 0.11),
        shadow: Colors.black.withValues(alpha: 0.42),
        accent: scheme.primary,
        sliderInactive: Colors.white.withValues(alpha: 0.16),
        pillFill: Colors.white.withValues(alpha: 0.08),
      );
    }

    final base = Color.lerp(bg.color, const Color(0xFFFFFCF7), 0.42)!;
    final ink = bg.textColor;
    return ReaderChromePalette(
      isDark: false,
      surface: base.withValues(alpha: 0.96),
      frostedSurface: base.withValues(alpha: 0.82),
      foreground: ink,
      secondary: ink.withValues(alpha: 0.62),
      disabled: ink.withValues(alpha: 0.30),
      border: ink.withValues(alpha: 0.11),
      shadow: Colors.black.withValues(alpha: 0.09),
      accent: scheme.primary,
      sliderInactive: ink.withValues(alpha: 0.16),
      pillFill: ink.withValues(alpha: 0.06),
    );
  }
}

/// 顶栏 / 底栏统一底板（协调色 + 细描边 + 可选实时磨砂）。
class ReaderChromeSurface extends StatelessWidget {
  const ReaderChromeSurface({
    super.key,
    required this.palette,
    required this.frosted,
    required this.radius,
    required this.border,
    required this.shadowOffset,
    required this.child,
  });

  final ReaderChromePalette palette;
  final bool frosted;
  final BorderRadius radius;
  final BoxBorder border;
  final Offset shadowOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: frosted ? palette.frostedSurface : palette.surface,
      borderRadius: radius,
      border: border,
      boxShadow: [
        BoxShadow(color: palette.shadow, blurRadius: 16, offset: shadowOffset),
      ],
    );
    final box = DecoratedBox(decoration: decoration, child: child);
    if (!frosted) return box;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: box,
      ),
    );
  }
}

/// 阅读器顶栏。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.visible,
    required this.bg,
    required this.frosted,
    required this.book,
    required this.chapterIndex,
    required this.offlineProgress,
    required this.currentChapterUrl,
    required this.annotationCount,
    required this.onBack,
    required this.onShowXray,
    required this.onShowAnnotations,
    required this.onShowChapters,
    this.onOpenEpubOriginal,
    this.onDownloadWholeBook,
    this.onOpenChapterSource,
  });

  final bool visible;
  final ReaderBg bg;
  final bool frosted;
  final Book? book;
  final int chapterIndex;
  final OfflineDownloadProgress? offlineProgress;
  final String? currentChapterUrl;
  final int annotationCount;
  final VoidCallback onBack;
  final VoidCallback onShowXray;
  final VoidCallback onShowAnnotations;
  final VoidCallback onShowChapters;
  final VoidCallback? onOpenEpubOriginal;
  final VoidCallback? onDownloadWholeBook;
  final VoidCallback? onOpenChapterSource;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderChromePalette.from(bg, Theme.of(context).colorScheme);
    final b = book;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: visible ? 0 : -150,
      child: IgnorePointer(
        ignoring: !visible,
        child: ReaderChromeSurface(
          palette: palette,
          frosted: frosted,
          radius: const BorderRadius.vertical(bottom: Radius.circular(18)),
          border: Border(
            bottom: BorderSide(color: palette.border, width: 0.75),
          ),
          shadowOffset: const Offset(0, 4),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 6, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: palette.foreground,
                    ),
                    tooltip: '返回',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          b?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.1,
                          ),
                        ),
                        if (b != null) ...[
                          const SizedBox(height: 1),
                          if (offlineProgress != null)
                            Row(
                              children: [
                                SizedBox(
                                  width: 46,
                                  height: 5,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: offlineProgress!.fraction,
                                      minHeight: 5,
                                      color: palette.accent,
                                      backgroundColor: palette.sliderInactive,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '缓存 ${offlineProgress!.done}/${offlineProgress!.total}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.secondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              '第 ${chapterIndex + 1}/${b.chapterCount} 章',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.secondary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onShowAnnotations,
                    icon: Badge(
                      isLabelVisible: annotationCount > 0,
                      label: Text('$annotationCount'),
                      child: Icon(
                        Icons.edit_note_rounded,
                        color: palette.foreground,
                      ),
                    ),
                    tooltip: '划线笔记',
                  ),
                  IconButton(
                    onPressed: onShowXray,
                    icon: Icon(
                      Icons.groups_2_outlined,
                      color: palette.foreground,
                    ),
                    tooltip: '人物',
                  ),
                  IconButton(
                    onPressed: onShowChapters,
                    icon: Icon(
                      Icons.format_list_bulleted_rounded,
                      color: palette.foreground,
                    ),
                    tooltip: '目录',
                  ),
                  if (b?.format == BookFormat.epub &&
                      onOpenEpubOriginal != null)
                    IconButton(
                      tooltip: '原书排版（插图与注释）',
                      icon: Icon(
                        Icons.auto_stories_outlined,
                        color: palette.foreground,
                      ),
                      onPressed: onOpenEpubOriginal,
                    ),
                  if (b?.format == BookFormat.online &&
                      onDownloadWholeBook != null)
                    IconButton(
                      onPressed: onDownloadWholeBook,
                      icon: Icon(
                        offlineProgress != null
                            ? Icons.cloud_sync_rounded
                            : Icons.cloud_download_outlined,
                        color: palette.foreground,
                      ),
                      tooltip: '离线缓存',
                    ),
                  if (currentChapterUrl != null && onOpenChapterSource != null)
                    IconButton(
                      onPressed: onOpenChapterSource,
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        color: palette.foreground,
                      ),
                      tooltip: '查看本章来源',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 阅读器底栏（与顶栏同源协调色 + 无重叠进度条 + 均分功能按钮）。
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.visible,
    required this.bg,
    required this.frosted,
    required this.book,
    required this.chapterIndex,
    required this.progress,
    required this.ttsActive,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onShowChapters,
    required this.onShowBookmarks,
    required this.onStartTts,
    required this.onShowSettings,
    required this.onJumpProgress,
    this.onShowSourceSwitch,
  });

  final bool visible;
  final ReaderBg bg;
  final bool frosted;
  final Book? book;
  final int chapterIndex;
  final double progress;
  final bool ttsActive;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onShowChapters;
  final VoidCallback onShowBookmarks;
  final VoidCallback onStartTts;
  final VoidCallback onShowSettings;
  final ValueChanged<double> onJumpProgress;
  final VoidCallback? onShowSourceSwitch;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderChromePalette.from(bg, Theme.of(context).colorScheme);
    final b = book;
    final hasPrev = chapterIndex > 0;
    final hasNext = b != null && chapterIndex < b.chapterCount - 1;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: visible ? 0 : -240,
      child: IgnorePointer(
        ignoring: !visible,
        child: ReaderChromeSurface(
          palette: palette,
          frosted: frosted,
          radius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: palette.border, width: 0.75)),
          shadowOffset: const Offset(0, -4),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReaderProgressSlider(
                    progress: progress,
                    palette: palette,
                    onJump: onJumpProgress,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _ChromeActionButton(
                          icon: Icons.skip_previous_rounded,
                          label: '上一章',
                          enabled: hasPrev,
                          palette: palette,
                          onTap: onPrevChapter,
                        ),
                      ),
                      Expanded(
                        child: _ChromeActionButton(
                          icon: Icons.format_list_bulleted_rounded,
                          label: '目录',
                          palette: palette,
                          onTap: onShowChapters,
                        ),
                      ),
                      Expanded(
                        child: _ChromeActionButton(
                          icon: Icons.bookmark_border_rounded,
                          label: '书签',
                          palette: palette,
                          onTap: onShowBookmarks,
                        ),
                      ),
                      Expanded(
                        child: _ChromeActionButton(
                          icon: ttsActive
                              ? Icons.record_voice_over_rounded
                              : Icons.record_voice_over_outlined,
                          label: '朗读',
                          highlighted: ttsActive,
                          palette: palette,
                          onTap: onStartTts,
                        ),
                      ),
                      if (b?.format == BookFormat.online &&
                          onShowSourceSwitch != null)
                        Expanded(
                          child: _ChromeActionButton(
                            icon: Icons.swap_horiz_rounded,
                            label: '换源',
                            palette: palette,
                            onTap: onShowSourceSwitch!,
                          ),
                        ),
                      Expanded(
                        child: _ChromeActionButton(
                          icon: Icons.tune_rounded,
                          label: '设置',
                          palette: palette,
                          onTap: onShowSettings,
                        ),
                      ),
                      Expanded(
                        child: _ChromeActionButton(
                          icon: Icons.skip_next_rounded,
                          label: '下一章',
                          enabled: hasNext,
                          palette: palette,
                          onTap: onNextChapter,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeActionButton extends StatelessWidget {
  const _ChromeActionButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.enabled = true,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final ReaderChromePalette palette;
  final VoidCallback onTap;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? palette.disabled
        : highlighted
        ? palette.accent
        : palette.foreground;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderProgressSlider extends StatefulWidget {
  const _ReaderProgressSlider({
    required this.progress,
    required this.palette,
    required this.onJump,
  });

  final double progress;
  final ReaderChromePalette palette;
  final ValueChanged<double> onJump;

  @override
  State<_ReaderProgressSlider> createState() => _ReaderProgressSliderState();
}

class _ReaderProgressSliderState extends State<_ReaderProgressSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.progress).clamp(0.0, 1.0);
    final palette = widget.palette;
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: palette.accent,
              inactiveTrackColor: palette.sliderInactive,
              thumbColor: palette.accent,
              overlayColor: palette.accent.withValues(alpha: 0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                widget.onJump(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.pillFill,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '${(value * 100).round()}%',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: palette.secondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
