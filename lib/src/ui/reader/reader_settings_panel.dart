import 'package:flutter/material.dart';

import '../../data/pet_store.dart';
import '../../data/prefs.dart';

/// 阅读设置面板（阅读器底部弹层 / 设置页共用）。
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key, required this.prefs, this.petStore});

  final AppPrefs prefs;

  /// 桌宠仓库（提供「阅读时显示桌宠」开关；为空则不显示该项）。
  final PetStore? petStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        // 有效夜间状态：深色阅读背景 / 全局深色 / 跟随系统且系统为深色
        final nightOn =
            prefs.readerBgIndex >= 4 ||
            prefs.themeMode == ThemeMode.dark ||
            (prefs.themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 一键日夜：阅读背景与全局主题同步（浅色状态也会被记住）
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
                    onSelectionChanged: (s) => prefs.setNightMode(s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '切换后阅读背景与整个软件的日夜模式一起变化',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            _sliderRow(
              context,
              label: '字号',
              value: prefs.fontSize,
              min: 12,
              max: 34,
              divisions: 22,
              display: prefs.fontSize.round().toString(),
              onChanged: prefs.setFontSize,
              preview: 'A',
            ),
            _sliderRow(
              context,
              label: '行距',
              value: prefs.lineHeight,
              min: 1.2,
              max: 2.6,
              divisions: 14,
              display: prefs.lineHeight.toStringAsFixed(1),
              onChanged: prefs.setLineHeight,
            ),
            _sliderRow(
              context,
              label: '页边距',
              value: prefs.readerMarginH,
              min: 8,
              max: 48,
              divisions: 20,
              display: prefs.readerMarginH.round().toString(),
              onChanged: prefs.setReaderMarginH,
            ),
            _sliderRow(
              context,
              label: '字间距',
              value: prefs.letterSpacing,
              min: 0,
              max: 3,
              divisions: 12,
              display: prefs.letterSpacing.toStringAsFixed(1),
              onChanged: prefs.setLetterSpacing,
            ),
            const SizedBox(height: 6),
            const _Label('字体'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final option in kFontOptions)
                  ChoiceChip(
                    label: Text(
                      option.$1,
                      style: TextStyle(
                        fontFamily: option.$2.isEmpty ? null : option.$2,
                      ),
                    ),
                    selected: prefs.fontFamily == option.$2,
                    onSelected: (_) => prefs.setFontFamily(option.$2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _Label('背景'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (var i = 0; i < kReaderBgs.length; i++)
                  GestureDetector(
                    onTap: () => prefs.setReaderBgIndex(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: kReaderBgs[i].color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: prefs.readerBgIndex == i
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: prefs.readerBgIndex == i ? 2.5 : 1,
                            ),
                          ),
                          child: prefs.readerBgIndex == i
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: scheme.primary,
                                )
                              : null,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          kReaderBgs[i].name,
                          style: TextStyle(
                            fontSize: 10,
                            color: prefs.readerBgIndex == i
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _Label('翻页动画'),
            const SizedBox(height: 8),
            SegmentedButton<PageTurnMode>(
              segments: const [
                ButtonSegment(value: PageTurnMode.slide, label: Text('滑动')),
                ButtonSegment(value: PageTurnMode.cover, label: Text('覆盖')),
                ButtonSegment(value: PageTurnMode.fade, label: Text('淡入')),
                ButtonSegment(value: PageTurnMode.scroll, label: Text('滚动')),
              ],
              selected: {prefs.pageMode},
              onSelectionChanged: (s) => prefs.setPageMode(s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.paragraphIndent,
              onChanged: prefs.setParagraphIndent,
              title: const Text('段首缩进两格', style: TextStyle(fontSize: 13.5)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.keepScreenOn,
              onChanged: prefs.setKeepScreenOn,
              title: const Text('阅读时保持屏幕常亮', style: TextStyle(fontSize: 13.5)),
            ),
            // 桌宠：阅读时也显示（会到处乱跑捣乱，可在此关闭）
            if (petStore != null) ...[
              const SizedBox(height: 6),
              const _Label('看板娘'),
              AnimatedBuilder(
                animation: petStore!,
                builder: (_, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: petStore!.showPetInReader,
                  onChanged: petStore!.setShowPetInReader,
                  title: const Text(
                    '阅读时也显示桌宠',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '她会到处乱跑捣乱哦～（不介意的话就开着吧）',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _sliderRow(
    BuildContext context, {
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
          width: 52,
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
