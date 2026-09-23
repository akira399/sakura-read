import 'dart:io';

import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/file_scan.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../data/shelf_sort.dart';
import '../platform/native_bridge.dart';
import '../source/source_store.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import 'book_detail_page.dart';
import 'folder_picker_page.dart';
import 'reader/reader_page.dart';
import 'source/source_search_page.dart';
import 'widgets/book_cover.dart';
import 'widgets/cute.dart';
import 'widgets/kanban_mascot.dart';
import 'widgets/sakura_petals.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.sourceStore,
  });

  final BookStore store;
  final AppPrefs prefs;
  final SourceStore sourceStore;

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  /// 空书架的看板娘台词。
  static const _emptyShelfLines = [
    '书架上还空着哦',
    '点右下角的＋导入你的书吧',
    'TXT 和 EPUB 都可以的',
    '要一起等一本书到来吗？',
    '嘘……在等你的故事呢',
    '先放一本书进来，好不好？',
  ];

  String get _headerLine {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息';
    if (h < 11) return '早上好呀';
    if (h < 14) return '午后适合读书';
    if (h < 18) return '下午好呀';
    return '晚上好呀';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.prefs]),
      builder: (context, _) {
        final books = widget.store.books.toList();
        _sortBooks(books);
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddSheet(context),
            tooltip: '导入书籍',
            child: const Icon(Icons.add_rounded, size: 30),
          ),
          body: CustomScrollView(
            slivers: [
              _buildHeader(context, books.length),
              if (books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmpty(context),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  sliver: _buildBooksSliver(books),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 按当前「排列方式」渲染书架（网格 / 小图 / 列表）。
  Widget _buildBooksSliver(List<Book> books) {
    switch (widget.prefs.shelfView) {
      case ShelfViewMode.grid:
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 158,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: .64,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _BookCard(
              book: books[index],
              store: widget.store,
              onOpen: () => _openDetail(books[index]),
              onMenu: () => _showBookMenu(books[index]),
            ),
            childCount: books.length,
          ),
        );
      case ShelfViewMode.compact:
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .66,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _CompactBookCard(
              book: books[index],
              onOpen: () => _openDetail(books[index]),
              onMenu: () => _showBookMenu(books[index]),
            ),
            childCount: books.length,
          ),
        );
      case ShelfViewMode.list:
        return SliverList.separated(
          itemCount: books.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _BookListTile(
            book: books[index],
            subtitle: _bookSubtitle(books[index]),
            onOpen: () => _openDetail(books[index]),
            onMenu: () => _showBookMenu(books[index]),
          ),
        );
    }
  }

  /// 列表视图副标题：排序会随当前方式给出相关信息。
  String _bookSubtitle(Book book) {
    final parts = <String>['${book.chapterCount} 章'];
    if (book.totalChars > 0) {
      parts.add('${(book.totalChars / 10000).toStringAsFixed(1)} 万字');
    }
    switch (widget.prefs.shelfSort) {
      case ShelfSortMode.author:
        parts.insert(0, book.author.isEmpty ? '佚名' : book.author);
      case ShelfSortMode.progress:
        parts.add('已读 ${book.progressLabel}');
      case ShelfSortMode.recentRead:
        if (book.lastReadAt > 0) {
          parts.add(timeAgo(book.lastReadAt));
        }
      case _:
        if (book.author.isNotEmpty) parts.insert(0, book.author);
    }
    return parts.join(' · ');
  }

  void _sortBooks(List<Book> books) {
    sortBooksForShelf(
      books,
      widget.prefs.shelfSort,
      ascending: widget.prefs.shelfAscending,
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          gradient: SakuraTheme.headerGradient(context),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 18,
          left: 20,
          right: 8,
          bottom: 18,
        ),
        child: Row(
          children: [
            // 看板娘小头像（纯装饰；互动已统一收进全局桌宠）
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .28),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/pet_wave.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '樱读',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '$_headerLine · $count 本书',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .88),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _openSearch(context),
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              tooltip: '搜索',
            ),
            IconButton(
              onPressed: _showArrangeSheet,
              icon: const Icon(Icons.tune_rounded, color: Colors.white),
              tooltip: '排列方式',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return SakuraPetals(
      count: 16,
      child: EmptyState(
        icon: Icons.auto_stories_outlined,
        illustration: const KanbanMascot(size: 168, lines: _emptyShelfLines),
        title: '书架还空着呢',
        subtitle: '点击右下角「+」\n导入本地 TXT / EPUB 小说吧',
        actions: [
          FilledButton.icon(
            onPressed: () => _pickFiles(),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('导入文件'),
          ),
          OutlinedButton.icon(
            onPressed: () => _scanFolder(),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('扫描文件夹'),
          ),
        ],
      ),
    );
  }

  // ---------- 打开 ----------

  void _openDetail(Book book) {
    widget.store.touch(book.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailPage(
          store: widget.store,
          prefs: widget.prefs,
          bookId: book.id,
        ),
      ),
    );
  }

  void _continueReading(Book book) {
    widget.store.touch(book.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          store: widget.store,
          prefs: widget.prefs,
          bookId: book.id,
          chapterIndex: book.safeChapterIndex,
          charOffset: book.charOffset,
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _ShelfSearchDelegate(
        widget.store,
        widget.sourceStore,
        widget.prefs,
        _openDetail,
      ),
    );
  }

  // ---------- 排列方式 ----------

  /// 「排列方式」底部弹层：排序方式 + 方向 + 显示样式，全部即改即生效并记忆。
  void _showArrangeSheet() {
    final prefs = widget.prefs;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: AnimatedBuilder(
          animation: prefs,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '排列方式',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _arrangeLabel('排序方式'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in ShelfSortMode.values)
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(mode.label),
                            if (prefs.shelfSort == mode) ...[
                              const SizedBox(width: 4),
                              Icon(
                                prefs.shelfAscending
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 14,
                              ),
                            ],
                          ],
                        ),
                        selected: prefs.shelfSort == mode,
                        onSelected: (_) {
                          if (prefs.shelfSort == mode) {
                            // 再次点击同一项：翻转方向
                            prefs.toggleShelfAscending();
                          } else {
                            prefs.setShelfSort(mode);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      _directionHint(prefs),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: prefs.toggleShelfAscending,
                      icon: Icon(
                        prefs.shelfAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                      label: Text(
                        prefs.shelfAscending ? '正序' : '倒序',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _arrangeLabel('显示样式'),
                const SizedBox(height: 8),
                SegmentedButton<ShelfViewMode>(
                  segments: [
                    for (final view in ShelfViewMode.values)
                      ButtonSegment(
                        value: view,
                        label: Text(view.label),
                        icon: Icon(_viewIcon(view), size: 16),
                      ),
                  ],
                  selected: {prefs.shelfView},
                  onSelectionChanged: (s) => prefs.setShelfView(s.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '小技巧：连点同一个排序方式可以切换正序 / 倒序',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _viewIcon(ShelfViewMode view) => switch (view) {
    ShelfViewMode.grid => Icons.grid_view_rounded,
    ShelfViewMode.compact => Icons.apps_rounded,
    ShelfViewMode.list => Icons.view_list_rounded,
  };

  String _directionHint(AppPrefs prefs) {
    final name = switch (prefs.shelfSort) {
      ShelfSortMode.recentRead => '最近阅读时间',
      ShelfSortMode.addedTime => '加入书架时间',
      ShelfSortMode.title => '书名字母 / 笔画',
      ShelfSortMode.author => '作者名',
      ShelfSortMode.progress => '阅读进度',
      ShelfSortMode.chars => '全书字数',
    };
    final dir = prefs.shelfAscending ? '从低到高' : '从高到低';
    return '按$name$dir';
  }

  Widget _arrangeLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );

  // ---------- 导入 ----------

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '导入书籍',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            ListTile(
              leading: const _SheetIcon(Icons.public_rounded),
              title: const Text('在线搜书'),
              subtitle: const Text('通过书源搜索网络上的小说'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SourceSearchPage(
                      store: widget.sourceStore,
                      bookStore: widget.store,
                      prefs: widget.prefs,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const _SheetIcon(Icons.upload_file_rounded),
              title: const Text('选择文件'),
              subtitle: const Text('支持 .txt / .epub，可多选'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFiles();
              },
            ),
            ListTile(
              leading: const _SheetIcon(Icons.folder_open_rounded),
              title: const Text('扫描文件夹'),
              subtitle: const Text('导入文件夹里的所有小说（含子文件夹）'),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanFolder();
              },
            ),
            ListTile(
              leading: const _SheetIcon(Icons.travel_explore_rounded),
              title: const Text('扫描常见目录'),
              subtitle: const Text('自动查找 Download / Documents / Books 等'),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanCommonDirs();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerPage(mode: PickerMode.files),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _importPaths(picked);
  }

  Future<void> _scanFolder() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerPage(mode: PickerMode.folder),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _importPaths(picked, scanFolder: true);
  }

  Future<void> _scanCommonDirs() async {
    final root = await NativeBridge.storageRoot();
    final candidates = [
      'Download',
      'Downloads',
      'Documents',
      'Books',
      '小说',
      'novels',
      'Novels',
    ];
    final existing = <String>[];
    for (final name in candidates) {
      final dir = Directory('$root/$name');
      if (await dir.exists()) existing.add(dir.path);
    }
    if (!mounted) return;
    if (existing.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有找到常见目录，试试手动选择吧')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '扫描常见目录？',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          '将扫描以下目录里的所有 TXT / EPUB：\n\n'
          '${existing.map((e) => '· ${pathFileName(e)}').join('\n')}',
          style: const TextStyle(height: 1.6, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始扫描'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _importPaths(existing, scanFolder: true);
  }

  Future<void> _importPaths(
    List<String> paths, {
    bool scanFolder = false,
  }) async {
    // 收集待导入文件
    final files = <String>[];
    var skippedDup = 0;
    for (final p in paths) {
      final type = await FileSystemEntity.type(p, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        if (scanFolder) {
          final found = await scanNovelFiles(Directory(p));
          files.addAll(found.map((f) => f.path));
        }
      } else if (type == FileSystemEntityType.file) {
        if (isNovelFile(p)) files.add(p);
      }
    }

    final toImport = <String>[];
    for (final f in files) {
      if (widget.store.containsPath(f)) {
        skippedDup++;
      } else {
        toImport.add(f);
      }
    }

    if (toImport.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            files.isEmpty ? '没有找到 TXT / EPUB 小说文件' : '这 $skippedDup 本书都已经在书架里啦',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final progress = ValueNotifier<String>('准备导入…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (context, value, _) =>
                    Text(value, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );

    var okCount = 0;
    final failures = <String>[];
    try {
      for (var i = 0; i < toImport.length; i++) {
        final path = toImport[i];
        progress.value =
            '导入 ${i + 1}/${toImport.length}\n${pathFileName(path)}';
        final result = await widget.store.importFile(path);
        if (result.success) {
          okCount++;
        } else {
          failures.add('${pathFileName(path)}：${result.error ?? '未知错误'}');
        }
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (okCount == 0 && failures.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${failures.first}')));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已导入 $okCount 本'
            '${skippedDup > 0 ? '，跳过 $skippedDup 本重复' : ''}'
            '${failures.isNotEmpty ? '，${failures.length} 本失败' : ''}',
          ),
        ),
      );
    }
  }

  // ---------- 长按菜单 ----------

  void _showBookMenu(Book book) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                book.author.isEmpty ? book.path : book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('继续阅读'),
              onTap: () {
                Navigator.pop(sheetContext);
                _continueReading(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('书籍详情'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openDetail(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(sheetContext);
                _renameBook(book);
              },
            ),
            ListTile(
              leading: Icon(
                book.finished
                    ? Icons.restart_alt_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              title: Text(book.finished ? '标记为未读' : '标记为已读'),
              onTap: () {
                Navigator.pop(sheetContext);
                if (book.finished) {
                  widget.store.markUnread(book.id);
                } else {
                  widget.store.markFinished(book.id);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                '从书架移除',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmRemove(book);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameBook(Book book) async {
    final controller = TextEditingController(text: book.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '重命名',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的书名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) widget.store.rename(book.id, result);
  }

  Future<void> _confirmRemove(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '从书架移除？',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          '「${book.title}」会从书架移除（本地文件不会被删除）。',
          style: const TextStyle(height: 1.5, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok == true) widget.store.removeById(book.id);
  }
}

// ---------- 子组件 ----------

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.store,
    required this.onOpen,
    required this.onMenu,
  });

  final Book book;
  final BookStore store;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final percent = (book.progress * 100).round();
    return GestureDetector(
      onLongPress: onMenu,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .13),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book),
                  // 底部信息条
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!book.generatedCover) ...[
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            book.author.isEmpty ? '佚名' : book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: book.progress,
                                    minHeight: 4,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: .25,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Color(0xFFFFB7C5),
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                book.finished ? '读完' : '$percent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (book.finished)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF9BE89B),
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小图模式卡片：封面 + 单行书名 + 进度条（紧凑，一屏更多书）。
class _CompactBookCard extends StatelessWidget {
  const _CompactBookCard({
    required this.book,
    required this.onOpen,
    required this.onMenu,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onMenu,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .13),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCover(book: book),
                        if (book.finished)
                          const Positioned(
                            top: 5,
                            right: 5,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF9BE89B),
                              size: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: book.progress,
                  minHeight: 3.5,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表模式条目：小封面 + 书名 / 副标题 + 进度，信息密度最高。
class _BookListTile extends StatelessWidget {
  const _BookListTile({
    required this.book,
    required this.subtitle,
    required this.onOpen,
    required this.onMenu,
  });

  final Book book;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: onOpen,
      child: GestureDetector(
        onLongPress: onMenu,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 66,
              child: BookCover(book: book, radius: 10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: book.progress,
                            minHeight: 4,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        book.finished ? '读完' : book.progressLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              tooltip: '更多',
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: .85),
            scheme.secondary.withValues(alpha: .85),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _ShelfSearchDelegate extends SearchDelegate<void> {
  _ShelfSearchDelegate(this.store, this.sourceStore, this.prefs, this.onOpen);

  final BookStore store;
  final SourceStore sourceStore;
  final AppPrefs prefs;
  final void Function(Book book) onOpen;

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    onPressed: () => close(context, null),
  );

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: '在线搜书',
      icon: const Icon(Icons.travel_explore_rounded),
      onPressed: () {
        // 携带当前关键词跳到在线搜索（书架搜索会保留在下层，返回即可切回）
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceSearchPage(
              store: sourceStore,
              bookStore: store,
              prefs: prefs,
              initialQuery: query.trim(),
            ),
          ),
        );
      },
    ),
    if (query.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    final items = store.books
        .where(
          (b) =>
              q.isEmpty ||
              b.title.toLowerCase().contains(q) ||
              b.author.toLowerCase().contains(q),
        )
        .toList();
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到',
        subtitle: '换个关键词试试？',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final book = items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 44,
            height: 60,
            child: BookCover(book: book, radius: 10),
          ),
          title: Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${book.formatLabel} · ${book.chapterCount} 章'
            '${book.author.isEmpty ? '' : ' · ${book.author}'}',
          ),
          onTap: () {
            close(context, null);
            onOpen(book);
          },
        );
      },
    );
  }
}
