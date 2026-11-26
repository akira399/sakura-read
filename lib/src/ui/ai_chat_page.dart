import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../core/database/sakura_database.dart';
import '../core/theme/sakura_tokens.dart';
import '../data/ai_service.dart';
import '../data/book_store.dart';
import '../data/library_search.dart';
import '../data/local_llm.dart';
import '../data/models.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../features/ai_companion/spoiler_free_memory.dart';
import '../features/pet/live_sakura_pet.dart';
import '../features/pet/pet_mood_bus.dart';
import '../source/source_store.dart';
import 'ai_settings_page.dart';
import 'library_search_page.dart';
import 'reading_assistant_home.dart';
import 'source/source_health_page.dart';
import 'widgets/cute.dart';

/// AI 对话页是否打开：打开时隐藏全局桌宠，避免挡住气泡和输入框。
final ValueNotifier<bool> kAiChatActive = ValueNotifier<bool>(false);

/// 小樱 AI 阅读助手入口（默认先进入阅读工作台；测试或直达对话时展示对话页）。
class AiChatPage extends StatelessWidget {
  const AiChatPage({
    super.key,
    required this.store,
    required this.prefs,
    this.statsStore,
    this.debugSeedBubbles,
    this.aiService,
    this.database,
  });

  final BookStore store;
  final AppPrefs prefs;
  final StatsStore? statsStore;
  final List<(String, bool)>? debugSeedBubbles;
  final AiService? aiService;
  final SakuraDatabase? database;

  @override
  Widget build(BuildContext context) => debugSeedBubbles != null
      ? AiConversationPage(
          store: store,
          prefs: prefs,
          statsStore: statsStore,
          debugSeedBubbles: debugSeedBubbles,
          aiService: aiService,
          database: database,
        )
      : ReadingAssistantHome(
          store: store,
          prefs: prefs,
          stats: statsStore,
          onChat: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AiConversationPage(
                store: store,
                prefs: prefs,
                statsStore: statsStore,
                aiService: aiService,
                database: database,
              ),
            ),
          ),
        );
}

/// 流式 AI 阅读伴侣自由对话页（SSE 流式输出 + GptMarkdown + 防剧透记忆胶囊）。
class AiConversationPage extends StatefulWidget {
  const AiConversationPage({
    super.key,
    required this.store,
    required this.prefs,
    this.statsStore,
    this.debugSeedBubbles,
    this.aiService,
    this.database,
    this.initialPrompt,
  });

  final BookStore store;
  final AppPrefs prefs;
  final StatsStore? statsStore;
  final AiService? aiService;
  final SakuraDatabase? database;
  final String? initialPrompt;

  /// 仅用于文档截图或测试：预置几条对话气泡，正常运行时保持 null。
  ///
  /// 记录为 `(文本, 是否是我说的)`。
  @visibleForTesting
  final List<(String, bool)>? debugSeedBubbles;

  @override
  State<AiConversationPage> createState() => _AiConversationPageState();
}

class _BubbleData {
  _BubbleData.user(this.text) : mine = true, error = false;
  _BubbleData.assistant(this.text, {this.badge}) : mine = false, error = false;
  _BubbleData.error(this.text) : mine = false, error = true;

  String text;
  final bool mine;
  String? badge;

  /// 出错气泡（红色）；流式失败时也会从普通气泡转成错误气泡。
  bool error;

  /// 正在逐字输出（这条气泡的内容会持续追加）。
  bool streaming = false;
}

class _QuickPill {
  const _QuickPill({
    required this.label,
    required this.icon,
    required this.prompt,
  });

  final String label;
  final IconData icon;
  final String prompt;
}

