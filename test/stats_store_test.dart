// 书签与阅读统计（stats_store）的单元测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/util/format.dart';

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  late Directory tmp;
  late AppDirs dirs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sakura_stats_test');
    dirs = AppDirs(files: tmp.path, cache: tmp.path);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('BookmarkStore', () {
    test('同一位置 ±12 字符内判重，不产生重复书签', () async {
      final store = BookmarkStore(dirsOverride: dirs);
      await store.load();

      store.add(
        Bookmark(id: 'a', bookId: 'b1', chapterIndex: 2, charOffset: 100),
      );
      final dup = store.add(
        Bookmark(id: 'b', bookId: 'b1', chapterIndex: 2, charOffset: 108),
      );
      expect(dup.id, 'a');
      expect(store.count, 1);

      store.add(
        Bookmark(id: 'c', bookId: 'b1', chapterIndex: 2, charOffset: 200),
      );
      expect(store.count, 2);

      // 不同章节即使偏移接近也不算重复
      store.add(
        Bookmark(id: 'd', bookId: 'b1', chapterIndex: 3, charOffset: 100),
      );
      expect(store.count, 3);

      // 不同书即使章节偏移相同也不算重复
      store.add(
        Bookmark(id: 'e', bookId: 'b2', chapterIndex: 2, charOffset: 100),
      );
      expect(store.count, 4);
    });

    test('forBook 按章节 + 偏移排序', () async {
      final store = BookmarkStore(dirsOverride: dirs);
      await store.load();
      store.add(
        Bookmark(id: '1', bookId: 'b1', chapterIndex: 3, charOffset: 10),
      );
      store.add(
        Bookmark(id: '2', bookId: 'b1', chapterIndex: 1, charOffset: 50),
      );
      store.add(
        Bookmark(id: '3', bookId: 'b1', chapterIndex: 1, charOffset: 5),
      );
      store.add(
        Bookmark(id: '4', bookId: 'b2', chapterIndex: 0, charOffset: 1),
      );

      final list = store.forBook('b1');
      expect(list.map((b) => b.id).toList(), ['3', '2', '1']);
    });

    test('remove / removeForBook', () async {
      final store = BookmarkStore(dirsOverride: dirs);
      await store.load();
      store.add(
        Bookmark(id: '1', bookId: 'b1', chapterIndex: 0, charOffset: 0),
      );
      store.add(
        Bookmark(id: '2', bookId: 'b1', chapterIndex: 1, charOffset: 30),
      );
      store.add(
        Bookmark(id: '3', bookId: 'b2', chapterIndex: 0, charOffset: 0),
      );

      store.remove('2');
      expect(store.count, 2);
      store.removeForBook('b1');
      expect(store.count, 1);
      expect(store.forBook('b1'), isEmpty);
    });

    test('持久化：写入后重新加载', () async {
      final store = BookmarkStore(dirsOverride: dirs);
      await store.load();
      store.add(
        Bookmark(
          id: 'persist',
          bookId: 'b1',
          chapterIndex: 4,
          charOffset: 66,
          chapterTitle: '第四章',
          excerpt: '摘录内容',
        ),
      );
      await store.debugFlush();

      final reloaded = BookmarkStore(dirsOverride: dirs);
      await reloaded.load();
      expect(reloaded.count, 1);
      final b = reloaded.items.first;
      expect(b.id, 'persist');
      expect(b.chapterIndex, 4);
      expect(b.charOffset, 66);
      expect(b.chapterTitle, '第四章');
      expect(b.excerpt, '摘录内容');
    });
  });

  group('StatsStore', () {
    test('单次累计上限 90 秒 + 每日累计', () async {
      final stats = StatsStore(dirsOverride: dirs);
      await stats.load();

      stats.addReadingSeconds(200); // 截断到 90
      expect(stats.totalSeconds, 90);
      stats.addReadingSeconds(30);
      expect(stats.totalSeconds, 120);
      expect(stats.readDays, 1);
      expect(stats.days[_key(DateTime.now())], 120);

      stats.addReadingSeconds(0);
      stats.addReadingSeconds(-5);
      expect(stats.totalSeconds, 120);
    });

    test('连续天数：今天没读从昨天起算', () async {
      final now = DateTime.now();

      final stats = StatsStore(dirsOverride: dirs);
      await stats.load();
      stats.debugAddSecondsForDate(_key(now), 10);
      stats.debugAddSecondsForDate(
        _key(now.subtract(const Duration(days: 1))),
        10,
      );
      stats.debugAddSecondsForDate(
        _key(now.subtract(const Duration(days: 2))),
        10,
      );
      expect(stats.streak, 3);

      final stats2 = StatsStore(dirsOverride: dirs);
      await stats2.load();
      stats2.debugAddSecondsForDate(
        _key(now.subtract(const Duration(days: 1))),
        10,
      );
      stats2.debugAddSecondsForDate(
        _key(now.subtract(const Duration(days: 2))),
        10,
      );
      expect(stats2.streak, 2);

      final stats3 = StatsStore(dirsOverride: dirs);
      await stats3.load();
      stats3.debugAddSecondsForDate(
        _key(now.subtract(const Duration(days: 3))),
        10,
      );
      expect(stats3.streak, 0);
    });

    test('recentDays 返回含今天在内的连续日期', () async {
      final stats = StatsStore(dirsOverride: dirs);
      await stats.load();
      final today = _key(DateTime.now());
      stats.debugAddSecondsForDate(today, 60);

      final days = stats.recentDays(7);
      expect(days.length, 7);
      expect(days.last.$1, today);
      expect(days.last.$2, 60);
      expect(days.first.$2, 0);
      // 日期从早到晚排列
      expect(days.first.$1.compareTo(days.last.$1) < 0, isTrue);
    });

    test('addFinishedBook 计数', () async {
      final stats = StatsStore(dirsOverride: dirs);
      await stats.load();
      stats.addFinishedBook();
      stats.addFinishedBook();
      expect(stats.finishedBooks, 2);
    });

    test('持久化：写入后重新加载', () async {
      final stats = StatsStore(dirsOverride: dirs);
      await stats.load();
      stats.addReadingSeconds(45);
      stats.addFinishedBook();
      await stats.debugFlush();

      final reloaded = StatsStore(dirsOverride: dirs);
      await reloaded.load();
      expect(reloaded.totalSeconds, 45);
      expect(reloaded.finishedBooks, 1);
      expect(reloaded.days[_key(DateTime.now())], 45);
    });
  });

  group('formatDuration', () {
    test('时长格式化', () {
      expect(formatDuration(0), '0 分钟');
      expect(formatDuration(45), '45 秒');
      expect(formatDuration(90), '1 分钟');
      expect(formatDuration(3600), '1 小时');
      expect(formatDuration(3900), '1 小时 5 分钟');
    });
  });
}
