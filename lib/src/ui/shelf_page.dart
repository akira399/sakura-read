import 'library_search_page.dart';
import 'legado_import_page.dart';

import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/icons/sakura_icons.dart';
import '../core/motion/sakura_motion.dart';
import '../core/theme/sakura_layout.dart';
import '../core/theme/sakura_tokens.dart';
import '../data/book_store.dart';
import '../data/file_scan.dart';
import '../data/models.dart';
import '../data/pet_guide.dart';
import '../data/prefs.dart';
import '../data/shelf_sort.dart';
import '../data/stats_store.dart';
import '../features/bookshelf/widgets/book_grid_card.dart';
import '../features/bookshelf/widgets/book_list_tile.dart';
import '../features/bookshelf/widgets/continue_reading_card.dart';
import '../features/bookshelf/widgets/shelf_backdrop.dart';
import '../features/bookshelf/widgets/shelf_group_bar.dart';
import '../features/bookshelf/widgets/shelf_header.dart';
import '../features/bookshelf/widgets/shelf_plank.dart';
import '../platform/native_bridge.dart';
import '../source/source_store.dart';
import '../util/format.dart';
import 'ai_chat_page.dart';
import 'book_detail_page.dart';
import 'folder_picker_page.dart';
import 'reader/reader_page.dart';
import 'shelf_manage_page.dart';
import 'source/source_search_page.dart';
import 'widgets/book_cover.dart';
import 'widgets/cute.dart';
import 'widgets/kanban_mascot.dart';
import 'widgets/pet_guide_overlay.dart';
import 'widgets/sakura_petals.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.sourceStore,
    this.statsStore,
  });

  final BookStore store;
  final AppPrefs prefs;
  final SourceStore sourceStore;

  /// 阅读统计（AI 助手用来总结阅读习惯；测试里可以没有）。
  final StatsStore? statsStore;

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  /// 底栏（NavigationBar 80 + 间距）占的高度：加号按钮要让出这一段。
  static const double _navBarClearance = 96;

  /// 当前分组筛选：null = 全部，'' = 未分组，其余为分组名。
  String? _groupFilter;

  /// 空书架的看板娘台词。
  static const _emptyShelfLines = [
    '书架上还空着哦',
    '点右下角的＋导入你的书吧',
    'TXT 和 EPUB 都可以的',
    '要一起等一本书到来吗？',
    '嘘……在等你的故事呢',
    '先放一本书进来，好不好？',
  ];

  @override
  void initState() {
    super.initState();
    kPetGuideStepId.addListener(_onGuideStepForSearch);
  }

  @override
  void dispose() {
    kPetGuideStepId.removeListener(_onGuideStepForSearch);
    super.dispose();
  }

  /// 引导走到「搜索页」那一步时，替用户把搜索面板打开。
  ///
  /// 引导遮罩会吃掉放大镜的点击（遮罩要推进步骤，不能同时把点击透下去），
  /// 于是「点一下这个放大镜」只会让对话前进，搜索页并不会真的打开，
  /// 下一步就会停在书架上说「这里就是搜索页」。这里由引导驱动打开，
  /// 用户看到的就是真实的搜索页，返回箭头也是真实可点的。
  void _onGuideStepForSearch() {
    if (kPetGuideStepId.value != 'search_return' || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || kPetGuideStepId.value != 'search_return') return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _openSearch(context);
    });
  }

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
        final allBooks = widget.store.books.toList();
        _sortBooks(allBooks);
        final books = _groupFilter == null
            ? allBooks
            : allBooks.where((b) => b.group == _groupFilter).toList();
        final continueBook = _groupFilter == null
            ? _latestReadBook(allBooks)
            : null;
        final activeBook =
            continueBook ?? (books.isNotEmpty ? books.first : null);
        final singleBookSpotlight =
            continueBook != null &&
            books.length == 1 &&
            _groupFilter == null &&
            books.first.id == continueBook.id;
        final prefs = widget.prefs;
        final isWide = SakuraLayout.isWide(context);
        final hInsets = SakuraLayout.horizontalInsets(context);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final contentAvailWidth = min(
          screenWidth - hInsets.horizontal,
          SakuraLayout.contentMaxWidth,
        ).clamp(240.0, SakuraLayout.contentMaxWidth);
        final extraCenterPad = max(
          0.0,
          (screenWidth - hInsets.horizontal - SakuraLayout.contentMaxWidth) / 2,
        );
        final sliverHPadLeft = hInsets.left + extraCenterPad;
        final sliverHPadRight = hInsets.right + extraCenterPad;
        final bottomClearance = MediaQuery.paddingOf(context).bottom + 110;
        final hasPlank =
            prefs.shelfPlankStyle == ShelfPlankStyle.frostedGlass ||
            prefs.shelfPlankStyle == ShelfPlankStyle.warmWood;

        return Scaffold(
          // 底栏用 extendBody 盖在正文上，Scaffold 感知不到它的高度：
          // 默认 endFloat 会把「＋」摆进底栏区域，正好压住最右侧的「设置」，
          // 导致点不到加号、还容易误跳设置（线上反馈）。这里显式抬高一段。
          floatingActionButton: Padding(
            padding: EdgeInsets.only(
              bottom: _navBarClearance,
              right: MediaQuery.paddingOf(context).right,
            ),
            child: PetGuideTarget(
              id: 'shelf_add',
              child: FloatingActionButton(
                // 显式 heroTag：书架与设置页的 FAB 同时在 IndexedStack 里存活，
                // 使用默认 tag 会在路由切换（Hero 动画扫描）时冲突
                heroTag: 'shelf-add-fab',
                onPressed: () => _showAddSheet(context),
                tooltip: '导入书籍',
                child: const SakuraIcon(
                  glyph: SakuraGlyph.addBook,
                  color: Colors.white,
                  accent: Color(0xFFFFDCE8),
                  size: 24,
                ),
              ),
            ),
          ),
          body: ShelfBackdrop(
            visualStyle: prefs.visualStyle,
            ambientAura: prefs.ambientCoverAura,
            showPetals: prefs.shelfSakuraPetals,
            activeBook: activeBook,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ShelfHeader(
                    greeting: _headerLine,
                    bookCount: books.length,
                    visualStyle: prefs.visualStyle,
                    activeBook: activeBook,
                    onAiTap: () => Navigator.of(context).push(
                      SakuraPageRoute(
                        slideHorizontal: true,
                        builder: (_) => AiChatPage(
                          store: widget.store,
                          prefs: widget.prefs,
                          statsStore: widget.statsStore,
                        ),
                      ),
                    ),
                    onSearchTap: () => _openSearch(context),
                    onArrangeTap: _showArrangeSheet,
                    onManageTap: _openManage,
                  ),
                ),
                if (continueBook != null && !(singleBookSpotlight && isWide))
                  SliverToBoxAdapter(
                    child: Center(
                      heightFactor: 1.0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              SakuraLayout.contentMaxWidth + hInsets.horizontal,
                        ),
                        child: ContinueReadingCard(
                          book: continueBook,
                          visualStyle: prefs.visualStyle,
                          plankStyle: prefs.shelfPlankStyle,
                          silkBookmarkAndStamp: prefs.silkBookmarkAndStamp,
                          margin: EdgeInsets.fromLTRB(
                            hInsets.left,
                            14,
                            hInsets.right,
                            4,
                          ),
                          onContinue: () => _continueReading(continueBook),
                          onOpenDetail: () => _openDetail(continueBook),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Center(
                    heightFactor: 1.0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            SakuraLayout.contentMaxWidth + hInsets.horizontal,
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: max(0.0, hInsets.left - 16),
                          right: max(0.0, hInsets.right - 16),
                        ),
                        child: ShelfGroupBar(
                          allBooks: allBooks,
                          selectedGroup: _groupFilter,
                          visualStyle: prefs.visualStyle,
                          onSelectGroup: (group) =>
                              setState(() => _groupFilter = group),
                        ),
                      ),
                    ),
                  ),
                ),
                if (books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: widget.store.isLoading
                        ? const SizedBox.shrink()
                        : _buildEmpty(context),
                  )
                else if (singleBookSpotlight && isWide)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sliverHPadLeft,
                      14,
                      sliverHPadRight,
                      bottomClearance,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 11,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ContinueReadingCard(
                                  book: continueBook,
                                  visualStyle: prefs.visualStyle,
                                  plankStyle: prefs.shelfPlankStyle,
                                  silkBookmarkAndStamp:
                                      prefs.silkBookmarkAndStamp,
                                  margin: EdgeInsets.zero,
                                  onContinue: () =>
                                      _continueReading(continueBook),
                                  onOpenDetail: () => _openDetail(continueBook),
                                ),
                                if (hasPlank) ...[
                                  const SizedBox(height: 10),
                                  ShelfPlank(style: prefs.shelfPlankStyle),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 10,
                            child: _buildSingleBookShelfInvitation(
                              context,
                              prefs,
                              showPlank: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (singleBookSpotlight)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sliverHPadLeft,
                      14,
                      sliverHPadRight,
                      bottomClearance,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _buildSingleBookShelfInvitation(
                        context,
                        prefs,
                        showPlank: hasPlank,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sliverHPadLeft,
                      12,
                      sliverHPadRight,
                      bottomClearance,
                    ),
                    sliver: _buildBooksSliver(
                      books,
                      availWidth: contentAvailWidth,
                      isWide: isWide,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleBookShelfInvitation(
    BuildContext context,
    AppPrefs prefs, {
    required bool showPlank,
  }) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPlank) ...[
          ShelfPlank(style: prefs.shelfPlankStyle),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sakura.card.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sakura.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SakuraIconBadge(
                    glyph: SakuraGlyph.addBook,
                    color: accent,
                    size: 36,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '书架还有充裕的藏书空间',
                          style: TextStyle(
                            color: sakura.inkPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '导入本地 TXT / EPUB，或通过阅读 3.0 书源在线淘书',
                          style: TextStyle(
                            color: sakura.inkSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickFiles(),
                      icon: const Icon(Icons.upload_file_rounded, size: 17),
                      label: const Text('导入新书'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        SakuraPageRoute(
                          slideHorizontal: true,
                          builder: (_) => SourceSearchPage(
                            store: widget.sourceStore,
                            bookStore: widget.store,
                            prefs: widget.prefs,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.travel_explore_rounded, size: 17),
                      label: const Text('在线搜书'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 按当前「排列方式」渲染书架（网格 / 小图 / 列表 / 大封面）。
  Widget _buildBooksSliver(
    List<Book> books, {
    required double availWidth,
    required bool isWide,
  }) {
    final prefs = widget.prefs;
    final usePlankRows =
        prefs.shelfPlankStyle == ShelfPlankStyle.frostedGlass ||
        prefs.shelfPlankStyle == ShelfPlankStyle.warmWood;
    final width = MediaQuery.sizeOf(context).width;

    switch (prefs.shelfView) {
      case ShelfViewMode.grid:
        final cols = width >= 900
            ? 5
            : width >= 620
            ? 4
            : 3;
        if (usePlankRows) {
          return _buildPlankedRowsSliver(
            books: books,
            columns: cols,
            gap: 14,
            aspectRatio: 0.52,
            compact: false,
            coverEmphasized: false,
            availWidth: availWidth,
          );
        }
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 156,
            mainAxisSpacing: 16,
            crossAxisSpacing: 14,
            childAspectRatio: .54,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => StaggeredReveal(
              index: index,
              child: BookGridCard(
                book: books[index],
                plankStyle: prefs.shelfPlankStyle,
                visualStyle: prefs.visualStyle,
                onOpen: () => _openDetail(books[index]),
                onMenu: () => _showBookMenu(books[index]),
              ),
            ),
            childCount: books.length,
          ),
        );
      case ShelfViewMode.compact:
        final cols = width >= 900
            ? 6
            : width >= 620
            ? 5
            : 3;
        if (usePlankRows) {
          return _buildPlankedRowsSliver(
            books: books,
            columns: cols,
            gap: 12,
            aspectRatio: 0.56,
            compact: true,
            coverEmphasized: false,
            availWidth: availWidth,
          );
        }
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 112,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .58,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => StaggeredReveal(
              index: index,
              child: BookGridCard(
                book: books[index],
                compact: true,
                plankStyle: prefs.shelfPlankStyle,
                visualStyle: prefs.visualStyle,
                onOpen: () => _openDetail(books[index]),
                onMenu: () => _showBookMenu(books[index]),
              ),
            ),
            childCount: books.length,
          ),
        );
      case ShelfViewMode.list:
        if (isWide) {
          return SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 14,
              mainAxisExtent: 104,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => StaggeredReveal(
                index: index,
                child: BookListTile(
                  book: books[index],
                  subtitle: _bookSubtitle(books[index]),
                  onOpen: () => _openDetail(books[index]),
                  onMenu: () => _showBookMenu(books[index]),
                ),
              ),
              childCount: books.length,
            ),
          );
        }
        return SliverList.separated(
          itemCount: books.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => StaggeredReveal(
            index: index,
            child: BookListTile(
              book: books[index],
              subtitle: _bookSubtitle(books[index]),
              onOpen: () => _openDetail(books[index]),
              onMenu: () => _showBookMenu(books[index]),
            ),
          ),
        );
      case ShelfViewMode.cover:
        final columns = width >= 1100
            ? 6
            : width >= 840
            ? 5
            : width >= 600
            ? 4
            : 3;
        if (usePlankRows) {
          return _buildPlankedRowsSliver(
            books: books,
            columns: columns,
            gap: 16,
            aspectRatio: 0.53,
            compact: false,
            coverEmphasized: true,
            availWidth: availWidth,
          );
        }
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18,
            crossAxisSpacing: 16,
            childAspectRatio: .54,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => StaggeredReveal(
              index: index,
              child: BookGridCard(
                book: books[index],
                coverEmphasized: true,
                plankStyle: prefs.shelfPlankStyle,
                visualStyle: prefs.visualStyle,
                onOpen: () => _openDetail(books[index]),
                onMenu: () => _showBookMenu(books[index]),
              ),
            ),
            childCount: books.length,
          ),
        );
    }
  }

  Widget _buildPlankedRowsSliver({
    required List<Book> books,
    required int columns,
    required double gap,
    required double aspectRatio,
    required bool compact,
    required bool coverEmphasized,
    required double availWidth,
  }) {
    final rowCount = (books.length / columns).ceil();
    final prefs = widget.prefs;
    final colWidth = (availWidth - gap * (columns - 1)) / columns;
    final cardHeight = colWidth / aspectRatio;

    return SliverList.separated(
      itemCount: rowCount,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, rowIndex) {
        final start = rowIndex * columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: start + c < books.length
                        ? SizedBox(
                            height: cardHeight,
                            child: StaggeredReveal(
                              index: start + c,
                              child: BookGridCard(
                                book: books[start + c],
                                compact: compact,
                                coverEmphasized: coverEmphasized,
                                plankStyle: prefs.shelfPlankStyle,
                                visualStyle: prefs.visualStyle,
                                onOpen: () => _openDetail(books[start + c]),
                                onMenu: () => _showBookMenu(books[start + c]),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ShelfPlank(style: prefs.shelfPlankStyle),
          ],
        );
      },
    );
  }

  Book? _latestReadBook(List<Book> books) {
    Book? latest;
    for (final book in books) {
      if (book.lastReadAt <= 0) continue;
      if (latest == null || book.lastReadAt > latest.lastReadAt) {
        latest = book;
      }
    }
    return latest;
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
      manualOrder: widget.prefs.manualShelfOrder,
    );
    if (books.any((b) => b.pinned)) {
      final pinned = [
        for (final b in books)
          if (b.pinned) b,
      ];
      final rest = [
        for (final b in books)
          if (!b.pinned) b,
      ];
      books
        ..clear()
        ..addAll(pinned)
        ..addAll(rest);
    }
  }

  void _openManage() {
    Navigator.of(context).push(
      SakuraPageRoute(
        slideHorizontal: true,
        builder: (_) =>
            ShelfManagePage(store: widget.store, prefs: widget.prefs),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final shortLandscape = SakuraLayout.isShortLandscape(context);
    final bottomClearance =
        MediaQuery.paddingOf(context).bottom + (shortLandscape ? 84 : 104);
    return SakuraPetals(
      count: 16,
      child: EmptyState(
        icon: Icons.auto_stories_outlined,
        illustration: KanbanMascot(
          size: shortLandscape ? 108 : 168,
          lines: _emptyShelfLines,
        ),
        title: '书架还空着呢',
        subtitle: '点击右下角「+」\n导入本地 TXT / EPUB 小说吧',
        bottomClearance: bottomClearance,
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
      SakuraPageRoute(
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
      SakuraBookUnfoldRoute(
        enabled: widget.prefs.bookUnfoldTransition,
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openManage();
                  },
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('批量管理 · 多选删除 / 分组'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
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
                    if (prefs.shelfSort == ShelfSortMode.manual)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _openManualOrderSheet();
                        },
                        icon: const Icon(Icons.drag_handle_rounded, size: 16),
                        label: const Text(
                          '调整顺序',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
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
    ShelfViewMode.cover => Icons.photo_library_rounded,
  };

  String _directionHint(AppPrefs prefs) {
    final name = switch (prefs.shelfSort) {
      ShelfSortMode.recentRead => '最近阅读时间',
      ShelfSortMode.addedTime => '加入书架时间',
      ShelfSortMode.title => '书名字母 / 笔画',
      ShelfSortMode.author => '作者名',
      ShelfSortMode.progress => '阅读进度',
      ShelfSortMode.chars => '全书字数',
      ShelfSortMode.manual => '手动顺序',
    };
    final dir = prefs.shelfAscending ? '从低到高' : '从高到低';
    return prefs.shelfSort == ShelfSortMode.manual
        ? '按$name${prefs.shelfAscending ? '正序' : '倒序'}（可点右侧“调整顺序”拖拽）'
        : '按$name$dir';
  }

  Future<void> _openManualOrderSheet() async {
    final ordered = List<Book>.of(widget.store.books);
    _sortBooks(ordered);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.66,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 14, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator_rounded, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '拖拽调整书架顺序',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.prefs.setManualShelfOrder(
                            ordered.map((b) => b.id).toList(),
                          );
                          Navigator.pop(ctx);
                        },
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: ordered.length,
                    onReorderItem: (oldIdx, newIdx) {
                      setSheetState(() {
                        final item = ordered.removeAt(oldIdx);
                        ordered.insert(newIdx, item);
                      });
                      widget.prefs.setManualShelfOrder(
                        ordered.map((b) => b.id).toList(),
                      );
                    },
                    itemBuilder: (_, i) {
                      final b = ordered[i];
                      return ListTile(
                        key: ValueKey(b.id),
                        leading: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        title: Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: b.author.isEmpty
                            ? null
                            : Text(
                                b.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(Icons.drag_handle_rounded),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              leading: const _SheetIcon(Icons.find_in_page_outlined),
              title: const Text('搜索书籍正文'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibrarySearchPage(
                      store: widget.store,
                      prefs: widget.prefs,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const _SheetIcon(Icons.shuffle),
              title: const Text('随便读一本'),
              subtitle: const Text('从现有书架随机选择，不生成虚构推荐'),
              onTap: () {
                Navigator.pop(sheetContext);
                final books = widget.store.books
                    .where((b) => !b.finished)
                    .toList();
                if (books.isNotEmpty) {
                  _openDetail(books[Random().nextInt(books.length)]);
                }
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
              leading: const _SheetIcon(Icons.move_to_inbox_outlined),
              title: const Text('导入阅读书架备份'),
              subtitle: const Text('bookshelf.json / 备份 ZIP；先导入对应书源'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importLegacy();
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

  Future<void> _importLegacy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegadoImportPage(
          shelf: widget.store,
          sources: widget.sourceStore,
          prefs: widget.prefs,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有找到常见目录，试试手动选择吧')));
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
      // 横屏 / 小屏设备上条目会超出默认高度（曾报 BOTTOM OVERFLOWED），
      // 这里让面板整体可滚动，并允许按内容高度展开。
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
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
                leading: Icon(
                  book.pinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(book.pinned ? '取消置顶' : '置顶书籍'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.store.setPinned(book.id, !book.pinned);
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
                leading: const Icon(Icons.folder_outlined),
                title: Text(book.group.isEmpty ? '设置分组' : '分组：${book.group}'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _setBookGroup(book);
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
      ),
    );
  }

  /// 单本书设置分组：可输入新分组名，也可点已有分组快速归入。
  Future<void> _setBookGroup(Book book) async {
    final groups = <String>{
      for (final b in widget.store.books)
        if (b.group.isNotEmpty) b.group,
    }.toList()..sort();
    final controller = TextEditingController(text: book.group);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '设置分组',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '输入分组名（留空 = 未分组）'),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in groups)
                    ActionChip(
                      label: Text(g, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pop(dialogContext, g),
                    ),
                ],
              ),
            ],
          ],
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
    if (result != null) widget.store.setGroup(book.id, result);
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
    // 只有本地书（TXT / EPUB）才有文件可删；在线书没有本地文件。
    final canDeleteFile = book.format != BookFormat.online;
    var deleteFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            '从书架移除？',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                canDeleteFile
                    ? '「${book.title}」会从书架移除，本地文件默认保留。'
                    : '「${book.title}」会从书架移除。',
                style: const TextStyle(height: 1.5, fontSize: 13.5),
              ),
              if (canDeleteFile)
                // 用户反馈：移除的时候想连本地文件一起删掉
                CheckboxListTile(
                  value: deleteFile,
                  onChanged: (v) =>
                      setDialogState(() => deleteFile = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '同时删除本地文件',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    book.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
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
      ),
    );
    if (ok == true) {
      await widget.store.removeById(book.id, deleteLocalFile: deleteFile);
      if (!mounted || !deleteFile) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已移除并删除「${book.title}」的本地文件')));
    }
  }
}

// ---------- 子组件 ----------

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
  Widget buildLeading(BuildContext context) => PetGuideTarget(
    id: 'search_back',
    child: IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: '返回书架',
      onPressed: () => close(context, null),
    ),
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