class _AiConversationPageState extends State<AiConversationPage> {
  static const List<_QuickPill> _quickPills = [
    _QuickPill(label: '前情提要', icon: Icons.auto_stories_rounded, prompt: '前情提要'),
    _QuickPill(
      label: '帮我选下一本',
      icon: Icons.explore_outlined,
      prompt: '根据我的书架和口味，帮我选下一本最值得读的书',
    ),
    _QuickPill(label: '整理人物关系', icon: Icons.hub_outlined, prompt: '整理人物关系'),
    _QuickPill(
      label: '阅读习惯分析',
      icon: Icons.insights_rounded,
      prompt: '结合我的阅读时长和最近记录，分析一下我的阅读习惯并给点小建议',
    ),
  ];

  late final AiService _service;
  late final bool _ownsService;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_BubbleData>[];
  final _history = <AiTurn>[];

  AiCancelToken? _cancelToken;
  bool _sending = false;
  String? _status;

  bool get _useLocal => widget.prefs.aiUseLocalModel;

  Book? get _recentBook {
    final books = [...widget.store.books]
      ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    for (final book in books) {
      if (book.lastReadAt > 0 && book.chapterCount > 0) return book;
    }
    return books.isNotEmpty && books.first.chapterCount > 0
        ? books.first
        : null;
  }

  PetLiveMood get _headerMood {
    if (_bubbles.isNotEmpty && _bubbles.last.error) return PetLiveMood.pouting;
    final streamingBubble = _bubbles.where((b) => b.streaming).firstOrNull;
    if (streamingBubble != null) {
      return streamingBubble.text.isEmpty
          ? PetLiveMood.thinking
          : PetLiveMood.speaking;
    }
    if (_sending) return PetLiveMood.thinking;
    return PetLiveMood.idle;
  }

