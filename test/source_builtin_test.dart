// 内置书源测试：清单 / 规则齐备 / 两类搜索链路 / 详情与目录解析。
//
// 重要回归背景（为什么会有这个文件）：
//   hkmtxt / bqgiu 的搜索接口已改为「令牌 + POST 表单」：
//     ① 先访问 /user/hm.html 取 hm Cookie（preRequest）；
//     ② POST /user/search.html，且必须携带
//        Content-Type: application/x-www-form-urlencoded。
//   缺任一环节，站点会**静默返回单字符 `1`**（表现为「搜索 0 本」）。
//   这里用 MockClient 复刻站点行为——规则若退化回 GET，测试会立刻失败。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/source/analyze_rule.dart';
import 'package:sakura_read/src/source/analyze_url.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_book_service.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

BookSource _byHost(List<BookSource> list, String host) =>
    list.firstWhere((s) => s.bookSourceUrl.contains(host));

void main() {
  late List<BookSource> builtin;

  setUpAll(() async {
    final raw = jsonDecode(
      await File('assets/sources/builtin_sources.json').readAsString(),
    );
    builtin = BookSource.listFromJson(raw);
  });

  group('内置清单', () {
    test('包含 4 个源：公版维基文库 ×2 + 第三方聚合 ×2', () {
      expect(builtin.length, 4);
      final urls = builtin.map((s) => s.bookSourceUrl).toList();
      expect(urls, contains('https://zh.wikisource.org'));
      expect(urls, contains('https://zh.m.wikisource.org'));
      expect(urls, contains('https://www.hkmtxt.cc'));
      expect(urls, contains('https://www.bqgiu.cc'));
      for (final s in builtin) {
        expect(s.enabled, isTrue);
        expect(s.searchUrl, isNotNull);
        expect(s.searchRule, isNotNull);
        expect(s.bookInfoRule, isNotNull);
        expect(s.tocRule, isNotNull);
        expect(s.contentRule, isNotNull);
      }
    });

    test('资产不再把 hkmtxt / bqgiu 列为待清理项（否则升级会把恢复的源删掉）', () async {
      final raw =
          jsonDecode(
                await File(
                  'assets/sources/builtin_sources.json',
                ).readAsString(),
              )
              as List;
      final urls = <String>[];
      for (final item in raw) {
        final v = (item as Map)['legacyBuiltinUrls'];
        if (v is List) urls.addAll(v.map((e) => e.toString()));
      }
      expect(urls, isNot(contains('https://www.hkmtxt.cc')));
      expect(urls, isNot(contains('https://www.bqgiu.cc')));
    });

    test('第三方源搜索规则是「令牌 + POST」，并带正文相关扩展字段', () {
      for (final host in ['hkmtxt', 'bqgiu']) {
        final s = _byHost(builtin, host);
        final opts = parseUrlTemplate(s.searchUrl!).options;
        expect(opts['method'], 'POST', reason: '$host 搜索应为 POST（GET 已被站点静默拒绝）');
        expect(
          '${opts['body']}',
          contains('{{key}}'),
          reason: '$host 搜索 body 应带关键词模板',
        );
        final headers = opts['headers'];
        expect(headers, isA<Map>());
        expect(
          '${(headers as Map)['Content-Type']}',
          contains('application/x-www-form-urlencoded'),
          reason: '$host 缺表单 Content-Type 会被站点拒绝（返回单字符 1）',
        );
        expect(s.extra['preRequest'], isA<List>(), reason: '$host 需要令牌预热请求');
        expect(s.extra['webView'], isTrue, reason: '$host 正文需隐藏浏览器渲染');
        expect(s.extra['gatewayPath'], '/userverify');
      }
    });
  });

  group('第三方源搜索：令牌 + POST 全链路（MockClient 复刻站点校验）', () {
    /// 复刻站点行为：非 POST / 缺表单 Content-Type / 缺令牌 Cookie → 静默返回 `1`。
    Future<List<SearchBook>> runSearch(
      String hostKey,
      String fixturePath,
      String key,
    ) async {
      final src = _byHost(builtin, hostKey);
      final fixture = await File(fixturePath).readAsString();
      final mock = MockClient((req) async {
        if (req.url.path == '/user/hm.html') {
          return http.Response(
            'ok',
            200,
            headers: {'set-cookie': 'hm=token123; Path=/'},
          );
        }
        final ct = req.headers['content-type'] ?? '';
        final cookie = req.headers['cookie'] ?? '';
        if (req.method != 'POST' ||
            !ct.contains('application/x-www-form-urlencoded') ||
            !cookie.contains('hm=token123')) {
          return http.Response('1', 200); // 站点的"静默失败"
        }
        return http.Response(
          fixture,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repo = OnlineRepo(
        store: SourceStore(initial: [src]),
        client: SourceHttpClient(client: mock),
        perSourceTimeout: const Duration(seconds: 5),
      );
      final results = await repo.searchAll(key);
      expect(results.single.ok, isTrue, reason: '搜索失败：${results.single.error}');
      return results.single.books;
    }

    test('好看吗：解析真实搜索夹具并补全相对链接', () async {
      final books = await runSearch(
        'hkmtxt',
        'test/fixtures/source/hkmtxt_search.json',
        '完美世界',
      );
      expect(books.length, greaterThan(50));
      final b = books.firstWhere((x) => x.name == '完美世界');
      expect(b.author, '辰东');
      expect(b.bookUrl, 'https://www.hkmtxt.cc/book/126/');
      expect(b.coverUrl, startsWith('https://'));
    });

    test('笔趣阁：解析真实搜索夹具并补全相对链接', () async {
      final books = await runSearch(
        'bqgiu',
        'test/fixtures/source/bqgiu_search.json',
        '斗破',
      );
      expect(books.length, greaterThan(50));
      final b = books.firstWhere((x) => x.name == '斗破苍穹之淫宗肆虐');
      expect(b.author, '琉璃狐');
      expect(b.bookUrl, 'https://www.bqgiu.cc/book/40917/');
    });
  });

  group('第三方源详情 / 目录（真实书页夹具）', () {
    test('好看吗：详情字段 + 2079 章大目录', () async {
      final src = _byHost(builtin, 'hkmtxt');
      final html = await File(
        'test/fixtures/source/hkmtxt_book.html',
      ).readAsString();
      final engine = AnalyzeRule(html, baseUrl: src.bookSourceUrl);
      expect(engine.getString(src.bookInfoRule!.name!), '完美世界');
      expect(engine.getString(src.bookInfoRule!.author!), '辰东');
      final intro = engine.getString(src.bookInfoRule!.intro!);
      expect(intro, isNotNull);
      expect(intro!, contains('大荒'));
      expect(intro.endsWith('1w0-455'), isFalse, reason: '章节尾号应被替换链清掉');

      final chapters = OnlineBookService.parseChapters(
        engine,
        src.tocRule!,
        'https://www.hkmtxt.cc/book/126/',
      );
      expect(chapters.length, 2079);
      expect(chapters.first.title, '第1章 序章 大荒');
      expect(chapters.first.href, 'https://www.hkmtxt.cc/book/126/1.html');
      expect(chapters.last.title, contains('独断万古'));
    });

    test('笔趣阁：详情字段 + 42 章目录', () async {
      final src = _byHost(builtin, 'bqgiu');
      final html = await File(
        'test/fixtures/source/bqgiu_book.html',
      ).readAsString();
      final engine = AnalyzeRule(html, baseUrl: src.bookSourceUrl);
      expect(engine.getString(src.bookInfoRule!.name!), '斗破苍穹之淫宗肆虐');
      expect(engine.getString(src.bookInfoRule!.author!), '琉璃狐');
      final chapters = OnlineBookService.parseChapters(
        engine,
        src.tocRule!,
        'https://www.bqgiu.cc/book/40917/',
      );
      expect(chapters.length, 42);
      expect(chapters.first.href, 'https://www.bqgiu.cc/book/40917/1.html');
    });
  });

  group('公版源（维基文库）规则回归', () {
    BookSource wikisource() => builtin.firstWhere(
      (s) => s.bookSourceUrl == 'https://zh.wikisource.org',
    );

    test('搜索：解析 generator=search 接口夹具', () async {
      final src = wikisource();
      final fixture = await File(
        'test/fixtures/ws/wikisource_search.json',
      ).readAsString();
      final repo = OnlineRepo(store: SourceStore(initial: [src]));
      final books = repo.parseSearchPage(src, fixture);

      expect(books.length, greaterThanOrEqualTo(4));
      final b = books.firstWhere((x) => x.name == '論語');
      expect(b.author, isNull, reason: '公版古籍无作者字段时留空');
      expect(b.bookUrl, startsWith('https://zh.wikisource.org/wiki/'));
      expect(b.originName, src.bookSourceName);
      expect(books.where((x) => x.coverUrl != null).length, greaterThan(0));
    });

    test('详情 + 目录：解析真实书页（《論語》）', () async {
      final src = wikisource();
      final html = await File(
        'test/fixtures/ws/wikisource_book.html',
      ).readAsString();
      final engine = AnalyzeRule(html, baseUrl: src.bookSourceUrl);

      expect(engine.getString(src.bookInfoRule!.name!), '論語');
      expect(engine.getString(src.bookInfoRule!.intro!), contains('孔子'));

      final chapters = OnlineBookService.parseChapters(
        engine,
        src.tocRule!,
        'https://zh.wikisource.org/wiki/論語',
      );
      expect(chapters.length, greaterThan(10), reason: '《論語》应解析出多篇');
      expect(chapters.first.title, '序說');
      expect(
        chapters.first.href,
        startsWith('https://zh.wikisource.org/wiki/'),
      );
    });

    test('正文：解析真实章节页并按段拼接', () async {
      final src = wikisource();
      final html = await File(
        'test/fixtures/ws/wikisource_chapter.html',
      ).readAsString();
      final engine = AnalyzeRule(html, baseUrl: src.bookSourceUrl);
      final raw = engine.getStrings(src.contentRule!.content!).join('\n');
      final text = OnlineBookService.cleanChapterText(raw);

      expect(text.length, greaterThan(300), reason: '应取到多段正文');
      expect(text, contains('學而時習之'));
      expect(text.split('\n').length, greaterThan(3));
    });
  });
}
