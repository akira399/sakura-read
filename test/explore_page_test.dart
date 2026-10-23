// 发现页解析回归测试（issue #3）。
//
// 真实书源「得奇」的 ruleExplore 用裸标签选择器：
//   bookList: ".item", name: "h3@text", bookUrl: "tag.a.0@href"
// 旧实现把 `h3` 当成属性名（因为 h3 符合「字母开头的单词」），
// 于是每本书的 name 都是空 → 整页解析出 0 本，用户看到「发现页出不了书」。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

const _html = '''
<html><body>
<div class="wrap">
  <div class="item">
    <a href="/2677/"><img src="/files/2677s.jpg" alt="书一" /></a>
    <div class="itemtxt">
      <h3><b class="rank1"></b><a href="/2677/">说好的纨绔</a></h3>
      <span>连载</span>
      <p>作者：甲</p>
    </div>
  </div>
  <div class="item">
    <a href="/715/"><img src="/files/715s.jpg" alt="书二" /></a>
    <div class="itemtxt">
      <h3><a href="/715/">武逆九千界</a></h3>
      <span>完结</span>
      <p>作者：乙</p>
    </div>
  </div>
</div>
</body></html>
''';

BookSource _source() => BookSource.fromJson(
  jsonDecode('''
{
  "bookSourceName": "得奇",
  "bookSourceUrl": "https://www.deqixs.org",
  "enabled": true,
  "enabledExplore": true,
  "exploreUrl": "玄幻小说::/sort/1/{{page}}.html\\n都市小说::/sort/3/{{page}}.html",
  "ruleExplore": {
    "bookList": ".item",
    "name": "h3@text",
    "author": "p@text",
    "bookUrl": "tag.a.0@href",
    "coverUrl": "img@src",
    "kind": "span@text"
  },
  "ruleSearch": {"bookList": ".item", "name": "h3@text"}
}
'''),
);

void main() {
  test('exploreUrl 行格式解析出分类', () {
    final cats = OnlineRepo.parseExploreCategories(_source());
    expect(cats.map((c) => c.title), ['玄幻小说', '都市小说']);
    expect(cats.first.url, '/sort/1/{{page}}.html');
  });

  test('裸标签选择器 h3@text 能取到书名（issue #3 根因）', () {
    final source = _source();
    final repo = OnlineRepo(store: SourceStore(initial: [source]));
    final books = repo.parseExplorePage(source, _html);
    expect(books, hasLength(2));
    expect(books[0].name, '说好的纨绔');
    expect(books[0].author, '作者：甲');
    expect(books[0].kind, '连载');
    expect(books[0].bookUrl, 'https://www.deqixs.org/2677/');
    expect(books[0].coverUrl, 'https://www.deqixs.org/files/2677s.jpg');
    expect(books[1].name, '武逆九千界');
  });

  test('裸标签 span@text / a@href 同样可用', () {
    final source = _source();
    final repo = OnlineRepo(store: SourceStore(initial: [source]));
    final books = repo.parseExplorePage(source, _html);
    expect(books[1].kind, '完结');
  });
}
