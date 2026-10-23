import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/local_llm.dart';
import '../data/prefs.dart';
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
    localModels.selectedId = widget.prefs.aiLocalModelId;
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

  void _save() {
    if (_useLocal) {
      // 本地模式不校验接口；模型没下载也可以先保存，对话页会引导下载。
      widget.prefs.setAiUseLocalModel(true);
      widget.prefs.setAiLocalModelId(localModels.spec.id);
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
    _toast('已保存');
    Navigator.of(context).pop();
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
            _LocalModelCard(prefs: widget.prefs, onToast: _toast)
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
          const SectionTitle(
            icon: Icons.memory_rounded,
            title: '运行方式',
          ),
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
            subtitle: '模型下载到手机后完全离线运行，不联网、不花钱',
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

/// 本地模型的下载 / 删除 / 状态卡片。
class _LocalModelCard extends StatelessWidget {
  const _LocalModelCard({required this.prefs, required this.onToast});

  final AppPrefs prefs;
  final void Function(String) onToast;

  Future<void> _download(BuildContext context) async {
    final manager = LocalModelManager.instance;
    if (!manager.isDownloaded) {
      onToast('开始下载 ${manager.spec.name}（${manager.spec.sizeLabel}），'
          '请保持网络畅通');
      await manager.download();
      if (manager.phase == LocalModelPhase.error) {
        onToast(manager.error ?? '下载失败');
      } else {
        onToast('模型下载完成');
      }
      return;
    }
    if (manager.isReady) return;
    onToast('正在把模型加载到内存…');
    final ok = await manager.ensureLoaded();
    onToast(ok ? '模型已就绪' : (manager.error ?? '加载失败'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manager = LocalModelManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final spec = manager.spec;
        final downloaded = manager.isDownloaded;
        final percent = (manager.progress * 100).clamp(0, 100).toStringAsFixed(0);
        final receivedMb = (manager.receivedBytes / (1024 * 1024))
            .toStringAsFixed(1);
        final totalMb = (manager.totalBytes / (1024 * 1024)).toStringAsFixed(0);

        String status;
        Color statusColor = scheme.onSurfaceVariant;
        switch (manager.phase) {
          case LocalModelPhase.downloading:
            status = '正在下载 $percent% · $receivedMb/$totalMb MB';
            statusColor = scheme.primary;
          case LocalModelPhase.downloaded:
            status = '已下载（${spec.sizeLabel}），可以开始对话';
            statusColor = scheme.primary;
          case LocalModelPhase.loading:
            status = '正在加载到内存…首次约 10~30 秒';
            statusColor = scheme.primary;
          case LocalModelPhase.ready:
            status = '已就绪，可以离线对话';
            statusColor = scheme.primary;
          case LocalModelPhase.error:
            status = manager.error ?? '出错了';
            statusColor = scheme.error;
          case LocalModelPhase.idle:
            status = '还没下载（${spec.sizeLabel}），下载一次长期可用';
        }

        return SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.smart_toy_outlined,
                title: '本地模型',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _Tag(text: spec.params),
                  const SizedBox(width: 6),
                  _Tag(text: spec.license),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                spec.summary,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (manager.phase == LocalModelPhase.downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: manager.progress == 0 ? null : manager.progress,
                    minHeight: 7,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Icon(
                    downloaded
                        ? Icons.check_circle_outline_rounded
                        : Icons.download_outlined,
                    size: 15,
                    color: statusColor,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(fontSize: 12, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!downloaded)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: manager.isDownloading
                            ? null
                            : () => _download(context),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          manager.isDownloading ? '下载中…' : '下载模型',
                        ),
                      ),
                    )
                  else ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: manager.isDownloading
                            ? null
                            : () async {
                                await manager.deleteModel();
                                onToast('模型文件已删除');
                              },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('删除模型'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: manager.isReady || manager.phase == LocalModelPhase.loading
                            ? null
                            : () => _download(context),
                        icon: const Icon(Icons.memory_rounded, size: 18),
                        label: Text(
                          manager.isReady
                              ? '已就绪'
                              : (manager.phase == LocalModelPhase.loading
                                    ? '加载中…'
                                    : '提前加载'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '模型由 MediaPipe LLM Inference（Apache-2.0）在端侧运行；'
                '文件保存在应用私有目录，卸载 App 会一并清除。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
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
