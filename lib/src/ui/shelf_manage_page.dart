import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/models.dart';
import '../data/prefs.dart';

/// 批量管理书架：多选删除 + 自定义分组。
///
/// 用户反馈：
/// - 「书架里的书籍可以批量删除吗？或者全选、部分选中部分删除？」
/// - 「书架可不可以设置批量删除图书」
/// - 「书架里的书籍可以分组吗自定义分组」
///
/// 为什么单独一页：书架卡片有四种样式，直接在卡片上叠多选遮罩会牵动
/// 四种布局；集中到一页用 CheckboxListTile，逻辑更清楚也不会误触。
class ShelfManagePage extends StatefulWidget {
  const ShelfManagePage({super.key, required this.store, required this.prefs});

  final BookStore store;
  final AppPrefs prefs;

  @override
  State<ShelfManagePage> createState() => _ShelfManagePageState();
}

class _ShelfManagePageState extends State<ShelfManagePage> {
  final Set<String> _selected = <String>{};

  List<Book> get _books => widget.store.books;

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _books.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_books.map((b) => b.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    var deleteFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            '删除 ${_selected.length} 本书？',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '只从书架移除，书籍文件保留在手机里，随时可以再导入。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteFile,
                onChanged: (v) => setDialogState(() => deleteFile = v ?? false),
                title: const Text('同时删除本地文件', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  '删除后书籍文件也会从手机里删掉，无法恢复',
                  style: TextStyle(fontSize: 11.5),
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
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final ids = _selected.toList();
    for (final id in ids) {
      await widget.store.removeById(id, deleteLocalFile: deleteFile);
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 ${ids.length} 本书')));
  }

  Future<void> _moveSelected() async {
    if (_selected.isEmpty) return;
    final groups = <String>{
      for (final b in _books)
        if (b.group.isNotEmpty) b.group,
    }.toList()..sort();
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          '把 ${_selected.length} 本书移到分组',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '输入分组名（留空 = 取消分组）'),
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
    if (result == null || !mounted) return;
    final ids = _selected.toList();
    for (final id in ids) {
      widget.store.setGroup(id, result);
    }
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.trim().isEmpty ? '已取消分组' : '已移到「${result.trim()}」',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final books = _books;
        final allSelected =
            books.isNotEmpty && _selected.length == books.length;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selected.isEmpty ? '批量管理' : '已选 ${_selected.length} 本',
            ),
            actions: [
              TextButton(
                onPressed: books.isEmpty ? null : _selectAll,
                child: Text(allSelected ? '取消全选' : '全选'),
              ),
            ],
          ),
          body: books.isEmpty
              ? const Center(child: Text('书架是空的'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
                    final on = _selected.contains(book.id);
                    return ListTile(
                      selected: on,
                      onTap: () => _toggle(book.id),
                      leading: Checkbox(
                        value: on,
                        onChanged: (_) => _toggle(book.id),
                      ),
                      title: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        [
                          if (book.group.isNotEmpty) book.group,
                          book.formatLabel,
                          '${book.chapterCount} 章',
                          '已读 ${book.progressLabel}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selected.isEmpty ? null : _moveSelected,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('移动到分组'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _selected.isEmpty
                            ? scheme.surfaceContainerHighest
                            : Colors.redAccent,
                      ),
                      onPressed: _selected.isEmpty ? null : _deleteSelected,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
