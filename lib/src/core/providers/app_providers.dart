import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/book_store.dart';
import '../../data/models.dart';
import '../../data/pet_store.dart';
import '../../data/prefs.dart';
import '../../data/stats_store.dart';
import '../../source/source_store.dart';
import '../database/sakura_database.dart';

/// 全局 SQLite 数据库（后台打开后通过 [SakuraDatabase.shared] 获取；测试未注入时可为 null）。
final sakuraDatabaseProvider = Provider<SakuraDatabase?>(
  (_) => SakuraDatabase.shared,
);

/// 书架状态仓库（由 SakuraApp 在根部 override 注入）。
final bookStoreProvider = ChangeNotifierProvider<BookStore>((_) {
  throw UnimplementedError('bookStoreProvider must be overridden by SakuraApp');
});

/// 应用与阅读偏好设置。
final prefsProvider = ChangeNotifierProvider<AppPrefs>((_) {
  throw UnimplementedError('prefsProvider must be overridden by SakuraApp');
});

/// 书源仓库。
final sourceStoreProvider = ChangeNotifierProvider<SourceStore>((_) {
  throw UnimplementedError(
    'sourceStoreProvider must be overridden by SakuraApp',
  );
});

/// 阅读统计（可为 null）。
final statsStoreProvider = ChangeNotifierProvider<StatsStore?>((_) => null);

/// 桌宠状态（可为 null）。
final petStoreProvider = ChangeNotifierProvider<PetStore?>((_) => null);

/// 书架当前分组筛选：null = 全部，'' = 未分组，其余为分组名。
final shelfGroupFilterProvider = StateProvider<String?>((_) => null);

/// 书架实时搜索关键词。
final shelfQueryProvider = StateProvider<String>((_) => '');

/// 最近阅读中的第一本书（用于书架顶部「继续阅读」聚焦卡片）。
final continueReadingBookProvider = Provider<Book?>((ref) {
  final store = ref.watch(bookStoreProvider);
  Book? latest;
  for (final book in store.books) {
    if (book.lastReadAt <= 0) continue;
    if (latest == null || book.lastReadAt > latest.lastReadAt) {
      latest = book;
    }
  }
  return latest;
});

/// 书架中已使用的全部非空分组名（按字母序排列）。
final shelfGroupsProvider = Provider<List<String>>((ref) {
  final store = ref.watch(bookStoreProvider);
  final groups = <String>{
    for (final book in store.books)
      if (book.group.isNotEmpty) book.group,
  }.toList()..sort();
  return groups;
});
