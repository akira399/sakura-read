import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/theme/sakura_tokens.dart';
import '../../data/ai_service.dart';
import '../../data/local_llm.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/stats_store.dart';
import '../../ui/ai_settings_page.dart';
import '../pet/live_sakura_pet.dart';
import '../pet/pet_mood_bus.dart';

/// 阅读器内划词 AI 伴读动作。
enum InlineAiAction {
  explain('语境解释', Icons.menu_book_rounded),
  translate('翻译', Icons.translate_rounded),
  character('人物设定', Icons.person_search_rounded),
  appreciate('赏析', Icons.auto_awesome_rounded);

  const InlineAiAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 便捷弹窗入口：在阅读器内呼出划词 AI 伴读底部面板。
Future<void> showInlineAiReaderSheet(
  BuildContext context, {
  required Book book,
  required int chapterIndex,
  required String selectedText,
  required AppPrefs prefs,
  int charOffset = 0,
  String? surroundingContext,
  InlineAiAction initialAction = InlineAiAction.explain,
  AiService? aiService,
  BookmarkStore? bookmarkStore,
  VoidCallback? onSavedNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => InlineAiReaderSheet(
      book: book,
      chapterIndex: chapterIndex,
      selectedText: selectedText,
      prefs: prefs,
      charOffset: charOffset,
      surroundingContext: surroundingContext,
      initialAction: initialAction,
      aiService: aiService,
      bookmarkStore: bookmarkStore,
      onSavedNote: onSavedNote,
    ),
  );
}

/// 阅读器内划词伴读面板：支持 4 项即时切换（语境解释 / 翻译 / 人物设定 / 赏析）、
/// SSE 实时流式 Markdown 输出，以及一键「存为本书笔记」。
class InlineAiReaderSheet extends StatefulWidget {
  const InlineAiReaderSheet({
    super.key,
    required this.book,
    required this.chapterIndex,
    required this.selectedText,
    required this.prefs,
    this.charOffset = 0,
    this.surroundingContext,
    this.initialAction = InlineAiAction.explain,
    this.aiService,
    this.bookmarkStore,
    this.onSavedNote,
    this.autoStart = true,
  });

  final Book book;
  final int chapterIndex;
  final int charOffset;
  final String selectedText;
  final String? surroundingContext;
  final AppPrefs prefs;
  final InlineAiAction initialAction;
  final AiService? aiService;
  final BookmarkStore? bookmarkStore;
  final VoidCallback? onSavedNote;

  /// 是否在打开时立即开始当前标签的流式分析（默认开启）。
  final bool autoStart;

  @override
  State<InlineAiReaderSheet> createState() => _InlineAiReaderSheetState();
}

class _InlineAiReaderSheetState extends State<InlineAiReaderSheet> {
  late final AiService _service;
  late final bool _ownsService;

  late InlineAiAction _action = widget.initialAction;
  final Map<InlineAiAction, String> _results = {};
  final Set<InlineAiAction> _savedActions = {};
  final ScrollController _scroll = ScrollController();

  AiCancelToken? _cancelToken;
  bool _streaming = false;
  String? _error;
  bool _savedFeedback = false;

  String get _currentText => _results[_action] ?? '';

  String get _chapterTitle {
    if (widget.book.chapters.isEmpty) return '当前正文';
    final safeIdx = widget.chapterIndex
        .clamp(0, widget.book.chapters.length - 1)
        .toInt();
    return widget.book.chapters[safeIdx].title;
  }

  bool get _isConfigured {
    if (widget.prefs.aiUseLocalModel) {
      return LocalModelManager.instance.isDownloaded;
    }
    return widget.prefs.aiHttpConfigured;
  }

