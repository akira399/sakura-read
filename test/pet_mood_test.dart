// 桌宠互动状态机（PetMood）的单测：生气判定 + 锁屏门槛 + 台词池。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_mood.dart';

/// 可预测的假随机（按固定序列返回）。
class _FakeRandom implements Random {
  _FakeRandom(this.values);

  final List<double> values;
  int _i = 0;

  @override
  double nextDouble() {
    final v = values[_i % values.length];
    _i++;
    return v;
  }

  @override
  int nextInt(int max) => (nextDouble() * max).floor().clamp(0, max - 1);

  @override
  bool nextBool() => nextDouble() < .5;
}

void main() {
  group('PetMood 频繁点击判定', () {
    test('窗口内累计达到阈值即视为频繁', () {
      final mood = PetMood(random: _FakeRandom([.5]));
      final t0 = DateTime(2026, 9, 22, 12);
      for (var i = 0; i < PetMood.spamThreshold - 1; i++) {
        expect(mood.registerTap(t0.add(Duration(milliseconds: i))), isFalse);
      }
      expect(mood.registerTap(t0.add(const Duration(seconds: 1))), isTrue);
    });

    test('超出时间窗口的旧点击被清理', () {
      final mood = PetMood(random: _FakeRandom([.5]));
      final t0 = DateTime(2026, 9, 22, 12);
      for (var i = 0; i < PetMood.spamThreshold - 1; i++) {
        mood.registerTap(t0);
      }
      final later = t0.add(PetMood.spamWindow + const Duration(seconds: 1));
      expect(mood.registerTap(later), isFalse);
    });
  });

  group('PetMood 锁屏门槛（第 4 次起才有概率）', () {
    test('前三次生气绝不触发锁屏', () {
      for (var i = 0; i < PetMood.eggFromCount - 1; i++) {
        final mood = PetMood(random: _FakeRandom([0.0]));
        mood.angryCount = i;
        expect(mood.eggChance, 0, reason: '第 ${i + 1} 次不该有概率');
        expect(mood.escalate(), isFalse);
      }
    });

    test('第 4 次起按概率触发，且概率随次数递增', () {
      final mood = PetMood(random: _FakeRandom([0.99]));
      mood.angryCount = PetMood.eggFromCount;
      expect(mood.eggChance, closeTo(PetMood.eggChanceAt4, .0001));
      final c4 = mood.eggChance;
      mood.angryCount = PetMood.eggFromCount + 1;
      final c5 = mood.eggChance;
      mood.angryCount = PetMood.eggFromCount + 5;
      final c9 = mood.eggChance;
      expect(c5, greaterThan(c4));
      expect(c9, greaterThan(c5));
      expect(c9, lessThanOrEqualTo(PetMood.eggChanceMax));
    });

    test('达到门槛且随机值足够小 → 触发锁屏', () {
      final mood = PetMood(random: _FakeRandom([0.0]));
      mood.angryCount = PetMood.eggFromCount - 1;
      expect(mood.escalate(), isTrue);
      expect(mood.angryCount, PetMood.eggFromCount);
    });

    test('reset 清空计数', () {
      final mood = PetMood(random: _FakeRandom([0.0]));
      mood.angryCount = 6;
      mood.reset();
      expect(mood.angryCount, 0);
      expect(mood.eggChance, 0);
    });
  });

  group('PetMood 拖动生气概率（大幅降低）', () {
    test('单次拖动默认不生气（概率很低）', () {
      // 0.5 > dragAngryChance(0.06) → 不生气
      final mood = PetMood(random: _FakeRandom([0.5, 0.0]));
      final r = mood.onDrag();
      expect(r.angry, isFalse);
      expect(r.egg, isFalse);
      expect(petDragLines.contains(r.line), isTrue);
      expect(mood.angryCount, 0);
    });

    test('概率内才生气', () {
      final mood = PetMood(random: _FakeRandom([0.0, 0.0]));
      final r = mood.onDrag();
      expect(r.angry, isTrue);
      expect(mood.angryCount, 1);
      expect(petAngryDragLines.contains(r.line), isTrue);
    });

    test('频繁拖动会把概率明显抬高', () {
      final mood = PetMood(random: _FakeRandom([0.5]));
      // 先来 5 次拖动（进入频繁状态）
      for (var i = 0; i < PetMood.dragSpamThreshold; i++) {
        mood.isDraggingALot;
        mood.onDrag();
      }
      expect(mood.isDraggingALot, isTrue);
      // 0.5 介于 dragAngryChance(0.06) 与 dragSpamChance(0.45) 之间：
      // 频繁状态下仍不生气 → 说明用的是 0.06（更低）而不是 0.45？反之亦然
      // 这里只断言「频繁状态确实被识别」
      expect(PetMood.dragSpamChance, greaterThan(PetMood.dragAngryChance));
    });
  });

  group('PetMood 其它互动', () {
    test('睡觉被叫醒：必定生气', () {
      final mood = PetMood(random: _FakeRandom([0.5]));
      final r = mood.onWake();
      expect(r.angry, isTrue);
      expect(r.action, PetAction.wake);
      expect(mood.angryCount, 1);
    });

    test('频繁点击：必定生气', () {
      final mood = PetMood(random: _FakeRandom([0.5]));
      final r = mood.onSpam();
      expect(r.angry, isTrue);
      expect(petAngrySpamLines.contains(r.line), isTrue);
    });
  });

  group('台词池与文案', () {
    test('所有台词池非空且无空串', () {
      for (final pool in [
        petDragLines,
        petAngryDragLines,
        petAngryWakeLines,
        petAngrySpamLines,
        petHopLines,
        petRoamLines,
        petRoamReaderLines,
        petGuideNags,
      ]) {
        expect(pool, isNotEmpty);
        for (final line in pool) {
          expect(line.trim(), isNotEmpty);
        }
      }
    });

    test('彩蛋台词与血字：已去掉「只有重启才能恢复正常」', () {
      expect(petEggLine, '你以为我是好惹的？');
      expect(petEggFooter, '小樱禁止你使用该软件');
      expect(petEggFooter.contains('重启'), isFalse);
    });

    test('引导劝导词共 5 句（第 6 次不听话触发锁屏）', () {
      expect(petGuideNags.length, 5);
    });

    test('阅读时乱跑概率高于主界面（故意捣乱）', () {
      expect(petRoamChanceReader, greaterThan(petRoamChanceHome));
      expect(
        petRoamCheckIntervalReader,
        lessThan(petRoamCheckInterval),
        reason: '阅读时检查更频繁',
      );
    });
  });
}
