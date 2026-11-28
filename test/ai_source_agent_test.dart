import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/core/theme/sakura_tokens.dart';
import 'package:sakura_read/src/data/ai_service.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/features/book_source/ai_source_studio.dart';
import 'package:sakura_read/src/features/book_source/source_debugger_page.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/book_grid_card.dart';
import 'package:sakura_read/src/features/bookshelf/widgets/shelf_header.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/ui/source/discover_page.dart';
import 'package:sakura_read/src/ui/source/source_manager_page.dart';

http.Response _utf8Json(Object data, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

http.Response _utf8Html(String html, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(html),
    status,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}

void main() {
  group('AiSourceStudio 工具与安全校验', () {
    test('distillHtmlForSourceAgent 剥离脚本并提取表单与链接', () {
      const html = '''
<html>
  <head><title>测试小说站</title><style>.x{color:red}</style></head>
  <body>
    <script>alert("xss")</script>
    <form action="/search.php" method="GET">
      <input type="text" name="keyword" placeholder="输入书名">
    </form>
    <div class="list">
      <a href="/book/101.html" onclick="hack()">我的冰山美女老婆</a>
    </div>
  </body>
</html>
''';
      final distilled = AiSourceStudio.distillHtmlForSourceAgent(
        html,
        url: 'https://novel.example/',
      );
      expect(distilled, contains('Title: 测试小说站'));
      expect(distilled, contains('[Forms]'));
      expect(distilled, contains('action="/search.php"'));
      expect(distilled, contains('name=keyword'));
      expect(distilled, contains('[Sample Links]'));
      expect(distilled, contains('/book/101.html'));
      expect(distilled, isNot(contains('alert("xss")')));
      expect(distilled, isNot(contains('onclick')));

      final focused = AiSourceStudio.distillHtmlForSourceAgent(
        html,
        selector: 'div.list',
      );
      expect(focused, contains('Selector "div.list" matched: 1'));
      expect(focused, contains('我的冰山美女老婆'));
    });

    test('validatePublicSiteUrl 拦截内网/本地地址并自动补全协议', () {
      expect(
        AiSourceStudio.normalizeSiteUrl('www.demo.org'),
        'https://www.demo.org',
      );
      expect(AiSourceStudio.validatePublicSiteUrl('www.demo.org'), isNull);
      expect(
        AiSourceStudio.validatePublicSiteUrl('http://localhost:8080'),
        isNotNull,
      );
      expect(
        AiSourceStudio.validatePublicSiteUrl('http://127.0.0.1/'),
        isNotNull,
      );
      expect(
        AiSourceStudio.validatePublicSiteUrl('http://192.168.1.10'),
        isNotNull,
      );
      expect(
        AiSourceStudio.validatePublicSiteUrl('http://10.0.0.5'),
        isNotNull,
      );
      expect(
        AiSourceStudio.validatePublicSiteUrl('ftp://demo.org/a'),
        isNotNull,
      );
    });

    test('detectAccessBlock 识别 Cloudflare / 人机验证 / HTTP 401/403', () {
      expect(
        AiSourceStudio.detectAccessBlock(
          statusCode: 403,
          body: '<html><title>Just a moment...</title><div class="cf-browser-verification"></div></html>',
          finalUrl: 'https://blocked.example',
        ),
        contains('Cloudflare'),
      );
      expect(
        AiSourceStudio.detectAccessBlock(
          statusCode: 200,
          body: '<html><body>请完成人机验证 <div class="g-recaptcha"></div></body></html>',
          finalUrl: 'https://captcha.example',
        ),
        contains('验证码'),
      );
      expect(
        AiSourceStudio.detectAccessBlock(
          statusCode: 200,
          body: '<html><body>正常小说目录页</body></html>',
          finalUrl: 'https://ok.example',
        ),
        isNull,
      );
      expect(
        AiSourceStudio.detectAccessBlock(
          statusCode: 200,
          body: '<html><title>飘天文学</title><script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script><body>小说列表</body></html>',
          finalUrl: 'https://piaotia.example',
        ),
        isNull,
      );
    });

    test('distillHtmlForSourceAgent 提取同域脚本与内联搜索线索并直出 .js 文件内容', () {
      const biqugeHtml = '''
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=gbk" />
    <title>笔趣阁测试</title>
    <script src="https://hm.baidu.com/hm.js"></script>
    <script src="/tpl/pc/js/common.js?v=1"></script>
  </head>
  <body>
    <script>var searchUrl = "/search.html?searchkey=";</script>
    <div id="list"><a href="/book/1/">我的徒弟</a></div>
  </body>
</html>
''';
      final distilled = AiSourceStudio.distillHtmlForSourceAgent(
        biqugeHtml,
        url: 'https://biquge.example/',
      );
      expect(distilled, contains('Charset: gbk'));
      expect(distilled, contains('[Same-Site Scripts]'));
      expect(distilled, contains('/tpl/pc/js/common.js?v=1'));
      expect(distilled, isNot(contains('hm.baidu.com')));
      expect(distilled, contains('[Inline Script Search Hints]'));
      expect(distilled, contains('/search.html?searchkey='));

      const jsRaw =
          'document.write(\'<form action="/s" method="get"><input name="q"></form>\');';
      expect(
        AiSourceStudio.distillHtmlForSourceAgent(
          jsRaw,
          url: 'https://biquge.example/js/compc.js?v=1.25',
        ),
        equals(jsRaw),
      );
    });

    test('仅支持在线大模型：本地模型且未填在线接口时直接报错，填好在线接口后放行', () async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      prefs.aiUseLocalModel = true;
      final client = SourceHttpClient(
        client: MockClient((_) async => _utf8Html('<html>ok</html>')),
      );
      addTearDown(client.close);
      final studio = AiSourceStudio(httpClient: client);

      await expectLater(
        studio.generateAndValidate(
          siteUrl: 'https://demo.example',
          prefs: prefs,
        ),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('AiSourceStudio 多轮工具取证与自动修复闭环', () {
    test('通过 tool_calls 抓页取证 → 首轮调试失败 → AI 修复选择器 → 二轮 4/4 通过', () async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      prefs.aiUseLocalModel = true; // 聊天用本地模型时，只要配了在线接口照样可写源
      prefs.setAiConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test-dummy',
        model: 'deepseek-chat',
        includeReading: false,
      );

      final siteClient = SourceHttpClient(
        client: MockClient((req) async {
          if (req.url.path == '/' || req.url.path.isEmpty) {
            return _utf8Html('''
<html><head><title>樱花测试站</title></head><body>
  <form action="/search" method="GET"><input name="q" placeholder="搜索"></form>
  <a href="/book/1">我的剑仙之路</a>
</body></html>''');
          }
          if (req.url.path == '/search') {
            return _utf8Html('''
<html><body>
  <ul class="search-list">
    <li><a href="/book/1">我的剑仙之路</a><span class="au">青莲</span></li>
  </ul>
</body></html>''');
          }
          if (req.url.path == '/book/1') {
            return _utf8Html('''
<html><body>
  <h1 class="book-title">我的剑仙之路</h1>
  <div class="author">青莲</div>
  <div class="toc"><a href="/ch/1">第一章 初入山门</a></div>
</body></html>''');
          }
          if (req.url.path == '/ch/1') {
            return _utf8Html('''
<html><body>
  <article id="chapter-content">
    灵气复苏百年之后，少年背负长剑踏入青云山门，心中唯有一念长存不灭。
  </article>
</body></html>''');
          }
          return _utf8Html('not found', status: 404);
        }),
      );
      addTearDown(siteClient.close);

      var aiTurn = 0;
      final aiHttp = MockClient((req) async {
        aiTurn++;
        final reqJson = jsonDecode(
          utf8.decode(Uint8List.fromList(req.bodyBytes)),
        );
        expect(reqJson['tools'], isNotEmpty);

        if (aiTurn == 1) {
          return _utf8Json({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'fetch_source_html',
                        'arguments': jsonEncode({
                          'url': 'https://novel.example/search?q=%E6%88%91%E7%9A%84',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          });
        }
        if (aiTurn == 2) {
          return _utf8Json({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_2',
                      'type': 'function',
                      'function': {
                        'name': 'fetch_source_html',
                        'arguments': jsonEncode({
                          'url': 'https://novel.example/book/1',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          });
        }
        if (aiTurn == 3) {
          // 故意给一个错误的正文选择器 #wrong-id，验证失败后 AI 自动回修
          final brokenSource = jsonEncode({
            'bookSourceUrl': 'https://novel.example',
            'bookSourceName': '樱花测试站',
            'searchUrl': '/search?q={{key}}',
            'ruleSearch': {
              'bookList': 'ul.search-list li',
              'name': 'a@text',
              'author': 'span.au@text',
              'bookUrl': 'a@href',
            },
            'ruleBookInfo': {
              'name': 'h1.book-title@text',
              'author': 'div.author@text',
            },
            'ruleToc': {
              'chapterList': 'div.toc a',
              'chapterName': 'text',
              'chapterUrl': 'href',
            },
            'ruleContent': {'content': '#wrong-id@text'},
          });
          return _utf8Json({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'id': 'call_3',
                      'type': 'function',
                      'function': {
                        'name': 'debug_book_source',
                        'arguments': jsonEncode({'sourceJson': brokenSource}),
                      },
                    },
                  ],
                },
              },
            ],
          });
        }

        // Turn 4: 看到 failingStageHtml 后修复正文选择器为 #chapter-content@text
        final messages = reqJson['messages'] as List;
        final lastToolMsg =
            jsonDecode(messages.last['content'] as String) as Map;
        expect(lastToolMsg['passedCount'], 3);
        expect(lastToolMsg['failingStageHtml'], contains('chapter-content'));

        final fixedSource = jsonEncode({
          'bookSourceUrl': 'https://novel.example',
          'bookSourceName': '樱花测试站',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': {
            'bookList': 'ul.search-list li',
            'name': 'a@text',
            'author': 'span.au@text',
            'bookUrl': 'a@href',
          },
          'ruleBookInfo': {
            'name': 'h1.book-title@text',
            'author': 'div.author@text',
          },
          'ruleToc': {
            'chapterList': 'div.toc a',
            'chapterName': 'text',
            'chapterUrl': 'href',
          },
          'ruleContent': {'content': '#chapter-content@text'},
        });
        return _utf8Json({
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'id': 'call_4',
                    'type': 'function',
                    'function': {
                      'name': 'debug_book_source',
                      'arguments': jsonEncode({'sourceJson': fixedSource}),
                    },
                  },
                ],
              },
            },
          ],
        });
      });

      final aiService = AiService(client: aiHttp);
      addTearDown(aiService.dispose);
      final studio = AiSourceStudio(
        httpClient: siteClient,
        aiService: aiService,
      );

      final result = await studio.generateAndValidate(
        siteUrl: 'novel.example',
        prefs: prefs,
      );

      expect(result.validated, isTrue);
      expect(result.rounds, 2);
      expect(result.source.bookSourceName, '樱花测试站');
      expect(result.validationTrace?.sampleBook?.name, '我的剑仙之路');
      expect(result.validationTrace?.sampleChapters.first.title, '第一章 初入山门');
      expect(result.validationTrace?.sampleContent, contains('灵气复苏百年之后'));
      expect(result.failureReason, isNull);
    });

    test('站点返回 Cloudflare 拦截时立即报错中止', () async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      prefs.setAiConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test-dummy',
        model: 'deepseek-chat',
        includeReading: false,
      );
      final blockedClient = SourceHttpClient(
        client: MockClient(
          (_) async => _utf8Html(
            '<html><title>Just a moment...</title><div class="cf-browser-verification"></div></html>',
            status: 403,
          ),
        ),
      );
      addTearDown(blockedClient.close);
      final studio = AiSourceStudio(httpClient: blockedClient);

      await expectLater(
        studio.generateAndValidate(siteUrl: 'https://cf.example', prefs: prefs),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Cloudflare'),
          ),
        ),
      );
    });
  });

  group('UI 默认关键词「我的」、显眼入口与一键自动导入', () {
    testWidgets('SourceDebuggerPage 默认关键词为「我的」，一键验证通过后自动导入，失败时不导入', (
      tester,
    ) async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      prefs.setAiConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        model: 'deepseek-chat',
        includeReading: false,
      );
      final store = SourceStore();
      final mockHttp = SourceHttpClient(
        client: MockClient((req) async {
          if (req.url.path == '/' || req.url.path.isEmpty) {
            return _utf8Html(
              '<html><body><a href="/s?q=我的">我的</a></body></html>',
            );
          }
          if (req.url.path == '/s') {
            return _utf8Html(
              '<html><body><ul class="l"><li><a href="/b/1">我的世界</a></li></ul></body></html>',
            );
          }
          if (req.url.path == '/b/1') {
            return _utf8Html(
              '<html><body><h1>我的世界</h1><ul class="c"><li><a href="/c/1">第一章</a></li></ul></body></html>',
            );
          }
          if (req.url.path == '/c/1') {
            return _utf8Html(
              '<html><body><div id="txt">这是一段超过二十个字符的真实小说第一章测试正文内容，用于验证自动入库。</div></body></html>',
            );
          }
          return _utf8Html('404', status: 404);
        }),
      );
      addTearDown(mockHttp.close);

      final aiClient = MockClient((req) async {
        final src = jsonEncode({
          'bookSourceUrl': 'https://ok.example',
          'bookSourceName': '一键自动源',
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': {
            'bookList': 'ul.l li',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
          'ruleBookInfo': {'name': 'h1@text'},
          'ruleToc': {
            'chapterList': 'ul.c li',
            'chapterName': 'a@text',
            'chapterUrl': 'a@href',
          },
          'ruleContent': {'content': '#txt@text'},
        });
        return _utf8Json({
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'id': 'c1',
                    'type': 'function',
                    'function': {
                      'name': 'debug_book_source',
                      'arguments': jsonEncode({'sourceJson': src}),
                    },
                  },
                ],
              },
            },
          ],
        });
      });
      final aiService = AiService(client: aiClient);
      addTearDown(aiService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [SakuraColors.light(SakuraAccents.sakura)],
          ),
          home: SourceDebuggerPage(
            store: store,
            prefs: prefs,
            initialTab: 1,
            httpClient: mockHttp,
            studio: AiSourceStudio(httpClient: mockHttp, aiService: aiService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('在线模型已就绪：deepseek-chat'), findsOneWidget);
      expect(find.text('高级选项（测试词「我的」· 通过即自动导入）'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '目标小说网站链接'),
        'https://ok.example',
      );
      await tester.tap(find.text('AI 一键写源并导入'));
      await tester.pumpAndSettle();

      expect(store.sources.length, 1);
      expect(store.sources.first.bookSourceName, '一键自动源');
      await tester.drag(find.byType(ListView).last, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(find.textContaining('已自动导入书源库'), findsOneWidget);
    });

    testWidgets('SourceDebuggerPage 验证未通过时不自动导入，并展示失败原因与继续修复按钮', (
      tester,
    ) async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      prefs.setAiConfig(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        model: 'deepseek-chat',
        includeReading: false,
      );
      final store = SourceStore();
      final mockHttp = SourceHttpClient(
        client: MockClient((req) async {
          if (req.url.path == '/' || req.url.path.isEmpty) {
            return _utf8Html(
              '<html><body><form action="/s"></form></body></html>',
            );
          }
          return _utf8Html('<html><body>empty</body></html>');
        }),
      );
      addTearDown(mockHttp.close);

      final aiClient = MockClient((req) async {
        final src = jsonEncode({
          'bookSourceUrl': 'https://bad.example',
          'bookSourceName': '失败测试源',
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': {
            'bookList': 'ul.none li',
            'name': 'a@text',
            'bookUrl': 'a@href',
          },
          'ruleBookInfo': {'name': 'h1@text'},
          'ruleToc': {
            'chapterList': 'ul.c li',
            'chapterName': 'a@text',
            'chapterUrl': 'a@href',
          },
          'ruleContent': {'content': '#txt@text'},
        });
        return _utf8Json({
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'id': 'c1',
                    'type': 'function',
                    'function': {
                      'name': 'debug_book_source',
                      'arguments': jsonEncode({'sourceJson': src}),
                    },
                  },
                ],
              },
            },
          ],
        });
      });
      final aiService = AiService(client: aiClient);
      addTearDown(aiService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [SakuraColors.light(SakuraAccents.sakura)],
          ),
          home: SourceDebuggerPage(
            store: store,
            prefs: prefs,
            initialTab: 1,
            httpClient: mockHttp,
            studio: AiSourceStudio(httpClient: mockHttp, aiService: aiService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '目标小说网站链接'),
        'https://bad.example',
      );
      await tester.tap(find.text('AI 一键写源并导入'));
      await tester.pumpAndSettle();

      expect(store.sources, isEmpty);
      expect(find.text('AI 继续修复'), findsOneWidget);
      expect(find.textContaining('未自动导入书源'), findsWidgets);
    });

    testWidgets('DiscoverPage 与 SourceManagerPage 在显眼位置展示「AI 写源」入口', (
      tester,
    ) async {
      final prefs = AppPrefs(
        dirsOverride: const AppDirs(files: '.', cache: '.'),
      );
      final store = SourceStore(
        initial: [
          BookSource(
            bookSourceUrl: 'https://demo.example',
            bookSourceName: '示例书源',
            searchUrl: '/s?q={{key}}',
          ),
        ],
      );
      final bookStore = BookStore();

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverPage(
            bookStore: bookStore,
            prefs: prefs,
            sourceStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI 一键写源'), findsOneWidget);
      expect(find.text('AI 写源'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: SourceManagerPage(store: store, prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI 一键写源'), findsOneWidget);
      expect(find.text('立即写源'), findsOneWidget);
    });

    testWidgets('轻漫风格（animePop）窄屏顶栏无重叠且封面无异常大黑边', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final book = Book(
        id: 'pop-1',
        title: '十国千娇',
        author: '西风紧',
        format: BookFormat.epub,
        path: '/tmp/pop.epub',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: [SakuraColors.light(SakuraAccents.sakura)],
          ),
          home: Scaffold(
            body: Column(
              children: [
                ShelfHeader(
                  greeting: '晚上好',
                  bookCount: 18,
                  visualStyle: VisualStylePreset.animePop,
                  activeBook: book,
                  onAiTap: () {},
                  onSearchTap: () {},
                  onArrangeTap: () {},
                  onManageTap: () {},
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: 0.62,
                      children: [
                        BookGridCard(
                          book: book,
                          visualStyle: VisualStylePreset.animePop,
                          onOpen: () {},
                          onMenu: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('桜読・蔵書'), findsOneWidget);
      expect(find.text('18 卷'), findsOneWidget);
    });
  });
}
