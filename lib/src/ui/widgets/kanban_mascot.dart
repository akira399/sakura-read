import 'package:flutter/material.dart';

/// 互动看板娘：点击切换表情 + 台词气泡（用于空状态等场景）。
///
/// 立绘为透明 PNG（背景已去除），只显示人物本身。
class KanbanMascot extends StatefulWidget {
  const KanbanMascot({
    super.key,
    this.size = 200,
    this.showBubble = true,
    this.lines,
  });

  /// 立绘显示高度（宽度按图片比例自适应）。
  final double size;
  final bool showBubble;

  /// 自定义台词组（默认使用通用台词；空书架场景可传入专属台词）。
  final List<String>? lines;

  @override
  State<KanbanMascot> createState() => _KanbanMascotState();
}

/// 透明立绘差分（只含人物，无背景）。
const kanbanFaces = [
  'assets/images/pet_chibi.png',
  'assets/images/pet_wave.png',
  'assets/images/pet_read.png',
  'assets/images/pet_cheer.png',
  'assets/images/pet_sleep.png',
  'assets/images/pet_shy.png',
];

class _KanbanMascotState extends State<KanbanMascot> {
  static const _defaultLines = [
    '今天也要好好读书哦',
    '我在呢，随时都能来找我',
    '读到第几章啦？',
    '书里藏着好多世界呢',
    '呼……看书看累了就休息下',
    '嘿嘿，被你点到啦',
  ];

  var _i = 0;

  void _next() {
    setState(() => _i = (_i + 1) % kanbanFaces.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.lines ?? _defaultLines;
    return GestureDetector(
      onTap: _next,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Image.asset(
              kanbanFaces[_i],
              key: ValueKey<int>(_i),
              height: widget.size,
              fit: BoxFit.contain,
            ),
          ),
          if (widget.showBubble) ...[
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey<String>('bubble$_i'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  lines[_i % lines.length],
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
