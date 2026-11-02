import 'package:flutter/material.dart';
import '../data/book_store.dart';
import '../data/library_search.dart';
import '../data/prefs.dart';
import 'reader/reader_page.dart';

class LibrarySearchPage extends StatefulWidget {
  const LibrarySearchPage({
    super.key,
    required this.store,
    required this.prefs,
  });
  final BookStore store;
  final AppPrefs prefs;
  @override
  State<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends State<LibrarySearchPage> {
  final _input = TextEditingController();
  final _search = LibrarySearch();
  bool _busy = false;
  List<LibraryMatch> _matches = [];
  String _status = '搜索本地 TXT / EPUB 和已缓存的在线章节；不会上传正文';
  @override
  void dispose() {
    _search.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy || _input.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _matches = [];
      _status = '正在检索…';
    });
    try {
      final matches = await _search.search(
        widget.store,
        _input.text,
        onProgress: (n, total) {
          if (mounted) setState(() => _status = '已检索 $n / $total 本');
        },
      );
      if (mounted) {
        setState(() {
          _matches = matches;
          _status = '找到 ${matches.length} 处（最多显示 100 处）；在线书仅搜索缓存正文';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status = '部分内容无法检索，请检查本地文件');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书籍正文检索')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _input,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              labelText: '输入原文关键词或句子',
              suffixIcon: IconButton(
                tooltip: _busy ? '停止检索' : '检索',
                icon: Icon(_busy ? Icons.stop : Icons.search),
                onPressed: _busy ? _search.cancel : _run,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_status),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _matches.length,
            itemBuilder: (context, i) {
              final match = _matches[i];
              return ListTile(
                title: Text(
                  '《${match.book.title}》· ${match.book.chapters[match.chapter].title}',
                ),
                subtitle: Text(match.excerpt),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderPage(
                      store: widget.store,
                      prefs: widget.prefs,
                      bookId: match.book.id,
                      chapterIndex: match.chapter,
                      charOffset: match.offset,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
