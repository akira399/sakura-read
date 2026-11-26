import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/prefs.dart';
import '../../source/http_client.dart';
import '../../source/models.dart';
import '../../source/source_store.dart';
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
  final TextEditingController _keywordCtrl = TextEditingController(text: '西游记');
  bool _debugRunning = false;
  final Map<SourceDebugStage, SourceDebugStageResult> _stageMap = {};
  SourceDebugTrace? _lastTrace;

  // ---- Tab 2: AI 写源工坊状态 ----
  final TextEditingController _siteUrlCtrl = TextEditingController();
  final TextEditingController _searchHintCtrl = TextEditingController();
  final TextEditingController _studioKeywordCtrl = TextEditingController(
    text: '西游记',
  );
  BookSource? _repairTarget;
  String? _repairError;
  bool _studioRunning = false;
  String _studioStatus = '';
  String? _studioError;
  AiSourceStudioResult? _studioResult;

  AppPrefs? _resolvedPrefs;

  @override
  void initState() {
    super.initState();
    _selectedSource =
        widget.initialSource ??
        (widget.store.sources.isNotEmpty ? widget.store.sources.first : null);
    if (_selectedSource != null) {
      _siteUrlCtrl.text = _selectedSource!.bookSourceUrl;
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
    final keyword = _keywordCtrl.text.trim();
    if (source == null || keyword.isEmpty || _debugRunning) return;
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
          ? '西游记'
          : _keywordCtrl.text.trim();
    });
    _tabs.animateTo(1);
  }

  Future<void> _runAiStudio() async {
    final url = _siteUrlCtrl.text.trim();
    if (url.isEmpty || _studioRunning) return;
    setState(() {
      _studioRunning = true;
      _studioStatus = '准备抓页…';
      _studioError = null;
      _studioResult = null;
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
        onProgress: (status) {
          if (mounted) setState(() => _studioStatus = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _studioRunning = false;
        _studioStatus = '';
        _studioResult = res;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _studioRunning = false;
        _studioStatus = '';
        _studioError = '$e';
      });
    }
  }

  void _saveGeneratedSource() {
    final res = _studioResult;
    if (res == null) return;
    final report = widget.store.addAll([res.source]);
    setState(() {
      _selectedSource = res.source;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          report.updated > 0
              ? '已更新书源「${res.source.bookSourceName}」'
              : '已保存新书源「${res.source.bookSourceName}」到书源库',
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
                  '书源库为空，可先切换到「AI 写源工坊」生成一个新书源。',
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
                  hintText: '输入书名或作者，例如：西游记 / 诡秘之主',
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

  // ---------- Tab 2: AI 智能写源工坊 ----------

  Widget _buildAiStudioTab(BuildContext context, SakuraColors colors) {
    final accent = Theme.of(context).colorScheme.primary;
    final aiReady = _resolvedPrefs?.aiConfigured ?? false;
    final res = _studioResult;

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
                              ? 'AI 自动写源（Legado 3.0）'
                              : 'AI 修复书源：${_repairTarget!.bookSourceName}',
                          style: TextStyle(
                            color: colors.inkPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        Text(
                          aiReady
                              ? '抓取站点 DOM → 大模型生成规则 → 自动四阶段实测校验'
                              : '提示：请先在「设置 → AI 助手」配置模型接口',
                          style: TextStyle(
                            color: colors.inkSecondary,
                            fontSize: 12,
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
                decoration: const InputDecoration(
                  labelText: '目标小说网站 URL',
                  hintText: 'https://www.example.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _searchHintCtrl,
                      decoration: const InputDecoration(
                        labelText: '搜索页地址参考（可选）',
                        hintText: '/search.php?q=西游记',
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _studioRunning ? null : _runAiStudio,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    _studioRunning
                        ? (_studioStatus.isEmpty ? '生成中…' : _studioStatus)
                        : (_repairTarget == null ? '抓取页面并生成书源' : '抓取页面并修复书源'),
                  ),
                ),
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
                    color: Theme.of(context).colorScheme.errorContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _studioError!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (res != null) ...[
          const SizedBox(height: 14),
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
                Row(
                  children: [
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
                            color: res.validated ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _saveGeneratedSource,
                      icon: const Icon(Icons.save_alt_rounded, size: 17),
                      label: const Text('保存到书源库'),
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
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 280),
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
      ],
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
