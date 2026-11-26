import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/pet_store.dart';
import '../../data/prefs.dart';
import '../folder_picker_page.dart';

/// 阅读设置面板（阅读器底部弹层 / 设置页共用）。
///
/// 布局：**三页签**（排版 / 外观 / 更多）。
/// 紧凑模式下限高约屏幕 42%（≤45%），调整字号 / 页边距时上方正文保持可见。
class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.prefs,
    this.petStore,
    this.compact = false,
  });

  final AppPrefs prefs;

  /// 桌宠仓库（提供「阅读时显示桌宠」开关；为空则不显示该项）。
  final PetStore? petStore;

  /// 紧凑模式（阅读器弹层）：限制整体高度，只占屏幕下半部。
  final bool compact;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.prefs,
      builder: (context, _) {
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _tabSelector(),
            const SizedBox(height: 12),
            switch (_tab) {
              0 => _typographyTab(),
              1 => _appearanceTab(),
              _ => _moreTab(),
            },
          ],
        );
        if (!widget.compact) return body;
        // 紧凑模式：限高（约屏幕 42%，严格 ≤ 45%），保证正文区域始终可见。
        final h = (MediaQuery.sizeOf(context).height * .42).clamp(280.0, 360.0);
        return SizedBox(
          height: h,
          child: SingleChildScrollView(child: body),
        );
      },
    );
  }

  Widget _tabSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('排版')),
          ButtonSegment(value: 1, label: Text('外观')),
          ButtonSegment(value: 2, label: Text('更多')),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }

  /// 排版：字号 / 行距 / 段间距 / 字间距 / 左右边距 / 上下留白 / 段首缩进。
  Widget _typographyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fontSizeRow(),
        _sliderRow(
          label: '行距',
          value: widget.prefs.lineHeight,
          min: 1.0,
          max: 2.6,
          divisions: 16,
          display: widget.prefs.lineHeight.toStringAsFixed(1),
          onChanged: widget.prefs.setLineHeight,
        ),
        _sliderRow(
          label: '段间距',
          value: widget.prefs.paragraphSpacing,
          min: 0,
          max: 40,
          divisions: 20,
          display: widget.prefs.paragraphSpacing.round().toString(),
          onChanged: widget.prefs.setParagraphSpacing,
        ),
        _sliderRow(
          label: '字间距',
          value: widget.prefs.letterSpacing,
          min: 0,
          max: 3,
          divisions: 12,
          display: widget.prefs.letterSpacing.toStringAsFixed(1),
          onChanged: widget.prefs.setLetterSpacing,
        ),
        _sliderRow(
          label: '左右边距',
          value: widget.prefs.readerMarginH,
          min: 8,
          max: 48,
          divisions: 20,
          display: widget.prefs.readerMarginH.round().toString(),
          onChanged: widget.prefs.setReaderMarginH,
        ),
        _sliderRow(
          label: '距顶部',
          value: widget.prefs.readerPaddingTop,
          min: 0,
          max: 160,
          divisions: 32,
          display: widget.prefs.readerPaddingTop.round().toString(),
          onChanged: widget.prefs.setReaderPaddingTop,
        ),
        _sliderRow(
          label: '距底部',
          value: widget.prefs.readerPaddingBottom,
          min: 0,
          max: 160,
          divisions: 32,
          display: widget.prefs.readerPaddingBottom.round().toString(),
          onChanged: widget.prefs.setReaderPaddingBottom,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.paragraphIndent,
          onChanged: widget.prefs.setParagraphIndent,
          title: const Text('段首缩进两格', style: TextStyle(fontSize: 13.5)),
        ),
      ],
    );
  }

  /// 字号行：滑杆 + 快捷 A- / A+ 微调按钮。
  Widget _fontSizeRow() {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.prefs.fontSize;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '字号',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        _StepButton(
          label: 'A-',
          onTap: size > 12 ? () => widget.prefs.setFontSize(size - 1) : null,
        ),
        Expanded(
          child: SliderTheme(
            data: _compactSliderTheme(context),
            child: Slider(
              value: size.clamp(12, 34),
              min: 12,
              max: 34,
              divisions: 22,
              onChanged: widget.prefs.setFontSize,
            ),
          ),
        ),
        _StepButton(
          label: 'A+',
          onTap: size < 34 ? () => widget.prefs.setFontSize(size + 1) : null,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(
            size.round().toString(),
            textAlign: TextAlign.end,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  /// 外观：日夜切换 / 纸张主题色板 / 字体。
  Widget _appearanceTab() {
    final scheme = Theme.of(context).colorScheme;
    final nightOn =
        widget.prefs.readerBgIndex >= 4 ||
        widget.prefs.themeMode == ThemeMode.dark ||
        (widget.prefs.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode_rounded, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('夜间'),
                icon: Icon(Icons.dark_mode_rounded, size: 16),
              ),
            ],
            selected: {nightOn},
            onSelectionChanged: (s) => widget.prefs.setNightMode(s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '日夜切换会同时改变阅读背景与整个软件',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        const _Label('背景'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < kReaderBgs.length; i++)
              _PaperSwatch(
                bg: kReaderBgs[i],
                selected: widget.prefs.readerBgIndex == i,
                accent: scheme.primary,
                outline: scheme.outlineVariant,
                labelColor: scheme.onSurfaceVariant,
                onTap: () => widget.prefs.setReaderBgIndex(i),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => _importAsset(true),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.font_download_outlined, size: 16),
              label: const Text('导入字体'),
            ),
            OutlinedButton.icon(
              onPressed: () => _importAsset(false),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.wallpaper, size: 16),
              label: const Text('导入背景'),
            ),
            if (widget.prefs.customBackgroundPath.isNotEmpty)
              TextButton(
                onPressed: widget.prefs.clearReaderBackground,
                child: const Text('清除背景'),
              ),
            if (widget.prefs.customFontPath.isNotEmpty)
              ChoiceChip(
                label: const Text('自定义字体'),
                selected:
                    widget.prefs.fontFamily == widget.prefs.customFontFamily,
                onSelected: (_) =>
                    widget.prefs.setFontFamily(widget.prefs.customFontFamily),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const _Label('字体'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in kFontOptions)
              ChoiceChip(
                label: Text(
                  option.$1,
                  style: TextStyle(
                    fontFamily: option.$2.isEmpty ? null : option.$2,
                  ),
                ),
                selected: widget.prefs.fontFamily == option.$2,
                onSelected: (_) => widget.prefs.setFontFamily(option.$2),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _importAsset(bool font) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => FolderPickerPage(
          mode: font ? PickerMode.fonts : PickerMode.images,
          title: font ? '选择 TTF / OTF 字体' : '选择阅读背景',
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await widget.prefs.importReaderAsset(picked.first, font: font);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入失败，请选择有效文件（最大 20 MB）')));
      }
    }
  }

  /// 更多：翻页动画（含仿真 3D 卷页） / 屏幕常亮 / 音量键 / 页眉页脚 / 桌宠。
  Widget _moreTab() {
    final scheme = Theme.of(context).colorScheme;
    final petStore = widget.petStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Label('翻页动画'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PageTurnMode>(
            segments: const [
              ButtonSegment(
                value: PageTurnMode.simulation,
                label: Text('仿真', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: PageTurnMode.cover,
                label: Text('覆盖', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: PageTurnMode.slide,
                label: Text('滑动', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: PageTurnMode.fade,
                label: Text('淡入', maxLines: 1, softWrap: false),
              ),
              ButtonSegment(
                value: PageTurnMode.scroll,
                label: Text('滚动', maxLines: 1, softWrap: false),
              ),
            ],
            selected: {widget.prefs.pageMode},
            onSelectionChanged: (s) => widget.prefs.setPageMode(s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 6),
              ),
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.keepScreenOn,
          onChanged: widget.prefs.setKeepScreenOn,
          title: const Text('阅读时保持屏幕常亮', style: TextStyle(fontSize: 13.5)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.volumeKeyPaging,
          onChanged: widget.prefs.setVolumeKeyPaging,
          title: const Text('音量键翻页', style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            '音量上 = 上一页，音量下 = 下一页（仅在阅读页生效）',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.readerHeaderVisible,
          onChanged: widget.prefs.setReaderHeaderVisible,
          title: const Text('显示页眉（章节名）', style: TextStyle(fontSize: 13.5)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.readerFooterVisible,
          onChanged: widget.prefs.setReaderFooterVisible,
          title: const Text(
            '显示页脚（时间 / 页码 / 电量）',
            style: TextStyle(fontSize: 13.5),
          ),
        ),
        if (petStore != null)
          AnimatedBuilder(
            animation: petStore,
            builder: (_, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: petStore.showPetInReader,
              onChanged: petStore.setShowPetInReader,
              title: const Text('阅读时也显示桌宠', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                '她会安静陪在屏幕边角，点一下就能聊天～',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  SliderThemeData _compactSliderTheme(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliderTheme.of(context).copyWith(
      trackHeight: 3,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.45),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: _compactSliderTheme(context),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            display,
            textAlign: TextAlign.end,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: onTap == null
                ? scheme.onSurface.withValues(alpha: 0.3)
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 现代纸张主题色卡：直接预览纸底色 + 墨字色，选中带高亮描边与角标。
class _PaperSwatch extends StatelessWidget {
  const _PaperSwatch({
    required this.bg,
    required this.selected,
    required this.accent,
    required this.outline,
    required this.labelColor,
    required this.onTap,
  });

  final ReaderBg bg;
  final bool selected;
  final Color accent;
  final Color outline;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 46,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg.color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : outline.withValues(alpha: 0.7),
                width: selected ? 2.2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: bg.textColor,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.check_rounded, size: 12, color: accent),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bg.name,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
