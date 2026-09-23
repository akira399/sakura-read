import 'package:flutter/material.dart';

import '../../platform/tts_service.dart';

/// 朗读控制条：悬浮在阅读页底部，显示进度并控制播放。
class TtsBar extends StatelessWidget {
  const TtsBar({
    super.key,
    required this.service,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
    required this.onStop,
    required this.onOpenSettings,
    this.dark = true,
  });

  final TtsService service;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  /// 深色底（阅读器默认）还是浅色底。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Colors.black87;
    final fgDim = fg.withValues(alpha: .55);
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final total = service.total;
        final idx = service.index;
        final label = service.lastError != null
            ? service.lastError!
            : (total == 0
                  ? '准备朗读…'
                  : (idx < 0 ? '共 $total 段' : '第 ${idx + 1} / $total 段'));
        return Container(
          decoration: BoxDecoration(
            color: dark
                ? Colors.black.withValues(alpha: .86)
                : Colors.white.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: service.speaking ? fg : fgDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: idx < 0 ? 0 : (idx + 1) / total,
                          minHeight: 3,
                          backgroundColor: fg.withValues(alpha: .18),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            dark ? const Color(0xFFFFB7C5) : Colors.pinkAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _btn(
                icon: Icons.skip_previous_rounded,
                fg: fg,
                tooltip: '上一段',
                onTap: onPrev,
              ),
              _btn(
                icon: service.speaking
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                fg: fg,
                tooltip: service.speaking ? '暂停' : '继续',
                onTap: onToggle,
                big: true,
              ),
              _btn(
                icon: Icons.skip_next_rounded,
                fg: fg,
                tooltip: '下一段',
                onTap: onNext,
              ),
              _btn(
                icon: Icons.tune_rounded,
                fg: fg,
                tooltip: '朗读设置',
                onTap: onOpenSettings,
              ),
              _btn(
                icon: Icons.close_rounded,
                fg: fg,
                tooltip: '退出朗读',
                onTap: onStop,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _btn({
    required IconData icon,
    required Color fg,
    required String tooltip,
    required VoidCallback onTap,
    bool big = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: big ? 26 : 20,
      color: fg,
      icon: Icon(icon),
    );
  }
}
