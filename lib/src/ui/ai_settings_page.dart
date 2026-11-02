import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/local_llm.dart';
import '../data/prefs.dart';
import '../platform/native_bridge.dart';
import 'widgets/cute.dart';

/// AI 助手的运行方式与接口配置。
///
/// 两条路二选一：
/// - 在线接口（OpenAI 兼容：地址 / Key / 模型名）；
/// - 内置本地小模型（离线、免费、数据不出手机）。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  static const _presets = <(String, String, String)>[
    ('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    ('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    ('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
    ('Ollama 本地', 'http://127.0.0.1:11434/v1', 'qwen2.5:7b'),
  ];

  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.prefs.aiBaseUrl,
  );
  late final TextEditingController _apiKey = TextEditingController(
    text: widget.prefs.aiApiKey,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.prefs.aiModel,
  );
  late bool _includeReading = widget.prefs.aiIncludeReading;
  late bool _useLocal = widget.prefs.aiUseLocalModel;
  bool _showKey = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    // 目录里有多档模型，老设置里存的 id 可能已经不在目录里（或从没存过）：
    // 这时候落到第一档（最轻的那档），否则单选列表会一个都不亮。
    final saved = widget.prefs.aiLocalModelId;
    final known = localModelCatalog.any((spec) => spec.id == saved);
    localModels.selectedId = known ? saved : localModelCatalog.first.id;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _applyPreset(String base, String model) {
    setState(() {
      _baseUrl.text = base;
      _model.text = model;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 卡片里换了模型：整页重建，让上面「运行方式」也显示新模型名。
  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    if (_testing) return;
    final base = _baseUrl.text.trim();
    final model = _model.text.trim();
    if (base.isEmpty || model.isEmpty) {
      _toast('先填好接口地址和模型名');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _testing = true);
    final service = AiService();
    try {
      final reply = await service.testConnection(
        baseUrl: base,
        apiKey: _apiKey.text,
        model: model,
      );
      _toast('连接成功：$reply');
    } on AiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('连接失败，检查接口地址和网络');
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 切换运行方式。这是「开关」不是表单字段：点一下立刻落盘，
  /// 否则用户切到内置本地模型后直接返回，对话页还会走在线接口。
  void _setMode(bool local) {
    if (_useLocal == local) return;
    setState(() => _useLocal = local);
    widget.prefs.setAiUseLocalModel(local);
    if (local) {
      widget.prefs.setAiLocalModelId(localModels.spec.id);
    }
    _toast(local ? '已切换为本地模型（离线运行）' : '已切换为在线接口');
  }

  Future<void> _save() async {
    if (_useLocal) {
      // 本地模式不校验接口；模型没下载也可以先保存，对话页会引导下载。
      widget.prefs.setAiUseLocalModel(true);
      widget.prefs.setAiLocalModelId(localModels.spec.id);
      if (!await _flushSettings() || !mounted) return;
      _toast('已切换为本地模型');
      Navigator.of(context).pop();
      return;
    }
    final base = _baseUrl.text.trim();
    final model = _model.text.trim();
    if (base.isEmpty || model.isEmpty) {
      _toast('接口地址和模型名不能为空');
      return;
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      _toast('接口地址要以 http:// 或 https:// 开头');
      return;
    }
    widget.prefs.setAiConfig(
      baseUrl: base,
      apiKey: _apiKey.text,
      model: model,
      includeReading: _includeReading,
    );
    widget.prefs.setAiUseLocalModel(false);
    if (!await _flushSettings() || !mounted) return;
    _toast('已保存');
    Navigator.of(context).pop();
  }

  Future<bool> _flushSettings() async {
    try {
      await widget.prefs.flush();
      return true;
    } catch (_) {
      if (mounted) _toast('保存失败，请重试；设置尚未安全保存');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildModeCard(context),
          const SizedBox(height: 14),
          if (_useLocal)
            _LocalModelCard(
              prefs: widget.prefs,
              onToast: _toast,
              onSelectionChanged: _onModelChanged,
            )
          else ...[
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    icon: Icons.auto_awesome_rounded,
                    title: '接口预设',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _presets)
                        ActionChip(
                          label: Text(
                            p.$1,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _applyPreset(p.$2, p.$3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点一下自动填好地址和常见模型，Key 需要你自己填。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    icon: Icons.link_rounded,
                    title: '接口地址（Base URL）',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'https://api.openai.com/v1',
                      helperText: '兼容 OpenAI Chat Completions；可只填到 /v1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'API Key',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apiKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: !_showKey,
                    decoration: InputDecoration(
                      hintText: 'sk-…',
                      helperText: '只保存在本机；本地模型不需要可以留空',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(
                          _showKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 19,
                        ),
                        tooltip: _showKey ? '隐藏' : '显示',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '模型名',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _model,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'gpt-4o-mini / deepseek-chat …',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  icon: Icons.privacy_tip_outlined,
                  title: '阅读数据',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeReading,
                  onChanged: (v) => setState(() => _includeReading = v),
                  title: const Text(
                    '让 AI 读取我的阅读数据',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    '发送消息时附带书架、进度、时长和连续天数，用于推荐和总结；'
                    '不包含书籍正文。关闭后仍可聊天。',
                    style: TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _useLocal ? Icons.shield_outlined : Icons.cloud_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _useLocal
                        ? '本地模型完全在你的手机上运行：不联网、不上传任何数据，'
                              '也不消耗 API 额度。代价是回答没有云端大模型那么聪明。'
                        : '对话内容和阅读数据会直接发送到你填写的接口，'
                              '请确认你信任该服务；由此产生的费用由服务商收取。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              if (!_useLocal) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 19),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.memory_rounded, title: '运行方式'),
          const SizedBox(height: 8),
          _ModeTile(
            selected: !_useLocal,
            icon: Icons.cloud_outlined,
            title: '在线接口',
            subtitle: 'OpenAI / DeepSeek / Kimi / 本地 Ollama，回答更聪明，需要 Key',
            onTap: () => _setMode(false),
          ),
          const SizedBox(height: 6),
          _ModeTile(
            selected: _useLocal,
            icon: Icons.offline_bolt_outlined,
            title: '内置本地模型',
            subtitle: _useLocal
                ? '${localModels.spec.name}（${localModels.spec.sizeLabel}）· '
                      '完全离线，不联网、不花钱'
                : '模型下载到手机后完全离线运行，不联网、不花钱',
            onTap: LocalModelManager.instance.supported
                ? () => _setMode(true)
                : null,
          ),
          if (!LocalModelManager.instance.supported)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                '当前平台不支持本地模型（仅 Android 可用）',
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: .45)
              : scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled
                  ? (selected ? scheme.primary : scheme.onSurfaceVariant)
                  : scheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? null
                          : scheme.onSurfaceVariant.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 19, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// 本地模型的「选一档 → 下载 → 删除」卡片。
///
/// 管理器（[LocalModelManager]）同一时间只跟踪「当前选中」那一档的进度，
/// 所以「哪些档已经下载过」这里自己扫一遍 `<files>/models/`：
/// 不然先下 1.5B、再切回 0.5B，列表会把后者显示成没下载。
class _LocalModelCard extends StatefulWidget {
  const _LocalModelCard({
    required this.prefs,
    required this.onToast,
    required this.onSelectionChanged,
  });

  final AppPrefs prefs;
  final void Function(String) onToast;

  /// 选中项变了通知上层重建（上面「运行方式」要跟着显示模型名）。
  final VoidCallback onSelectionChanged;

  @override
  State<_LocalModelCard> createState() => _LocalModelCardState();
}

class _LocalModelCardState extends State<_LocalModelCard> {
  /// 按钮统一压扁一点，一行里塞得下状态文字 + 操作。
  static const ButtonStyle _compactButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: WidgetStatePropertyAll(Size(0, 34)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
  );

  LocalModelManager get _manager => localModels;

  /// 文件真实落地的模型 id（大小对得上才算）。
  final Set<String> _downloaded = <String>{};
  bool _scanning = false;

  /// 正在删除某一档：管理器只会删「当前选中」，这里临时借一下选中项；
  /// 借的过程不重建，免得单选按钮来回跳。
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_handleManager);
    // 管理器启动时核对的是目录第一档，这里对齐到真正选中的那一档。
    if (!_manager.isDownloading && _manager.phase != LocalModelPhase.loading) {
      unawaited(_manager.refresh());
    }
    unawaited(_scan());
  }

  @override
  void dispose() {
    _manager.removeListener(_handleManager);
    super.dispose();
  }

  void _handleManager() {
    if (!mounted || _busyId != null) return;
    setState(() {});
    // 下载 / 删除落盘后重扫一次，「已下载」标记跟着文件走。
    if (_manager.phase == LocalModelPhase.downloaded ||
        _manager.phase == LocalModelPhase.idle) {
      unawaited(_scan());
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      final dirs = await NativeBridge.appDirs();
      final found = <String>{};
      for (final spec in localModelCatalog) {
        final path =
            '${dirs.files}${Platform.pathSeparator}models'
            '${Platform.pathSeparator}${spec.fileName}';
        try {
          final file = File(path);
          // 只认完整的文件：半截下载（还有 .part）不算「已下载」。
          if (await file.exists() && await file.length() == spec.bytes) {
            found.add(spec.id);
          }
        } catch (_) {
          // 单个文件读不到别影响其它档。
        }
      }
      if (!mounted) return;
      setState(() {
        _downloaded
          ..clear()
          ..addAll(found);
      });
    } finally {
      _scanning = false;
    }
  }

  LocalModelSpec? _specById(String? id) {
    if (id == null) return null;
    for (final spec in localModelCatalog) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  Future<void> _select(LocalModelSpec spec) async {
    if (_busyId != null) return;
    if (_manager.isDownloading) {
      widget.onToast('等这次下载完再换模型，不然文件会乱');
      return;
    }
    if (_manager.spec.id == spec.id) return;
    _manager.selectedId = spec.id;
    widget.prefs.setAiLocalModelId(spec.id);
    widget.onSelectionChanged();
    await _manager.refresh();
    if (!mounted) return;
    widget.onToast('已切到 ${spec.name}，下次提问生效');
  }

  Future<void> _download(LocalModelSpec spec) async {
    if (_busyId != null || _manager.isDownloading) return;
    if (_manager.spec.id != spec.id) {
      // 下载器只下「当前选中」那一档，所以先选中再下。
      _manager.selectedId = spec.id;
      widget.prefs.setAiLocalModelId(spec.id);
      widget.onSelectionChanged();
      await _manager.refresh();
    }
    widget.onToast('开始下载 ${spec.name}（${spec.sizeLabel}），请保持网络畅通');
    await _manager.download();
    await _scan();
    if (!mounted) return;
    if (_manager.phase == LocalModelPhase.error) {
      widget.onToast(_manager.error ?? '下载失败');
      return;
    }
    widget.onToast(
      _manager.isDownloaded ? '${spec.name} 下载完成，下次提问会自动加载' : '下载已暂停，进度已保留',
    );
  }

  Future<void> _delete(LocalModelSpec spec) async {
    if (_busyId != null || _manager.isDownloading) return;
    final previous = _manager.spec;
    setState(() => _busyId = spec.id);
    try {
      // 管理器只会删「当前选中」那一档：临时选中，删完再切回去。
      if (previous.id != spec.id) {
        _manager.selectedId = spec.id;
        await _manager.refresh();
      }
      await _manager.deleteModel();
      if (previous.id != spec.id) {
        _manager.selectedId = previous.id;
        await _manager.refresh();
      }
      await _scan();
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
        widget.onSelectionChanged();
      }
    }
    if (!mounted) return;
    widget.onToast('已删掉 ${spec.name}，腾出 ${spec.sizeLabel} 空间');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.smart_toy_outlined, title: '模型选择'),
          const SizedBox(height: 8),
          Text(
            '模型不打进安装包（最小的也有 500 MB）：先选一档，再点「下载」存到手机上，'
            '下完就能离线聊，换模型不用重装 App。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: _manager.spec.id,
            onChanged: (id) {
              final spec = _specById(id);
              if (spec != null) unawaited(_select(spec));
            },
            child: Column(
              children: [
                for (final spec in localModelCatalog) _tile(context, spec),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '正在回答时换模型不影响这一条，下次提问才会用新模型。'
            '模型由 MediaPipe LLM Inference（Apache-2.0）在端侧运行，'
            '文件放在应用私有目录，卸载 App 会一起清掉。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, LocalModelSpec spec) {
    final scheme = Theme.of(context).colorScheme;
    final manager = _manager;
    final selected = manager.spec.id == spec.id;
    final downloading = selected && manager.isDownloading;
    final busy = _busyId != null;
    final downloaded =
        _downloaded.contains(spec.id) || (selected && manager.isDownloaded);

    final String status;
    final Color statusColor;
    if (downloading) {
      final percent = (manager.progress * 100).clamp(0, 100).toStringAsFixed(0);
      final received = (manager.receivedBytes / (1024 * 1024)).toStringAsFixed(
        0,
      );
      final total = (manager.totalBytes / (1024 * 1024)).toStringAsFixed(0);
      status = '正在下载 $percent% · $received/$total MB';
      statusColor = scheme.primary;
    } else if (selected && manager.phase == LocalModelPhase.loading) {
      status = '正在加载到内存…首次要 10~30 秒';
      statusColor = scheme.primary;
    } else if (selected && manager.phase == LocalModelPhase.ready) {
      status = '已就绪，可以离线对话';
      statusColor = scheme.primary;
    } else if (selected && manager.phase == LocalModelPhase.error) {
      status = manager.error ?? '出错了';
      statusColor = scheme.error;
    } else if (downloaded) {
      status = '已下载，下次提问时自动加载';
      statusColor = scheme.primary;
    } else {
      status = '还没下载';
      statusColor = scheme.onSurfaceVariant;
    }

    final Widget action;
    if (downloading) {
      action = FilledButton.tonalIcon(
        onPressed: null,
        icon: const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('暂停'),
        style: _compactButton,
      );
    } else if (downloaded) {
      action = OutlinedButton.icon(
        onPressed: busy || manager.isDownloading
            ? null
            : () => unawaited(_delete(spec)),
        icon: const Icon(Icons.delete_outline_rounded, size: 16),
        label: const Text('删除'),
        style: _compactButton,
      );
    } else {
      action = FilledButton.icon(
        onPressed: busy || manager.isDownloading
            ? null
            : () => unawaited(_download(spec)),
        icon: const Icon(Icons.download_rounded, size: 16),
        label: const Text('下载 / 继续'),
        style: _compactButton,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .42)
            : scheme.surfaceContainerHighest.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy || manager.isDownloading
              ? null
              : () => unawaited(_select(spec)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Radio<String>(
                    value: spec.id,
                    enabled: !busy && !manager.isDownloading,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          _Tag(text: spec.params),
                          _Tag(text: spec.sizeLabel),
                          _Tag(text: spec.license),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        spec.summary,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (downloading) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: manager.progress == 0
                                ? null
                                : manager.progress,
                            minHeight: 6,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            downloaded
                                ? Icons.check_circle_rounded
                                : Icons.cloud_download_outlined,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          action,
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
