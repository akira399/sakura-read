// 朗读分段（splitForSpeech）的单元测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/platform/tts_service.dart';

void main() {
  group('splitForSpeech', () {
    test('按行切分并去掉空行（短行会合并成一段）', () {
      const text = '第一段内容。\n\n第二段内容。\n   \n第三段内容。';
      final parts = splitForSpeech(text);
      // 三行都很短（<maxLen），会合并成一段
      expect(parts.length, 1);
      expect(parts.first.contains('第一段内容。'), isTrue);
      expect(parts.first.contains('第二段内容。'), isTrue);
      expect(parts.first.contains('第三段内容。'), isTrue);
      // 不合并时（maxLen 很小）应保持 3 段
      final split = splitForSpeech(text, maxLen: 8);
      expect(split.length, 3);
      expect(split[0], '第一段内容。');
      expect(split[1], '第二段内容。');
      expect(split[2], '第三段内容。');
    });

    test('短行合并到 maxLen 以内', () {
      // 每行 ~10 字，maxLen=30 → 每段合并 2~3 行
      const text =
          '一二三四五六七八九十\n'
          '十一十二十三十四十五\n'
          '十六十七十八十九二十\n'
          '二十一二十二二十三\n';
      final parts = splitForSpeech(text, maxLen: 30);
      for (final p in parts) {
        expect(p.replaceAll(' ', '').length, lessThanOrEqualTo(30));
      }
      // 总字数守恒（忽略合并时插入的空格）
      final joined = parts.join('').replaceAll(' ', '');
      expect(joined.contains('一二三四五六七八九十'), isTrue);
      expect(joined.contains('二十一二十二二十三'), isTrue);
    });

    test('超长行按标点切分', () {
      final long = List.generate(30, (i) => '这是第$i句话，').join();
      final parts = splitForSpeech(long, maxLen: 60, minLen: 20);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(60));
      }
      // 切分应尽量落在标点后
      for (final p in parts.take(parts.length - 1)) {
        final last = p.substring(p.length - 1);
        expect('。！？；，、…'.contains(last), isTrue);
      }
    });

    test('全角空格被规整为半角空格', () {
      const text = '　　「你好。」她说。';
      final parts = splitForSpeech(text);
      expect(parts.first.startsWith('「'), isTrue);
      expect(parts.first.contains('　'), isFalse);
    });

    test('空文本返回空列表', () {
      expect(splitForSpeech(''), isEmpty);
      expect(splitForSpeech('   \n  \n '), isEmpty);
    });

    test('单行不超长时保持完整', () {
      const text = '这是一句短话。';
      final parts = splitForSpeech(text);
      expect(parts, ['这是一句短话。']);
    });
  });

  group('splitForSpeechWithOffsets', () {
    test('偏移指向原文中的段落起点', () {
      const text = '第一段内容。\n第二段内容。\n第三段内容。';
      // 用很小的 maxLen 保证每行独立成段
      final paras = splitForSpeechWithOffsets(text, maxLen: 8);
      expect(paras.length, 3);
      // 每段的 offset 应指向原文中该段的起点
      for (final p in paras) {
        expect(text.startsWith(p.text, p.offset), isTrue);
      }
      expect(paras[0].offset, 0);
      expect(paras[1].offset, 7); // '第一段内容。'（6 字）+ '\n'
    });

    test('超长行的分段偏移递增', () {
      final long = List.generate(20, (i) => '句子$i。').join();
      final paras = splitForSpeechWithOffsets(long, maxLen: 40, minLen: 10);
      expect(paras.length, greaterThan(1));
      for (var i = 1; i < paras.length; i++) {
        expect(paras[i].offset, greaterThan(paras[i - 1].offset));
      }
    });

    test('splitForSpeech 与 WithOffsets 文本一致', () {
      const text = '甲段。\n乙段。\n丙段。';
      expect(
        splitForSpeech(text),
        splitForSpeechWithOffsets(text).map((p) => p.text).toList(),
      );
    });
  });
}
