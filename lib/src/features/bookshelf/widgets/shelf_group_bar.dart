import 'package:flutter/material.dart';

import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';

/// 书架分组筛选条：按视觉风格呈现「和纸胶带 / 轻漫斜切 / 液态玻璃胶囊」。
class ShelfGroupBar extends StatelessWidget {
  const ShelfGroupBar({
    super.key,
    required this.allBooks,
    required this.selectedGroup,
    required this.onSelectGroup,
    this.visualStyle = VisualStylePreset.sakuraAtelier,
  });

  final List<Book> allBooks;
  final String? selectedGroup;
  final ValueChanged<String?> onSelectGroup;
  final VisualStylePreset visualStyle;

  @override
  Widget build(BuildContext context) {
    final groups = <String>{
      for (final b in allBooks)
        if (b.group.isNotEmpty) b.group,
    }.toList()..sort();
    if (groups.isEmpty) return const SizedBox.shrink();

    final ungroupedCount = allBooks.where((b) => b.group.isEmpty).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _GroupPill(
              index: 0,
              visualStyle: visualStyle,
              label: '全部 (${allBooks.length})',
              selected: selectedGroup == null,
              onTap: () => onSelectGroup(null),
            ),
            const SizedBox(width: 9),
            _GroupPill(
              index: 1,
              visualStyle: visualStyle,
              label: '未分组 ($ungroupedCount)',
              selected: selectedGroup == '',
              onTap: () => onSelectGroup(selectedGroup == '' ? null : ''),
            ),
            for (var i = 0; i < groups.length; i++) ...[
              const SizedBox(width: 9),
              _GroupPill(
                index: i + 2,
                visualStyle: visualStyle,
                label:
                    '${groups[i]} (${allBooks.where((b) => b.group == groups[i]).length})',
                selected: selectedGroup == groups[i],
                onTap: () => onSelectGroup(
                  selectedGroup == groups[i] ? null : groups[i],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupPill extends StatelessWidget {
  const _GroupPill({
    required this.index,
    required this.visualStyle,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final VisualStylePreset visualStyle;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;

    final isTape =
        visualStyle == VisualStylePreset.sakuraAtelier ||
        visualStyle == VisualStylePreset.kyotoWashi;
    final isAnime = visualStyle == VisualStylePreset.animePop;

    final tapeBg = switch (index % 3) {
      0 =>
        isDark
            ? const Color(0xFFE86A92).withValues(alpha: selected ? 0.34 : 0.14)
            : const Color(0xFFFFD5E3).withValues(alpha: selected ? 0.78 : 0.42),
      1 =>
        isDark
            ? const Color(0xFF46A884).withValues(alpha: selected ? 0.30 : 0.12)
            : const Color(0xFFCDEEE0).withValues(alpha: selected ? 0.75 : 0.38),
      _ =>
        isDark
            ? const Color(0xFFE58E49).withValues(alpha: selected ? 0.30 : 0.12)
            : const Color(0xFFFBE1B8).withValues(alpha: selected ? 0.78 : 0.42),
    };

    final angle = isTape ? (index.isEven ? -0.022 : 0.020) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: angle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: isAnime
                ? (selected ? const Color(0xFF38BDF8) : sakura.card)
                : isTape
                ? (selected ? tapeBg : sakura.card.withValues(alpha: 0.72))
                : (selected
                      ? sakura.accentSoft
                      : sakura.card.withValues(alpha: 0.72)),
            borderRadius: BorderRadius.circular(
              isAnime ? 8 : (isTape ? 7 : 999),
            ),
            border: Border.all(
              color: isAnime
                  ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F172A))
                  : selected
                  ? accent.withValues(alpha: 0.48)
                  : sakura.hairline,
              width: isAnime ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: isAnime && selected
                  ? const Color(0xFF0F172A)
                  : selected
                  ? (isTape ? sakura.inkPrimary : accent)
                  : sakura.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
