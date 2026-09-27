import 'package:flutter/material.dart';

import '../../data/pet_store.dart';
import '../../data/prefs.dart';

/// 阅读设置面板（阅读器底部弹层 / 设置页共用）。
///
/// 布局：**三页签**（排版 / 外观 / 更多）。
///
/// 为什么不堆成一列：设置项越加越多，单列面板在阅读器弹层里会占满整屏——
/// 用户调字号 / 页边距时**看不到正文变化**（用户反馈）。分页签后面板高度
/// 腰斩、弹层只占屏幕下半部，上方正文保持可见。
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
            const SizedBox(height: 10),
            switch (_tab) {
              0 => _typographyTab(),
              1 => _appearanceTab(),
              _ => _moreTab(),
            },
          ],
        );
        if (!widget.compact) return body;
        // 紧凑模式：限高（约屏幕 42%），保证正文区域始终可见。
        final h = (MediaQuery.sizeOf(context).height * .42).clamp(280.0, 380.0);
        return SizedBox(
          height: h,
          child: SingleChildScrollView(child: body),
        );
      },
    );
  }

  Widget _tabSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('排版')),
        ButtonSegment(value: 1, label: Text('外观')),
        ButtonSegment(value: 2, label: Text('更多')),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  /// 排版：字号 / 行距 / 字间距 / 页边距 / 段首缩进。
  Widget _typographyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sliderRow(
          label: '字号',
          value: widget.prefs.fontSize,
          min: 12,
          max: 34,
          divisions: 22,
          display: widget.prefs.fontSize.round().toString(),
          onChanged: widget.prefs.setFontSize,
          preview: 'A',
        ),
        _sliderRow(
          label: '行距',
          value: widget.prefs.lineHeight,
          min: 1.2,
          max: 2.6,
          divisions: 14,
          display: widget.prefs.lineHeight.toStringAsFixed(1),
          onChanged: widget.prefs.setLineHeight,
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
          label: '页边距',
          value: widget.prefs.readerMarginH,
          min: 8,
          max: 48,
          divisions: 20,
          display: widget.prefs.readerMarginH.round().toString(),
          onChanged: widget.prefs.setReaderMarginH,
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

  /// 外观：日夜切换 / 背景色 / 字体。
  Widget _appearanceTab() {
    final scheme = Theme.of(context).colorScheme;
    // 有效夜间状态：深色阅读背景 / 全局深色 / 跟随系统且系统为深色
    final nightOn =
        widget.prefs.readerBgIndex >= 4 ||
        widget.prefs.themeMode == ThemeMode.dark ||
        (widget.prefs.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
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
          ],
        ),
        Text(
          '日夜切换会同时改变阅读背景与整个软件',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        const _Label('背景'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (var i = 0; i < kReaderBgs.length; i++)
              GestureDetector(
                onTap: () => widget.prefs.setReaderBgIndex(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: kReaderBgs[i].color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.prefs.readerBgIndex == i
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: widget.prefs.readerBgIndex == i ? 2.5 : 1,
                        ),
                      ),
                      child: widget.prefs.readerBgIndex == i
                          ? Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: scheme.primary,
                            )
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      kReaderBgs[i].name,
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.prefs.readerBgIndex == i
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
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

  /// 更多：翻页动画 / 屏幕常亮 / 桌宠开关。
  Widget _moreTab() {
    final scheme = Theme.of(context).colorScheme;
    final petStore = widget.petStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Label('翻页动画'),
        const SizedBox(height: 8),
        SegmentedButton<PageTurnMode>(
          segments: const [
            ButtonSegment(value: PageTurnMode.slide, label: Text('滑动')),
            ButtonSegment(value: PageTurnMode.cover, label: Text('覆盖')),
            ButtonSegment(value: PageTurnMode.fade, label: Text('淡入')),
            ButtonSegment(value: PageTurnMode.scroll, label: Text('滚动')),
          ],
          selected: {widget.prefs.pageMode},
          onSelectionChanged: (s) => widget.prefs.setPageMode(s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.prefs.keepScreenOn,
          onChanged: widget.prefs.setKeepScreenOn,
          title: const Text('阅读时保持屏幕常亮', style: TextStyle(fontSize: 13.5)),
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
                '她会到处乱跑捣乱哦～（不介意的话就开着吧）',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
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
    String? preview,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        if (preview != null)
          Text(
            preview,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      ],
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
