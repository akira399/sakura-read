import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/sakura_database.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/sakura_tokens.dart';
import 'replace_rule.dart';
import 'replace_rule_store.dart';

/// 正文净化 / 替换规则管理页（Design System 2.0 · 兼容 Legado 3.0 JSON）。
class ReplaceRulesPage extends StatefulWidget {
  const ReplaceRulesPage({super.key, this.store, this.database});

  final ReplaceRuleStore? store;
  final SakuraDatabase? database;

  @override
  State<ReplaceRulesPage> createState() => _ReplaceRulesPageState();
}

class _ReplaceRulesPageState extends State<ReplaceRulesPage> {
  late ReplaceRuleStore _store;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _store = widget.store ?? ReplaceRuleStore.shared;
    SakuraDatabase? db = widget.database;
    if (db == null) {
      try {
        db = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(sakuraDatabaseProvider);
      } catch (_) {
        // 独立 widget 测试未包 ProviderScope 时忽略
      }
    }
    if (db != null) {
      _store.attachDatabase(db);
    }
    if (!_store.loaded) {
      _store.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.sakura;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('正文净化规则'),
        actions: [
          IconButton(
            tooltip: '净化试测',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => _showTestSheet(context),
          ),
          IconButton(
            tooltip: '导入 Legado JSON',
            icon: const Icon(Icons.content_paste_go_rounded),
            onPressed: () => _showImportDialog(context),
          ),
          IconButton(
            tooltip: '导出 JSON',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _exportJson(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditorSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建规则'),
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final rules = _store.rules;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _buildSummaryBanner(colors, accent, rules),
                ),
              ),
              if (rules.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(colors, accent),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: rules.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildRuleCard(context, rules[index], colors, accent),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBanner(
    SakuraColors colors,
    Color accent,
    List<ReplaceRule> rules,
  ) {
    return Container(
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '共 ${rules.length} 条规则 · 已启用 ${_store.enabledCount} 条',
                      style: TextStyle(
                        color: colors.inkPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '完全兼容阅读 3.0 替换规则，自动净化章节广告、水印与排版噪音',
                      style: TextStyle(
                        color: colors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionPill(
                icon: Icons.science_outlined,
                label: '净化试测',
                colors: colors,
                accent: accent,
                onTap: () => _showTestSheet(context),
              ),
              _ActionPill(
                icon: Icons.auto_awesome_outlined,
                label: '加载常用预设',
                colors: colors,
                accent: accent,
                onTap: _addBuiltinPresets,
              ),
              _ActionPill(
                icon: Icons.content_paste_go_rounded,
                label: '粘贴导入',
                colors: colors,
                accent: accent,
                onTap: () => _showImportDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SakuraColors colors, Color accent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.cleaning_services_rounded,
                color: accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有正文净化规则',
              style: TextStyle(
                color: colors.inkPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持导入 Legado 3.0 替换规则 JSON，或先加载内置常用去广告预设',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.inkSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _addBuiltinPresets,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('一键添加常用预设'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    ReplaceRule rule,
    SakuraColors colors,
    Color accent,
  ) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showEditorSheet(context, existing: rule),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.inkPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch(
                    value: rule.isEnabled,
                    onChanged: (v) => _store.setEnabled(rule.id, v),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: colors.inkSecondary,
                    ),
                    onPressed: () => _confirmDelete(context, rule),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(
                    label: rule.isRegex ? '正则' : '纯文本',
                    bg: rule.isRegex ? colors.accentSoft : colors.surfaceSubtle,
                    fg: rule.isRegex ? accent : colors.inkSecondary,
                  ),
                  _Badge(
                    label: rule.scope.isEmpty ? '全局生效' : '范围：${rule.scope}',
                    bg: colors.surfaceSubtle,
                    fg: colors.inkSecondary,
                  ),
                  _Badge(
                    label: '排序 ${rule.order}',
                    bg: colors.surfaceSubtle,
                    fg: colors.inkSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${rule.pattern}  →  ${rule.replacement.isEmpty ? '（删除）' : rule.replacement}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: colors.inkPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addBuiltinPresets() async {
    var added = 0;
    for (final preset in ReplaceRuleStore.builtinPresets()) {
      final exists = _store.rules.any((r) => r.id == preset.id);
      if (!exists) {
        await _store.upsert(preset);
        added++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added > 0 ? '已添加 $added 条常用净化预设' : '常用预设已全部存在')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ReplaceRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除净化规则'),
        content: Text('确定删除「${rule.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(rule.id);
    }
  }

  Future<void> _showEditorSheet(
    BuildContext context, {
    ReplaceRule? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final patternCtrl = TextEditingController(text: existing?.pattern ?? '');
    final repCtrl = TextEditingController(text: existing?.replacement ?? '');
    final scopeCtrl = TextEditingController(text: existing?.scope ?? '');
    final orderCtrl = TextEditingController(
      text: (existing?.order ?? _store.rules.length * 10).toString(),
    );
    var isRegex = existing?.isRegex ?? true;
    var isEnabled = existing?.isEnabled ?? true;
    String? errorText;

    final saved = await showModalBottomSheet<ReplaceRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? '新建净化规则' : '编辑净化规则',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '规则名称',
                      hintText: '例如：去除网站水印',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: patternCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: '匹配规则（pattern）',
                      hintText: isRegex ? r'例如：请记住本书.*$' : '输入需要替换的固定文本',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: repCtrl,
                    decoration: const InputDecoration(
                      labelText: '替换为（留空表示删除）',
                      hintText: r'正则模式支持 $1 / $& 捕获组',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: scopeCtrl,
                          decoration: const InputDecoration(
                            labelText: '作用范围（留空全局）',
                            hintText: '书名或书源网址，逗号分隔',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: orderCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '排序',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用正则表达式（isRegex）'),
                    value: isRegex,
                    onChanged: (v) => setModalState(() => isRegex = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用该规则'),
                    value: isEnabled,
                    onChanged: (v) => setModalState(() => isEnabled = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final candidate = ReplaceRule(
                          id: existing?.id ?? ReplaceRule.newId(),
                          name: nameCtrl.text.trim().isEmpty
                              ? '未命名规则'
                              : nameCtrl.text.trim(),
                          pattern: patternCtrl.text,
                          replacement: repCtrl.text,
                          isRegex: isRegex,
                          scope: scopeCtrl.text.trim(),
                          isEnabled: isEnabled,
                          order: int.tryParse(orderCtrl.text.trim()) ?? 0,
                        );
                        final err = candidate.validatePattern();
                        if (err != null) {
                          setModalState(() => errorText = err);
                          return;
                        }
                        Navigator.pop(ctx, candidate);
                      },
                      child: const Text('保存规则'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (saved != null) {
      await _store.upsert(saved);
    }
  }

  Future<void> _showTestSheet(BuildContext context) async {
    final sampleCtrl = TextEditingController(
      text:
          '　　夜风拂过长街，灯火如昼。\n\n\n'
          '请记住本书首发域名：www.example.com\n'
          '　　【求月票求推荐票】他推开了古宅的大门。',
    );
    final bookCtrl = TextEditingController();
    final sourceCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final colors = ctx.sakura;
          final trace = _store.previewApply(
            sampleCtrl.text,
            bookTitle: bookCtrl.text.trim().isEmpty
                ? null
                : bookCtrl.text.trim(),
            sourceUrl: sourceCtrl.text.trim().isEmpty
                ? null
                : sourceCtrl.text.trim(),
          );
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '净化效果实时试测',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sampleCtrl,
                    maxLines: 4,
                    onChanged: (_) => setModalState(() {}),
                    decoration: const InputDecoration(
                      labelText: '原始样本文本',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bookCtrl,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            labelText: '测试书名（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sourceCtrl,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            labelText: '测试书源（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '命中 ${trace.matchedRules.length} 条规则'
                    '${trace.matchedRules.isEmpty ? '' : '：${trace.matchedRules.map((r) => r.name).join('、')}'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.hairline),
                    ),
                    child: SelectableText(
                      trace.output.isEmpty ? '（净化后为空）' : trace.output,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: colors.inkPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入 Legado 替换规则 JSON'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '粘贴 Legado 3.0 替换规则 JSON（对象或数组）…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    final report = await _store.importFromJson(text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(report.summary)));
  }

  Future<void> _exportJson(BuildContext context) async {
    if (_store.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有净化规则可导出')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: _store.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制全部净化规则 JSON 到剪贴板')));
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.colors,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final SakuraColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceSubtle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.inkPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
