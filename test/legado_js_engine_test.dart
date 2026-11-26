import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/core/theme/sakura_tokens.dart';
import 'package:sakura_read/src/features/book_source/ai_source_studio.dart';
import 'package:sakura_read/src/features/book_source/source_debugger_page.dart';
import 'package:sakura_read/src/source/analyze_rule.dart';
import 'package:sakura_read/src/source/analyze_url.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/js_engine.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_book_service.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  group('LegadoJsEngine 内置编码、哈希、变量与 Cookie API', () {
    setUp(() {
      SourceVariableStore.shared.clear();
      MemoryJsCookieBridge.shared.clear();
    });

    test('java.base64Encode / base64Decode / md5Encode / md5Encode16 / hexDecodeToString', () {
      final engine = LegadoJsEngine.shared;
      // 验证在纯 Dart VM 无原生 DLL 时也能优雅降级不崩溃
      expect(engine.isNativeQuickJsAvailable, isA<bool>());

      final b64 = engine.eval('java.base64Encode("樱读Sakura")');
      expect(b64.ok, isTrue);
      expect(b64.asString, base64Encode(utf8.encode('樱读Sakura')));

      final dec = engine.eval('java.base64Decode("${b64.asString}")');
      expect(dec.ok, isTrue);
      expect(dec.asString, '樱读Sakura');

      final md5 = engine.eval('java.md5Encode("abc")');
      expect(md5.ok, isTrue);
      expect(md5.asString, '900150983cd24fb0d6963f7d28e17f72');

      final md516 = engine.eval('java.md5Encode16("abc")');
      expect(md516.ok, isTrue);
      expect(md516.asString, '3cd24fb0d6963f7d');

      final hex = engine.eval('java.hexDecodeToString("68656c6c6f")');
      expect(hex.ok, isTrue);
      expect(hex.asString, 'hello');
    });

    test('source.setVariable / getVariable 与 cookie.setCookie / getCookie', () {
      final engine = LegadoJsEngine.shared;
      final ctx = JsEvalContext(
        baseUrl: 'https://novel.example',
        sourceKey: 'https://novel.example',
      );

      engine.eval('source.setVariable("vip_token_42")', context: ctx);
      final readVar = engine.eval('source.getVariable()', context: ctx);
      expect(readVar.asString, 'vip_token_42');

      engine.eval(
        'cookie.setCookie("https://novel.example", "sid=xyz999")',
        context: ctx,
      );
      final readCookie = engine.eval(
        'cookie.getCookie("https://novel.example")',
        context: ctx,
      );
      expect(readCookie.asString, 'sid=xyz999');
    });

    test('console.log / java.log 捕获调试日志', () {
      final logs = <String>[];
      final res = LegadoJsEngine.shared.eval(
        'java.log("step1"); console.log("step2"); result.trim()',
        context: JsEvalContext(result: '  hello  ', logs: logs),
      );
      expect(res.ok, isTrue);
      expect(res.asString, 'hello');
      expect(logs, containsAll(['step1', 'step2']));
    });

    test('java.ajax / java.get / java.post 异步网络回放', () async {
      final httpClient = SourceHttpClient(
        client: MockClient((req) async {
          if (req.url.path == '/token') {
            return http.Response('tok_888', 200);
          }
          if (req.url.path == '/echo' && req.method == 'POST') {
            return http.Response(
              'posted:${req.body}:${req.headers['x-auth'] ?? ''}',
              200,
            );
          }
          return http.Response('get:${req.url.path}', 200);
        }),
      );
      addTearDown(httpClient.close);

      final ctx = JsEvalContext(
        baseUrl: 'https://api.example',
        cookieBridge: httpClient,
        httpAsync: httpClient.asJsAsyncHttpCallback(),
      );

      final ajaxRes = await LegadoJsEngine.shared.evalAsync(
        'var t = java.ajax("/token"); "Bearer " + t',
        context: ctx,
      );
      expect(ajaxRes.ok, isTrue);
      expect(ajaxRes.asString, 'Bearer tok_888');

      final getRes = await LegadoJsEngine.shared.evalAsync(
        'java.get("https://api.example/info", {"Accept":"text/plain"}).body()',
        context: ctx,
      );
      expect(getRes.ok, isTrue);
      expect(getRes.asString, 'get:/info');

      final postRes = await LegadoJsEngine.shared.evalAsync(
        'java.post("https://api.example/echo", "k=1", {"x-auth":"yes"}).body()',
        context: ctx,
      );
      expect(postRes.ok, isTrue);
      expect(postRes.asString, 'posted:k=1:yes');
    });
  });

  group('PersistCookieJar 持久化与 SourceHttpClient 集成', () {
    test('PersistCookieJar 跨客户端实例持久化 Cookie', () async {
      final dir = await Directory.systemTemp.createTemp('sakura_cookie_test_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final client1 = SourceHttpClient.persistent(cookieDir: dir.path);
      await client1.saveCookieHeader('https://persist.example', 'uid=sakura42');
      expect(
        client1.getCookie('https://persist.example'),
        contains('uid=sakura42'),
      );
      client1.close();

      // 重建新客户端指向同一目录，应能读回持久化 Cookie
      final client2 = SourceHttpClient.persistent(cookieDir: dir.path);
      final loaded = await client2.loadCookieHeader('https://persist.example');
      expect(loaded, contains('uid=sakura42'));
      client2.close();
    });
  });

  group('AnalyzeRule & AnalyzeUrl 支持 @js: / <js> / {{...}}', () {
    test('searchUrl 支持 @js:、<js>...</js> 和 {{...}} 内联 JS 表达式', () {
      final req1 = buildRequest(
        '@js:"/search?q=" + encodeURIComponent(key) + "&sign=" + java.md5Encode16(key)',
        'https://js.example',
        {'key': 'abc', 'page': 2},
      );
      expect(req1.url, 'https://js.example/search?q=abc&sign=3cd24fb0d6963f7d');

      final req2 = buildRequest(
        '/s?q={{key}}&p={{page * 10}}&h={{java.md5Encode16("abc")}}',
        'https://js.example',
        {'key': 'abc', 'page': 3},
      );
      expect(req2.url, 'https://js.example/s?q=abc&p=30&h=3cd24fb0d6963f7d');

      final req3 = buildRequest(
        '<js>"/v2/find?k=" + key + "&pg=" + page</js>',
        'https://js.example',
        {'key': 'book', 'page': 4},
      );
      expect(req3.url, 'https://js.example/v2/find?k=book&pg=4');
    });

    test('AnalyzeRule 支持 CSS + @js: 管线、java.getString / java.getElements 与内联 {{...}}', () {
      const html = '''
      <html><body>
        <div class="card">
          <h2 class="title">  【正版】诡秘之主  </h2>
          <span class="id">9527</span>
        </div>
        <ul class="items"><li>A</li><li>B</li></ul>
      </body></html>
      ''';
      final ar = AnalyzeRule(html, baseUrl: 'https://book.example');

      expect(
        ar.getString('class.title@text\n@js:result.replace("【正版】", "").trim()'),
        '诡秘之主',
      );
      expect(
        ar.getString('<js>java.getString("class.title@text").trim()</js>'),
        '【正版】诡秘之主',
      );
      expect(
        ar.getString('https://book.example/detail/{{class.id@text}}.html'),
        'https://book.example/detail/9527.html',
      );
      expect(ar.getString('@js:java.getElements(".items li").size()'), '2');
    });

    test('全链路 JS 书源：searchUrl + bookList + chapterList + content', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/search') {
          return http.Response(
            jsonEncode({
              'items': [
                {'title': 'JS测试小说', 'writer': '测试作者', 'bid': '101'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.url.path == '/book/101') {
          return http.Response(
            '<html><body><h1 class="bname">JS测试小说</h1>'
            '<div class="bauthor">作者：测试作者</div>'
            '<div class="bintro">一本用来测试 JS 书源的书。</div>'
            '<ul class="toc"><li><a href="/ch/1">第一章 启程</a></li></ul>'
            '</body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (req.url.path == '/ch/1') {
          final encoded = base64Encode(utf8.encode('这是经过 Base64 编码的正文内容。'));
          return http.Response(
            '<html><body><div id="cipher">$encoded</div></body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      });

      final client = SourceHttpClient(client: mock);
      addTearDown(client.close);

      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://jssrc.example',
        'bookSourceName': 'JS 全链路测试源',
        'searchUrl': '@js:"/api/search?q=" + encodeURIComponent(key)',
        'ruleSearch': {
          'bookList': '<js>JSON.parse(src).items</js>',
          'name': r'$.title',
          'author': r'$.writer',
          'bookUrl': r'/book/{{$.bid}}',
        },
        'ruleBookInfo': {
          'name': 'h1.bname@text',
          'author': '.bauthor@text\n@js:result.replace("作者：", "")',
          'intro': '.bintro@text',
        },
        'ruleToc': {
          'chapterList': '.toc li',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
        'ruleContent': {
          'content': '#cipher@text\n@js:java.base64Decode(result)',
        },
      });

      // 1. 搜索
      final repo = OnlineRepo(
        store: SourceStore(initial: [source]),
        client: client,
      );
      final searchRes = await repo.searchOne(source, '测试');
      expect(searchRes.ok, isTrue, reason: searchRes.error ?? '');
      expect(searchRes.books, hasLength(1));
      expect(searchRes.books.first.name, 'JS测试小说');
      expect(searchRes.books.first.bookUrl, 'https://jssrc.example/book/101');

      // 2. 详情 + 目录
      final bookService = OnlineBookService(client: client);
      final info = await bookService.fetchInfo(
        source,
        searchRes.books.first.bookUrl!,
      );
      expect(info.name, 'JS测试小说');
      expect(info.author, '测试作者');
      expect(info.chapters, hasLength(1));
      expect(info.chapters.first.href, 'https://jssrc.example/ch/1');

      // 3. 正文（Base64 JS 解密）
      final text = await bookService.fetchChapterText(
        source,
        info.chapters.first.href!,
      );
      expect(text, '这是经过 Base64 编码的正文内容。');

      // 4. 四阶段实时调试器验证
      final runner = SourceDebugRunner(client: client);
      final trace = await runner.run(source, '测试');
      expect(trace.allPassed, isTrue, reason: trace.errorSummary);
      expect(trace.passedCount, 4);
      expect(trace.sampleContent, '这是经过 Base64 编码的正文内容。');
    });
  });

  group('AiSourceStudio 与 SourceDebuggerPage', () {
    test('HTML 裁剪 + Prompt 生成 + AI JSON 解析 + 自动四阶段校验', () async {
      final mock = MockClient((req) async {
        const htmlHeaders = {'content-type': 'text/html; charset=utf-8'};
        if (req.url.path == '/' || req.url.path.isEmpty) {
          return http.Response(
            '<html><head><script>alert(1)</script><style>body{}</style></head>'
            '<body><div class="search-box">小说站</div></body></html>',
            200,
            headers: htmlHeaders,
          );
        }
        if (req.url.path == '/s') {
          return http.Response(
            '<html><body><ul class="list"><li><a href="/b/1">西游记</a></li></ul></body></html>',
            200,
            headers: htmlHeaders,
          );
        }
        if (req.url.path == '/b/1') {
          return http.Response(
            '<html><body><h1>西游记</h1><p class="au">吴承恩</p>'
            '<ul class="chs"><li><a href="/c/1">第一回</a></li></ul></body></html>',
            200,
            headers: htmlHeaders,
          );
        }
        if (req.url.path == '/c/1') {
          return http.Response(
            '<html><body><article id="body">灵根育孕源流出，心性修持大道生。</article></body></html>',
            200,
            headers: htmlHeaders,
          );
        }
        return http.Response('404', 404);
      });

      final client = SourceHttpClient(client: mock);
      addTearDown(client.close);
      final studio = AiSourceStudio(httpClient: client);

      final result = await studio.generateAndValidate(
        siteUrl: 'https://demo-novel.example',
        keyword: '西游记',
        llmOverride: (prompt) async {
          expect(prompt, contains('bookSourceUrl'));
          expect(prompt, isNot(contains('<script>')));
          return '''
这是为您生成的书源：
```json
{
  "bookSourceUrl": "https://demo-novel.example",
  "bookSourceName": "AI 示例小说站",
  "searchUrl": "/s?q={{key}}",
  "ruleSearch": {
    "bookList": "ul.list li",
    "name": "a@text",
    "bookUrl": "a@href"
  },
  "ruleBookInfo": {
    "name": "h1@text",
    "author": "p.au@text"
  },
  "ruleToc": {
    "chapterList": "ul.chs li",
    "chapterName": "a@text",
    "chapterUrl": "a@href"
  },
  "ruleContent": {
    "content": "#body@text"
  }
}
```
''';
        },
      );

      expect(result.source.bookSourceName, 'AI 示例小说站');
      expect(result.validated, isTrue);
      expect(result.validationTrace?.passedCount, 4);
      expect(result.validationTrace?.sampleContent, contains('灵根育孕源流出'));
    });

    testWidgets('SourceDebuggerPage 正常渲染实时调试与 AI 写源两个标签页', (tester) async {
      final store = SourceStore(
        initial: [
          BookSource(
            bookSourceUrl: 'https://s.example',
            bookSourceName: '测试书源',
            searchUrl: '/s?q={{key}}',
          ),
        ],
      );
      final mockHttp = SourceHttpClient(
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      addTearDown(mockHttp.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [SakuraColors.light(SakuraAccents.sakura)],
          ),
          home: SourceDebuggerPage(store: store, httpClient: mockHttp),
        ),
      );
      expect(find.text('书源调试与 AI 工坊'), findsOneWidget);
      expect(find.text('实时调试'), findsOneWidget);
      expect(find.text('AI 写源工坊'), findsOneWidget);
      expect(find.text('开始四阶段调试'), findsOneWidget);

      await tester.tap(find.text('AI 写源工坊'));
      await tester.pumpAndSettle();
      expect(find.text('抓取页面并生成书源'), findsOneWidget);
    });
  });
}
