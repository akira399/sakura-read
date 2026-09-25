// 书源管理：列表 / 启用开关 / 删除 / 导入（粘贴・文件・订阅链接）/ 导出。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../source/http_client.dart';
import '../../source/source_store.dart';
import '../folder_picker_page.dart';
import '../widgets/cute.dart';

class SourceManagerPage extends StatelessWidget {
  const SourceManagerPage({super.key, required this.store});

  final SourceStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源管理'),
        actions: [
          IconButton(
            tooltip: '导出（复制到剪贴板）',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: store.exportJson()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制全部书源 JSON 到剪贴板')),
                );
              }
            },
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '导入书源',
            onPressed: () => _showImportSheet(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final sources = store.sources;
          if (sources.isEmpty) {
            return _EmptyView(onImport: () => _showImportSheet(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
            itemCount: sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (context, i) {
              final s = sources[i];
              return Card(
                elevation: 0,
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .18),
                    child: Text(
                      s.bookSourceName.characters.first,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
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
                      if ((s.bookSourceGroup ?? '').isNotEmpty)
                        s.bookSourceGroup!,
                      if (s.searchUrl == null) '（未配置搜索）',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.enabled,
                        onChanged: (v) => store.setEnabled(s.bookSourceUrl, v),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        onPressed: () => _confirmDelete(
                          context,
                          s.bookSourceUrl,
                          s.bookSourceName,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _showDetail(context, i),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  void _showDetail(BuildContext context, int index) {
    final s = store.sources[index];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
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
              const SizedBox(height: 8),
              _kv('地址', s.bookSourceUrl),
              if ((s.bookSourceGroup ?? '').isNotEmpty)
                _kv('分组', s.bookSourceGroup!),
              _kv('并发率', s.concurrentRate ?? '不限'),
              _kv('评论', (s.bookSourceComment ?? '（无）')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            k,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
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

  // ---------- 导入 ----------

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
