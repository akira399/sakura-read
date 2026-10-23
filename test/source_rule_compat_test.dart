// 书源规则兼容性回归测试（真实站点的写法，逐条钉死）。
//
// 背景：用户导入的「阅读 3.0 常用书源」大量使用下面这些写法，而早期引擎
// 只认最基础的 CSS，导致整源失效（表现为搜索 0 本 / 目录为空 / 正文空白）：
//   - `text.下一页@href`            按文本定位翻页链接
//   - `a#next:contains(下一页)@href` jQuery 伪类
//   - `li:has(a)`                   jQuery 伪类
//   - `#content@p!0@html`           排除第 0 段（去掉章节标题/广告）
//   - `-1`                          倒数第一个
//   - `##{{chapter.title}}`         替换串里的变量
//   - 301 换域名 + POST 搜索        必须保留方法与请求体
//   - `nextContentUrl` / `nextTocUrl` 分页正文与分页目录
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/source/analyze_rule.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_book_service.dart';

BookSource _source(Map<String, dynamic> json) => BookSource.fromJson({
  'bookSourceName': '测试源',
  'bookSourceUrl': 'https://example.com',
  'bookSourceGroup': '测试',
  'enabled': true,
  ...json,
});

void main() {
  group('文本选择器', () {
    const html = '''
<html><body>
  <div id="pager"><a href="/p2.html">下一页</a></div>
  <ol><li><a href="/c1.html">第一章 起点</a></li></ul></ol>
</body></html>''';

    test('text.下一页@href 定位翻页链接', () {
      final r = AnalyzeRule(html);
      expect(r.getString('text.下一页@href'), '/p2.html');
      // 换成「下一章」也必须能定位（不能写死关键字）
      expect(r.getString('text.第一章@href'), '/c1.html');
    });

    test('text= 与 text. 等价', () {
      final r = AnalyzeRule(html);
      expect(r.getString('text=下一页@href'), '/p2.html');
    });
  });

  group('jQuery 伪类', () {
    const html = '''
<html><body>
  <div class="prenext"><span><a href="/n.html">下一页</a></span></div>
  <ul class="list"><li><a href="/b1.html">书一</a></li><li>纯文本</li></ul>
  <a id="next" href="/n2.html">下一页</a>
</body></html>''';

    test('a:contains(下一页)@href', () {
      final r = AnalyzeRule(html);
      expect(r.getString('a#next:contains(下一页)@href'), '/n2.html');
    });

    test('.prenext span a:contains(下一页)@href', () {
      final r = AnalyzeRule(html);
      expect(r.getString('.prenext span a:contains(下一页)@href'), '/n.html');
    });

    test('li:has(a) 只留含链接的 li', () {
      final r = AnalyzeRule(html);
      final items = r.getElements('li:has(a)');
      expect(items.length, 1);
      expect(r.getString('a@href', ctx: items.first), '/b1.html');
    });
  });

  group('位置索引', () {
    const html = '''
<html><body>
  <div id="content">
    <p>第十二章 标题行</p>
    <p>正文第一段。</p>
    <p>正文第二段。</p>
  </div>
</body></html>''';

    test('p!0 排除第 0 个', () {
      final r = AnalyzeRule(html);
      final got = r.getStrings('#content@p!0@html');
      expect(got.length, 2);
      expect(got.first.contains('正文第一段'), isTrue);
    });

    test('-1 取倒数第一个', () {
      final r = AnalyzeRule(html);
      expect(r.getString('#content@p@-1@text'), '正文第二段。');
    });
  });

  group('替换链变量', () {
    const html = '<div id="content"><p>第十二章 标题行</p><p>正文。</p></div>';

    test('##{{chapter.title}} 用上下文变量替换', () {
      final r = AnalyzeRule(html, vars: const {'chapter.title': '第十二章 标题行'});
      expect(r.getString('#content@text##{{chapter.title}}'), '正文。');
    });

    test('未提供的变量按空串处理（不留 {{}} 字面量）', () {
      final r = AnalyzeRule(html);
      expect(r.getString('#content@text##{{nope.x}}'), isNotEmpty);
      expect(r.getString('#content@text##{{nope.x}}')!.contains('{{'), isFalse);
    });
  });

  group('正文清洗', () {
    test('单行章节带站点水印时不能整章丢弃', () {
      const raw =
          '　　正文第一段内容，很长很长。<br><br>'
          '　　（请记住本书首发域名：www.example.com。'
          '某某手机版阅读网址：wap.example.com）';
      final text = OnlineBookService.cleanChapterText(raw);
      expect(text.contains('正文第一段内容'), isTrue);
      expect(text.contains('首发域名'), isFalse);
      expect(text.contains('<br>'), isFalse);
    });

    test('@html 里的标签与 &nbsp; 被还原成段落', () {
      const raw = '<p>第一段。</p><p>第二段。</p>';
      final text = OnlineBookService.cleanChapterText(raw);
      expect(text.split('\n'), ['第一段。', '第二段。']);
    });
  });

  group('HTTP 重定向', () {
    test('301 换域名时保留 POST 方法与请求体', () async {
      final seen = <String>[];
      final client = MockClient((req) async {
        seen.add('${req.method} ${req.url}');
        if (req.url.host == 'old.example.com') {
          return _resp('', 301, {
            'location': 'https://new.example.com/search.php',
          });
        }
        expect(req.method, 'POST');
        expect(req.body, 'searchkey=诡秘之主');
        return _resp('<div class="bookbox">ok</div>', 200);
      });
      final http = SourceHttpClient(client: client);
      final resp = await http.post(
        'https://old.example.com/search.php',
        body: 'searchkey=诡秘之主',
      );
      expect(resp.statusCode, 200);
      expect(resp.body.contains('bookbox'), isTrue);
      expect(seen.length, 2);
      expect(seen[1], contains('new.example.com'));
    });
  });

  group('分页抓取', () {
    test('nextContentUrl 把多页正文拼成一章', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/c1.html') {
          return _resp(
            '<html><body><div id="c">第一页正文。</div>'
            '<a href="/c1_2.html">下一页</a></body></html>',
            200,
          );
        }
        if (req.url.path == '/c1_2.html') {
          return _resp(
            '<html><body><div id="c">第二页正文。</div></body></html>',
            200,
          );
        }
        return _resp('', 404);
      });
      final service = OnlineBookService(
        client: SourceHttpClient(client: client),
      );
      final source = _source({
        'ruleContent': {
          'content': '#c@html',
          'nextContentUrl': 'text.下一页@href',
        },
      });
      final text = await service.fetchChapterText(
        source,
        'https://example.com/c1.html',
      );
      expect(text.contains('第一页正文'), isTrue);
      expect(text.contains('第二页正文'), isTrue);
    });

    test('nextTocUrl 把分页目录拼成完整目录', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/book/1.html') {
          return _resp(
            '<html><body><h1 class="name">测试书</h1>'
            '<ul id="list"><li><a href="/c/1.html">第1章</a></li>'
            '<li><a href="/c/2.html">第2章</a></li></ul>'
            '<a href="/book/1_2.html">下一页</a></body></html>',
            200,
          );
        }
        if (req.url.path == '/book/1_2.html') {
          return _resp(
            '<html><body><ul id="list">'
            '<li><a href="/c/3.html">第3章</a></li>'
            '<li><a href="/c/4.html">第4章</a></li></ul></body></html>',
            200,
          );
        }
        return _resp('', 404);
      });
      final service = OnlineBookService(
        client: SourceHttpClient(client: client),
      );
      final source = _source({
        'ruleBookInfo': {'name': 'h1.name@text'},
        'ruleToc': {
          'chapterList': '#list li a',
          'chapterName': 'text',
          'chapterUrl': 'href',
          'nextTocUrl': 'text.下一页@href',
        },
      });
      final info = await service.fetchInfo(
        source,
        'https://example.com/book/1.html',
      );
      expect(info.chapters.length, 4);
      expect(info.chapters.last.title, '第4章');
    });
  });
}

/// 最小响应构造（http 包的 MockClient 需要 http.Response）。
http.Response _resp(String body, int status, [Map<String, String>? headers]) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: headers ?? const {'content-type': 'text/html; charset=utf-8'},
    );
