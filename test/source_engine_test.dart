// 书源规则引擎测试（M1）：夹具驱动的离线测试，不依赖网络。
//
// 覆盖：规则拆分（|| / && / ##）、CSS、JSONPath、XPath、正则、
//       URL 模板、书源模型解析与容错。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:sakura_read/src/source/analyze_css.dart';
import 'package:sakura_read/src/source/analyze_json.dart';
import 'package:sakura_read/src/source/analyze_regex.dart';
import 'package:sakura_read/src/source/analyze_rule.dart';
import 'package:sakura_read/src/source/analyze_url.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/rule_analyzer.dart';

const _html = '''
<html><body>
<div class="wrap">
<ul class="book-list">
<li class="item"><a href="/book/1.html" title="书一"><h3 class="name">斗破苍穹</h3></a><span class="author">天蚕土豆</span><p class="intro">简介一</p></li>
<li class="item"><a href="/book/2.html" title="书二"><h3 class="name">凡人修仙传</h3></a><span class="author">忘语</span><p class="intro">简介二</p></li>
</ul>
<div id="content"><p>第一段</p><p>第二段</p></div>
<div class="info"><span>作者：张三</span><span>状态：连载</span></div>
<div class="x">直接<a>链</a>接</div>
</div>
</body></html>
''';

const _json = '''
{"code":0,"data":{"total":2,"list":[
{"name":"书一","author":"甲","url":"/b/1"},
{"name":"书二","author":"乙","url":"/b/2"}]}}
''';

