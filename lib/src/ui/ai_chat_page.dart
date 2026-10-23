import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/book_store.dart';
import '../data/local_llm.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import 'ai_settings_page.dart';
import 'widgets/cute.dart';

/// AI 对话页是否打开：打开时隐藏全局桌宠，避免挡住气泡和输入框。
final ValueNotifier<bool> kAiChatActive = ValueNotifier<bool>(false);

/// 小樱 AI 阅读助手对话框。
class AiChatPage extends StatefulWidget {
  const AiChatPage({
    super.key,
    required this.store,
    required this.prefs,
    this.statsStore,
    this.debugSeedBubbles,
  });

  final BookStore store;
  final AppPrefs prefs;
  final StatsStore? statsStore;

  /// 仅用于文档截图：预置几条对话气泡，正常运行时保持 null。
  ///
  /// 记录为 `(文本, 是否是我说的)`。
  @visibleForTesting
  final List<(String, bool)>? debugSeedBubbles;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _BubbleData {
  _BubbleData.user(this.text) : mine = true, error = false;
  _BubbleData.assistant(this.text) : mine = false, error = false;
  _BubbleData.error(this.text) : mine = false, error = true;

  String text;
  final bool mine;

  /// 出错气泡（红色）；本地模型流式失败时也会从普通气泡转成错误气泡。
  bool error;

  /// 正在逐字输出（这条气泡的内容会一直变）。
  bool streaming = false;
}

class _AiChatPageState extends State<AiChatPage> {
  static const _quickAsks = [
    '我最近读到哪了？',
    '根据我的口味推荐一本书',
    '总结一下我的阅读习惯',
    '鼓励我坚持阅读',
  ];

  final _service = AiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_BubbleData>[];
  final _history = <AiTurn>[];
  bool _sending = false;

  /// 本地模式下正在加载模型 / 等待首字。
  String? _status;

  bool get _useLocal => widget.prefs.aiUseLocalModel;

  @override
  void initState() {
    super.initState();
    kAiChatActive.value = true;
    final seed = widget.debugSeedBubbles;
    if (seed != null) {
      for (final (text, mine) in seed) {
        _bubbles.add(
          mine ? _BubbleData.user(text) : _BubbleData.assistant(text),
        );
      }
    }
  }

