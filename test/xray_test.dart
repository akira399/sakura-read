import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/xray.dart';

/// 一段「翻译小说」风格的中文正文：人名 + 说话动词。
const _sample = '''
　　西蒙特说：「你终于回来了。」
　　萨洛美问道：「这几年你去了哪儿？」
　　马尔塔说：「先坐下，喝口茶。」
　　约翰娜说道：「他早就不在了。」
　　大家都说这事儿奇怪，可谁也说不清。
　　老人说：「等一等。」
　　医生问道：「他还有救吗？」
　　西蒙特说：「我会去。」
　　萨洛美说：「我也去。」
　　马丁说：「别争了。」
　　西蒙特说：「那就这么定了。」
　　萨洛美问道：「真的？」
　　马尔塔说：「放心。」
　　马丁说：「明天出发。」
　　约翰娜说：「我不去。」
　　约翰娜说：「我得留下看家。」
　　西蒙特说：「好。」
　　马丁说：「一路顺风。」
''';

void main() {
  test('从翻译小说正文里认出人名，并排除「大家 / 老人 / 医生」这类通名', () {
    final index = buildXrayIndex(const [_sample]);

    final names = index.entities.map((e) => e.name).toSet();
    expect(names.contains('西蒙特'), isTrue, reason: '应识别出「西蒙特」');
    expect(names.contains('萨洛美'), isTrue, reason: '应识别出「萨洛美」');
    expect(names.contains('马尔塔'), isTrue, reason: '应识别出「马尔塔」');
    expect(names.contains('马丁'), isTrue, reason: '应识别出「马丁」');

    expect(names.contains('大家'), isFalse);
    expect(names.contains('老人'), isFalse);
    expect(names.contains('医生'), isFalse);
    expect(names.contains('约翰娜') || names.contains('约翰'), isTrue);
  });

  test('统计出现次数与章节跨度', () {
    final index = buildXrayIndex(const [
      '西蒙特说：「一。」\n萨洛美说：「二。」',
      '西蒙特说：「三。」\n马丁说：「四。」',
      '西蒙特问道：「五？」\n马丁说：「六。」',
    ]);
    final xm = index.entities.firstWhere((e) => e.name == '西蒙特');
    expect(xm.count, 3);
    expect(xm.chapterSpread, 3);
    expect(xm.firstChapter, 0);
  });

  test('高亮正则能命中所有实体，长名优先', () {
    final index = buildXrayIndex(const [_sample]);
    final pattern = index.pattern!;
    final matched = pattern
        .allMatches('西蒙特说，萨洛美问道，马尔塔说。')
        .map((m) => m.group(0))
        .toList();
    expect(matched, contains('西蒙特'));
    expect(matched, contains('萨洛美'));
    expect(matched, contains('马尔塔'));
  });

  test('带称呼的写法折叠到本名：别名不重复计数，高亮按整段匹配', () {
    final index = buildXrayIndex(const [
      '西蒙说：「一。」\n西蒙先生说道：「二。」\n马丁说：「三。」',
      '西蒙问道：「四？」\n西蒙先生笑道：「五。」\n马丁说：「六。」',
      '西蒙说：「七。」\n马丁说：「八。」',
    ]);

    final simon = index.entities.firstWhere((e) => e.name == '西蒙');
    expect(simon.aliases, contains('西蒙先生'));
    // 3 次本名 + 2 次「西蒙先生」，合并成同一个人的 5 处
    expect(simon.count, 5);

    // 「西蒙先生」只有一个条目，不会单独再占一行
    expect(index.entities.where((e) => e.name == '西蒙先生'), isEmpty);

    // 高亮时整段匹配，不会拆成「西蒙」+「先生」
    final matched = index.pattern!
        .allMatches('西蒙先生说，西蒙点头。')
        .map((m) => m.group(0))
        .toList();
    expect(matched, ['西蒙先生', '西蒙']);
  });

  test('「老马丁」和「马丁」归并成一个人', () {
    final index = buildXrayIndex(const [
      '马丁说：「一。」\n老马丁说：「二。」',
      '马丁说：「三。」\n马丁说：「四。」',
      '马丁说：「五。」',
    ]);
    final martin = index.entities.firstWhere((e) => e.name == '马丁');
    expect(martin.aliases, contains('老马丁'));
    expect(martin.count, 5);
  });

  test('「人名：台词」的排版也能认出来（不写「说」）', () {
    final index = buildXrayIndex(const [
      '　　贝亚特丽：你终于回来了。\n　　克劳斯：路上耽搁了。',
      '　　贝亚特丽：那就好。\n　　克劳斯：明天再说。',
      '　　贝亚特丽：好。\n　　牧师：愿主保佑。',
    ]);
    final names = index.entities.map((e) => e.name).toSet();
    expect(names.contains('贝亚特丽'), isTrue);
    expect(names.contains('克劳斯'), isTrue);
    // 提示语里的动词不该被当成名字
    expect(names.any((n) => n.endsWith('说')), isFalse);
  });

  test('按关键字过滤：别名也能搜到，空关键字返回全部', () {
    final index = buildXrayIndex(const [
      '西蒙说：「一。」\n西蒙先生说道：「二。」',
      '马丁说：「三。」\n老马丁说：「四。」',
      '西蒙说：「五。」\n马丁说：「六。」',
    ]);

    expect(
      filterXrayEntities(index.entities, '').length,
      index.entities.length,
    );

    final byAlias = filterXrayEntities(index.entities, '先生');
    expect(byAlias.map((e) => e.name), ['西蒙']);

    final byBare = filterXrayEntities(index.entities, '马丁');
    expect(byBare.map((e) => e.name), ['马丁']);

    expect(filterXrayEntities(index.entities, '不存在的人'), isEmpty);
  });

  test('正文里没有对话动词的流水句不会凭空造出人名', () {
    final index = buildXrayIndex(const [
      '他走进屋子，看见桌上放着一封信，信纸已经发黄。',
      '窗外的雨下了一整夜，屋檐上的水一直滴着。',
      '时间过得很慢，她一直坐在那里没有动。',
    ]);
    expect(index.entities, isEmpty);
  });

  group('排序 / 同场 / 人物表', () {
    XrayEntity make(String name, List<List<int>> positions) =>
        XrayEntity(name, <XrayMention>[
          for (final p in positions) XrayMention(p[0], p[1], name.length),
        ], ownCount: positions.length);

    final simon = make('西蒙', [
      [0, 10],
      [1, 20],
      [2, 30],
    ]);
    final martin = make('马丁', [
      [1, 5],
      [2, 8],
      [3, 12],
      [4, 40],
    ]);
    final salome = make('萨洛美', [
      [0, 50],
      [1, 60],
      [2, 70],
    ]);
    final heinrich = make('海因里希', [
      [5, 1],
      [5, 90],
      [6, 30],
    ]);
    final all = <XrayEntity>[simon, martin, salome, heinrich];

    test('按出场次数排序：次数多的在前，次数相同按首次出场', () {
      final ranked = rankXrayEntities(<XrayEntity>[
        heinrich,
        salome,
        simon,
        martin,
      ], XraySortOrder.count);
      expect(ranked.map((e) => e.name).toList(), ['马丁', '西蒙', '萨洛美', '海因里希']);
    });

    test('按首次出场排序：第一章就出现的人排前面', () {
      final ranked = rankXrayEntities(<XrayEntity>[
        heinrich,
        martin,
        simon,
      ], XraySortOrder.firstAppear);
      expect(ranked.map((e) => e.name).toList(), ['西蒙', '马丁', '海因里希']);
    });

    test('同场人物：按共同章节数排序，不含自己，零重叠的不算', () {
      final companions = companionsOf(simon, all);
      expect(companions.map((c) => c.entity.name).toList(), ['萨洛美', '马丁']);
      expect(companions.first.sharedChapters, 3);
      expect(companions.map((c) => c.entity.name), isNot(contains('西蒙')));
      expect(companions.map((c) => c.entity.name), isNot(contains('海因里希')));
    });

    test('人物表文本：表头 + 一行一个人，别名进最后一列', () {
      final text = formatXrayTable(<XrayEntity>[simon, martin]);
      final lines = text.split('\n');
      expect(lines.first, '人物\t出现\t章节\t别名');
      expect(lines[1], '西蒙\t3\t3\t');
      expect(lines[2], '马丁\t4\t4\t');
    });
  });
}
