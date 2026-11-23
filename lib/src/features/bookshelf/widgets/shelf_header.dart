import 'package:flutter/material.dart';

import '../../../core/motion/sakura_motion.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../theme/app_theme.dart';
import '../../../ui/widgets/pet_guide_overlay.dart';

/// 书架 2.0 顶部编辑风头栏：渐变延伸至透明状态栏底下，保留柔和纸感与清晰层级。
class ShelfHeader extends StatelessWidget {
  const ShelfHeader({
    super.key,
    required this.greeting,
    required this.bookCount,
    required this.onAiTap,
    required this.onSearchTap,
    required this.onArrangeTap,
    required this.onManageTap,
  });

  final String greeting;
  final int bookCount;
  final VoidCallback onAiTap;
  final VoidCallback onSearchTap;
  final VoidCallback onArrangeTap;
  final VoidCallback onManageTap;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        gradient: SakuraTheme.headerGradient(context),
        border: Border(bottom: BorderSide(color: sakura.hairline, width: 0.8)),
      ),
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 14, 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sakura.card.withValues(alpha: 0.85),
              border: Border.all(color: sakura.hairline),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/pet_wave.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '樱读',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: sakura.inkPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$greeting · $bookCount 本藏书',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sakura.inkSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'AI 助手',
            onTap: onAiTap,
            accentTint: true,
          ),
          const SizedBox(width: 6),
          PetGuideTarget(
            id: 'shelf_search',
            child: _HeaderIconButton(
              icon: Icons.search_rounded,
              tooltip: '搜索',
              onTap: onSearchTap,
            ),
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: '排列方式',
            onTap: onArrangeTap,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.checklist_rounded,
            tooltip: '批量管理',
            onTap: onManageTap,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accentTint = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accentTint;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentTint
                ? sakura.accentSoft
                : sakura.card.withValues(alpha: 0.78),
            border: Border.all(
              color: accentTint
                  ? accent.withValues(alpha: 0.28)
                  : sakura.hairline,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: accentTint ? accent : sakura.inkPrimary,
          ),
        ),
      ),
    );
  }
}
