import 'package:flutter/material.dart';

import '../../core/icons/sakura_icons.dart';
import '../../core/motion/sakura_motion.dart';
import '../../core/theme/sakura_layout.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/prefs.dart';
import '../../data/shelf_sort.dart';

/// 外观与书房风格工坊：4 套视觉艺术预设 + 7 项自由混搭特效 + 主题色。
class AppearanceStudioPage extends StatelessWidget {
  const AppearanceStudioPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Scaffold(
      appBar: AppBar(title: const Text('外观与书房风格')),
      body: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) {
          final accent = Theme.of(context).colorScheme.primary;
          final hInsets = SakuraLayout.horizontalInsets(context);
          return SafeArea(
            top: false,
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SakuraLayout.contentMaxWidth,
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    hInsets.left,
                    8,
                    hInsets.right,
                    36,
                  ),
                  children: [
                    _sectionHeader(
                      context,
                      SakuraGlyph.appearance,
                      '书房视觉风格预设',
                      '一键切换整套氛围与材质，之后仍可自由微调下方特效',
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth >= 720 ? 4 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: VisualStylePreset.values.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 178,
                              ),
                          itemBuilder: (context, i) {
                            final preset = VisualStylePreset.values[i];
                            return _PresetCard(
                              preset: preset,
                              selected: prefs.visualStyle == preset,
                              onTap: () => prefs.applyVisualStylePreset(preset),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _sectionHeader(
                      context,
                      SakuraGlyph.arrange,
                      '书架陈列与视觉特效混搭',
                      '所有招牌动效均可独立开关或跨风格组合',
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: sakura.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: sakura.hairline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '书架显示样式（含立体书脊）',
                              style: TextStyle(
                                color: sakura.inkPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final view in ShelfViewMode.values)
                                  ChoiceChip(
                                    label: Text(
                                      view.label,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: prefs.shelfView == view,
                                    onSelected: (_) => prefs.setShelfView(view),
                                  ),
                              ],
                            ),
                            const Divider(height: 22),
                            Text(
                              '书架层板 / 封面陈列样式',
                              style: TextStyle(
                                color: sakura.inkPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final plank in ShelfPlankStyle.values)
                                  ChoiceChip(
                                    label: Text(
                                      plank.shortLabel,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: prefs.shelfPlankStyle == plank,
                                    onSelected: (_) =>
                                        prefs.setShelfPlankStyle(plank),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              prefs.shelfPlankStyle.subtitle,
                              style: TextStyle(
                                color: sakura.inkSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            const Divider(height: 22),
                            _toggleRow(
                              context,
                              title: '封面动态取色光影',
                              subtitle: '根据当前在读书籍封面实时渲染柔和流体极光与窗格光斑',
                              value: prefs.ambientCoverAura,
                              onChanged: prefs.setAmbientCoverAura,
                            ),
                            _toggleRow(
                              context,
                              title: '陀螺仪重力光晕',
                              subtitle: '随手机倾斜柔和流动的环境光晕，阅读正文时自动隐藏',
                              value: prefs.gyroHaloEnabled,
                              onChanged: prefs.setGyroHaloEnabled,
                            ),
                            if (prefs.gyroHaloEnabled) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final (name, argb)
                                      in AppPrefs.gyroHaloPresets)
                                    ChoiceChip(
                                      avatar: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: Color(argb),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: sakura.hairline,
                                          ),
                                        ),
                                      ),
                                      label: Text(
                                        name,
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      selected: prefs.gyroHaloColor == argb,
                                      onSelected: (_) =>
                                          prefs.setGyroHaloColor(argb),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    '光晕强度',
                                    style: TextStyle(
                                      color: sakura.inkSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: prefs.gyroHaloIntensity,
                                      min: 0.15,
                                      max: 1.0,
                                      divisions: 17,
                                      onChanged: prefs.setGyroHaloIntensity,
                                    ),
                                  ),
                                  Text(
                                    '${(prefs.gyroHaloIntensity * 100).round()}%',
                                    style: TextStyle(
                                      color: sakura.inkSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            _toggleRow(
                              context,
                              title: '悬浮液态玻璃底栏',
                              subtitle: '底部导航化为高光折射悬浮胶囊（关闭则全宽贴底磨砂）',
                              value: prefs.floatingGlassDock,
                              onChanged: prefs.setFloatingGlassDock,
                            ),
                            _toggleRow(
                              context,
                              title: '书架微风樱花飘落',
                              subtitle: '轻柔花瓣随微风飘过书房（自动遵循系统减弱动效）',
                              value: prefs.shelfSakuraPetals,
                              onChanged: prefs.setShelfSakuraPetals,
                            ),
                            _toggleRow(
                              context,
                              title: '案头丝绸书签与藏书印',
                              subtitle: '「继续阅读」卡片展示垂坠书签带与可盖章「桜読蔵書」印',
                              value: prefs.silkBookmarkAndStamp,
                              onChanged: prefs.setSilkBookmarkAndStamp,
                            ),
                            _toggleRow(
                              context,
                              title: '3D 翻书展开进入正文',
                              subtitle: '点击继续阅读时模拟实体书从左书脊缓缓翻开',
                              value: prefs.bookUnfoldTransition,
                              onChanged: prefs.setBookUnfoldTransition,
                            ),
                            _toggleRow(
                              context,
                              title: '阅读顶/底栏实时磨砂玻璃',
                              subtitle: '阅读器呼出菜单时实时模糊底下正文；低端机可关闭省电',
                              value: prefs.frostedGlass,
                              onChanged: prefs.setFrostedGlass,
                            ),
                            _toggleRow(
                              context,
                              title: '启动开屏插画动画',
                              subtitle: '保留原版开屏插画与樱花入场；关闭后直达书架',
                              value: prefs.showSplashAnimation,
                              onChanged: prefs.setShowSplashAnimation,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionHeader(
                      context,
                      SakuraGlyph.appearance,
                      '明暗模式与主题点缀色',
                      null,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: sakura.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sakura.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text('跟随系统'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text('浅色'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text('深色'),
                              ),
                            ],
                            selected: {prefs.themeMode},
                            onSelectionChanged: (s) =>
                                prefs.setThemeMode(s.first),
                            showSelectedIcon: false,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '点缀主色',
                            style: TextStyle(
                              color: sakura.inkPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              for (var i = 0; i < AppPrefs.accents.length; i++)
                                GestureDetector(
                                  onTap: () => prefs.setAccentIndex(i),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: AppPrefs.accents[i],
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: prefs.accentIndex == i
                                                ? accent
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppPrefs.accents[i]
                                                  .withValues(alpha: 0.38),
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
                                      const SizedBox(height: 4),
                                      Text(
                                        AppPrefs.accentNames[i],
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: prefs.accentIndex == i
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: prefs.accentIndex == i
                                              ? accent
                                              : sakura.inkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    SakuraGlyph glyph,
    String title,
    String? subtitle,
  ) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        SakuraIcon(
          glyph: glyph,
          color: sakura.inkPrimary,
          accent: accent,
          size: 19,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: sakura.inkPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(color: sakura.inkSecondary, fontSize: 11.5),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final sakura = context.sakura;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          color: sakura.inkPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: sakura.inkSecondary, fontSize: 11.5),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final VisualStylePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final previewColors = switch (preset) {
      VisualStylePreset.sakuraAtelier =>
        isDark
            ? const [Color(0xFF2B1C32), Color(0xFF191522)]
            : const [Color(0xFFFDF0EC), Color(0xFFF6E7F2)],
      VisualStylePreset.liquidGlass =>
        isDark
            ? const [Color(0xFF1C294A), Color(0xFF121020)]
            : const [Color(0xFFE7F0FF), Color(0xFFF6EDFF)],
      VisualStylePreset.kyotoWashi =>
        isDark
            ? const [Color(0xFF2D221D), Color(0xFF1C1613)]
            : const [Color(0xFFF7ECD9), Color(0xFFEFDFC8)],
      VisualStylePreset.animePop =>
        isDark
            ? const [Color(0xFF1A3459), Color(0xFF3E1D6E)]
            : const [Color(0xFF38BDF8), Color(0xFFF472B6)],
    };

    return SakuraPressable(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected ? sakura.accentSoft : sakura.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? accent : sakura.hairline,
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 迷你书房风格预览窗
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: previewColors,
                  ),
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          preset.badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    // 迷你书本与层板示意
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _miniBook(const Color(0xFF5D9DF5)),
                              const SizedBox(width: 6),
                              _miniBook(const Color(0xFFEC729E)),
                              const SizedBox(width: 6),
                              _miniBook(const Color(0xFF56BA96)),
                            ],
                          ),
                          if (preset == VisualStylePreset.sakuraAtelier ||
                              preset == VisualStylePreset.kyotoWashi)
                            Container(
                              height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: preset == VisualStylePreset.kyotoWashi
                                    ? const Color(0xFFC8A482)
                                    : Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: sakura.inkPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: accent, size: 17),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              preset.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: sakura.inkSecondary,
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBook(Color color) {
    return Container(
      width: 17,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 0.7,
        ),
      ),
    );
  }
}
