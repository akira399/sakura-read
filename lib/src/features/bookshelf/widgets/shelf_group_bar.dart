import 'package:flutter/material.dart';

import '../../../core/theme/sakura_tokens.dart';
import '../../../data/models.dart';

/// 书架分组筛选条：仅在存在自定义分组时显示。
class ShelfGroupBar extends StatelessWidget {
  const ShelfGroupBar({
    super.key,
    required this.allBooks,
    required this.selectedGroup,
    required this.onSelectGroup,
  });

  final List<Book> allBooks;
  final String? selectedGroup;
  final ValueChanged<String?> onSelectGroup;

  @override
  Widget build(BuildContext context) {
    final groups = <String>{
      for (final b in allBooks)
        if (b.group.isNotEmpty) b.group,
    }.toList()..sort();
    if (groups.isEmpty) return const SizedBox.shrink();

    final ungroupedCount = allBooks.where((b) => b.group.isEmpty).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _GroupPill(
              label: '全部 (${allBooks.length})',
              selected: selectedGroup == null,
              onTap: () => onSelectGroup(null),
            ),
            const SizedBox(width: 8),
            _GroupPill(
              label: '未分组 ($ungroupedCount)',
              selected: selectedGroup == '',
              onTap: () => onSelectGroup(selectedGroup == '' ? null : ''),
            ),
            for (final g in groups) ...[
              const SizedBox(width: 8),
              _GroupPill(
                label: '$g (${allBooks.where((b) => b.group == g).length})',
                selected: selectedGroup == g,
                onTap: () => onSelectGroup(selectedGroup == g ? null : g),
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
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? sakura.accentSoft : sakura.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.45) : sakura.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : sakura.inkSecondary,
          ),
        ),
      ),
    );
  }
}
