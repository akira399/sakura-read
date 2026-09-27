// 书源管理：列表 / 启用开关 / 批量管理 / 详情（访问・复制・删除）/ 导入导出。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../source/http_client.dart';
import '../../source/models.dart';
import '../../source/source_export.dart';
import '../../source/source_store.dart';
import '../../util/format.dart';
import '../folder_picker_page.dart';
import '../widgets/cute.dart';
import '../../platform/url_launcher.dart';

class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({super.key, required this.store});

  final SourceStore store;

  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends State<SourceManagerPage> {
  SourceStore get store => widget.store;

  /// 批量管理模式：非空表示正在多选（值为已选书源 URL）。
  final Set<String> _selected = {};
  bool _bulkMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final sources = store.sources;
          if (sources.isEmpty) {
            return _EmptyView(onImport: () => _showImportSheet(context));
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(12, 8, 12, _bulkMode ? 100 : 40),
            itemCount: sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (context, i) => _buildTile(context, sources[i]),
          );
        },
      ),
      bottomNavigationBar: _bulkMode ? _bulkBar(context) : null,
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    if (_bulkMode) {
      final allSelected = _selected.length == store.sources.length;
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '退出批量管理',
          onPressed: () => setState(() {
            _bulkMode = false;
            _selected.clear();
          }),
        ),
        title: Text('已选 ${_selected.length} / ${store.sources.length}'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(store.sources.map((s) => s.bookSourceUrl));
              }
            }),
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('书源管理'),
      actions: [
        IconButton(
          tooltip: '批量管理',
          onPressed: () => setState(() {
            _bulkMode = true;
            _selected.clear();
          }),
          icon: const Icon(Icons.checklist_rounded),
        ),
        IconButton(
          tooltip: '导出书源',
          onPressed: () => _export(context),
          icon: const Icon(Icons.ios_share_rounded),
        ),
        IconButton(
          tooltip: '导入书源',
          onPressed: () => _showImportSheet(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, BookSource s) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = _selected.contains(s.bookSourceUrl);
    return Card(
      elevation: 0,
      color: chosen
          ? scheme.primary.withValues(alpha: .12)
          : scheme.surfaceContainerHighest.withValues(alpha: .45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: _bulkMode
            ? Icon(
                chosen
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: chosen ? scheme.primary : scheme.onSurfaceVariant,
              )
            : CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: .18),
                child: Text(
                  s.bookSourceName.characters.first,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
        title: Text(
          s.bookSourceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            _hostOf(s.bookSourceUrl),
            if ((s.bookSourceGroup ?? '').isNotEmpty) s.bookSourceGroup!,
            if (s.searchUrl == null) '（未配置搜索）',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _bulkMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: s.enabled,
                    onChanged: (v) => store.setEnabled(s.bookSourceUrl, v),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    onPressed: () => _confirmDelete(
                      context,
                      s.bookSourceUrl,
                      s.bookSourceName,
                    ),
                  ),
                ],
              ),
        onTap: () {
          if (_bulkMode) {
            setState(() {
              if (chosen) {
                _selected.remove(s.bookSourceUrl);
              } else {
                _selected.add(s.bookSourceUrl);
              }
            });
          } else {
            _showDetail(context, s.bookSourceUrl);
          }
        },
        onLongPress: () {
          if (!_bulkMode) {
            setState(() {
              _bulkMode = true;
              _selected
                ..clear()
                ..add(s.bookSourceUrl);
            });
          }
        },
      ),
    );
  }

  /// 底部批量操作栏：启用 / 停用 / 删除（作用于已选条目）。
  Widget _bulkBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _selected.isNotEmpty;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? () => _bulkSetEnabled(true) : null,
                icon: const Icon(Icons.toggle_on_rounded, size: 20),
                label: const Text('启用'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? () => _bulkSetEnabled(false) : null,
                icon: const Icon(Icons.toggle_off_rounded, size: 20),
                label: const Text('停用'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: enabled ? () => _bulkDelete() : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                label: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _bulkSetEnabled(bool value) {
    final n = store.setEnabledAll(_selected, value);
    _snack(value ? '已启用 $n 个书源' : '已停用 $n 个书源');
    setState(_selected.clear);
  }

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除已选的 $count 个书源吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = store.removeMany(_selected);
    setState(() {
      _selected.clear();
      // 删空后自动退出批量模式
      if (store.sources.isEmpty) _bulkMode = false;
    });
    _snack('已删除 $n 个书源');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  /// 书源详情（底部弹层）：完整信息 + 单源操作（访问 / 复制 / 删除）。
  void _showDetail(BuildContext context, String url) {
    final s = store.byUrl(url);
    if (s == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.bookSourceName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.enabled ? '已启用' : '已停用',
                style: TextStyle(
                  fontSize: 12,
                  color: s.enabled
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              _kv(ctx, '地址', s.bookSourceUrl),
              if ((s.bookSourceGroup ?? '').isNotEmpty)
                _kv(ctx, '分组', s.bookSourceGroup!),
              _kv(ctx, '搜索', s.searchUrl ?? '（未配置）'),
              _kv(ctx, '并发率', s.concurrentRate ?? '不限'),
              _kv(ctx, '评论', s.bookSourceComment ?? '（无）'),
              const SizedBox(height: 12),
              // ---- 单源操作 ----
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await launchUrlString(s.bookSourceUrl);
                      if (!ctx.mounted || ok) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('没有找到可用的浏览器')),
                      );
                    },
                    icon: const Icon(Icons.public_rounded, size: 18),
                    label: const Text('访问网站'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.bookSourceUrl));
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(const SnackBar(content: Text('地址已复制')));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制地址'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      store.setEnabled(s.bookSourceUrl, !s.enabled);
                      Navigator.pop(ctx);
                    },
                    icon: Icon(
                      s.enabled
                          ? Icons.toggle_off_rounded
                          : Icons.toggle_on_rounded,
                      size: 18,
                    ),
                    label: Text(s.enabled ? '停用' : '启用'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDelete(ctx, s.bookSourceUrl, s.bookSourceName);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext ctx, String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            k,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(v, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
  );

  Future<void> _confirmDelete(
    BuildContext context,
    String url,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定删除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) store.remove(url);
  }

  // ---------- 导入 / 导出 ----------

  /// 导出全部书源。
  ///
  /// 小数据（≤ 200KB）复制到剪贴板；更大的数据（书源很多时 JSON 可达数 MB，
  /// 超出 Android 剪贴板 ~1MB 上限）自动保存为文件。无论成败都有明确提示
  /// （旧实现把大 JSON 塞剪贴板抛异常、且无捕获 → 点击"没反应"）。
  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (store.sources.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('还没有书源可导出')));
      return;
    }
    final json = store.exportJson();
    try {
      final result = await exportSourcesJson(
        json,
        copyToClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
      );
      final text = result.savedToFile
          ? '书源较多（${formatBytes(result.byteLength)}），'
                '已保存到文件：\n${result.path}'
          : '已复制全部书源 JSON 到剪贴板';
      messenger.showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  void _showImportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '导入书源',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('粘贴导入'),
              subtitle: const Text('支持阅读 3.0 格式的书源 JSON（数组或单个对象）'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _importFromPaste(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('从文件导入'),
              subtitle: const Text('选择 .json / .txt 文件'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _importFromFile(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('从订阅链接导入'),
              subtitle: const Text('从网络地址获取书源 JSON'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _importFromUrl(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _report(BuildContext context, SourceImportReport r) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(r.summary)));
  }

  Future<void> _importFromPaste(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴书源 JSON'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '在此粘贴书源 JSON…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    _report(context, store.importFromText(text));
  }

  Future<void> _importFromFile(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        // 用「书源文件」模式：书源是 .json（该模式同时允许 .txt）
        builder: (_) => const FolderPickerPage(mode: PickerMode.sourceFiles),
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    // 支持多选：逐个导入并合并统计（选择器允许一次选多个文件）
    var added = 0, updated = 0, invalid = 0;
    String? error;
    for (final path in picked) {
      final r = await store.importFromFile(path);
      added += r.added;
      updated += r.updated;
      invalid += r.invalid;
      error ??= r.error;
    }
    if (!context.mounted) return;
    _report(
      context,
      SourceImportReport(
        added: added,
        updated: updated,
        invalid: invalid,
        // 至少导入成功过就不展示错误（个别文件失败由 invalid 计数体现）
        error: added + updated > 0 ? null : error,
      ),
    );
  }

  Future<void> _importFromUrl(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从订阅链接导入'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://…（书源 JSON 的直链）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('获取'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在获取订阅…')));
    try {
      final resp = await SourceHttpClient().get(
        url,
        timeout: const Duration(seconds: 20),
        retries: 1,
      );
      if (!resp.ok) throw SourceHttpException('HTTP ${resp.statusCode}');
      final report = store.importFromText(resp.body);
      messenger.showSnackBar(SnackBar(content: Text(report.summary)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('获取失败：$e')));
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PetalLogo(size: 64),
            const SizedBox(height: 18),
            const Text(
              '还没有书源',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '导入「阅读 3.0」格式的书源后\n就能在这里一键搜索网络上的小说',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('导入书源'),
            ),
          ],
        ),
      ),
    );
  }
}