  PetLiveMood get _petMood {
    if (_savedFeedback) return PetLiveMood.happy;
    if (_error != null) return PetLiveMood.pouting;
    if (_streaming && _currentText.isEmpty) return PetLiveMood.thinking;
    if (_streaming) return PetLiveMood.speaking;
    return PetLiveMood.reading;
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.aiService == null;
    _service = widget.aiService ?? AiService();
    if (widget.autoStart && _isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runAction(_action));
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('sheet_disposed');
    kPetMoodBus.onAiIdle();
    _scroll.dispose();
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  String _buildPrompt(InlineAiAction action) {
    final selected = widget.selectedText.trim();
    final surrounding = widget.surroundingContext?.trim() ?? '';
    final contextPart = surrounding.isEmpty
        ? ''
        : '\n<周边语境（仅限当前已读章节，严禁剧透）>\n$surrounding\n</周边语境>';

    final instruction = switch (action) {
      InlineAiAction.explain =>
        '请结合上下文，用简明温柔的中文对选中语句做「语境解释」：拆解难词/典故/潜台词，并说明这句话在当下情节中的作用。',
      InlineAiAction.translate =>
        '请对选中文本做自然流畅的「翻译」：若是外文/文言则译为通顺的现代简体中文；若已是现代中文，则提供优雅的英文对照译文并简析关键词。',
      InlineAiAction.character =>
        '请严格依据选中语句及当前语境，梳理其中涉及的「人物设定」：角色称呼、当前情绪/动机、与对话者的关系；未在当前文本出现的信息不要剧透或编造。',
      InlineAiAction.appreciate =>
        '请从文学表达角度对选中片段做「赏析」：点出修辞、意象、节奏或留白之美，并附一句简短的阅读共鸣感言。',
    };

    return '$instruction\n'
        '出处：《${widget.book.title}》· $_chapterTitle\n'
        '<选中原文>\n$selected\n</选中原文>$contextPart';
  }

  Future<void> _runAction(
    InlineAiAction action, {
    bool forceRefresh = false,
  }) async {
    _stopGeneration();
    if (!forceRefresh && (_results[action]?.trim().isNotEmpty ?? false)) {
      setState(() {
        _action = action;
        _error = null;
        _savedFeedback = _savedActions.contains(action);
      });
      return;
    }

    if (!_isConfigured) {
      setState(() {
        _action = action;
        _error = null;
      });
      return;
    }

    final token = AiCancelToken();
    _cancelToken = token;
    setState(() {
      _action = action;
      _streaming = true;
      _error = null;
      _savedFeedback = false;
      _results[action] = '';
    });
    kPetMoodBus.onAiThinking();

    try {
      if (widget.prefs.aiUseLocalModel) {
        await _runLocal(action, token);
      } else {
        var startedSpeaking = false;
        await for (final chunk in _service.analyzeStream(
          prefs: widget.prefs,
          prompt: _buildPrompt(action),
          cancelToken: token,
        )) {
          if (!mounted || token.isCancelled) break;
          if (!startedSpeaking) {
            startedSpeaking = true;
            kPetMoodBus.onAiSpeaking();
          }
          setState(() {
            _results[action] = (_results[action] ?? '') + chunk;
          });
          _scrollToEnd();
        }
      }
    } on AiException catch (e) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => _error = '分析中断了，请检查网络后重试');
      }
    } finally {
      if (_cancelToken == token) {
        _cancelToken = null;
      }
      kPetMoodBus.onAiIdle();
      if (mounted) {
        setState(() => _streaming = false);
      }
    }
  }

  Future<void> _runLocal(InlineAiAction action, AiCancelToken token) async {
    final manager = LocalModelManager.instance;
    if (!manager.isReady) {
      final ok = await manager.ensureLoaded();
      if (!ok) {
        throw AiException(manager.error ?? '本地模型加载失败');
      }
    }
    final req = await LocalLlmChat.buildRequest(
      history: const [],
      userText: _buildPrompt(action),
      includeReading: false,
    );
    var acc = '';
    final stream = await LocalLlmEngine.generate(
      req.userText,
      system: req.system,
      history: req.history,
    );
    var speaking = false;
    await for (final event in stream) {
      if (!mounted || token.isCancelled) {
        await LocalLlmEngine.cancel();
        break;
      }
      if (event.isError) throw AiException('本地模型出错：${event.text}');
      if (event.isDone) break;
      if (!speaking) {
        speaking = true;
        kPetMoodBus.onAiSpeaking();
      }
      if (acc.isNotEmpty && event.text.startsWith(acc)) {
        acc = event.text;
      } else {
        acc += event.text;
      }
      setState(() => _results[action] = LocalLlmChat.clean(acc));
      _scrollToEnd();
    }
  }

  void _stopGeneration() {
    if (_cancelToken != null) {
      _cancelToken!.cancel('user_stopped');
      _cancelToken = null;
    }
    if (widget.prefs.aiUseLocalModel && _streaming) {
      unawaited(LocalLlmEngine.cancel());
    }
    kPetMoodBus.onAiIdle();
    if (_streaming && mounted) {
      setState(() => _streaming = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _saveAsBookNote() async {
    final content = _currentText.trim();
    if (content.isEmpty || _savedActions.contains(_action)) return;
    final store = widget.bookmarkStore ?? BookmarkStore.shared;
    if (store == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('书签库尚未就绪，暂无法保存笔记')));
      }
      return;
    }
    final quote = widget.selectedText.trim();
    final clippedQuote = quote.length > 80
        ? '${quote.substring(0, 80)}…'
        : quote;
    final note = Bookmark(
      id: Bookmark.newId(),
      bookId: widget.book.id,
      chapterIndex: widget.chapterIndex,
      charOffset: widget.charOffset,
      chapterTitle: _chapterTitle,
      excerpt: '小樱伴读 · ${_action.label}\n「$clippedQuote」\n$content',
    );
    store.addNote(note);
    try {
      await store.flush();
      if (!mounted) return;
      setState(() {
        _savedActions.add(_action);
        _savedFeedback = true;
      });
      kPetMoodBus.onReadingMilestone('笔记已记下啦～');
      widget.onSavedNote?.call();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('已存为本书笔记')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('保存失败，请检查存储空间后重试')));
    }
  }

  Future<void> _copyResult() async {
    final text = _currentText.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('已复制解读内容')));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AiSettingsPage(prefs: widget.prefs)),
    );
    if (!mounted) return;
    setState(() {});
    if (_isConfigured) {
      unawaited(_runAction(_action, forceRefresh: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final saved = _savedActions.contains(_action);
    final hasOutput = _currentText.trim().isNotEmpty;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: sakura.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: sakura.hairline)),
        boxShadow: [
          BoxShadow(
            color: sakura.coverShadow,
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽条
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: sakura.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          // 标题栏：动态迷你小樱 + 章节出处 + 停止/关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 10, 8),
            child: Row(
              children: [
                LiveSakuraPet(
                  size: 40,
                  mood: _petMood,
                  showSparkles: _savedFeedback,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '小樱 · 划词伴读',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: sakura.inkPrimary,
                        ),
                      ),
                      Text(
                        '《${widget.book.title}》· $_chapterTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: sakura.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_streaming)
                  TextButton.icon(
                    onPressed: _stopGeneration,
                    icon: const Icon(Icons.stop_circle_outlined, size: 17),
                    label: const Text('停止'),
                  ),
                IconButton(
                  tooltip: '关闭',
                  icon: Icon(Icons.close_rounded, color: sakura.inkSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // 选中原文预览条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: sakura.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: accent, width: 3.5)),
              ),
              child: Text(
                widget.selectedText.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.48,
                  color: sakura.inkSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 4 项即时动作标签：语境解释 / 翻译 / 人物设定 / 赏析
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: InlineAiAction.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = InlineAiAction.values[index];
                final active = item == _action;
                return ChoiceChip(
                  selected: active,
                  avatar: Icon(
                    item.icon,
                    size: 16,
                    color: active ? accent : sakura.inkSecondary,
                  ),
                  label: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? accent : sakura.inkPrimary,
                    ),
                  ),
                  backgroundColor: sakura.card,
                  selectedColor: sakura.accentSoft,
                  side: BorderSide(color: active ? accent : sakura.hairline),
                  showCheckmark: false,
                  onSelected: (_) => unawaited(_runAction(item)),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // 内容展示区
          Flexible(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sakura.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sakura.hairline),
              ),
              child: _buildBody(context, sakura, accent),
            ),
          ),
          // 底部操作栏：复制 / 重新生成 / 存为本书笔记
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  IconButton.outlined(
                    tooltip: '复制',
                    onPressed: hasOutput ? _copyResult : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: '重新生成',
                    onPressed: _isConfigured && !_streaming
                        ? () =>
                              unawaited(_runAction(_action, forceRefresh: true))
                        : null,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: hasOutput && !_streaming && !saved
                          ? _saveAsBookNote
                          : null,
                      icon: Icon(
                        saved
                            ? Icons.bookmark_added_rounded
                            : Icons.bookmark_add_outlined,
                        size: 18,
                      ),
                      label: Text(saved ? '已存为本书笔记' : '存为本书笔记'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, SakuraColors sakura, Color accent) {
    if (!_isConfigured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '先配置 AI 接口或下载本地模型，小樱就能帮你实时解读划词原文啦。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: sakura.inkSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('去配置 AI 助手'),
          ),
        ],
      );
    }

    if (_error != null && _currentText.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            style: TextStyle(
              fontSize: 13.5,
              color: Theme.of(context).colorScheme.error,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => unawaited(_runAction(_action, forceRefresh: true)),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('再试一次'),
          ),
        ],
      );
    }

    if (_streaming && _currentText.isEmpty) {
      return _ThinkingShimmer(sakura: sakura, accent: accent);
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GptMarkdown(
            _currentText,
            isStreaming: _streaming,
            style: TextStyle(
              fontSize: 14,
              height: 1.65,
              color: sakura.inkPrimary,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThinkingShimmer extends StatelessWidget {
  const _ThinkingShimmer({required this.sakura, required this.accent});

  final SakuraColors sakura;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final disableAnim =
        MediaQuery.disableAnimationsOf(context) ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final bars = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 15, color: accent),
            const SizedBox(width: 6),
            Text(
              '小樱正在细读这段文字…',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: sakura.inkSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _line(double.infinity),
        const SizedBox(height: 8),
        _line(240),
        const SizedBox(height: 8),
        _line(170),
      ],
    );
    if (disableAnim) return bars;
    return bars
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1200.ms, color: accent.withValues(alpha: 0.22));
  }

  Widget _line(double width) => Container(
    width: width,
    height: 11,
    decoration: BoxDecoration(
      color: sakura.surfaceSubtle,
      borderRadius: BorderRadius.circular(999),
    ),
  );
}
