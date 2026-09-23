import 'package:flutter/material.dart';

import '../data/stats_store.dart';
import '../util/format.dart';
import 'widgets/cute.dart';

/// 阅读记录 / 统计页：累计时长、最近 7 天柱状图、连续天数、读完书数。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.statsStore});

  final StatsStore statsStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读记录'), centerTitle: true),
      body: AnimatedBuilder(
        animation: statsStore,
        builder: (context, _) {
          final days = statsStore.recentDays(7);
          var maxSeconds = 1;
          for (final d in days) {
            if (d.$2 > maxSeconds) maxSeconds = d.$2;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _heroCard(context),
              const SizedBox(height: 14),
              _badgesRow(context),
              const SizedBox(height: 14),
              _weeklyCard(context, days, maxSeconds),
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

  Widget _weeklyCard(
    BuildContext context,
    List<(String, int)> days,
    int maxSeconds,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.insights_rounded, title: '最近 7 天'),
          const SizedBox(height: 4),
          Text(
            '只统计真正在看书的时间，安心阅读不焦虑',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: _bar(
                      context,
                      days[i],
                      maxSeconds,
                      isToday: i == days.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    (String, int) day,
    int maxSeconds, {
    required bool isToday,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final seconds = day.$2;
    final ratio = (seconds / maxSeconds).clamp(0.0, 1.0);
    final barHeight = seconds <= 0 ? 4.0 : (8 + ratio * 96).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 14,
            child: seconds <= 0
                ? null
                : FittedBox(
                    child: Text(
                      _shortDuration(seconds),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          Container(
            height: barHeight,
            decoration: BoxDecoration(
              gradient: seconds <= 0
                  ? null
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.primary.withValues(alpha: .95),
                        scheme.primary.withValues(alpha: .45),
                      ],
                    ),
              color: seconds <= 0
                  ? scheme.outlineVariant.withValues(alpha: .5)
                  : null,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isToday ? '今天' : day.$1.substring(8),
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${(seconds / 3600).toStringAsFixed(1)}h';
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
