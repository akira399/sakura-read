import 'ai_settings_page.dart';

import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/book_store.dart';
import '../data/local_llm.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../data/reading_excerpt.dart';
import '../data/stats_store.dart';
import '../source/source_store.dart';
import 'library_search_page.dart';
import 'reader/reader_page.dart';
import 'source/source_health_page.dart';
import 'stats_page.dart';

class ReadingAssistantHome extends StatelessWidget {
  const ReadingAssistantHome({
    super.key,
    required this.store,
    required this.prefs,
    required this.onChat,
    this.stats,
  });
  final BookStore store;
  final AppPrefs prefs;
  final StatsStore? stats;
  final VoidCallback onChat;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('小樱 · 阅读工作台'),
      actions: [TextButton(onPressed: onChat, child: const Text('自由对话'))],
    ),
    body: AnimatedBuilder(
      animation: Listenable.merge([
        store,
        prefs,
        if (BookmarkStore.shared != null) BookmarkStore.shared!,
      ]),
      builder: (context, _) {
        final recent = store.books.where((b) => b.lastReadAt > 0).toList()
          ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '先完成阅读任务，再和小樱聊聊',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('正文检索、书签和继续阅读无需模型。模型分析会先显示文本范围，并明确选择本地或在线方式。'),
            const SizedBox(height: 16),
            if (recent.isNotEmpty)
              _task(
                context,
                Icons.play_arrow,
                '继续《${recent.first.title}》',
                recent.first.chapters.isEmpty
                    ? '回到阅读进度'
                    : recent
                          .first
                          .chapters[recent.first.safeChapterIndex]
                          .title,
                () => _open(context, recent.first),
              ),
            _task(
              context,
              Icons.find_in_page_outlined,
              '找一句原文',
              '检索本地书和在线缓存，显示出处并跳转',
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LibrarySearchPage(store: store, prefs: prefs),
                ),
              ),
            ),
            _task(
              context,
              Icons.auto_awesome,
              '读懂当前章节',
              '摘要、人物关系、情节解释；结果可保存为笔记',
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ChapterAssistantPage(store: store, prefs: prefs),
                ),
              ),
            ),
            _task(
              context,
              Icons.bookmarks_outlined,
              '我的书签与笔记',
              '${BookmarkStore.shared?.count ?? 0} 条，点击回到原文',
              () => _bookmarks(context),
            ),
            if (stats != null)
              _task(
                context,
                Icons.bar_chart,
                '阅读回顾',
                '查看真实的阅读记录与趋势',
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StatsPage(statsStore: stats!),
                  ),
                ),
              ),
            if (SourceStore.shared != null)
              _task(
                context,
                Icons.health_and_safety_outlined,
                '检查书源',
                '实际检测搜索规则，不自动删除或停用',
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SourceHealthPage(store: SourceStore.shared!),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '模型状态：${prefs.aiUseLocalModel
                  ? '本地模型'
                  : prefs.aiHttpConfigured
                  ? '在线接口已配置'
                  : '尚未配置，以上本地工具仍可使用'}',
            ),
          ],
        );
      },
    ),
  );
  Widget _task(
    BuildContext context,
    IconData icon,
    String title,
    String detail,
    VoidCallback action,
  ) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: action,
    ),
  );
  void _open(BuildContext context, Book book, {int? chapter, int? offset}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            store: store,
            prefs: prefs,
            bookId: book.id,
            chapterIndex: chapter ?? book.safeChapterIndex,
            charOffset: offset ?? book.charOffset,
          ),
        ),
      );
  Future<void> _bookmarks(BuildContext context) async {
    final marks = BookmarkStore.shared?.items ?? [];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => marks.isEmpty
          ? const Center(child: Text('还没有书签或笔记'))
          : ListView(
              children: [
                for (final mark in marks)
                  ListTile(
                    title: Text(store.byId(mark.bookId)?.title ?? '书籍已移除'),
                    subtitle: Text(
                      mark.excerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      final book = store.byId(mark.bookId);
                      if (book != null) {
                        Navigator.pop(ctx);
                        _open(
                          context,
                          book,
                          chapter: mark.chapterIndex,
                          offset: mark.charOffset,
                        );
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

class ChapterAssistantPage extends StatefulWidget {
  const ChapterAssistantPage({
    super.key,
    required this.store,
    required this.prefs,
  });
  final BookStore store;
  final AppPrefs prefs;
  @override
  State<ChapterAssistantPage> createState() => _ChapterAssistantPageState();
}

class _ChapterAssistantPageState extends State<ChapterAssistantPage> {
  String? _bookId;
  String _task = '总结主要事件';
  bool _busy = false;
  bool _useLocal = true;
  String? _answer;
  ReadingExcerpt? _excerpt;
  Bookmark? _pendingNote;
  bool _saved = false;
  final _service = AiService();
  @override
  void dispose() {
    _service.dispose();
    if (_busy && _useLocal) LocalLlmEngine.cancel();
    super.dispose();
  }

  Future<void> _analyze() async {
    final book = widget.store.byId(_bookId ?? '');
    if (_busy || book == null) return;
    setState(() {
      _busy = true;
      _answer = null;
      _excerpt = null;
      _pendingNote = null;
      _saved = false;
    });
    try {
      final excerpt = await ReadingExcerpt.load(
        widget.store,
        book,
        limit: _useLocal ? 700 : 6000,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_useLocal ? '本地分析预览' : '将正文片段发送至在线接口？'),
          content: SingleChildScrollView(
            child: Text(
              '${excerpt.source}\n${excerpt.text.length} 字${excerpt.truncated ? '，已截取章节开头' : ''}\n${_useLocal ? '正文留在本机' : widget.prefs.aiBaseUrl}\n\n${excerpt.text.substring(0, excerpt.text.length.clamp(0, 400))}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始分析'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      String answer;
      if (_useLocal) {
        if (!localModels.isDownloaded) {
          throw StateError('请先在自由对话的 AI 设置中下载本地模型');
        }
        if (!await localModels.ensureLoaded()) {
          throw StateError(localModels.error ?? '本地模型加载失败');
        }
        final prompt = await LocalLlmChat.buildPrompt(
          history: [],
          userText: excerpt.prompt(_task),
          includeReading: false,
        );
        final output = StringBuffer();
        final stream = await LocalLlmEngine.generate(prompt);
        await for (final event in stream.timeout(const Duration(seconds: 90))) {
          if (event.isError) throw StateError('本地模型分析失败');
          if (event.isDone) {
            if (output.isEmpty) output.write(event.text);
            break;
          }
          final current = output.toString();
          if (current.isNotEmpty && event.text.startsWith(current)) {
            output.clear();
          }
          output.write(event.text);
        }
        answer = LocalLlmChat.clean(output.toString());
      } else {
        if (!widget.prefs.aiHttpConfigured) {
          throw StateError('请先在自由对话的 AI 设置中配置在线接口');
        }
        answer = await _service.analyzeExcerpt(
          prefs: widget.prefs,
          prompt: excerpt.prompt(_task),
        );
      }
      if (answer.trim().isEmpty) throw StateError('模型未返回结果，请缩小文本范围后重试');
      if (mounted) {
        setState(() {
          _answer = answer;
          _excerpt = excerpt;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNote() async {
    final marks = BookmarkStore.shared;
    final excerpt = _excerpt;
    if (marks == null || excerpt == null || _answer == null) return;
    final note = Bookmark(
      id: Bookmark.newId(),
      bookId: excerpt.book.id,
      chapterIndex: excerpt.chapter,
      charOffset: 0,
      chapterTitle: excerpt.book.chapters[excerpt.chapter].title,
      excerpt: '模型辅助笔记 · $_task\n来源：${excerpt.source}\n$_answer',
    );
    if (_saved) return;
    _pendingNote ??= note;
    marks.addNote(_pendingNote!);
    try {
      await marks.flush();
      if (mounted) setState(() => _saved = true);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存为书签笔记')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('笔记尚未保存，请检查存储空间后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('读懂当前章节')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AiSettingsPage(prefs: widget.prefs),
                  ),
                ),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('配置本地模型 / 在线接口'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _bookId,
          decoration: const InputDecoration(labelText: '选择书籍（使用当前阅读章节）'),
          items: [
            for (final book in widget.store.books)
              DropdownMenuItem(
                value: book.id,
                child: Text(book.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  _bookId = v;
                  _answer = null;
                  _excerpt = null;
                }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final task in ['总结主要事件', '梳理人物关系', '解释情节与伏笔'])
              ChoiceChip(
                label: Text(task),
                selected: _task == task,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _task = task;
                        _answer = null;
                        _excerpt = null;
                      }),
              ),
          ],
        ),
        SwitchListTile(
          title: const Text('在本地模型分析'),
          subtitle: const Text('关闭后使用在线接口；每次发送正文前先确认'),
          value: _useLocal,
          onChanged: _busy ? null : (v) => setState(() => _useLocal = v),
        ),
        FilledButton.icon(
          onPressed: _busy || _bookId == null ? null : _analyze,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? '正在分析…' : '预览文本并分析'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_answer != null) ...[
          const SizedBox(height: 20),
          Text('${_excerpt!.source}${_excerpt!.truncated ? ' · 片段分析' : ''}'),
          const Text('模型辅助结果可能有误，请核对原文。'),
          const SizedBox(height: 12),
          SelectableText(_answer!),
          TextButton.icon(
            onPressed: _saved ? null : _saveNote,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(_saved ? '已保存为书签笔记' : '保存为书签笔记'),
          ),
        ],
      ],
    ),
  );
}
