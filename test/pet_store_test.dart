// 桌宠亲密度系统（pet_store）的单元测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';

void main() {
  late Directory tmp;
  late AppDirs dirs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sakura_pet_test');
    dirs = AppDirs(files: tmp.path, cache: tmp.path);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('PetStore 亲密度', () {
    test('等级阶梯：0/30/90/200/400/700/1200 → Lv.1~7', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      expect(pet.level, 1);
      expect(pet.levelName, '初遇');

      final cases = [
        (29, 1, '初遇'),
        (30, 2, '相识'),
        (90, 3, '书友'),
        (200, 4, '好友'),
        (400, 5, '知己'),
        (700, 6, '亲密'),
        (1200, 7, '挚爱'),
        (2000, 7, '挚爱'),
      ];
      for (final (affinity, level, name) in cases) {
        final p = PetStore(dirsOverride: dirs);
        await p.load();
        p.debugAddAffinity(affinity);
        expect(p.level, level, reason: '$affinity -> Lv.$level');
        expect(p.levelName, name);
      }
    });

    test('等级内进度与下一级阈值', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.debugAddAffinity(60); // Lv.2 区间 30~90
      expect(pet.level, 2);
      expect(pet.nextLevelAt, 90);
      expect(pet.levelProgress, closeTo((60 - 30) / (90 - 30), 0.001));
    });

    test('点击互动：+1/次，每日上限 20', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();

      for (var i = 0; i < 20; i++) {
        final r = pet.interact();
        expect(r.reason, 'ok');
        expect(r.points, 1);
      }
      expect(pet.affinity, 20);
      expect(pet.interactions, 20);

      // 第 21 次：上限
      final capped = pet.interact();
      expect(capped.reason, 'daily_cap');
      expect(capped.points, 0);
      expect(pet.affinity, 20);
    });

    test('跨天重置点击计数', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      final day1 = DateTime(2026, 1, 1, 10);
      final day2 = DateTime(2026, 1, 2, 10);
      for (var i = 0; i < 20; i++) {
        pet.interact(now: day1);
      }
      expect(pet.interact(now: day1).reason, 'daily_cap');
      // 第二天恢复
      expect(pet.interact(now: day2).reason, 'ok');
    });

    test('升级返回 leveledUp', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.debugAddAffinity(29); // 差 1 点到 Lv.2
      final r = pet.interact();
      expect(r.leveledUp, isTrue);
      expect(r.level, 2);
    });

    test('摸头（双击）：+2/次，每日上限 10', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      for (var i = 0; i < 10; i++) {
        final r = pet.pat();
        expect(r.reason, 'ok');
        expect(r.points, 2);
      }
      expect(pet.affinity, 20);
      final capped = pet.pat();
      expect(capped.reason, 'pat_cap');
      expect(capped.points, 0);
      // 摸头与点击独立计数（点击仍可用）
      expect(pet.interact().reason, 'ok');
    });
  });

  group('PetStore 打瞌睡', () {
    test('深夜时段（23:00~6:00）打瞌睡', () {
      final base = DateTime(2026, 6, 15, 12);
      expect(
        shouldPetDoze(
          now: DateTime(2026, 6, 15, 23, 30),
          lastInteraction: DateTime(2026, 6, 15, 23, 29),
        ),
        isTrue,
      );
      expect(
        shouldPetDoze(
          now: DateTime(2026, 6, 15, 3),
          lastInteraction: DateTime(2026, 6, 15, 2, 59),
        ),
        isTrue,
      );
      expect(
        shouldPetDoze(
          now: base,
          lastInteraction: base.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('白天长时间未互动（≥5分钟）打瞌睡', () {
      final now = DateTime(2026, 6, 15, 14);
      expect(
        shouldPetDoze(
          now: now,
          lastInteraction: now.subtract(const Duration(minutes: 5)),
        ),
        isTrue,
      );
      expect(
        shouldPetDoze(
          now: now,
          lastInteraction: now.subtract(const Duration(minutes: 4)),
        ),
        isFalse,
      );
    });
  });

  group('PetStore 时段问候', () {
    test('按小时返回对应问候语（覆盖 6 个时段边界）', () {
      expect(petGreetingForHour(4), contains('夜深'));
      expect(petGreetingForHour(5), contains('早上好'));
      expect(petGreetingForHour(10), contains('早上好'));
      expect(petGreetingForHour(11), contains('午后'));
      expect(petGreetingForHour(13), contains('午后'));
      expect(petGreetingForHour(14), contains('下午好'));
      expect(petGreetingForHour(17), contains('下午好'));
      expect(petGreetingForHour(18), contains('晚上好'));
      expect(petGreetingForHour(22), contains('晚上好'));
      expect(petGreetingForHour(23), contains('快休息'));
      expect(petGreetingForHour(0), contains('夜深'));
      expect(petGreetingForHour(3), contains('夜深'));
    });
  });

  group('PetStore 投喂', () {
    test('投喂消耗库存并加亲密度', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      // 没有库存时投喂失败
      expect(pet.feed('mochi').reason, 'no_food');

      // 阅读 20 分钟：获得 1 个樱饼
      pet.onReadingTick(20 * 60);
      expect(pet.foodCount('mochi'), 1);

      final r = pet.feed('mochi');
      expect(r.reason, 'ok');
      expect(r.points, 5);
      expect(pet.affinity, 5);
      expect(pet.foodCount('mochi'), 0);
      expect(pet.feeds, 1);
    });

    test('未知食物 id 投喂失败', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      expect(pet.feed('unknown').reason, 'no_food');
    });
  });

  group('PetStore 阅读奖励', () {
    test('里程碑发放（增量式）：樱饼 20min / 团子 1h / 大福 5h / 蛋糕 20h', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();

      pet.onReadingTick(20 * 60); // 总累计 20 分钟
      expect(pet.foodCount('mochi'), 1);
      expect(pet.foodCount('dango'), 0);

      pet.onReadingTick(40 * 60); // 总累计 60 分钟
      expect(pet.foodCount('mochi'), 3);
      expect(pet.foodCount('dango'), 1);

      pet.onReadingTick(4 * 60 * 60); // 总累计 5 小时
      expect(pet.foodCount('mochi'), 15);
      expect(pet.foodCount('dango'), 5);
      expect(pet.foodCount('daifuku'), 1);

      pet.onReadingTick(15 * 60 * 60); // 总累计 20 小时
      expect(pet.foodCount('cake'), 1);
      expect(pet.foodCount('daifuku'), 4);
      expect(pet.foodCount('dango'), 20);
      expect(pet.totalFoodEarned, 60 + 20 + 4 + 1);
      expect(pet.readSeconds, 20 * 60 * 60);
    });

    test('增量式累计：新时长继续累计，0 / 负数忽略', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.onReadingTick(40 * 60); // 总 40 分钟 → 2 樱饼
      expect(pet.foodCount('mochi'), 2);
      pet.onReadingTick(0); // 无增长
      pet.onReadingTick(-10); // 负数忽略
      expect(pet.foodCount('mochi'), 2);
      expect(pet.readSeconds, 40 * 60);
      pet.onReadingTick(20 * 60); // 总 60 分钟 → 3 樱饼 + 1 团子
      expect(pet.foodCount('mochi'), 3);
      expect(pet.foodCount('dango'), 1);
    });

    test('每天首次打开阅读器送 1 个团子', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      final day1 = DateTime(2026, 1, 1, 10);
      final day2 = DateTime(2026, 1, 2, 8);

      pet.onReadingSessionStart(now: day1);
      expect(pet.foodCount('dango'), 1);
      // 同一天再次打开：不重复送
      pet.onReadingSessionStart(now: day1);
      expect(pet.foodCount('dango'), 1);
      // 第二天：再送
      pet.onReadingSessionStart(now: day2);
      expect(pet.foodCount('dango'), 2);
    });

    test('unseenGains 播报后清零', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.onReadingTick(60 * 60);
      expect(pet.unseenGains, 4); // 3 樱饼 + 1 团子
      final n = pet.takeUnseenGains();
      expect(n, 4);
      expect(pet.unseenGains, 0);
      expect(pet.takeUnseenGains(), 0);
    });
  });

  group('PetStore 持久化', () {
    test('持久化：写入后重新加载', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.debugAddAffinity(120);
      pet.onReadingTick(60 * 60);
      pet.feed('mochi'); // 消耗 1 个
      pet.setPosition(0.2, 0.4);
      await pet.debugFlush();

      final reloaded = PetStore(dirsOverride: dirs);
      await reloaded.load();
      expect(reloaded.affinity, 120 + 5);
      expect(reloaded.foodCount('mochi'), 2); // 3 - 1
      expect(reloaded.foodCount('dango'), 1);
      expect(reloaded.petX, closeTo(0.2, 0.001));
      expect(reloaded.petY, closeTo(0.4, 0.001));
    });

    test('位置边界收敛', () async {
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      pet.setPosition(-1, 2);
      expect(pet.petX, 0);
      expect(pet.petY, 1);
      pet.resetPosition();
      expect(pet.petX, 0.86);
      expect(pet.petY, 0.62);
    });
  });
}
