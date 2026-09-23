// 搜索相关性排序 & 合并键的单元测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_repo.dart';

void main() {
  test('搜索相关性：完全匹配 > 前缀派生 > 包含 > 无关', () {
    const key = '斗破苍穹';
    const exact = SearchBook(name: '斗破苍穹', author: '天蚕土豆');
    const prefix = SearchBook(name: '斗破苍穹之淫宗肆虐', author: '琉璃狐');
    const contains = SearchBook(name: '武动乾坤斗破苍穹外传', author: 'x');
    const authorMatch = SearchBook(name: '随便的书', author: '斗破苍穹');
    const unrelated = SearchBook(name: '逆天邪神', author: '火星引力');

    final s1 = bookRelevanceScore(exact, key);
    final s2 = bookRelevanceScore(prefix, key);
    final s3 = bookRelevanceScore(contains, key);
    final s4 = bookRelevanceScore(authorMatch, key);
    final s5 = bookRelevanceScore(unrelated, key);

    expect(s1, 1000);
    expect(s1, greaterThan(s2));
    expect(s2, greaterThan(s3));
    expect(s3, greaterThan(s5));
    expect(s4, greaterThan(s5));
    expect(s5, 100);
  });

  test('合并键：跨源同名书归并（忽略装饰括号与空白）', () {
    expect(
      bookMergeKey(const SearchBook(name: '完美世界', author: '辰东')),
      bookMergeKey(const SearchBook(name: '完美世界（大结局）', author: '辰东')),
    );
    expect(
      bookMergeKey(const SearchBook(name: '斗破 苍穹', author: '天蚕土豆')),
      bookMergeKey(const SearchBook(name: '斗破苍穹', author: '天蚕土豆')),
    );
    expect(
      bookMergeKey(const SearchBook(name: '斗破苍穹', author: '天蚕土豆')),
      isNot(bookMergeKey(const SearchBook(name: '斗破苍穹', author: '其他人'))),
    );
  });
}
