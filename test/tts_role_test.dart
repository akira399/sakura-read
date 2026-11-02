import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/tts_role.dart';

void main() {
  group('TtsRolePlanner.classify', () {
    test('「人名：」前缀算对白并认出说话人', () {
      final role = TtsRolePlanner.classify('西蒙：我明天就走。', const ['西蒙']);
      expect(role.isDialogue, isTrue);
      expect(role.speaker, '西蒙');
    });

    test('引号对白能认出句子里的已有人名', () {
      final role = TtsRolePlanner.classify('「别走，」萨洛美抓住他的袖子，「再等一天。」', const [
        '西蒙',
        '萨洛美',
      ]);
      expect(role.isDialogue, isTrue);
      expect(role.speaker, '萨洛美');
    });

    test('旁白不算对白', () {
      final role = TtsRolePlanner.classify('天亮了，雨也停了。', const ['西蒙']);
      expect(role.isDialogue, isFalse);
      expect(role.speaker, isEmpty);
    });

    test('对白里没有已知人名时 speaker 为空但仍是对白', () {
      final role = TtsRolePlanner.classify('「谁在那儿？」', const ['西蒙']);
      expect(role.isDialogue, isTrue);
      expect(role.speaker, isEmpty);
    });
  });

  group('TtsRolePlanner.planPitches', () {
    const paragraphs = <String>[
      '天亮了，雨也停了。',
      '「西蒙，你终于来了。」',
      '「我来了。」西蒙放下伞。',
      '萨洛美：那就好。',
    ];

    test('长度与段落数一致且都在 0.5~2.0 之间', () {
      final pitches = TtsRolePlanner.planPitches(
        paragraphs,
        names: const ['西蒙', '萨洛美'],
        base: 1.2,
      );
      expect(pitches.length, paragraphs.length);
      for (final p in pitches) {
        expect(p, greaterThanOrEqualTo(0.5));
        expect(p, lessThanOrEqualTo(2.0));
      }
    });

    test('同一角色在不同段落音高一致', () {
      final pitches = TtsRolePlanner.planPitches(
        const ['「西蒙，你来了。」', '西蒙：我来了。'],
        names: const ['西蒙'],
        base: 1.0,
      );
      expect(pitches[0], closeTo(pitches[1], 1e-9));
    });

    test('旁白与对白音高不同', () {
      final pitches = TtsRolePlanner.planPitches(
        paragraphs,
        names: const ['西蒙', '萨洛美'],
        base: 1.0,
      );
      expect(TtsRolePlanner.differsFromBase(pitches, 1.0), isTrue);
    });

    test('空段落列表返回空表', () {
      expect(TtsRolePlanner.planPitches(const []), isEmpty);
    });
  });

  test('countSpeakers 数出「人名：」的个数', () {
    expect(TtsRolePlanner.countSpeakers('西蒙：走。\n萨洛美：等等。\n西蒙：快点。'), 2);
  });
}
