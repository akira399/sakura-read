// M2 网络与聚合测试：编码解码 / 请求层 / 限流 / 书源仓库 / 多源搜索（全离线）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

// ---------- 模拟站点数据 ----------

const _siteAHtml = '''
<html><body><ul class="book-list">
<li><a href="/book/1"><h3>斗破苍穹</h3></a><span class="author">天蚕土豆</span></li>
<li><a href="/book/2"><h3>凡人修仙传</h3></a><span class="author">忘语</span></li>
</ul></body></html>
''';

const _siteBJson = '''
{"code":0,"data":{"list":[
{"name":"诡秘之主","author":"爱潜水的乌贼","url":"/bk/9"},
{"name":"宿命之环","author":"爱潜水的乌贼","url":"/bk/10"}]}}
''';

BookSource _sourceA() => BookSource.fromJson(
  jsonDecode('''
{"bookSourceUrl":"https://site-a.com","bookSourceName":"站点A","searchUrl":"/search?q={{key}}",
 "ruleSearch":{"bookList":"class.book-list@tag.li","name":"tag.h3@text",
 "author":"class.author@text","bookUrl":"tag.a@href"}}'''),
);

BookSource _sourceB() => BookSource.fromJson(
  jsonDecode(
    '''
{"bookSourceUrl":"https://site-b.com","bookSourceName":"站点B","searchUrl":"/s?q={{key}}",
 "ruleSearch":{"bookList":"\$.data.list[*]","name":"\$.name","author":"\$.author","bookUrl":"\$.url"}}''',
  ),
);

