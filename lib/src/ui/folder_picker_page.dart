import 'dart:io';

import 'package:flutter/material.dart';

import '../data/file_scan.dart';
import '../data/natural_sort.dart';
import '../platform/native_bridge.dart';
import 'widgets/cute.dart';

enum PickerMode { files, folder }

/// 内置文件浏览器：多选小说文件，或选择一个文件夹。
class FolderPickerPage extends StatefulWidget {
  const FolderPickerPage({super.key, required this.mode, this.title});

  final PickerMode mode;
  final String? title;

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  Directory? _current;
  List<Directory> _dirs = [];
  List<File> _files = [];
  final Set<String> _selected = {};
  bool _loading = true;
  String? _error;
  late String _root;
  int _openSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _root = await NativeBridge.storageRoot();
    await _open(Directory(_root));
  }

  Future<void> _open(Directory dir) async {
    final seq = ++_openSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirs = <Directory>[];
      final files = <File>[];
      await for (final e in dir.list(followLinks: false)) {
        final name = pathFileName(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          if (isSkippedDirName(name)) continue;
          dirs.add(e);
        } else if (e is File &&
            widget.mode == PickerMode.files &&
            isNovelFile(e.path)) {
          files.add(e);
        }
      }
      dirs.sort(
        (a, b) => naturalCompare(pathFileName(a.path), pathFileName(b.path)),
      );
      files.sort(
        (a, b) => naturalCompare(pathFileName(a.path), pathFileName(b.path)),
      );
      if (!mounted || seq != _openSeq) return;
      setState(() {
        _current = dir;
        _dirs = dirs;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _openSeq) return;
      setState(() {
        _error = '无法访问这个文件夹\n（$e）';
        _loading = false;
      });
    }
  }

  List<String> _breadcrumbs() {
    final cur = _current?.path ?? _root;
    if (cur.length <= _root.length) return const [];
    final rel = cur.substring(_root.length);
    return rel.split('/').where((s) => s.isNotEmpty).toList();
  }

  void _toggle(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _current == null || _current!.path == _root;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _current != null) {
          _open(_current!.parent);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title ??
                (widget.mode == PickerMode.files ? '选择小说文件' : '选择文件夹'),
          ),
        ),
        body: Column(
          children: [
            _buildBreadcrumb(context),
            Expanded(child: _buildBody(context)),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    final crumbs = _breadcrumbs();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          ActionChip(
            label: const Text('内部存储'),
            avatar: Icon(
              Icons.sd_storage_rounded,
              size: 16,
              color: scheme.primary,
            ),
            onPressed: () => _open(Directory(_root)),
          ),
          for (var i = 0; i < crumbs.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.chevron_right_rounded, size: 18),
            ),
            ActionChip(
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(crumbs[i], overflow: TextOverflow.ellipsis),
              ),
              onPressed: () => _open(
                Directory('$_root/${crumbs.sublist(0, i + 1).join('/')}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: '打不开这个文件夹',
        subtitle: error,
        actions: [
          OutlinedButton(
            onPressed: () => _open(_current ?? Directory(_root)),
            child: const Text('重试'),
          ),
        ],
      );
    }
    final current = _current;
    if (current == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];

    if (widget.mode == PickerMode.folder) {
      final selectedHere = _selected.contains(current.path);
      rows.add(
        ListTile(
          leading: Icon(
            selectedHere
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: scheme.primary,
          ),
          title: const Text(
            '选择当前文件夹',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            current.path == _root ? '内部存储' : pathFileName(current.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _toggle(current.path),
        ),
      );
      rows.add(const Divider(height: 1));
    }

    for (final dir in _dirs) {
      final selected = _selected.contains(dir.path);
      rows.add(
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.folder_rounded, color: scheme.primary),
          ),
          title: Text(
            pathFileName(dir.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.mode == PickerMode.folder
              ? Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(dir),
        ),
      );
    }

    for (final file in _files) {
      final selected = _selected.contains(file.path);
      final isEpub = pathExtension(file.path) == 'epub';
      rows.add(
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isEpub ? scheme.secondary : scheme.primary).withValues(
                alpha: .14,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEpub ? Icons.auto_stories_rounded : Icons.description_rounded,
              color: isEpub ? scheme.secondary : scheme.primary,
            ),
          ),
          title: Text(
            pathFileName(file.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${(file.lengthSync() / 1024).toStringAsFixed(0)} KB',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          onTap: () => _toggle(file.path),
        ),
      );
    }

    if (rows.isEmpty) {
      return EmptyState(
        icon: widget.mode == PickerMode.files
            ? Icons.menu_book_outlined
            : Icons.folder_off_rounded,
        title: widget.mode == PickerMode.files ? '这个文件夹里没有小说' : '这里是空的',
        subtitle: widget.mode == PickerMode.files
            ? '进入别的文件夹找找 .txt / .epub 吧'
            : '换个文件夹看看吧',
      );
    }
    return ListView(children: rows);
  }

  Widget _buildBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? (widget.mode == PickerMode.files
                            ? '点击文件选中 · 可多选'
                            : '点击行进入文件夹 · 点圆圈选中')
                      : '已选 ${_selected.length} 项',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  widget.mode == PickerMode.files
                      ? (_selected.isEmpty ? '导入' : '导入 (${_selected.length})')
                      : '选择',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
