import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/stats_store.dart';
import '../util/format.dart';
import 'widgets/cute.dart';

/// 阅读记录 / 统计页：累计时长、阅读时长曲线、连续天数、读完书数。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.statsStore});

  final StatsStore statsStore;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// 曲线的时间跨度：7 / 14 / 30 天（用户反馈想要「详细的曲线图」）。
  int _range = 7;

  StatsStore get statsStore => widget.statsStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读记录'), centerTitle: true),
      body: AnimatedBuilder(
        animation: statsStore,
        builder: (context, _) {
          final days = statsStore.recentDays(_range);
          var maxSeconds = 1;
          var totalSeconds = 0;
          for (final d in days) {
            if (d.$2 > maxSeconds) maxSeconds = d.$2;
            totalSeconds += d.$2;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _heroCard(context),
              const SizedBox(height: 14),
              _badgesRow(context),
              const SizedBox(height: 14),
              _chartCard(context, days, maxSeconds, totalSeconds),
              const SizedBox(height: 14),
              _footerCard(context),
            ],
          );
        },
      ),
    );
  }

  Widget _heroCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Row(
        children: [
          const PetalLogo(size: 54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '累计阅读',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(statsStore.totalSeconds),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '已经在书海里游了 ${statsStore.readDays} 天',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgesRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _miniCard(
            context,
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFFF8A65),
            value: '${statsStore.streak}',
            unit: '天',
            label: '连续阅读',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _miniCard(
            context,
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFFFFB300),
            value: '${statsStore.finishedBooks}',
            unit: '本',
            label: '读完的书',
          ),
        ),
      ],
    );
  }

  Widget _miniCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String value,
    required String unit,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(
    BuildContext context,
    List<(String, int)> days,
    int maxSeconds,
    int totalSeconds,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final average = days.isEmpty ? 0 : totalSeconds ~/ days.length;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  icon: Icons.insights_rounded,
                  title: '阅读时长',
                ),
              ),
              _rangeChip(context, 7),
              const SizedBox(width: 6),
              _rangeChip(context, 14),
              const SizedBox(width: 6),
              _rangeChip(context, 30),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '合计 ${formatDuration(totalSeconds)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '日均 ${formatDuration(average)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 156,
            width: double.infinity,
            child: CustomPaint(
              painter: _ReadingCurvePainter(
                days: days,
                maxSeconds: maxSeconds,
                lineColor: scheme.primary,
                gridColor: scheme.outlineVariant.withValues(alpha: .35),
                textColor: scheme.onSurfaceVariant,
                textDirection: Directionality.of(context),
                // 横轴日期文字：从主题 labelSmall 派生，保留主题的字体族
                // （CustomPainter 里没有 DefaultTextStyle 可以继承）。
                labelStyle:
                    (Theme.of(context).textTheme.labelSmall ??
                            const TextStyle())
                        .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '只统计真正在看书的时间，安心阅读不焦虑',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _rangeChip(BuildContext context, int range) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _range == range;
    return GestureDetector(
      onTap: () => setState(() => _range = range),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: .16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: .6)
                : scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        child: Text(
          '$range 天',
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _footerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.spa_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '每天翻开一本书，樱花就会开一朵～',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 阅读时长平滑曲线（无第三方依赖，直接 CustomPainter 绘制）。
///
/// 用 Catmull-Rom 转三次贝塞尔，让折线变成顺滑曲线；曲线下方铺一层渐变，
/// 既能看出趋势，又保留「今天 / 峰值」这类可读锚点。
class _ReadingCurvePainter extends CustomPainter {
  _ReadingCurvePainter({
    required this.days,
    required this.maxSeconds,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
    required this.textDirection,
    required this.labelStyle,
  });

  final List<(String, int)> days;
  final int maxSeconds;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;
  final TextDirection textDirection;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 18.0;
    const topPad = 10.0;
    final chartHeight = size.height - bottomPad - topPad;
    if (days.isEmpty || chartHeight <= 0) return;

    // ---- 网格与纵轴刻度 ----
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = topPad + chartHeight * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ---- 数据点 ----
    final stepX = days.length == 1
        ? size.width
        : size.width / (days.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < days.length; i++) {
      final ratio = (days[i].$2 / maxSeconds).clamp(0.0, 1.0);
      points.add(
        Offset(
          days.length == 1 ? size.width / 2 : i * stepX,
          topPad + chartHeight * (1 - ratio),
        ),
      );
    }

    final path = _smoothPath(points);
    final fill = Path.from(path)
      ..lineTo(points.last.dx, topPad + chartHeight)
      ..lineTo(points.first.dx, topPad + chartHeight)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, topPad),
          Offset(0, topPad + chartHeight),
          [lineColor.withValues(alpha: .30), lineColor.withValues(alpha: .02)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ---- 数据点圆点（当天高亮） ----
    for (var i = 0; i < points.length; i++) {
      final isToday = i == points.length - 1;
      canvas.drawCircle(
        points[i],
        isToday ? 4.5 : 2.6,
        Paint()..color = lineColor,
      );
    }

    // ---- 横轴标签：天数多时自动抽稀，避免糊成一片 ----
    final labelEvery = days.length <= 8 ? 1 : (days.length / 6).ceil();
    for (var i = 0; i < days.length; i++) {
      final isToday = i == days.length - 1;
      if (!isToday && i % labelEvery != 0) continue;
      final label = isToday ? '今天' : days[i].$1.substring(5);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(
            fontSize: 9.5,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
            color: isToday ? lineColor : textColor,
          ),
        ),
        textDirection: textDirection,
        textScaler: TextScaler.noScaling,
      )..layout();
      final x = (points[i].dx - painter.width / 2).clamp(
        0.0,
        size.width - painter.width,
      );
      painter.paint(canvas, Offset(x, size.height - bottomPad + 4));
      painter.dispose();
    }
  }

  /// Catmull-Rom → 三次贝塞尔，得到过所有数据点的平滑曲线。
  Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _ReadingCurvePainter old) =>
      old.maxSeconds != maxSeconds ||
      old.labelStyle != labelStyle ||
      old.lineColor != lineColor ||
      old.days.length != days.length ||
      !_sameDays(old.days, days);

  bool _sameDays(List<(String, int)> a, List<(String, int)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1 || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }
}
