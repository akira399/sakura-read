import 'package:flutter/material.dart';

import '../data/book_store.dart';
import '../data/library_search.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import 'reader/reader_page.dart';

class LibrarySearchPage extends StatefulWidget {
  const LibrarySearchPage({
    super.key,
    required this.store,
    required this.prefs,
    this.onlyBook,
    this.returnSelection = false,
  });

  final BookStore store;
  final AppPrefs prefs;

  /// 限定只搜索单本书（如阅读器内「搜本书」）。
  final Book? onlyBook;

  /// 为 true 时点击结果直接返回 `{chapter, offset}` 给调用方跳转。
  final bool returnSelection;

  @override
  State<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends State<LibrarySearchPage> {
  final _input = TextEditingController();
  final _search = LibrarySearch();
  bool _busy = false;
  List<LibraryMatch> _matches = [];
  late String _status = widget.onlyBook != null
      ? '在本书本地正文或已缓存章节中精确检索'
      : '搜索本地 TXT / EPUB 和已缓存的在线章节；不会上传正文';

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
        onlyBook: widget.onlyBook,
        onProgress: (n, total) {
          if (mounted) {
            setState(
              () => _status = widget.onlyBook != null
                  ? '正在检索全书章节…'
                  : '已检索 $n / $total 本',
            );
          }
        },
      );
      if (mounted) {
        setState(() {
          _matches = matches;
          _status = widget.onlyBook?.format == BookFormat.online
              ? '在已缓存章节中找到 ${matches.length} 处（最多显示 100 处）'
              : '找到 ${matches.length} 处（最多显示 100 处）';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _status = '部分内容无法检索，请检查本地文件');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _highlightedExcerpt(
    String excerpt,
    String term,
    Color highlightColor,
    TextStyle baseStyle,
  ) {
    final q = term.trim().toLowerCase();
    if (q.isEmpty) return Text(excerpt, style: baseStyle);
    final lower = excerpt.toLowerCase();
    final spans = <TextSpan>[];
    var from = 0;
    while (from < excerpt.length) {
      final at = lower.indexOf(q, from);
      if (at < 0) {
        spans.add(TextSpan(text: excerpt.substring(from)));
        break;
      }
      if (at > from) {
        spans.add(TextSpan(text: excerpt.substring(from, at)));
      }
      spans.add(
        TextSpan(
          text: excerpt.substring(at, at + q.length),
          style: TextStyle(
            color: highlightColor,
            fontWeight: FontWeight.w800,
            backgroundColor: highlightColor.withValues(alpha: 0.14),
          ),
        ),
      );
      from = at + q.length;
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final onlyBook = widget.onlyBook;
    final scheme = Theme.of(context).colorScheme;
    final subtitleStyle = TextStyle(
      fontSize: 12.5,
      color: scheme.onSurfaceVariant,
      height: 1.45,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          onlyBook != null ? '搜本书 · ${onlyBook.title}' : '书籍正文检索',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _input,
              autofocus: onlyBook != null,
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _status,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, i) {
                final match = _matches[i];
                final chapterTitle = match.book.chapters[match.chapter].title;
                return ListTile(
                  title: Text(
                    onlyBook != null
                        ? chapterTitle
                        : '《${match.book.title}》· $chapterTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: _highlightedExcerpt(
                    match.excerpt,
                    _input.text,
                    scheme.primary,
                    subtitleStyle,
                  ),
                  onTap: () {
                    if (widget.returnSelection) {
                      Navigator.of(context)
                          .pop((chapter: match.chapter, offset: match.offset));
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReaderPage(
                          store: widget.store,
                          prefs: widget.prefs,
                          bookId: match.book.id,
                          chapterIndex: match.chapter,
                          charOffset: match.offset,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