void main() {
  group('规则拆分（rule_analyzer）', () {
    test('拆分 || 备选（忽略空段）', () {
      expect(RuleAnalyzer.splitAlternatives('a || b || '), ['a', 'b']);
    });

    test('拆分 && 串联', () {
      expect(RuleAnalyzer.splitConcat('a && b'), ['a', 'b']);
    });

    test('拆分 ## 替换链（成对）', () {
      final p = RuleAnalyzer.splitReplaces(r'x##a##b##c##d');
      expect(p.base, 'x');
      expect(p.chains.length, 2);
      expect(p.chains[0].pattern, 'a');
      expect(p.chains[0].replacement, 'b');
      expect(p.chains[1].pattern, 'c');
      expect(p.chains[1].replacement, 'd');
    });

    test('末尾落单的 ## 段视为删除匹配', () {
      final p = RuleAnalyzer.splitReplaces(r'x##\d+##');
      expect(p.base, 'x');
      expect(p.chains.length, 1);
      expect(p.chains[0].pattern, r'\d+');
      expect(p.chains[0].replacement, '');
    });

    test('应用替换链（删除）', () {
      expect(
        RuleAnalyzer.applyReplaces('a1b2c', const [ReplaceChain(r'\d', '')]),
        'abc',
      );
    });

    test('应用替换链（\$1 捕获组）', () {
      expect(
        RuleAnalyzer.applyReplaces('abc', const [ReplaceChain('(b)', '[\$1]')]),
        'a[b]c',
      );
    });
  });

  group('CSS 分析器', () {
    final ar = AnalyzeRule(_html);

    test('id 选择器 + text 提取', () {
      expect(ar.getString('id.content@text'), '第一段第二段');
    });

    test('元素列表（bookList）', () {
      final els = ar.getElements('class.book-list@tag.li');
      expect(els.length, 2);
      expect(els.first, isA<dom.Element>());
    });

    test('元素上下文内继续求值（子规则）', () {
      final els = ar.getElements('class.book-list@tag.li');
      expect(ar.getString('tag.h3@text', ctx: els[0]), '斗破苍穹');
      expect(ar.getString('tag.h3@text', ctx: els[1]), '凡人修仙传');
    });

    test('多级 @ 串联 + 属性提取', () {
      expect(ar.getStrings('class.book-list@tag.li@tag.h3@text'), [
        '斗破苍穹',
        '凡人修仙传',
      ]);
      expect(ar.getString('class.item@tag.a@href'), '/book/1.html');
      expect(ar.getStrings('class.item@tag.a@href'), [
        '/book/1.html',
        '/book/2.html',
      ]);
    });

    test('带索引合并写法 class.item.1', () {
      expect(ar.getString('class.item.1@tag.h3@text'), '凡人修仙传');
    });

    test('阶段解析：选择器/索引/提取器', () {
      final stages = parseCssStages('class.item.1@tag.h3@text');
      expect(stages.length, 4);
      expect(stages[0].type, CssStageType.selector);
      expect(stages[0].value, '.item');
      expect(stages[1].type, CssStageType.position);
      expect(stages[1].value, '1');
      expect(stages[2].type, CssStageType.selector);
      expect(stages[2].value, 'h3');
      expect(stages[3].type, CssStageType.extractor);
      expect(stages[3].value, 'text');
    });

    test('ownText / text / textNodes 的差异', () {
      expect(ar.getString('class.x@ownText'), '直接接');
      expect(ar.getString('class.x@text'), '直接链接');
      expect(ar.getStrings('class.x@textNodes'), ['直接', '接']);
    });

    test('html 提取器', () {
      expect(
        ar.getString('class.info@html'),
        '<span>作者：张三</span><span>状态：连载</span>',
      );
    });

    test('属性缺失 → 空结果', () {
      expect(ar.getStrings('class.info@data-nope'), isEmpty);
    });

    test('选择器无匹配 → null / 空', () {
      expect(ar.getString('class.nope@text'), isNull);
      expect(ar.getStrings('class.nope@text'), isEmpty);
    });

    test('|| 兜底：第一个备选为空时用第二个', () {
      expect(ar.getString('class.nope@text||id.content@text'), '第一段第二段');
    });

    test('&& 串联：两段结果用换行拼接', () {
      expect(
        ar.getString('class.info@tag.span.0@text&&class.info@tag.span.1@text'),
        '作者：张三\n状态：连载',
      );
    });
  });

  group('JSONPath 分析器', () {
    final root = jsonDecode(_json);
    final ar = AnalyzeRule(_json);

    test('基本字段', () {
      expect(jsonSelect(root, r'$.data.total'), [2]);
      expect(jsonSelectStrings(root, r'$.data.total'), ['2']);
    });

    test('数组通配 + 字段', () {
      expect(jsonSelectStrings(root, r'$.data.list[*].name'), ['书一', '书二']);
    });

    test('数组下标', () {
      expect(jsonSelectStrings(root, r'$.data.list[0].name'), ['书一']);
    });

    test('带引号字段', () {
      expect(jsonSelectStrings(root, r"$['data']['list'][1]['name']"), ['书二']);
    });

    test('递归后代查找', () {
      expect(jsonSelectStrings(root, r'$..author'), ['甲', '乙']);
    });

    test('不存在的路径 → 空', () {
      expect(jsonSelect(root, r'$.data.zzz'), isEmpty);
    });

    test('非法路径 → 空（不抛异常）', () {
      expect(jsonSelect(root, r'$.data.['), isEmpty);
    });

    test('引擎自动识别 JSON 文档 + \$. 前缀', () {
      expect(ar.getString(r'$.data.list[0].author'), '甲');
      expect(ar.getStrings(r'$.data.list[*].name'), ['书一', '书二']);
    });
  });

  group('XPath 分析器', () {
    final ar = AnalyzeRule(_html);

    test('text() 列表', () {
      expect(ar.getStrings('@xpath://h3/text()'), ['斗破苍穹', '凡人修仙传']);
    });

    test('属性提取', () {
      expect(ar.getString('@xpath://a/@href'), '/book/1.html');
    });

    test('属性断言 + 位置筛选', () {
      expect(ar.getStrings('@xpath://li[@class="item"][1]//h3/text()'), [
        '斗破苍穹',
      ]);
    });

    test('绝对路径 + 单引号断言', () {
      expect(ar.getStrings(r"@xpath:/html/body//div[@id='content']/p/text()"), [
        '第一段',
        '第二段',
      ]);
    });

    test('last() 位置', () {
      expect(ar.getStrings('@xpath://li[last()]//h3/text()'), ['凡人修仙传']);
    });

    test('不合法 HTML（<br>）的宽松解析', () {
      final ar2 = AnalyzeRule('<html><body>a<br>b</body></html>');
      expect(ar2.getElements('@xpath://br').length, 1);
    });
  });

  group('正则分析器', () {
    final ar = AnalyzeRule('价格：12.5 元，库存 3 件');

    test('捕获组优先', () {
      expect(ar.getString(r'@regex:(\d+\.?\d*)'), '12.5');
    });

    test('无捕获组取整个匹配', () {
      expect(ar.getStrings(r'@regex:(\d+)'), ['12', '5', '3']);
    });

    test('直接函数调用', () {
      expect(regexExtract('a1b22c', r'(\d+)'), ['1', '22']);
      expect(regexExtract('a1b2', r'\d'), ['1', '2']);
      expect(regexExtract('abc', '('), isEmpty); // 非法正则容错
    });

    test('替换链作用于结果', () {
      final arHtml = AnalyzeRule(_html);
      expect(arHtml.getString('class.info@tag.span.0@text##作者：##'), '张三');
    });
  });

  group('URL 模板', () {
    test('拆分 ,{...} 选项尾缀', () {
      final t = parseUrlTemplate(
        '/search?q={{key}},{"method":"POST","body":"q={{key}}"}',
      );
      expect(t.url, '/search?q={{key}}');
      expect(t.options['method'], 'POST');
    });

    test('渲染 key/page 并 URL 编码', () {
      expect(
        renderUrlTemplate('/s?q={{searchKey}}&p={{page}}', {
          'key': '剑 来',
          'page': 2,
        }),
        '/s?q=%E5%89%91%20%E6%9D%A5&p=2',
      );
    });

    test('相对路径补全', () {
      expect(
        resolveUrl('book/1.html', 'https://www.a.com/x/y/'),
        'https://www.a.com/x/y/book/1.html',
      );
      expect(resolveUrl('/b/1', 'https://a.com'), 'https://a.com/b/1');
      expect(resolveUrl('https://b.com/z', 'https://a.com'), 'https://b.com/z');
    });

    test('一步到位 buildRequest', () {
      final req = buildRequest('/s?q={{key}}', 'https://a.com', {'key': 'x'});
      expect(req.url, 'https://a.com/s?q=x');
    });

    test('无模板普通地址', () {
      final t = parseUrlTemplate('https://a.com/search');
      expect(t.url, 'https://a.com/search');
      expect(t.options, isEmpty);
    });
  });

  group('书源模型（models）', () {
    test('完整解析（含字符串布尔/数字兼容）', () {
      final src = BookSource.fromJson(
        jsonDecode('''
{"bookSourceUrl":"https://www.example.com","bookSourceName":"示例源",
 "bookSourceGroup":"测试","enabled":"true","weight":"3","customField":123,
 "searchUrl":"/s?q={{key}}",
 "ruleSearch":{"bookList":"class.item","name":"tag.h3@text","author":"class.author@text"},
 "ruleToc":{"chapterList":"#list@tag.li"}}'''),
      );
      expect(src.bookSourceName, '示例源');
      expect(src.bookSourceGroup, '测试');
      expect(src.enabled, true);
      expect(src.weight, 3);
      expect(src.extra['customField'], 123);
      expect(src.searchRule!.bookList, 'class.item');
      expect(src.searchRule!.name, 'tag.h3@text');
      expect(src.tocRule!.chapterList, '#list@tag.li');
    });

    test('未知字段导出时保留', () {
      final src = BookSource.fromJson(
        jsonDecode('{"bookSourceUrl":"u","bookSourceName":"n","x-new":42}'),
      );
      final back = src.toJson();
      expect(back['x-new'], 42);
      expect(back['bookSourceUrl'], 'u');
    });

    test('容错：空串 → null；类型混用', () {
      final src = BookSource.fromJson(
        jsonDecode(
          '{"bookSourceUrl":"u","bookSourceName":"n","concurrentRate":"","bookSourceType":"0"}',
        ),
      );
      expect(src.concurrentRate, isNull);
      expect(src.bookSourceType, 0);
    });

    test('列表导入：坏条目跳过', () {
      final list = BookSource.listFromJson(
        jsonDecode(
          '[{"bookSourceUrl":"a","bookSourceName":"A"},{"bookSourceName":"无地址"}]',
        ),
      );
      expect(list.length, 1);
      expect(list.first.bookSourceName, 'A');
    });
  });
}
