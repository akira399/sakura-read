import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/ai_service.dart';
import '../../data/prefs.dart';
import '../../source/http_client.dart';
import '../../source/models.dart';
import '../../source/source_store.dart';
import '../../ui/ai_settings_page.dart';
import 'ai_source_studio.dart';

/// 实时书源调试器 + AI 智能写源工坊（Design System 2.0）。
class SourceDebuggerPage extends StatefulWidget {
  const SourceDebuggerPage({
    super.key,
    required this.store,
    this.initialSource,
    this.initialTab = 0,
    this.prefs,
    this.httpClient,
    this.studio,
  });

  final SourceStore store;
  final BookSource? initialSource;
  final int initialTab;
  final AppPrefs? prefs;
  final SourceHttpClient? httpClient;
  final AiSourceStudio? studio;

  @override
  State<SourceDebuggerPage> createState() => _SourceDebuggerPageState();
}

class _SourceDebuggerPageState extends State<SourceDebuggerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );

  late final SourceDebugRunner _runner = SourceDebugRunner(
    client: widget.httpClient,
  );
  late final AiSourceStudio _studio =
      widget.studio ?? AiSourceStudio(httpClient: widget.httpClient);

  // ---- Tab 1: 实时四阶段调试状态 ----
  BookSource? _selectedSource;
  final TextEditingController _keywordCtrl = TextEditingController(
    text: AiSourceStudio.defaultKeyword,
  );
  bool _debugRunning = false;
  final Map<SourceDebugStage, SourceDebugStageResult> _stageMap = {};
  SourceDebugTrace? _lastTrace;

  // ---- Tab 2: AI 一键写源工坊状态 ----
  final TextEditingController _siteUrlCtrl = TextEditingController();
  final TextEditingController _searchHintCtrl = TextEditingController();
  final TextEditingController _studioKeywordCtrl = TextEditingController(
    text: AiSourceStudio.defaultKeyword,
  );
  BookSource? _repairTarget;
  String? _repairError;
  bool _autoImport = true;
  bool _studioRunning = false;
  String _studioStatus = '';
  String? _studioError;
  AiSourceStudioResult? _studioResult;
  bool _autoImported = false;
  final List<AiSourceStepEvent> _studioSteps = [];
  AiCancelToken? _cancelToken;

  AppPrefs? _resolvedPrefs;

  @override
  void initState() {
    super.initState();
    _selectedSource =
        widget.initialSource ??
        (widget.store.sources.isNotEmpty ? widget.store.sources.first : null);
    if (widget.initialSource != null) {
      _siteUrlCtrl.text = widget.initialSource!.bookSourceUrl;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvedPrefs = widget.prefs;
    if (_resolvedPrefs == null) {
      try {
        _resolvedPrefs = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(prefsProvider);
      } catch (_) {
        // 独立测试未包 ProviderScope 时忽略
      }
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    _tabs.dispose();
    _runner.dispose();
    if (widget.studio == null) _studio.dispose();
    _keywordCtrl.dispose();
    _siteUrlCtrl.dispose();
    _searchHintCtrl.dispose();
    _studioKeywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _runDebug() async {
    final source = _selectedSource;
    final rawKw = _keywordCtrl.text.trim();
    final keyword = rawKw.isEmpty ? AiSourceStudio.defaultKeyword : rawKw;
    if (source == null || _debugRunning) return;
    setState(() {
      _debugRunning = true;
      _stageMap.clear();
      _lastTrace = null;
    });
    final trace = await _runner.run(
      source,
      keyword,
      onStage: (stageResult) {
        if (!mounted) return;
        setState(() => _stageMap[stageResult.stage] = stageResult);
      },
    );
    if (!mounted) return;
    setState(() {
      _debugRunning = false;
      _lastTrace = trace;
    });
  }

  void _sendToAiRepair() {
    final source = _selectedSource;
    if (source == null) return;
    setState(() {
      _repairTarget = source;
      _repairError = _lastTrace?.errorSummary;
      _siteUrlCtrl.text = source.bookSourceUrl;
      _studioKeywordCtrl.text = _keywordCtrl.text.trim().isEmpty
          ? AiSourceStudio.defaultKeyword
          : _keywordCtrl.text.trim();
    });
    _tabs.animateTo(1);
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() {
      _siteUrlCtrl.text = text;
      _studioError = null;
    });
  }

  Future<void> _openQuickOnlineConfig() async {
    final prefs = _resolvedPrefs;
    if (prefs == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => _QuickOnlineAiSheet(prefs: prefs),
    );
    if (saved == true && mounted) {
      setState(() => _studioError = null);
    }
  }

  Future<void> _runAiStudio() async {
    final url = _siteUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _studioError = '请先输入或粘贴目标小说网站链接');
      return;
    }
    if (_studioRunning) return;
    FocusScope.of(context).unfocus();

    final cancel = AiCancelToken();
    _cancelToken = cancel;
    setState(() {
      _studioRunning = true;
      _studioStatus = '准备抓页分析…';
      _studioError = null;
      _studioResult = null;
      _autoImported = false;
      _studioSteps.clear();
      _stageMap.clear();
    });

    try {
      final res = await _studio.generateAndValidate(
        siteUrl: url,
        prefs: _resolvedPrefs,
        keyword: _studioKeywordCtrl.text.trim(),
        searchUrlHint: _searchHintCtrl.text.trim().isEmpty
            ? null
            : _searchHintCtrl.text.trim(),
        existingToRepair: _repairTarget,
        repairError: _repairError,
        cancelToken: cancel,
        onProgress: (status) {
          if (mounted) setState(() => _studioStatus = status);
        },
        onStep: (ev) {
          if (mounted) {
            setState(() => _studioSteps.add(ev));
          }
        },
        onValidationStage: (stage) {
          if (mounted) {
            setState(() => _stageMap[stage.stage] = stage);
          }
        },
      );
      if (!mounted) return;

      var imported = false;
      if (res.validated && _autoImport) {
        final report = widget.store.addAll([res.source]);
        unawaited(widget.store.flush());
        imported = true;
        _selectedSource = res.source;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                report.updated > 0
                    ? '验证通过并已更新书源「${res.source.bookSourceName}」'
                    : '验证通过并已自动导入书源「${res.source.bookSourceName}」',
              ),
            ),
          );
        }
      }

      setState(() {
        _studioRunning = false;
        _studioStatus = '';
        _studioResult = res;
        _autoImported = imported;
        _lastTrace = res.validationTrace;
        if (res.validationTrace != null) {
          for (final s in res.validationTrace!.stages) {
            _stageMap[s.stage] = s;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _studioRunning = false;
        _studioStatus = '';
        _studioError = '$e';
      });
    } finally {
      if (identical(_cancelToken, cancel)) {
        _cancelToken = null;
      }
    }
  }

  void _saveGeneratedSource({bool asDraft = false}) {
    final res = _studioResult;
    if (res == null) return;
    final report = widget.store.addAll([res.source]);
    unawaited(widget.store.flush());
    setState(() {
      _selectedSource = res.source;
      _autoImported = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          asDraft
              ? '已将草稿「${res.source.bookSourceName}」保存到书源库'
              : (report.updated > 0
                    ? '已更新书源「${res.source.bookSourceName}」'
                    : '已保存新书源「${res.source.bookSourceName}」到书源库'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.sakura;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('书源调试与 AI 工坊'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.bug_report_outlined, size: 18), text: '实时调试'),
            Tab(
              icon: Icon(Icons.auto_awesome_outlined, size: 18),
              text: 'AI 写源工坊',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLiveDebuggerTab(context, colors),
          _buildAiStudioTab(context, colors),
        ],
      ),
    );
  }

  // ---------- Tab 1: 四阶段实时调试 ----------

  Widget _buildLiveDebuggerTab(BuildContext context, SakuraColors colors) {
    final sources = widget.store.sources;
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择调试书源',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.inkSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (sources.isEmpty)
                Text(
                  '书源库为空，可先切换到「AI 写源工坊」贴入网站链接一键生成。',
                  style: TextStyle(color: colors.inkSecondary, fontSize: 13),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedSource?.bookSourceUrl,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.bookSourceUrl,
                        child: Text(
                          s.bookSourceName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _debugRunning
                      ? null
                      : (url) {
                          if (url == null) return;
                          final found = widget.store.byUrl(url);
                          if (found != null) {
                            setState(() {
                              _selectedSource = found;
                              _stageMap.clear();
                              _lastTrace = null;
                            });
                          }
                        },
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _keywordCtrl,
                decoration: const InputDecoration(
                  labelText: '测试关键词',
                  hintText: '输入书名或常用词，例如：我的 / 斗破苍穹 / 诡秘之主',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_selectedSource == null || _debugRunning)
                          ? null
                          : _runDebug,
                      icon: Icon(
                        _debugRunning
                            ? Icons.hourglass_top_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(_debugRunning ? '调试运行中…' : '开始四阶段调试'),
                    ),
                  ),
                  if (_debugRunning) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _runner.cancel,
                      child: const Text('停止'),
                    ),
                  ] else if (_lastTrace != null && !_lastTrace!.allPassed) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _sendToAiRepair,
                      icon: Icon(
                        Icons.auto_fix_high_rounded,
                        size: 16,
                        color: accent,
                      ),
                      label: const Text('AI 修复'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final stage in SourceDebugStage.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StageCard(
              stage: stage,
              result: _stageMap[stage],
              colors: colors,
            ),
          ),
      ],
    );
  }

  // ---------- Tab 2: AI 一键写源工坊 ----------

  Widget _buildAiStudioTab(BuildContext context, SakuraColors colors) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final prefs = _resolvedPrefs;
    final onlineReady = prefs?.aiHttpConfigured ?? false;
    final res = _studioResult;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        // 1. 在线大模型状态条（明确仅支持在线模型 + 一键配置入口）
        if (prefs != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: onlineReady
                  ? const Color(0xFF3E9C73).withValues(alpha: 0.10)
                  : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: onlineReady
                    ? const Color(0xFF3E9C73).withValues(alpha: 0.35)
                    : Colors.orange.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  onlineReady
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  size: 18,
                  color: onlineReady
                      ? const Color(0xFF2D8660)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    onlineReady
                        ? '在线模型已就绪：${prefs.aiModel}'
                        : 'AI 写源仅支持在线大模型（本地小模型暂无法稳定解析网页规则）',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.inkPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _studioRunning ? null : _openQuickOnlineConfig,
                  child: Text(onlineReady ? '切换接口' : '快速配置在线模型'),
                ),
              ],
            ),
          ),

        // 2. 一键输入与操作主卡片
        Material(
          color: colors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colors.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _repairTarget == null
                                ? 'AI 一键写源（贴入网址即可）'
                                : 'AI 自动修复：${_repairTarget!.bookSourceName}',
                            style: TextStyle(
                              color: colors.inkPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          Text(
                            'AI 自动取证首页 / 搜索 / 详情 / 目录 / 正文 → 4 阶段实测通过后自动导入',
                            style: TextStyle(
                              color: colors.inkSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_repairTarget != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _repairTarget = null;
                          _repairError = null;
                        }),
                        child: const Text('改为新建'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _siteUrlCtrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _runAiStudio(),
                  decoration: InputDecoration(
                    labelText: '目标小说网站链接',
                    hintText: 'https://www.example.com',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_siteUrlCtrl.text.isNotEmpty)
                          IconButton(
                            tooltip: '清空',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _studioRunning
                                ? null
                                : () => setState(() => _siteUrlCtrl.clear()),
                          ),
                        IconButton(
                          tooltip: '从剪贴板粘贴网址',
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          onPressed: _studioRunning ? null : _pasteUrl,
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 6, bottom: 4),
                    dense: true,
                    title: Text(
                      '高级选项（测试词「${_studioKeywordCtrl.text.trim().isEmpty ? AiSourceStudio.defaultKeyword : _studioKeywordCtrl.text.trim()}」· ${_autoImport ? '通过即自动导入' : '仅生成不导入'}）',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _searchHintCtrl,
                              decoration: const InputDecoration(
                                labelText: '搜索页地址参考（可选）',
                                hintText: '/search.php?q=我的',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _studioKeywordCtrl,
                              decoration: const InputDecoration(
                                labelText: '验证关键词',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _autoImport,
                        onChanged: _studioRunning
                            ? null
                            : (v) => setState(() => _autoImport = v),
                        title: const Text(
                          '4 阶段实测全部通过后自动导入书源库',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _studioRunning ? null : _runAiStudio,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(
                          _studioRunning
                              ? (_studioStatus.isEmpty
                                    ? '分析生成中…'
                                    : _studioStatus)
                              : (_repairTarget == null
                                    ? 'AI 一键写源并导入'
                                    : 'AI 自动修复并更新'),
                        ),
                      ),
                    ),
                    if (_studioRunning) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          _cancelToken?.cancel('user_cancelled');
                          setState(() {
                            _studioRunning = false;
                            _studioStatus = '';
                            _studioError = '已手动停止当前写源任务';
                          });
                        },
                        child: const Text('停止'),
                      ),
                    ],
                  ],
                ),
                if (_studioRunning) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
                if (_studioError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _studioError!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 3. 结果与报错诊断卡片（置顶展示，无需先滑过长链路日志）
        if (res != null) ...[
          const SizedBox(height: 14),
          Material(
            color: colors.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: res.validated
                    ? const Color(0xFF3E9C73).withValues(alpha: 0.45)
                    : Colors.orange.withValues(alpha: 0.50),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        res.validated
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 20,
                        color: res.validated
                            ? const Color(0xFF3E9C73)
                            : const Color(0xFFD9822B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          res.source.bookSourceName,
                          style: TextStyle(
                            color: colors.inkPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (res.validationTrace != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: res.validated
                                ? Colors.green.withValues(alpha: 0.14)
                                : Colors.orange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '实测 ${res.validationTrace!.passedCount}/4 阶段通过',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: res.validated
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (res.validated && _autoImported) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E9C73).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '已自动导入书源库！示例书籍：《${res.validationTrace?.sampleBook?.name ?? '未知'}》 · '
                        '目录 ${res.validationTrace?.sampleChapters.length ?? 0} 章 · '
                        '正文 ${res.validationTrace?.sampleContent.trim().length ?? 0} 字',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                  if (!res.validated && res.failureReason != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        res.failureReason!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: colors.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!res.validated)
                        FilledButton.icon(
                          onPressed: _studioRunning
                              ? null
                              : () {
                                  setState(() {
                                    _repairTarget = res.source;
                                    _repairError =
                                        res.validationTrace?.errorSummary;
                                  });
                                  _runAiStudio();
                                },
                          icon: const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 17,
                          ),
                          label: const Text('AI 继续修复'),
                        ),
                      if (!_autoImported)
                        res.validated
                            ? FilledButton.icon(
                                onPressed: () => _saveGeneratedSource(),
                                icon: const Icon(
                                  Icons.save_alt_rounded,
                                  size: 17,
                                ),
                                label: const Text('导入书源库'),
                              )
                            : OutlinedButton.icon(
                                onPressed: () =>
                                    _saveGeneratedSource(asDraft: true),
                                icon: const Icon(
                                  Icons.save_alt_rounded,
                                  size: 17,
                                ),
                                label: const Text('仍保存草稿'),
                              ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedSource = res.source;
                            _stageMap.clear();
                            if (res.validationTrace != null) {
                              for (final s in res.validationTrace!.stages) {
                                _stageMap[s.stage] = s;
                              }
                              _lastTrace = res.validationTrace;
                            }
                          });
                          _tabs.animateTo(0);
                        },
                        icon: const Icon(Icons.bug_report_outlined, size: 17),
                        label: const Text('查看 4 阶段详情'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: res.formattedJson),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制书源 JSON')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('复制 JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      dense: true,
                      initiallyExpanded: !res.validated,
                      title: Text(
                        '查看生成的 Legado 3.0 书源 JSON',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.inkSecondary,
                        ),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 260),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              res.formattedJson,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: colors.inkPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // 4. 实时步骤时间线（取证 / 实测 / 修复）
        if (_studioSteps.isNotEmpty) _buildStepsTimeline(colors),
      ],
    );
  }

  Widget _buildStepsTimeline(SakuraColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 执行链路（${_studioSteps.length} 步）',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: colors.inkSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final step in _studioSteps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _StepRow(step: step, colors: colors),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.colors});

  final AiSourceStepEvent step;
  final SakuraColors colors;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.kind) {
      AiSourceStepKind.fetch => (Icons.public_rounded, const Color(0xFF3B82F6)),
      AiSourceStepKind.debug => (
        Icons.bug_report_outlined,
        Theme.of(context).colorScheme.primary,
      ),
      AiSourceStepKind.repair => (
        Icons.auto_fix_high_rounded,
        const Color(0xFFD97706),
      ),
      AiSourceStepKind.success => (
        Icons.check_circle_rounded,
        const Color(0xFF3E9C73),
      ),
      AiSourceStepKind.error => (
        Icons.error_rounded,
        Theme.of(context).colorScheme.error,
      ),
      AiSourceStepKind.info => (
        Icons.auto_awesome_rounded,
        colors.inkSecondary,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.inkPrimary,
                ),
              ),
              if ((step.detail ?? '').trim().isNotEmpty)
                Text(
                  step.detail!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.inkSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickOnlineAiSheet extends StatefulWidget {
  const _QuickOnlineAiSheet({required this.prefs});

  final AppPrefs prefs;

  @override
  State<_QuickOnlineAiSheet> createState() => _QuickOnlineAiSheetState();
}

class _QuickOnlineAiSheetState extends State<_QuickOnlineAiSheet> {
  late final TextEditingController _baseCtrl = TextEditingController(
    text: widget.prefs.aiBaseUrl.isEmpty
        ? 'https://api.deepseek.com/v1'
        : widget.prefs.aiBaseUrl,
  );
  late final TextEditingController _keyCtrl = TextEditingController(
    text: widget.prefs.aiApiKey,
  );
  late final TextEditingController _modelCtrl = TextEditingController(
    text: widget.prefs.aiModel.isEmpty ? 'deepseek-chat' : widget.prefs.aiModel,
  );
  bool _showKey = false;
  bool _testing = false;
  String? _statusMsg;

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(AiProviderPreset preset) {
    setState(() {
      _baseCtrl.text = preset.baseUrl;
      _modelCtrl.text = preset.defaultModel;
      _statusMsg = null;
    });
  }

  Future<void> _test() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _statusMsg = null;
    });
    final ai = AiService();
    try {
      final reply = await ai.testConnection(
        baseUrl: _baseCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
      );
      if (mounted) setState(() => _statusMsg = '连接成功：$reply');
    } catch (e) {
      if (mounted) setState(() => _statusMsg = '连接失败：$e');
    } finally {
      ai.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final base = _baseCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (base.isEmpty || model.isEmpty) {
      setState(() => _statusMsg = '请先填写接口地址与模型名称');
      return;
    }
    widget.prefs.setAiConfig(
      baseUrl: base,
      apiKey: _keyCtrl.text.trim(),
      model: model,
      includeReading: widget.prefs.aiIncludeReading,
    );
    await widget.prefs.flush();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final onlinePresets = kAiProviderPresets
        .where((p) => p.id != 'ollama')
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '配置在线大模型（用于 AI 写源）',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '推荐使用 DeepSeek / OpenAI / Gemini / Kimi；不影响你在聊天里使用本地模型。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final p in onlinePresets)
                    ActionChip(
                      label: Text(p.name),
                      onPressed: () => _applyPreset(p),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baseCtrl,
                decoration: const InputDecoration(
                  labelText: '接口地址（Base URL）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _keyCtrl,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_statusMsg != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMsg!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusMsg!.startsWith('连接成功')
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AiSettingsPage(prefs: widget.prefs),
                        ),
                      );
                    },
                    child: const Text('完整设置'),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('保存并启用')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.result,
    required this.colors,
  });

  final SourceDebugStage stage;
  final SourceDebugStageResult? result;
  final SakuraColors colors;

  String get _defaultTitle => switch (stage) {
    SourceDebugStage.search => '1. 搜索（Search）',
    SourceDebugStage.info => '2. 详情（BookInfo）',
    SourceDebugStage.toc => '3. 目录（TOC）',
    SourceDebugStage.content => '4. 正文（Content）',
  };

  @override
  Widget build(BuildContext context) {
    final r = result;
    final status = r?.status ?? DebugStageStatus.pending;
    final (icon, iconColor) = switch (status) {
      DebugStageStatus.pending => (
        Icons.radio_button_unchecked,
        colors.inkSecondary,
      ),
      DebugStageStatus.running => (
        Icons.sync_rounded,
        Theme.of(context).colorScheme.primary,
      ),
      DebugStageStatus.success => (
        Icons.check_circle_rounded,
        const Color(0xFF3E9C73),
      ),
      DebugStageStatus.warning => (
        Icons.warning_amber_rounded,
        const Color(0xFFD9822B),
      ),
      DebugStageStatus.error => (
        Icons.error_rounded,
        Theme.of(context).colorScheme.error,
      ),
    };

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.hairline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded:
              status == DebugStageStatus.error ||
              status == DebugStageStatus.success,
          leading: Icon(icon, color: iconColor, size: 22),
          title: Text(
            r?.stageTitle ?? _defaultTitle,
            style: TextStyle(
              color: colors.inkPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            r == null ? '等待执行' : r.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.inkSecondary, fontSize: 12),
          ),
          trailing: r == null
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (r.httpStatus != null)
                      Text(
                        'HTTP ${r.httpStatus}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: iconColor,
                        ),
                      ),
                    Text(
                      '${r.elapsedMs} ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
          children: [
            if (r != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((r.url ?? '').isNotEmpty) _kv('请求地址', r.url!),
                    if (r.error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(
                          r.error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    if (r.matchedRules.isNotEmpty) ...[
                      _sectionHeader('命中规则'),
                      for (final e in r.matchedRules.entries)
                        _kv(e.key, e.value),
                    ],
                    if (r.extractedFields.isNotEmpty) ...[
                      _sectionHeader('提取字段'),
                      for (final e in r.extractedFields.entries)
                        _kv(e.key, e.value),
                    ],
                    if (r.jsLogs.isNotEmpty) ...[
                      _sectionHeader('JS 日志（${r.jsLogs.length}）'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(
                          r.jsLogs.join('\n'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: colors.inkPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: colors.inkSecondary,
      ),
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: colors.inkSecondary),
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: TextStyle(fontSize: 12, color: colors.inkPrimary),
          ),
        ),
      ],
    ),
  );
}