  @override
  void dispose() {
    kAiChatActive.value = false;
    _service.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _trimHistory() {
    // 本地小模型上下文很窄（1280 token），历史只留最近几轮。
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
    if (_useLocal) {
      await _sendLocal(text);
    } else {
      await _sendOnline(text);
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _status = null;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendOnline(String text) async {
    try {
      final prefs = widget.prefs;
      final snapshot = prefs.aiIncludeReading
          ? ReadingSnapshot.collect(
              store: widget.store,
              stats: widget.statsStore,
            )
          : null;
      final reply = await _service.chat(
        prefs: prefs,
        history: [..._history, AiTurn.user(text)],
        snapshot: snapshot,
      );
      if (!mounted) return;
      setState(() {
        _history.addAll([AiTurn.user(text), AiTurn.assistant(reply)]);
        _trimHistory();
        _bubbles.add(_BubbleData.assistant(reply));
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _bubbles.add(_BubbleData.error(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bubbles.add(_BubbleData.error('出了点小问题，稍后再试一次吧')));
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
      final prompt = await LocalLlmChat.buildPrompt(
        history: _history,
        userText: text,
        snapshot: snapshot,
        includeReading: prefs.aiIncludeReading,
      );
      if (!mounted) return;
      setState(() {
        _status = '小樱正在想…';
      });

      final bubble = _BubbleData.assistant('');
      bubble.streaming = true;
      setState(() {
        _bubbles.add(bubble);
        _status = null;
      });

      var accumulated = '';
      final stream = await LocalLlmEngine.generate(prompt);
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
        // 原生侧回调的可能是「增量」也可能是「累计」，两种都兼容：
        // 新内容以已累积内容开头 → 当作累计值替换，否则追加。
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

  Future<void> _stopLocal() async {
    await LocalLlmEngine.cancel();
  }

  void _clearChat() {
    setState(() {
      _bubbles.clear();
      _history.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: LocalModelManager.instance,
      builder: (context, _) {
        final localReady =
            !_useLocal || LocalModelManager.instance.isDownloaded;
        final configured = widget.prefs.aiConfigured && localReady;
        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 4,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: const AssetImage(
                    'assets/images/pet_wave.png',
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '小樱',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _useLocal ? 'AI 阅读助手 · 本地模型' : 'AI 阅读助手',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
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
                      ? _buildChat(context, scheme)
                      : _buildSetup(context, scheme),
                ),
                if (configured) _buildComposer(context, scheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChat(BuildContext context, ColorScheme scheme) {
    final showGreeting = _bubbles.isEmpty;
    final streaming = _bubbles.any((b) => b.streaming);
    final showTyping = (_sending || _status != null) && !streaming;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      itemCount:
          _bubbles.length + (showGreeting ? 1 : 0) + (showTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (showGreeting && index == 0) return _buildGreeting(context, scheme);
        final bubbleIndex = index - (showGreeting ? 1 : 0);
        if (bubbleIndex >= _bubbles.length) return _buildTyping(scheme);
        return _Bubble(data: _bubbles[bubbleIndex]);
      },
    );
  }

  Widget _buildGreeting(BuildContext context, ColorScheme scheme) {
    final share = widget.prefs.aiIncludeReading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bubble(
          data: _BubbleData.assistant(
            '呀，你来啦～我是小樱。'
            '${share ? '你的书架、进度和阅读时长我都看过啦，' : ''}'
            '想聊点什么？'
            '${_useLocal ? '\n（这次是手机自己跑的小模型，反应可能慢半拍，见谅呀）' : ''}',
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ask in _quickAsks)
                ActionChip(
                  label: Text(ask, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _send(ask),
                ),
            ],
          ),
        ),
        if (!share)
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 10, 8, 0),
            child: Text(
              '阅读数据共享已关闭，小樱看不到你的书架。可在「AI 设置」里打开。',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildTyping(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const _AiAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _status ?? '小樱正在想…',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, ColorScheme scheme) {
    final streaming = _bubbles.any((b) => b.streaming);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .4)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '和小樱说点什么…',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (streaming)
            IconButton.filled(
              onPressed: _stopLocal,
              tooltip: '停止',
              icon: const Icon(Icons.stop_rounded),
            )
          else
            IconButton.filled(
              onPressed: _sending ? null : () => _send(),
              tooltip: '发送',
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildSetup(BuildContext context, ColorScheme scheme) {
    final local = _useLocal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        Center(
          child: Image.asset(
            'assets/images/pet_wave.png',
            width: 116,
            height: 116,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          local ? '本地模型还没下载' : '先给小樱接上 AI 接口',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          local
              ? '你选了「内置本地模型」：把 ${LocalModelManager.instance.spec.name} '
                    '（${LocalModelManager.instance.spec.sizeLabel}）下载到手机上，'
                    '之后不联网也能聊，阅读数据不出手机。'
              : '支持任何兼容 OpenAI Chat Completions 的服务：OpenAI、DeepSeek、Kimi、'
                    '本地 Ollama……填好地址和模型名就能聊啦。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: scheme.onSurfaceVariant,
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
                          '对话不经过任何服务器。第一次加载需要十几秒，回答也会比云端模型简单些。'
                    : 'API Key 只保存在本机设置文件里；对话会直接发送到你填写的接口，'
                          '樱读不做中转、也不把对话存到服务器。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _openSettings,
          icon: Icon(local ? Icons.download_rounded : Icons.settings_outlined),
          label: Text(local ? '去下载模型' : '去设置接口'),
        ),
      ],
    );
  }
}

class _AiAvatar extends StatelessWidget {
  const _AiAvatar();

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: const AssetImage('assets/images/pet_wave.png'),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.data});

  final _BubbleData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = data.mine
        ? scheme.primary
        : data.error
        ? scheme.errorContainer.withValues(alpha: .55)
        : scheme.surfaceContainerHighest.withValues(alpha: .55);
    final fg = data.mine
        ? scheme.onPrimary
        : data.error
        ? scheme.onErrorContainer
        : scheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(data.mine ? 16 : 4),
      bottomRight: Radius.circular(data.mine ? 4 : 16),
    );
    final content = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .76,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: SelectableText(
        data.text.isEmpty && data.streaming ? '…' : data.text,
        style: TextStyle(fontSize: 14, height: 1.55, color: fg),
      ),
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
                : const _AiAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(child: content),
        ],
      ),
    );
  }
}
