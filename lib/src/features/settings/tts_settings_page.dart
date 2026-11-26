import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/icons/sakura_icons.dart';
import '../../core/theme/sakura_layout.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/prefs.dart';
import '../../data/tts_voice_catalog.dart';
import '../../data/tts_voice_store.dart';
import '../../platform/native_bridge.dart';
import '../../platform/tts_service.dart';

/// 听书与离线语音设置页：引擎检测、系统音色、离线语音包下载与 AI 分角色朗读。
class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  List<String>? _ttsEngines;
  List<String>? _ttsVoices;
  bool _ttsVoicesLoading = false;
  bool _ttsProbing = false;
  String? _ttsProbeResult;
  bool _ttsProbeOk = false;

  @override
  void initState() {
    super.initState();
    unawaited(TtsVoiceStore.instance.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    final tts = TtsService.instance;

    final hInsets = SakuraLayout.horizontalInsets(context);
    return Scaffold(
      appBar: AppBar(title: const Text('听书与离线语音')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SakuraLayout.detailMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(hInsets.left, 8, hInsets.right, 36),
              children: [
                Material(
                  color: sakura.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: sakura.hairline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([tts, widget.prefs]),
                      builder: (context, _) {
                        final engines = _ttsEngines;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SakuraIconBadge(
                                  glyph: SakuraGlyph.audio,
                                  color: scheme.primary,
                                  size: 38,
                                  iconSize: 19,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '语音引擎与自检',
                                        style: TextStyle(
                                          color: sakura.inkPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '系统无语音引擎时自动兜底「超文」内置离线语音',
                                        style: TextStyle(
                                          color: sakura.inkSecondary,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (engines == null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: const Icon(
                                  Icons.memory_rounded,
                                  size: 20,
                                ),
                                title: const Text(
                                  '语音引擎',
                                  style: TextStyle(fontSize: 14),
                                ),
                                subtitle: Text(
                                  _ttsProbing ? '正在检测…' : '点击检测设备上的语音引擎',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: _ttsProbing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.chevron_right_rounded),
                                onTap: _ttsProbing ? null : _probeTtsEngines,
                              )
                            else ...[
                              DropdownButtonFormField<String>(
                                initialValue: widget.prefs.ttsEngine,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '语音引擎',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('系统默认（推荐）'),
                                  ),
                                  const DropdownMenuItem(
                                    value: TtsService.builtinEngineId,
                                    child: Text('内置离线语音（无需安装）'),
                                  ),
                                  for (final e in engines)
                                    DropdownMenuItem(
                                      value: e,
                                      child: Text(
                                        _shortEngineName(e),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) => _changeTtsEngine(v ?? ''),
                              ),
                            ],
                            if (engines != null &&
                                engines.isNotEmpty &&
                                widget.prefs.ttsEngine !=
                                    TtsService.builtinEngineId) ...[
                              const SizedBox(height: 10),
                              if (_ttsVoices == null)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: const Icon(
                                    Icons.record_voice_over_rounded,
                                    size: 20,
                                  ),
                                  title: const Text(
                                    '音色（男声 / 女声）',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  subtitle: const Text(
                                    '点击加载系统音色列表',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  trailing: _ttsVoicesLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.chevron_right_rounded),
                                  onTap: _ttsVoicesLoading
                                      ? null
                                      : _loadTtsVoices,
                                )
                              else if (_ttsVoices!.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _ttsVoices!.contains(
                                        widget.prefs.ttsVoice,
                                      )
                                      ? widget.prefs.ttsVoice
                                      : '',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: '音色（男声 / 女声）',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('引擎默认音色'),
                                    ),
                                    for (final v in _ttsVoices!)
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          v,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) async {
                                    widget.prefs.setTtsVoice(v ?? '');
                                    final ok = await tts.setPreferredVoice(
                                      v ?? '',
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? '音色已切换，点「测试朗读」听听看'
                                              : '这个音色暂时用不了，先保持默认',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                            if (_ttsProbeResult != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    _ttsProbeOk
                                        ? Icons.check_circle_rounded
                                        : Icons.error_outline_rounded,
                                    size: 16,
                                    color: _ttsProbeOk
                                        ? scheme.primary
                                        : scheme.error,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _ttsProbeResult!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _ttsProbeOk
                                            ? sakura.inkSecondary
                                            : scheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _ttsProbing
                                      ? null
                                      : _probeTtsEngines,
                                  icon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('检测引擎'),
                                ),
                                FilledButton.icon(
                                  onPressed: _ttsProbing ? null : _testTts,
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('测试朗读'),
                                ),
                                if (_ttsEngines != null && _ttsEngines!.isEmpty)
                                  TextButton.icon(
                                    onPressed: () async {
                                      final ok =
                                          await NativeBridge.openTtsSettings();
                                      if (!ok && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '没能打开系统语音设置，请手动到「设置 → 无障碍 → 语音合成」查看',
                                                ),
                                              ),
                                            );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('去装系统语音'),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: sakura.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: sakura.hairline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _voicePackSection(context, scheme),
                        const Divider(height: 22),
                        AnimatedBuilder(
                          animation: widget.prefs,
                          builder: (_, _) => SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: widget.prefs.ttsRolePlay,
                            onChanged: widget.prefs.setTtsRolePlay,
                            secondary: const Icon(Icons.theater_comedy_rounded),
                            title: const Text(
                              'AI 分角色朗读',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              '旁白和对白用不同音调，同一角色保持一致；完全本地，不花 token',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voicePackSection(BuildContext context, ColorScheme scheme) {
    final store = TtsVoiceStore.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([store, widget.prefs]),
      builder: (context, _) {
        final currentId = widget.prefs.ttsVoicePack;
        final current = ttsVoicePackById(currentId) ?? builtinVoicePack;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '离线语音包',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '内置只有一个音色，想要更多男声 / 女声可按需下载',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final pack in ttsVoiceCatalog)
              _voicePackTile(context, scheme, store, pack, currentId),
            if (current.isMultiSpeaker) ...[
              const SizedBox(height: 8),
              Text(
                '音色（共 ${current.speakerCount} 个说话人）',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final preset in current.presets)
                    ChoiceChip(
                      label: Text(
                        preset.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: widget.prefs.ttsVoiceSid == preset.sid,
                      onSelected: (_) {
                        widget.prefs.setTtsVoiceSid(preset.sid);
                        unawaited(
                          TtsService.instance.setVoicePack(
                            current.id,
                            preset.sid,
                          ),
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _voicePackTile(
    BuildContext context,
    ColorScheme scheme,
    TtsVoiceStore store,
    TtsVoicePack pack,
    String currentId,
  ) {
    final installed = store.isInstalled(pack.id);
    final downloading = store.isDownloading(pack.id);
    final active = currentId == pack.id;
    final error = store.errorOf(pack.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: active
            ? Border.all(color: scheme.primary.withValues(alpha: 0.55))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          pack.bundled
                              ? '内置'
                              : '${pack.sizeMb.toStringAsFixed(0)} MB',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pack.tagline,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (downloading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: store.progressOf(pack.id) == 0
                        ? null
                        : store.progressOf(pack.id),
                  ),
                )
              else if (installed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!active)
                      TextButton(
                        onPressed: () => _selectVoicePack(pack),
                        child: const Text('使用', style: TextStyle(fontSize: 12)),
                      ),
                    if (!pack.bundled)
                      IconButton(
                        tooltip: '删除这个语音包',
                        onPressed: store.downloadingId == null
                            ? () async {
                                await store.remove(pack.id);
                                if (widget.prefs.ttsVoicePack == pack.id) {
                                  widget.prefs.setTtsVoicePack(
                                    builtinVoicePack.id,
                                  );
                                  widget.prefs.setTtsVoiceSid(0);
                                  unawaited(
                                    TtsService.instance.setVoicePack(
                                      builtinVoicePack.id,
                                      0,
                                    ),
                                  );
                                }
                                if (mounted) setState(() {});
                              }
                            : null,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                  ],
                )
              else
                FilledButton.tonal(
                  onPressed: store.downloadingId == null
                      ? () => _downloadVoicePack(pack)
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('下载', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: store.progressOf(pack.id) == 0
                  ? null
                  : store.progressOf(pack.id),
              minHeight: 4,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error, style: TextStyle(fontSize: 11.5, color: scheme.error)),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadVoicePack(TtsVoicePack pack) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await TtsVoiceStore.instance.install(pack);
    if (!mounted) return;
    if (ok) {
      await _selectVoicePack(pack);
      messenger.showSnackBar(SnackBar(content: Text('「${pack.name}」装好了，已切换')));
    } else {
      setState(() {});
    }
  }

  Future<void> _selectVoicePack(TtsVoicePack pack) async {
    widget.prefs.setTtsVoicePack(pack.id);
    widget.prefs.setTtsVoiceSid(pack.defaultSid);
    await TtsService.instance.setVoicePack(pack.id, pack.defaultSid);
    if (mounted) setState(() {});
  }

  Future<void> _loadTtsVoices() async {
    if (_ttsVoicesLoading) return;
    setState(() => _ttsVoicesLoading = true);
    try {
      final tts = TtsService.instance;
      await tts.ensureReady();
      final list = await tts.voices();
      if (!mounted) return;
      setState(() => _ttsVoices = list);
    } finally {
      if (mounted) setState(() => _ttsVoicesLoading = false);
    }
  }

  String _shortEngineName(String pkg) {
    final parts = pkg.split('.');
    if (parts.length >= 2) return '${parts[parts.length - 2]} · $pkg';
    return pkg;
  }

  Future<void> _probeTtsEngines() async {
    setState(() {
      _ttsProbing = true;
      _ttsProbeResult = null;
    });
    final tts = TtsService.instance;
    final list = await tts.engines();
    if (!mounted) return;
    await tts.setPreferredEngine(widget.prefs.ttsEngine);
    if (!mounted) return;
    final voices = list.isEmpty ? const <String>[] : await tts.voices();
    if (!mounted) return;
    setState(() {
      _ttsEngines = list;
      _ttsVoices = voices;
      _ttsProbing = false;
      _ttsProbeResult = list.isEmpty
          ? '没有系统语音引擎，可以改用上面的「内置离线语音」'
          : '检测到 ${list.length} 个引擎';
      _ttsProbeOk = true;
    });
  }

  Future<void> _changeTtsEngine(String engine) async {
    final tts = TtsService.instance;
    widget.prefs.setTtsEngine(engine);
    await tts.setPreferredEngine(engine);
    if (!mounted) return;
    setState(() {
      _ttsProbeResult = engine == TtsService.builtinEngineId
          ? '已切到内置离线语音（首次使用会释放语音模型，约需几秒）'
          : '已切换引擎，点「测试朗读」验证';
      _ttsProbeOk = true;
    });
  }

  Future<void> _testTts() async {
    final tts = TtsService.instance;
    setState(() {
      _ttsProbing = true;
      _ttsProbeResult = null;
    });
    await tts.setPreferredEngine(widget.prefs.ttsEngine);
    final ok = await tts.reinit();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _ttsProbing = false;
        _ttsProbeOk = false;
        _ttsProbeResult = tts.lastError ?? '初始化失败，试试换一个引擎';
      });
      return;
    }
    await tts.start(['樱读朗读测试，听到这句话说明朗读正常。'], from: 0);
    if (!mounted) return;
    setState(() {
      _ttsProbing = false;
      _ttsProbeOk = true;
      _ttsProbeResult = tts.usingOffline
          ? '正在用内置离线语音播放…能听到声音就说明可用'
          : '正在播放测试语音…能听到声音就说明可用';
    });
  }
}