  @override
  void initState() {
    super.initState();
    _ownsService = widget.aiService == null;
    _service = widget.aiService ?? AiService();
    kAiChatActive.value = true;
    final seed = widget.debugSeedBubbles;
    if (seed != null) {
      for (final (text, mine) in seed) {
        _bubbles.add(
          mine ? _BubbleData.user(text) : _BubbleData.assistant(text),
        );
      }
    }
    final initial = widget.initialPrompt?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_send(initial));
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('chat_disposed');
    if (_sending && _useLocal) {
      unawaited(LocalLlmEngine.cancel());
    }
    kPetMoodBus.onAiIdle();
    kAiChatActive.value = false;
    if (_ownsService) {
      _service.dispose();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _trimHistory() {
    final limit = _useLocal ? 6 : 20;
    while (_history.length > limit) {
      _history.removeRange(0, 2);
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) => AiSettingsPage(prefs: widget.prefs),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    if (text == '/书源体检' && SourceStore.shared != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceHealthPage(store: SourceStore.shared!),
        ),
      );
      return;
    }
    if (text.startsWith('/搜索 ')) {
      final query = text.substring(4).trim();
      setState(() {
        _sending = true;
        _bubbles.add(_BubbleData.user(text));
        _input.clear();
      });
      try {
        final hits = await LibrarySearch().search(widget.store, query);
        if (mounted) {
          setState(
            () => _bubbles.add(
              _BubbleData.assistant(
                hits.isEmpty
                    ? '未找到原文。仅检索本地书籍和已缓存的在线章节。'
                    : hits
                          .take(6)
                          .map(
                            (hit) =>
                                '**《${hit.book.title}》· ${hit.book.chapters[hit.chapter].title}**\n> ${hit.excerpt}',
                          )
                          .join('\n\n'),
              ),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          setState(() => _bubbles.add(_BubbleData.error('正文检索失败，请检查本地文件')));
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      _scrollToBottom();
      return;
    }
    if (!_useLocal && !widget.prefs.aiHttpConfigured) {
      _openSettings();
      return;
    }
    if (_useLocal && !LocalModelManager.instance.isDownloaded) {
      _openSettings();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _status = null;
      _input.clear();
      _bubbles.add(_BubbleData.user(text));
    });
    _scrollToBottom();
    kPetMoodBus.onAiThinking();

    try {
      if (_useLocal) {
        await _sendLocal(text);
      } else {
        await _sendOnlineStreaming(text);
      }
    } finally {
      kPetMoodBus.onAiIdle();
      if (mounted) {
        setState(() {
          _sending = false;
          _status = null;
        });
        _scrollToBottom();
      }
    }
  }

  /// 在线 SSE 流式对话（支持「前情提要 / 整理人物关系」自动触发严格防剧透记忆流）。
  Future<void> _sendOnlineStreaming(String text) async {
    final token = AiCancelToken();
    _cancelToken = token;

    final isRecap = text == '前情提要';
    final isWiki = text == '整理人物关系';
    final recent = _recentBook;
    final db = widget.database ?? widget.store.database;

    Stream<String>? stream;
    String? badge;

    if ((isRecap || isWiki) && recent != null) {
      final memoryService = SpoilerFreeMemoryService(
        aiService: _service,
        database: db,
      );
      final safeCtx = await SpoilerFreeMemoryService.collectSafeContext(
        widget.store,
        recent,
      );
      if (!safeCtx.isEmpty) {
        badge = '防剧透 · 《${recent.title}》第 ${recent.safeChapterIndex + 1} 章前';
        stream = isRecap
            ? memoryService.streamRecap(
                store: widget.store,
                book: recent,
                prefs: widget.prefs,
                database: db,
                cancelToken: token,
              )
            : memoryService.streamCharacterWiki(
                store: widget.store,
                book: recent,
                prefs: widget.prefs,
                database: db,
                cancelToken: token,
              );
      }
    }

    if (stream == null) {
      final prefs = widget.prefs;
      final snapshot = prefs.aiIncludeReading
          ? ReadingSnapshot.collect(
              store: widget.store,
              stats: widget.statsStore,
            )
          : null;
      stream = _service.chatStream(
        prefs: prefs,
        history: [..._history, AiTurn.user(text)],
        snapshot: snapshot,
        cancelToken: token,
      );
    }

    final bubble = _BubbleData.assistant('', badge: badge)..streaming = true;
    if (mounted) {
      setState(() => _bubbles.add(bubble));
      _scrollToBottom();
    }

    var startedSpeaking = false;
    try {
      await for (final chunk in stream) {
        if (!mounted || token.isCancelled) break;
        if (!startedSpeaking) {
          startedSpeaking = true;
          kPetMoodBus.onAiSpeaking();
        }
        setState(() {
          bubble.text += chunk;
        });
        _scrollToBottom();
      }
      if (!mounted) return;
      final reply = bubble.text.trim();
      setState(() {
        bubble.streaming = false;
        if (reply.isEmpty) {
          bubble.text = token.isCancelled ? '（已停止生成）' : '唔…小樱暂时没想出回复，再试试？';
        } else {
          bubble.text = reply;
        }
      });
      if (reply.isNotEmpty) {
        _history.addAll([AiTurn.user(text), AiTurn.assistant(reply)]);
        _trimHistory();
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        bubble
          ..streaming = false
          ..error = bubble.text.trim().isEmpty
          ..text = bubble.text.trim().isEmpty
              ? e.message
              : '${bubble.text.trim()}\n\n> ${e.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        bubble
          ..streaming = false
          ..error = bubble.text.trim().isEmpty
          ..text = bubble.text.trim().isEmpty
              ? '出了点小问题，稍后再试一次吧'
              : '${bubble.text.trim()}\n\n> 连接意外中断';
      });
    } finally {
      if (_cancelToken == token) {
        _cancelToken = null;
      }
    }
  }

  /// 本地模型的对话：加载模型 → 组提示词 → 流式吐字。
  Future<void> _sendLocal(String text) async {
    final manager = LocalModelManager.instance;
    try {
      if (!manager.isReady) {
        setState(() => _status = '把本地模型加载到内存，第一次要等十几秒…');
        final ok = await manager.ensureLoaded();
        if (!mounted) return;
        if (!ok) {
          setState(
            () => _bubbles.add(_BubbleData.error(manager.error ?? '本地模型加载失败了')),
          );
          return;
        }
      }

      final prefs = widget.prefs;
      final snapshot = prefs.aiIncludeReading
          ? ReadingSnapshot.collect(
              store: widget.store,
              stats: widget.statsStore,
            )
          : null;
      final req = await LocalLlmChat.buildRequest(
        history: _history,
        userText: text,
        snapshot: snapshot,
        includeReading: prefs.aiIncludeReading,
      );
      if (!mounted) return;
      setState(() => _status = '小樱正在想…');

      final bubble = _BubbleData.assistant('')..streaming = true;
      setState(() {
        _bubbles.add(bubble);
        _status = null;
      });

      var accumulated = '';
      var startedSpeaking = false;
      final stream = await LocalLlmEngine.generate(
        req.userText,
        system: req.system,
        history: req.history,
      );
      await for (final event in stream) {
        if (!mounted) return;
        if (event.isError) {
          setState(() {
            bubble
              ..streaming = false
              ..error = true
              ..text = '本地模型出错了：${event.text}';
          });
          return;
        }
        if (event.isDone) break;
        if (!startedSpeaking) {
          startedSpeaking = true;
          kPetMoodBus.onAiSpeaking();
        }
        if (accumulated.isNotEmpty && event.text.startsWith(accumulated)) {
          accumulated = event.text;
        } else {
          accumulated += event.text;
        }
        final cleaned = LocalLlmChat.clean(accumulated);
        setState(() => bubble.text = cleaned);
        _scrollToBottom();
      }
      if (!mounted) return;
      final reply = LocalLlmChat.clean(accumulated);
      setState(() {
        bubble.streaming = false;
        bubble.text = reply.isEmpty ? '唔…小樱没想出该说什么，再问一次试试？' : reply;
      });
      if (reply.isNotEmpty) {
        _history.addAll([AiTurn.user(text), AiTurn.assistant(reply)]);
        _trimHistory();
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _bubbles.add(_BubbleData.error(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bubbles.add(_BubbleData.error('本地模型出了点问题，再试一次吧')));
    }
  }

  Future<void> _stopGeneration() async {
    _cancelToken?.cancel('user_stopped');
    _cancelToken = null;
    if (_useLocal) {
      await LocalLlmEngine.cancel();
    }
    kPetMoodBus.onAiIdle();
    if (!mounted) return;
    setState(() {
      for (final b in _bubbles) {
        if (b.streaming) {
          b.streaming = false;
          if (b.text.trim().isEmpty) b.text = '（已停止生成）';
        }
      }
      _sending = false;
      _status = null;
    });
  }

  void _clearChat() {
    unawaited(_stopGeneration());
    setState(() {
      _bubbles.clear();
      _history.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: LocalModelManager.instance,
      builder: (context, _) {
        final localReady =
            !_useLocal || LocalModelManager.instance.isDownloaded;
        final configured = widget.prefs.aiConfigured && localReady;
        return Scaffold(
          backgroundColor: sakura.canvas,
          appBar: AppBar(
            backgroundColor: sakura.canvas,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            titleSpacing: 4,
            title: Row(
              children: [
                LiveSakuraPet(size: 38, mood: _headerMood),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '小樱',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: sakura.inkPrimary,
                      ),
                    ),
                    Text(
                      _useLocal
                          ? 'AI 阅读伴侣 · 本地模型'
                          : widget.prefs.aiModel.isNotEmpty
                          ? 'AI 阅读伴侣 · ${widget.prefs.aiModel}'
                          : 'AI 阅读伴侣 · 流式对话',
                      style: TextStyle(
                        fontSize: 11,
                        color: sakura.inkSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '检索书籍正文',
                icon: const Icon(Icons.find_in_page_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibrarySearchPage(
                      store: widget.store,
                      prefs: widget.prefs,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'AI 设置',
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'settings') _openSettings();
                  if (value == 'clear') _clearChat();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'settings', child: Text('AI 设置')),
                  PopupMenuItem(value: 'clear', child: Text('清空对话')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: configured
                      ? _buildChat(context, sakura, scheme)
                      : _buildSetup(context, sakura, scheme),
                ),
                if (configured) _buildComposer(context, sakura, scheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChat(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    final showGreeting = _bubbles.isEmpty;
    final hasStreamingBubble = _bubbles.any((b) => b.streaming);
    final showTyping = (_sending || _status != null) && !hasStreamingBubble;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      itemCount:
          _bubbles.length + (showGreeting ? 1 : 0) + (showTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (showGreeting && index == 0) {
          return _buildGreeting(context, sakura, scheme);
        }
        final bubbleIndex = index - (showGreeting ? 1 : 0);
        if (bubbleIndex >= _bubbles.length) {
          return _ThinkingBubble(
            sakura: sakura,
            accent: scheme.primary,
            status: _status ?? '小樱正在整理思路…',
          );
        }
        return _EditorialBubble(
          data: _bubbles[bubbleIndex],
          sakura: sakura,
          accent: scheme.primary,
        );
      },
    );
  }

  Widget _buildGreeting(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    final share = widget.prefs.aiIncludeReading;
    final disableAnim =
        MediaQuery.disableAnimationsOf(context) ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: sakura.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: sakura.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LiveSakuraPet(size: 56, mood: PetLiveMood.happy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '呀，你来啦～我是小樱',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: sakura.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      share
                          ? '你的书架、进度和阅读时长我都记在心里啦，随时可以做防剧透前情提要或选书建议～'
                          : '阅读数据共享已关闭；我们仍可以自由聊天，或在设置中开启数据同步。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: sakura.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pill in _quickPills)
                ActionChip(
                  avatar: Icon(pill.icon, size: 15, color: scheme.primary),
                  backgroundColor: sakura.surfaceSubtle,
                  side: BorderSide(color: sakura.hairline),
                  label: Text(
                    pill.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: sakura.inkPrimary,
                    ),
                  ),
                  onPressed: () => _send(pill.prompt),
                ),
            ],
          ),
        ],
      ),
    );
    if (disableAnim) return card;
    return card.animate().fadeIn(duration: 240.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildComposer(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    final isGenerating = _sending || _bubbles.any((b) => b.streaming);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: sakura.card,
        border: Border(top: BorderSide(color: sakura.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bubbles.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: _quickPills.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final pill = _quickPills[index];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: sakura.surfaceSubtle,
                    side: BorderSide(color: sakura.hairline),
                    label: Text(
                      pill.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: sakura.inkSecondary,
                      ),
                    ),
                    onPressed: isGenerating ? null : () => _send(pill.prompt),
                  );
                },
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '和小樱聊聊正在读的书…',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: sakura.inkSecondary,
                    ),
                    filled: true,
                    fillColor: sakura.surfaceSubtle,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isGenerating)
                FilledButton.tonalIcon(
                  onPressed: _stopGeneration,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: sakura.accentSoft,
                    foregroundColor: scheme.primary,
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 19),
                  label: const Text('停止'),
                )
              else
                IconButton.filled(
                  onPressed: () => _send(),
                  tooltip: '发送',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetup(
    BuildContext context,
    SakuraColors sakura,
    ColorScheme scheme,
  ) {
    final local = _useLocal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        const Center(child: LiveSakuraPet(size: 112, mood: PetLiveMood.happy)),
        const SizedBox(height: 18),
        Text(
          local ? '本地模型还没下载' : '先给小樱接上 AI 接口',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: sakura.inkPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          local
              ? '你选了「内置本地模型」：把 ${LocalModelManager.instance.spec.name} '
                    '（${LocalModelManager.instance.spec.sizeLabel}）下载到手机上，'
                    '之后不联网也能聊，阅读数据不出手机。'
              : '支持 OpenAI、DeepSeek、Gemini、Kimi、本地 Ollama 等 OpenAI 兼容接口，'
                    '一键填入预设即可体验实时流式对话与防剧透前情提要。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: sakura.inkSecondary,
          ),
        ),
        const SizedBox(height: 18),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    local
                        ? Icons.offline_bolt_outlined
                        : Icons.lock_outline_rounded,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    local ? '关于本地模型' : '关于隐私',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                local
                    ? '模型由 MediaPipe LLM Inference 在你的手机上运行（Apache-2.0），'
                          '对话不经过任何服务器。'
                    : 'API Key 只保存在本机加密凭据里；对话会直接发送到你填写的接口，'
                          '樱读不做中转、也不把对话存到服务器。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: sakura.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _openSettings,
          icon: Icon(local ? Icons.download_rounded : Icons.tune_rounded),
          label: Text(local ? '去下载模型' : '去设置接口'),
        ),
      ],
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({
    required this.sakura,
    required this.accent,
    required this.status,
  });

  final SakuraColors sakura;
  final Color accent;
  final String status;

  @override
  Widget build(BuildContext context) {
    final disableAnim =
        MediaQuery.disableAnimationsOf(context) ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final box = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: sakura.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: sakura.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: sakura.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 170,
            height: 9,
            decoration: BoxDecoration(
              color: sakura.surfaceSubtle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 118,
            height: 9,
            decoration: BoxDecoration(
              color: sakura.surfaceSubtle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LiveSakuraPet(size: 34, mood: PetLiveMood.thinking),
          const SizedBox(width: 8),
          disableAnim
              ? box
              : box
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(
                      duration: 1200.ms,
                      color: accent.withValues(alpha: 0.22),
                    ),
        ],
      ),
    );
  }
}

class _EditorialBubble extends StatelessWidget {
  const _EditorialBubble({
    required this.data,
    required this.sakura,
    required this.accent,
  });

  final _BubbleData data;
  final SakuraColors sakura;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disableAnim =
        MediaQuery.disableAnimationsOf(context) ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final bg = data.mine
        ? accent
        : data.error
        ? scheme.errorContainer.withValues(alpha: 0.65)
        : sakura.card;
    final fg = data.mine
        ? scheme.onPrimary
        : data.error
        ? scheme.onErrorContainer
        : sakura.inkPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(data.mine ? 18 : 5),
      bottomRight: Radius.circular(data.mine ? 5 : 18),
    );

    Widget body;
    if (data.mine || data.error) {
      body = SelectableText(
        data.text,
        style: TextStyle(fontSize: 14, height: 1.55, color: fg),
      );
    } else if (data.streaming && data.text.isEmpty) {
      final shimmer = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '小樱正在思考…',
            style: TextStyle(fontSize: 12.5, color: sakura.inkSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            width: 160,
            height: 9,
            decoration: BoxDecoration(
              color: sakura.surfaceSubtle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      );
      body = disableAnim
          ? shimmer
          : shimmer
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  duration: 1200.ms,
                  color: accent.withValues(alpha: 0.22),
                );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.badge != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: sakura.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                data.badge!,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
          GptMarkdown(
            data.text,
            isStreaming: data.streaming,
            style: TextStyle(fontSize: 14, height: 1.62, color: fg),
          ),
        ],
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: data.mine || data.error
            ? null
            : Border.all(color: sakura.hairline),
      ),
      child: body,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: data.mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!data.mine) ...[
            data.error
                ? CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.errorContainer,
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: scheme.onErrorContainer,
                    ),
                  )
                : LiveSakuraPet(
                    size: 34,
                    mood: data.streaming
                        ? PetLiveMood.speaking
                        : PetLiveMood.idle,
                  ),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}
