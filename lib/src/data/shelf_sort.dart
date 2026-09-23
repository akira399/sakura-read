// 书架排列：排序方式 / 显示方式 定义 + 比较与排序工具。
import 'models.dart';
import 'natural_sort.dart';

/// 书架排序方式。
enum ShelfSortMode {
  recentRead('最近阅读'),
  addedTime('添加时间'),
  title('书名'),
  author('作者'),
  progress('阅读进度'),
  chars('字数');

  const ShelfSortMode(this.label);

  final String label;

  /// 该方式的默认排序方向（true = 正序 / 升序）。
  ///
  /// - 最近阅读 / 添加时间：新的在前 → 降序；
  /// - 书名 / 作者：A→Z 顺读 → 升序；
  /// - 阅读进度 / 字数：多的在前 → 降序。
  bool get defaultAscending => switch (this) {
    ShelfSortMode.recentRead => false,
    ShelfSortMode.addedTime => false,
    ShelfSortMode.title => true,
    ShelfSortMode.author => true,
    ShelfSortMode.progress => false,
    ShelfSortMode.chars => false,
  };
}

/// 书架显示方式。
enum ShelfViewMode {
  grid('网格'),
  compact('小图'),
  list('列表');

  const ShelfViewMode(this.label);

  final String label;
}

/// 存储字符串 → 排序方式（未知 / 空回退「最近阅读」）。
ShelfSortMode shelfSortModeFrom(String? value) => switch (value) {
  'addedTime' => ShelfSortMode.addedTime,
  'title' => ShelfSortMode.title,
  'author' => ShelfSortMode.author,
  'progress' => ShelfSortMode.progress,
  'chars' => ShelfSortMode.chars,
  _ => ShelfSortMode.recentRead,
};

/// 存储字符串 → 显示方式（未知 / 空回退「网格」）。
ShelfViewMode shelfViewModeFrom(String? value) => switch (value) {
  'compact' => ShelfViewMode.compact,
  'list' => ShelfViewMode.list,
  _ => ShelfViewMode.grid,
};

/// 按 [mode] 的升序语义比较两本书（负值 = a 在前）。
///
/// 升 / 降序由调用方统一翻转（见 [sortBooksForShelf]）。
int compareBooks(Book a, Book b, ShelfSortMode mode) {
  switch (mode) {
    case ShelfSortMode.recentRead:
      // 没读过的新书用「添加时间」兜底
      final x = a.lastReadAt == 0 ? a.addedAt : a.lastReadAt;
      final y = b.lastReadAt == 0 ? b.addedAt : b.lastReadAt;
      return x.compareTo(y);
    case ShelfSortMode.addedTime:
      return a.addedAt.compareTo(b.addedAt);
    case ShelfSortMode.title:
      return naturalCompare(a.title, b.title);
    case ShelfSortMode.author:
      // 佚名（无作者）偏后
      final aEmpty = a.author.trim().isEmpty;
      final bEmpty = b.author.trim().isEmpty;
      if (aEmpty != bEmpty) return aEmpty ? 1 : -1;
      final c = naturalCompare(a.author, b.author);
      return c != 0 ? c : naturalCompare(a.title, b.title);
    case ShelfSortMode.progress:
      final c = a.progress.compareTo(b.progress);
      return c != 0 ? c : naturalCompare(a.title, b.title);
    case ShelfSortMode.chars:
      final c = a.totalChars.compareTo(b.totalChars);
      return c != 0 ? c : naturalCompare(a.title, b.title);
  }
}

/// 按 [mode] + 方向排序书架列表（原地）。
void sortBooksForShelf(
  List<Book> books,
  ShelfSortMode mode, {
  required bool ascending,
}) {
  books.sort((a, b) {
    final c = compareBooks(a, b, mode);
    return ascending ? c : -c;
  });
}
