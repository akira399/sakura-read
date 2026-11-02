import 'package:flutter/material.dart';
import '../../source/online_repo.dart';
import '../../source/source_store.dart';

class SourceHealthPage extends StatefulWidget {
  const SourceHealthPage({super.key, required this.store});
  final SourceStore store;
  @override
  State<SourceHealthPage> createState() => _SourceHealthPageState();
}

class _SourceHealthPageState extends State<SourceHealthPage> {
  late final _repo = OnlineRepo(
    store: widget.store,
    concurrency: 4,
    perSourceTimeout: const Duration(seconds: 10),
  );
  final _query = TextEditingController(text: '西游记');
  final _results = <SourceSearchResult>[];
  bool _running = false;
  @override
  void dispose() {
    _repo.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running || _query.text.trim().isEmpty) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    await _repo.searchAll(
      _query.text.trim(),
      onSourceDone: (result) {
        if (mounted) setState(() => _results.add(result));
      },
    );
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书源体检')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('按关键词测试已启用书源。空结果不等于失效；不会自动删除或停用任何书源。'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(labelText: '测试书名 / 作者'),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: _running ? null : _run,
              child: const Text('开始体检'),
            ),
            TextButton(
              onPressed: _running ? _repo.cancel : null,
              child: const Text('停止'),
            ),
            Text('已完成 ${_results.length}/${widget.store.enabledCount}'),
          ],
        ),
        if (_running) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final result = _results[i];
              return ListTile(
                leading: Icon(
                  result.ok ? Icons.check_circle_outline : Icons.error_outline,
                ),
                title: Text(result.source.bookSourceName),
                subtitle: Text(
                  result.error ??
                      '返回 ${result.books.length} 本 · ${result.elapsedMs} ms',
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
