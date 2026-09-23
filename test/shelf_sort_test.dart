// 书架排列（shelf_sort）的单元测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';

Book _book({
  required String id,
  required String title,
  String author = '',
  int addedAt = 0,
  int lastReadAt = 0,
  int totalChars = 0,
  int chapterIndex = 0,
  int charOffset = 0,
  bool finished = false,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFormat.txt,
    path: '/tmp/$id.txt',
    chapters: [
      ChapterRef(title: '第一章', charCount: 1000),
      ChapterRef(title: '第二章', charCount: 1000),
    ],
    totalChars: totalChars,
    chapterIndex: chapterIndex,
    charOffset: charOffset,
    addedAt: addedAt,
    lastReadAt: lastReadAt,
    finished: finished,
  );
}

void main() {
  group('shelf_sort', () {
    test('最近阅读：降序（新的在前），未读新书用添加时间兜底', () {
      final books = [
        _book(id: 'a', title: 'A', addedAt: 100, lastReadAt: 500),
        _book(
          id: 'b',
          title: 'B',
          addedAt: 900,
          lastReadAt: 0,
        ), // 未读，用 addedAt=900
        _book(id: 'c', title: 'C', addedAt: 100, lastReadAt: 300),
      ];
      sortBooksForShelf(books, ShelfSortMode.recentRead, ascending: false);
      expect(books.map((b) => b.id).toList(), ['b', 'a', 'c']);
    });

    test('书名：自然排序（第2话 < 第10话）', () {
      final books = [
        _book(id: '1', title: '第10话 决战'),
        _book(id: '2', title: '第2话 初见'),
        _book(id: '3', title: '第1话 起点'),
      ];
      sortBooksForShelf(books, ShelfSortMode.title, ascending: true);
      expect(books.map((b) => b.id).toList(), ['3', '2', '1']);
    });

    test('作者：佚名偏后，同作者按书名', () {
      final books = [
        _book(id: 'x', title: 'X', author: '天蚕土豆'),
        _book(id: 'y', title: 'Y', author: ''),
        _book(id: 'z', title: 'Z', author: '天蚕土豆', addedAt: 1),
      ];
      sortBooksForShelf(books, ShelfSortMode.author, ascending: true);
      // 天蚕土豆组在前（X 按书名 < Z），佚名 Y 在最后
      expect(books.map((b) => b.id).toList(), ['x', 'z', 'y']);
    });

    test('阅读进度：降序（读得多的在前）', () {
      final books = [
        _book(id: 'low', title: 'A', chapterIndex: 0, charOffset: 0),
        _book(id: 'mid', title: 'B', chapterIndex: 1, charOffset: 500),
        _book(id: 'done', title: 'C', finished: true),
      ];
      sortBooksForShelf(books, ShelfSortMode.progress, ascending: false);
      expect(books.map((b) => b.id).toList(), ['done', 'mid', 'low']);
    });

    test('字数：降序（字数多的在前）', () {
      final books = [
        _book(id: 'small', title: 'A', totalChars: 1000),
        _book(id: 'big', title: 'B', totalChars: 90000),
        _book(id: 'mid', title: 'C', totalChars: 30000),
      ];
      sortBooksForShelf(books, ShelfSortMode.chars, ascending: false);
      expect(books.map((b) => b.id).toList(), ['big', 'mid', 'small']);
    });

    test('方向翻转：同一方式正序 / 倒序互为镜像', () {
      final books = [
        _book(id: 'a', title: '第1话'),
        _book(id: 'b', title: '第2话'),
      ];
      sortBooksForShelf(books, ShelfSortMode.title, ascending: true);
      final asc = books.map((b) => b.id).toList();
      sortBooksForShelf(books, ShelfSortMode.title, ascending: false);
      final desc = books.map((b) => b.id).toList();
      expect(asc, ['a', 'b']);
      expect(desc, ['b', 'a']);
    });

    test('默认方向：书名升序 / 其余常用降序', () {
      expect(ShelfSortMode.title.defaultAscending, isTrue);
      expect(ShelfSortMode.author.defaultAscending, isTrue);
      expect(ShelfSortMode.recentRead.defaultAscending, isFalse);
      expect(ShelfSortMode.addedTime.defaultAscending, isFalse);
      expect(ShelfSortMode.progress.defaultAscending, isFalse);
      expect(ShelfSortMode.chars.defaultAscending, isFalse);
    });

    test('存储字符串解析：未知值回退默认', () {
      expect(shelfSortModeFrom('title'), ShelfSortMode.title);
      expect(shelfSortModeFrom('chars'), ShelfSortMode.chars);
      expect(shelfSortModeFrom('unknown'), ShelfSortMode.recentRead);
      expect(shelfSortModeFrom(null), ShelfSortMode.recentRead);
      expect(shelfViewModeFrom('list'), ShelfViewMode.list);
      expect(shelfViewModeFrom('compact'), ShelfViewMode.compact);
      expect(shelfViewModeFrom(null), ShelfViewMode.grid);
    });
  });
}