void main() {
  group('编码解码（decodeBody）', () {
    test('UTF-8 直通', () {
      expect(decodeBody(Uint8List.fromList(utf8.encode('你好世界')), null), '你好世界');
    });

    test('GBK 通过 Content-Type 解码', () {
      final bytes = Uint8List.fromList(gbk.encode('中文测试'));
      expect(
        decodeBody(bytes, {'content-type': 'text/html; charset=gbk'}),
        '中文测试',
      );
    });

    test('GBK 通过 meta 探测', () {
      final html =
          '<html><head><meta charset="gbk"></head><body>中文测试</body></html>';
      final bytes = Uint8List.fromList(gbk.encode(html));
      expect(decodeBody(bytes, null), contains('中文测试'));
    });

    test('无任何提示时的兜底链（GBK 字节）', () {
      final bytes = Uint8List.fromList(gbk.encode('中文测试内容'));
      expect(decodeBody(bytes, null), '中文测试内容');
    });
  });

  group('请求层（SourceHttpClient）', () {
    test('GET 正常返回 + 自定义请求头', () async {
      String? ua;
      String? token;
      final client = SourceHttpClient(
        client: MockClient((req) async {
          ua = req.headers['user-agent'];
          token = req.headers['x-token'];
          return http.Response('hello', 200);
        }),
      );
      final resp = await client.get(
        'https://x.com/a',
        headers: {'x-token': 't1'},
      );
      expect(resp.ok, true);
      expect(resp.body, 'hello');
      expect(ua, contains('Mozilla'));
      expect(token, 't1');
    });

    test('POST body 透传', () async {
      String? seenBody;
      String? seenMethod;
      final client = SourceHttpClient(
        client: MockClient((req) async {
          seenBody = req.body;
          seenMethod = req.method;
          return http.Response('ok', 200);
        }),
      );
      await client.post('https://x.com/p', body: 'q=1');
      expect(seenMethod, 'POST');
      expect(seenBody, 'q=1');
    });

    test('超时映射为 SourceHttpException', () async {
      final client = SourceHttpClient(
        client: MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response('late', 200);
        }),
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        client.get('https://x.com/slow', retries: 0),
        throwsA(isA<SourceHttpException>()),
      );
    });

    test('Cookie 收集与回传', () async {
      final seen = <String?>[];
      final client = SourceHttpClient(
        client: MockClient((req) async {
          seen.add(req.headers['cookie']);
          if (seen.length == 1) {
            return http.Response(
              'ok',
              200,
              headers: {'set-cookie': 'sid=abc123; Path=/'},
            );
          }
          return http.Response('ok', 200);
        }),
      );
      await client.get('https://x.com/a');
      await client.get('https://x.com/b');
      expect(seen[0], isNull);
      expect(seen[1], contains('sid=abc123'));
    });

    test('RateGate 限流（1/1 每秒一次）', () async {
      final gate = RateGate('1/1');
      final sw = Stopwatch()..start();
      await gate.waitSlot();
      await gate.waitSlot();
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(700));
    });
  });

  group('书源仓库（SourceStore）', () {
    test('导入 / 持久化 / 启用 / 更新（保留启用状态）', () async {
      final dir = Directory.systemTemp.createTempSync('sakura_src');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dirs = AppDirs(files: dir.path, cache: dir.path);

      final store = SourceStore(dirsOverride: dirs);
      await store.load();
      expect(store.isEmpty, true);

      final report = store.importFromText(
        jsonEncode([
          {'bookSourceUrl': 'https://a.com', 'bookSourceName': 'A'},
          {'bookSourceUrl': 'https://b.com', 'bookSourceName': 'B'},
          {'bookSourceName': '无地址条目'},
        ]),
      );
      expect(report.added, 2);
      expect(report.invalid, 1);
      await store.flush();

      // 重载校验持久化
      final store2 = SourceStore(dirsOverride: dirs);
      await store2.load();
      expect(store2.sources.length, 2);

      store2.setEnabled('https://a.com', false);
      expect(store2.enabledCount, 1);
      await store2.flush();

      // 再次导入同 URL → 更新，且用户关闭的状态保留
      final r2 = store2.importFromText(
        jsonEncode([
          {
            'bookSourceUrl': 'https://a.com',
            'bookSourceName': 'A2',
            'searchUrl': '/s',
          },
        ]),
      );
      expect(r2.updated, 1);
      expect(store2.byUrl('https://a.com')!.bookSourceName, 'A2');
      expect(store2.byUrl('https://a.com')!.enabled, false);

      expect(store2.exportJson(), contains('https://a.com'));

      // 删除
      store2.remove('https://b.com');
      expect(store2.sources.length, 1);
    });

    test('非法内容给出友好错误', () {
      final store = SourceStore();
      expect(store.importFromText('').error, isNotNull);
      expect(store.importFromText('not json').error, contains('JSON'));
      expect(store.importFromText('{"x":1}').error, contains('有效书源'));
    });
  });

  group('多源搜索（OnlineRepo）', () {
    OnlineRepo buildRepo(List<BookSource> items) {
      final store = SourceStore(initial: items);
      final mock = MockClient((req) async {
        final host = req.url.host;
        if (host == 'site-a.com') {
          return http.Response(
            _siteAHtml,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (host == 'site-b.com') {
          return http.Response(
            _siteBJson,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (host == 'site-post.com') {
          return http.Response(
            _siteAHtml,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('err', 503);
      });
      return OnlineRepo(
        store: store,
        client: SourceHttpClient(client: mock),
        perSourceTimeout: const Duration(seconds: 5),
      );
    }

    test('HTML 源与 JSON 源并行搜索 + 相对链接补全', () async {
      final repo = buildRepo([_sourceA(), _sourceB()]);
      final results = await repo.searchAll('测试');
      expect(results.length, 2);

      final a = results[0];
      expect(a.ok, true);
      expect(a.books.length, 2);
      expect(a.books[0].name, '斗破苍穹');
      expect(a.books[0].author, '天蚕土豆');
      expect(a.books[0].bookUrl, 'https://site-a.com/book/1');
      expect(a.books[0].originName, '站点A');

      final b = results[1];
      expect(b.ok, true);
      expect(b.books.length, 2);
      expect(b.books[0].name, '诡秘之主');
      expect(b.books[0].bookUrl, 'https://site-b.com/bk/9');
    });

    test('错误隔离：失败源不影响其它源', () async {
      final bad = BookSource.fromJson(
        jsonDecode(
          '{"bookSourceUrl":"https://site-x.com","bookSourceName":"坏源","searchUrl":"/s?q={{key}}","ruleSearch":{"bookList":"li","name":"h3@text"}}',
        ),
      );
      final repo = buildRepo([_sourceA(), bad]);
      final results = await repo.searchAll('测试');
      expect(results.length, 2);
      expect(results[0].ok, true);
      expect(results[1].ok, false);
      expect(results[1].error, contains('503'));
    });

    test('POST 源：method/body 正确透传', () async {
      String? method;
      String? body;
      final store = SourceStore(
        initial: [
          BookSource.fromJson(
            jsonDecode(
              '{"bookSourceUrl":"https://site-post.com","bookSourceName":"POST源","searchUrl":"/p,{\\"method\\":\\"POST\\",\\"body\\":\\"q={{key}}\\"}","ruleSearch":{"bookList":"class.book-list@tag.li","name":"tag.h3@text"}}',
            ),
          ),
        ],
      );
      final mock = MockClient((req) async {
        method = req.method;
        body = req.body;
        return http.Response(
          _siteAHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final repo = OnlineRepo(
        store: store,
        client: SourceHttpClient(client: mock),
      );
      final results = await repo.searchAll('测试');
      expect(method, 'POST');
      expect(body, 'q=${Uri.encodeComponent('测试')}');
      expect(results.single.books.length, 2);
    });

    test('预热请求（preRequest）：先取令牌再搜索，Cookie 贯通', () async {
      final seenCookies = <String>[];
      final mock = MockClient((req) async {
        if (req.url.path == '/user/hm.html') {
          return http.Response(
            'ok',
            200,
            headers: {'set-cookie': 'hm=token123; Path=/'},
          );
        }
        seenCookies.add(req.headers['cookie'] ?? '');
        return http.Response(
          _siteBJson,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final s = BookSource.fromJson({
        'bookSourceUrl': 'https://site-hm.com',
        'bookSourceName': '预热源',
        'searchUrl': '/user/search.html?q={{key}}',
        'preRequest': ['/user/hm.html?q={{key}}'],
        'ruleSearch': {'bookList': r'$.data.list[*]', 'name': r'$.name'},
      });
      final repo = OnlineRepo(
        store: SourceStore(initial: [s]),
        client: SourceHttpClient(client: mock),
      );
      final results = await repo.searchAll('测试');
      expect(seenCookies.single, contains('hm=token123'));
      expect(results.single.books.length, 2);
    });

    test('无启用书源时返回空列表', () async {
      final repo = buildRepo([]);
      expect(await repo.searchAll('任意'), isEmpty);
    });

    test('缺少 searchUrl 的源给出明确错误', () async {
      final s = BookSource.fromJson(
        jsonDecode('{"bookSourceUrl":"https://n.com","bookSourceName":"空源"}'),
      );
      final repo = buildRepo([s]);
      final results = await repo.searchAll('测试');
      expect(results.single.ok, false);
      expect(results.single.error, contains('searchUrl'));
    });
  });
}
