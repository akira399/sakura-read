// 内置书源测试：确认内置的是「公版内容源」、且规则对真实页面/接口夹具有效。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/analyze_rule.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_book_service.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  late List<BookSource> builtin;

  setUpAll(() async {
    final raw = jsonDecode(
      await File('assets/sources/builtin_sources.json').readAsString(),
    );
    builtin = BookSource.listFromJson(raw);
  });

  group('内置源合规性', () {
    test('至少包含一个源，且全部为公版内容源', () {
      expect(builtin, isNotEmpty);
      for (final s in builtin) {
        expect(
          s.bookSourceUrl.contains('wikisource.org'),
          isTrue,
          reason: '内置源只应指向公版内容站，实际：${s.bookSourceUrl}',
        );
        expect(s.enabled, isTrue);
      }
    });

    test('历史盗版聚合源已从内置资产中移除', () {
      const legacy = ['hkmtxt.cc', 'bqgiu.cc', 'biquge', 'bqg'];
      for (final s in builtin) {
        for (final bad in legacy) {
          expect(
            s.bookSourceUrl.contains(bad),
            isFalse,
            reason: '不应再内置盗版聚合源：$bad',
          );
        }
      }
    });

    test('资产里带有「升级时清理旧源」的清单', () async {
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
      expect(urls, contains('https://www.hkmtxt.cc'));
      expect(urls, contains('https://www.bqgiu.cc'));
    });

    test('规则齐备：搜索 / 详情 / 目录 / 正文', () {
      for (final s in builtin) {
        expect(s.searchUrl, isNotNull);
        expect(s.searchRule, isNotNull);
        expect(s.bookInfoRule, isNotNull);
        expect(s.tocRule, isNotNull);
        expect(s.contentRule, isNotNull);
        expect(s.extra['webView'], isNull, reason: '公版源走静态 HTTP 即可');
      }
    });
  });

  group('规则对真实数据有效', () {
    test('搜索：解析 generator=search 接口夹具', () async {
      final src = builtin.firstWhere(
        (s) => s.bookSourceUrl == 'https://zh.wikisource.org',
      );
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
      // 封面是可选的（thumbnail 缺失不应报错）
      expect(books.where((x) => x.coverUrl != null).length, greaterThan(0));
    });

    test('详情 + 目录：解析真实书页（《論語》）', () async {
      final src = builtin.firstWhere(
        (s) => s.bookSourceUrl == 'https://zh.wikisource.org',
      );
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
      final src = builtin.firstWhere(
        (s) => s.bookSourceUrl == 'https://zh.wikisource.org',
      );
      final html = await File(
        'test/fixtures/ws/wikisource_chapter.html',
      ).readAsString();
      final engine = AnalyzeRule(html, baseUrl: src.bookSourceUrl);
      final raw = engine.getStrings(src.contentRule!.content!).join('\n');
      final text = OnlineBookService.cleanChapterText(raw);

      expect(text.length, greaterThan(300), reason: '应取到多段正文');
      expect(text, contains('學而時習之'));
      // 多段之间应有换行（按段阅读）
      expect(text.split('\n').length, greaterThan(3));
    });
  });
}
