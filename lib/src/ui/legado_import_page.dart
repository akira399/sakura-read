import 'dart:io';

import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/legado_import.dart';
import '../data/prefs.dart';
import '../source/source_store.dart';
import 'source/source_manager_page.dart';
import 'widgets/cute.dart';

/// 「从『阅读』导入书架」页：读 legado 备份 json → 按书名在本地书源重新匹配 → 入架。
///
/// legado 的备份里只有书目和进度（没有正文），所以导入的本质是「照着清单
/// 在本机书源里重搜一遍」。这一步要联网、还挺慢，页面用进度条和当前书名
/// 让用户知道它在动，而不是卡死。
class LegadoImportPage extends StatefulWidget {
  const LegadoImportPage({
    super.key,
    required this.prefs,
    required this.shelf,
    required this.sources,
  });

  /// 与设置页其它子页保持一致的构造参数。
  ///
  /// 本页暂时没有需要持久化的偏好（导入是一次性任务），保留它是为了以后
  /// 想记住「上次用的备份路径」时不用回头改所有调用点。
  final AppPrefs prefs;
  final BookStore shelf;
  final SourceStore sources;

  @override
  State<LegadoImportPage> createState() => _LegadoImportPageState();
}

class _LegadoImportPageState extends State<LegadoImportPage> {
  final TextEditingController _pathCtrl = TextEditingController();

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _current = '';
  LegadoImportResult? _result;
  String? _error;

  /// 书源列表可能在「书源管理」里被改，空/非空要跟着变，按钮才能正确禁用。
  bool get _sourceEmpty => widget.sources.enabled.isEmpty;

  @override
  void initState() {
    super.initState();
    widget.sources.addListener(_onSourcesChanged);
  }

  @override
  void dispose() {
    widget.sources.removeListener(_onSourcesChanged);
    _pathCtrl.dispose();
    super.dispose();
  }

  void _onSourcesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canStart = !_running && !_sourceEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('从『阅读』导入书架'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _introCard(context),
          const SizedBox(height: 14),
          _formCard(context, canStart: canStart),
          if (_running) ...[const SizedBox(height: 14), _progressCard(context)],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorCard(context),
          ],
          if (_result != null) ...[
            const SizedBox(height: 14),
            _resultCard(context),
          ],
        ],
      ),
    );
  }

  Widget _introCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = TextStyle(
      fontSize: 12,
      height: 1.6,
      color: scheme.onSurfaceVariant,
    );
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.auto_stories_rounded,
            title: '把「阅读」里的书搬过来',
          ),
          const SizedBox(height: 6),
          Text('① 先在「阅读」里导出书架 JSON 或含 bookshelf.json 的备份 ZIP。', style: body),
          Text('② 把导出的 JSON 或备份 ZIP 路径填到下面，点「开始导入」。', style: body),
          Text('③ 本 App 会拿书名去你已导入的书源里重新找书、抓目录，再放进书架，阅读进度也一起带过来。', style: body),
          const SizedBox(height: 4),
          Text(
            '正文不会复制过来，导入后需要联网读；个别搜不到的书会列在失败里，不影响其它书。',
            style: body.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _formCard(BuildContext context, {required bool canStart}) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.file_open_rounded, title: '备份文件路径'),
          const SizedBox(height: 4),
          Text(
            '一般就在 Download 目录，文件名类似 legado_backup_2026-10-27.json',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pathCtrl,
            enabled: !_running,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '例如 /storage/emulated/0/Download/legado_backup.json',
              hintStyle: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.folder_open_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _running ? null : _autoFillBackup,
              icon: const Icon(Icons.search_rounded, size: 16),
              label: const Text(
                '自动查找 Download 里的备份',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_sourceEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '还没有导入书源，先去『书源管理』导入',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
            const SizedBox(height: 2),
            TextButton.icon(
              onPressed: _running ? null : _openSourceManager,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('去书源管理', style: TextStyle(fontSize: 12)),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canStart ? _startImport : null,
              icon: const Icon(Icons.shelves, size: 18),
              label: Text(_running ? '导入中…' : '开始导入'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _total;
    // 备份还没读完时 total 是 0：用不确定进度条，避免看起来像卡在 0%。
    final value = total <= 0
        ? null
        : (_done / total).clamp(0.0, 1.0).toDouble();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.downloading_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                total <= 0 ? '正在读备份…' : '正在导入 $_done / $total',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (_current.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '正在处理《$_current》',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '要联网搜书 + 抓目录，一本一本慢慢来～',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context) {
    final result = _result!;
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.celebration_rounded, title: '导入完成'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _stat('成功', result.imported, scheme.primary),
              _stat('已存在', result.skipped, scheme.onSurfaceVariant),
              _stat('失败', result.failed, scheme.error),
            ],
          ),
          if (result.failures.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '全都安排好了，去书架看看吧～',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            )
          else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              // 卡片里不需要 ExpansionTile 自带的分割线。
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                '失败原因（${result.failures.length} 本）',
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                for (final line in result.failures)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  /// 常见备份目录。用户手机上的「阅读」备份基本都落在这里。
  static const String _downloadDir = '/storage/emulated/0/Download';

  /// 在 Download 里找最像 legado 备份的 json（文件名带 legado / backup，取最新一个）。
  ///
  /// 让用户手打一长串路径很容易出错，网络上也拿不到「文件选择器」的能力，
  /// 所以退一步：自己扫目录，找到就直接填进输入框。
  static Future<File?> findBackupInDownload() async {
    final dir = Directory(_downloadDir);
    if (!await dir.exists()) return null;
    final candidates = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (!name.endsWith('.json')) continue;
      if (!name.contains('legado') && !name.contains('backup')) continue;
      candidates.add(entity);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final ta = a.statSync().modified;
      final tb = b.statSync().modified;
      return tb.compareTo(ta);
    });
    return candidates.first;
  }

  Future<void> _autoFillBackup() async {
    final found = await findBackupInDownload();
    if (!mounted) return;
    if (found == null) {
      setState(() => _error = 'Download 里没找到备份 json，手动填一下完整路径吧～');
      return;
    }
    _pathCtrl.text = found.path;
    _pathCtrl.selection = TextSelection.collapsed(offset: found.path.length);
    setState(() => _error = null);
  }

  void _openSourceManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceManagerPage(store: widget.sources),
      ),
    );
  }

  Future<void> _startImport() async {
    var path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      // 没填先自己找一次，别让用户对着输入框发呆。
      final found = await findBackupInDownload();
      if (!mounted) return;
      if (found == null) {
        setState(() => _error = '先填一下备份文件的路径吧～（Download 里也没找到）');
        return;
      }
      path = found.path;
      _pathCtrl.text = path;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _done = 0;
      _total = 0;
      _current = '';
      _result = null;
      _error = null;
    });

    final read = await LegadoImporter.readBackupFile(path);
    if (!mounted) return;
    if (read.error != null) {
      setState(() {
        _running = false;
        _error = read.error;
      });
      return;
    }
    final total = read.books.length;
    setState(() => _total = total);

    final result = await const LegadoImporter().importBooks(
      books: read.books,
      shelf: widget.shelf,
      sources: widget.sources,
      onProgress: (done, total, title) {
        // 导入是长任务，用户可能中途退出页面；回调里必须自己挡一下。
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
          _current = title;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
      _done = total;
      _current = '';
    });
  }
}
