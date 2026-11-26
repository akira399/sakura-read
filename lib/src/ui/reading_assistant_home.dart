import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../core/motion/sakura_motion.dart';
import '../core/theme/sakura_tokens.dart';
import '../data/ai_service.dart';
import '../data/book_store.dart';
import '../data/local_llm.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../data/reading_excerpt.dart';
import '../data/stats_store.dart';
import '../features/ai_companion/spoiler_free_memory.dart';
import '../features/pet/live_sakura_pet.dart';
import '../features/pet/pet_mood_bus.dart';
import '../source/source_store.dart';
import 'ai_settings_page.dart';
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
        final sakura = context.sakura;
        final accent = Theme.of(context).colorScheme.primary;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: sakura.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sakura.hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: sakura.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            prefs.aiUseLocalModel
                                ? '当前模型 · 本地模型'
                                : prefs.aiHttpConfigured
                                ? '当前模型 · 在线流式接口已配置'
                                : '本地工具可直接用 · 未配置在线模型',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '先完成阅读任务，再和小樱聊聊',
                          style: TextStyle(
                            color: sakura.inkPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '正文检索、书签和继续阅读无需模型。AI 伴读支持实时流式 Markdown 与严格防剧透记忆缓存。',
                          style: TextStyle(
                            color: sakura.inkSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const LiveSakuraPet(size: 66, mood: PetLiveMood.reading),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (recent.isNotEmpty)
              _task(
                context,
                Icons.play_arrow_rounded,
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
                SakuraPageRoute(
                  slideHorizontal: true,
                  builder: (_) => LibrarySearchPage(store: store, prefs: prefs),
                ),
              ),
            ),
            _task(
              context,
              Icons.auto_awesome_rounded,
              '读懂当前章节',
              '摘要、人物关系、情节解释；支持流式解读与存为笔记',
              () => Navigator.of(context).push(
                SakuraPageRoute(
                  slideHorizontal: true,
                  builder: (_) =>
                      ChapterAssistantPage(store: store, prefs: prefs),
                ),
              ),
            ),
            _task(
              context,
              Icons.shield_outlined,
              '防剧透前情提要 · 人物百科',
              '严格限定在已读章节内生成并缓存到本书记忆库',
              () => Navigator.of(context).push(
                SakuraPageRoute(
                  slideHorizontal: true,
                  builder: (_) =>
                      SpoilerFreeWikiPage(store: store, prefs: prefs),
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
                Icons.bar_chart_rounded,
                '阅读回顾',
                '查看真实的阅读记录与趋势',
                () => Navigator.of(context).push(
                  SakuraPageRoute(
                    slideHorizontal: true,
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
                  SakuraPageRoute(
                    slideHorizontal: true,
                    builder: (_) =>
                        SourceHealthPage(store: SourceStore.shared!),
                  ),
                ),
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
  ) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SakuraPressable(
        borderRadius: BorderRadius.circular(18),
        onTap: action,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: sakura.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: sakura.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: sakura.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: sakura.inkPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        color: sakura.inkSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: sakura.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }

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

/// 防剧透前情提要 & 本书人物百科页面（基于 SQLite `ai_book_memory` 缓存）。
class SpoilerFreeWikiPage extends StatefulWidget {
  const SpoilerFreeWikiPage({
    super.key,
    required this.store,
    required this.prefs,
  });

  final BookStore store;
  final AppPrefs prefs;

  @override
  State<SpoilerFreeWikiPage> createState() => _SpoilerFreeWikiPageState();
}

class _SpoilerFreeWikiPageState extends State<SpoilerFreeWikiPage> {
  final _service = AiService();
  late final SpoilerFreeMemoryService _memory = SpoilerFreeMemoryService(
    aiService: _service,
    database: widget.store.database,
  );

  String? _bookId;
  String _kind = SpoilerFreeMemoryService.kindRecap;
  bool _busy = false;
  String _content = '';
  AiCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.store.books]
      ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    if (sorted.isNotEmpty) {
      _bookId = sorted.first.id;
      unawaited(_loadCached());
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('page_disposed');
    kPetMoodBus.onAiIdle();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final book = widget.store.byId(_bookId ?? '');
    if (book == null) return;
    final cached = await _memory.loadCached(book: book, kind: _kind);
    if (!mounted) return;
    setState(() => _content = cached?.markdown ?? '');
  }

  Future<void> _generate({bool forceRefresh = false}) async {
    final book = widget.store.byId(_bookId ?? '');
    if (_busy || book == null) return;
    if (!widget.prefs.aiHttpConfigured) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AiSettingsPage(prefs: widget.prefs)),
      );
      return;
    }

    final token = AiCancelToken();
    _cancelToken = token;
    setState(() {
      _busy = true;
      _content = '';
    });
    kPetMoodBus.onAiThinking();

    try {
      final stream = _kind == SpoilerFreeMemoryService.kindRecap
          ? _memory.streamRecap(
              store: widget.store,
              book: book,
              prefs: widget.prefs,
              forceRefresh: forceRefresh,
              cancelToken: token,
            )
          : _memory.streamCharacterWiki(
              store: widget.store,
              book: book,
              prefs: widget.prefs,
              forceRefresh: forceRefresh,
              cancelToken: token,
            );
      var speaking = false;
      await for (final chunk in stream) {
        if (!mounted || token.isCancelled) break;
        if (!speaking) {
          speaking = true;
          kPetMoodBus.onAiSpeaking();
        }
        setState(() => _content += chunk);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (_cancelToken == token) _cancelToken = null;
      kPetMoodBus.onAiIdle();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final book = widget.store.byId(_bookId ?? '');
    return Scaffold(
      backgroundColor: sakura.canvas,
      appBar: AppBar(
        title: const Text('防剧透记忆与人物百科'),
        actions: [
          if (_busy)
            TextButton(
              onPressed: () => _cancelToken?.cancel('user_stopped'),
              child: const Text('停止'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _bookId,
            decoration: const InputDecoration(
              labelText: '选择书籍（仅读取已读章节，绝不剧透）',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in widget.store.books)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      _bookId = v;
                      _content = '';
                    });
                    unawaited(_loadCached());
                  },
          ),
          if (book != null) ...[
            const SizedBox(height: 8),
            Text(
              '当前防剧透红线：截至第 ${book.safeChapterIndex + 1}/${book.chapterCount} 章',
              style: TextStyle(fontSize: 12, color: sakura.inkSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('防剧透前情提要'),
                selected: _kind == SpoilerFreeMemoryService.kindRecap,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(
                          () => _kind = SpoilerFreeMemoryService.kindRecap,
                        );
                        unawaited(_loadCached());
                      },
              ),
              ChoiceChip(
                label: const Text('人物关系百科'),
                selected: _kind == SpoilerFreeMemoryService.kindWiki,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(
                          () => _kind = SpoilerFreeMemoryService.kindWiki,
                        );
                        unawaited(_loadCached());
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || book == null ? null : () => _generate(),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    _busy
                        ? '正在生成…'
                        : (_content.isNotEmpty ? '查看/刷新记忆' : '生成防剧透记忆'),
                  ),
                ),
              ),
              if (_content.isNotEmpty && !_busy) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _generate(forceRefresh: true),
                  child: const Text('重新整理'),
                ),
              ],
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_content.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sakura.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sakura.hairline),
              ),
              child: GptMarkdown(
                _content,
                isStreaming: _busy,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: sakura.inkPrimary,
                ),
              ),
            ),
          ],
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
  late bool _useLocal = widget.prefs.aiUseLocalModel;
  String? _answer;
  ReadingExcerpt? _excerpt;
  Bookmark? _pendingNote;
  bool _saved = false;
  AiCancelToken? _cancelToken;
  final _service = AiService();

  @override
  void dispose() {
    _cancelToken?.cancel('chapter_assistant_disposed');
    _service.dispose();
    kPetMoodBus.onAiIdle();
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
      setState(() {
        _excerpt = excerpt;
        _answer = '';
      });
      kPetMoodBus.onAiThinking();

      if (_useLocal) {
        if (!localModels.isDownloaded) {
          throw StateError('请先在自由对话的 AI 设置中下载本地模型');
        }
        if (!await localModels.ensureLoaded()) {
          throw StateError(localModels.error ?? '本地模型加载失败');
        }
        final req = await LocalLlmChat.buildRequest(
          history: [],
          userText: excerpt.prompt(_task),
          includeReading: false,
        );
        final output = StringBuffer();
        final stream = await LocalLlmEngine.generate(
          req.userText,
          system: req.system,
          history: req.history,
        );
        var speaking = false;
        await for (final event in stream.timeout(const Duration(seconds: 90))) {
          if (event.isError) throw StateError('本地模型分析失败');
          if (event.isDone) {
            if (output.isEmpty) output.write(event.text);
            break;
          }
          if (!speaking) {
            speaking = true;
            kPetMoodBus.onAiSpeaking();
          }
          final current = output.toString();
          if (current.isNotEmpty && event.text.startsWith(current)) {
            output.clear();
          }
          output.write(event.text);
          if (mounted) {
            setState(() => _answer = LocalLlmChat.clean(output.toString()));
          }
        }
        final finalAnswer = LocalLlmChat.clean(output.toString());
        if (finalAnswer.trim().isEmpty) {
          throw StateError('模型未返回结果，请缩小文本范围后重试');
        }
        if (mounted) setState(() => _answer = finalAnswer);
      } else {
        if (!widget.prefs.aiHttpConfigured) {
          throw StateError('请先在自由对话的 AI 设置中配置在线接口');
        }
        final token = AiCancelToken();
        _cancelToken = token;
        final buf = StringBuffer();
        var speaking = false;
        await for (final chunk in _service.analyzeStream(
          prefs: widget.prefs,
          prompt: excerpt.prompt(_task),
          cancelToken: token,
        )) {
          if (!mounted || token.isCancelled) break;
          if (!speaking) {
            speaking = true;
            kPetMoodBus.onAiSpeaking();
          }
          buf.write(chunk);
          setState(() => _answer = buf.toString());
        }
        if (buf.toString().trim().isEmpty && !token.isCancelled) {
          throw StateError('模型未返回结果，请缩小文本范围后重试');
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      _cancelToken = null;
      kPetMoodBus.onAiIdle();
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
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return Scaffold(
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _bookId == null ? null : _analyze,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_busy ? '正在分析…' : '预览文本并分析'),
                ),
              ),
              if (_busy) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _cancelToken?.cancel('user_stopped');
                    if (_useLocal) unawaited(LocalLlmEngine.cancel());
                  },
                  child: const Text('停止'),
                ),
              ],
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_answer != null && _answer!.isNotEmpty && _excerpt != null) ...[
            const SizedBox(height: 20),
            Text('${_excerpt!.source}${_excerpt!.truncated ? ' · 片段分析' : ''}'),
            const Text('模型辅助结果可能有误，请核对原文。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sakura.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sakura.hairline),
              ),
              child: GptMarkdown(
                _answer!,
                isStreaming: _busy,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.62,
                  color: sakura.inkPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _saved || _busy ? null : _saveNote,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(_saved ? '已保存为书签笔记' : '保存为书签笔记'),
            ),
          ],
        ],
      ),
    );
  }
}
