import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/database/sakura_database.dart';
import 'replace_rule.dart';

/// 规则导入统计。
class ReplaceRuleImportReport {
  const ReplaceRuleImportReport({
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.error,
  });

  final int added;
  final int updated;
  final int skipped;
  final String? error;

  bool get ok => error == null;

  String get summary {
    if (error != null) return error!;
    final parts = <String>[
      if (added > 0) '新增 $added 条',
      if (updated > 0) '更新 $updated 条',
      if (skipped > 0) '跳过 $skipped 条无效规则',
    ];
    return parts.isEmpty ? '没有可导入的净化规则' : parts.join('，');
  }
}

/// 净化试测命中摘要（用于 UI 展示哪些规则实际改动了正文）。
class ReplaceRuleApplyTrace {
  const ReplaceRuleApplyTrace({
    required this.output,
    required this.matchedRules,
  });

  final String output;
  final List<ReplaceRule> matchedRules;
}

/// 正文净化 / 替换规则仓库（持久化到 `SakuraDatabase.replace_rules`）。
///
/// 供阅读器通过 `ReplaceRuleStore.applyRules(text, bookTitle: ..., sourceUrl: ...)`
/// 一键应用全局与书籍专属净化规则。
class ReplaceRuleStore extends ChangeNotifier {
  ReplaceRuleStore({SakuraDatabase? database, List<ReplaceRule>? initial})
    : _db = database {
    if (initial != null) {
      _rules
        ..addAll(initial)
        ..sort(_compare);
    }
  }

  /// 进程内共享实例（供阅读器与书源管理页共用）。
  static final ReplaceRuleStore shared = ReplaceRuleStore();

  SakuraDatabase? _db;
  final List<ReplaceRule> _rules = [];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<ReplaceRule> get rules => List.unmodifiable(_rules);
  int get enabledCount => _rules.where((r) => r.isEnabled).length;
  bool get isEmpty => _rules.isEmpty;

  /// 绑定 SQLite 数据库（在应用已初始化 `SakuraDatabase` 后调用）。
  void attachDatabase(SakuraDatabase? db) {
    if (identical(_db, db)) return;
    _db = db;
    _loaded = false;
  }

  /// 快捷静态入口：使用共享规则库净化正文（供 `reader-core` 直接调用）。
  static String applyRules(
    String text, {
    String? bookTitle,
    String? sourceUrl,
  }) => shared.apply(text, bookTitle: bookTitle, sourceUrl: sourceUrl);

  /// 纯函数版本：将指定规则集合按顺序应用到正文。
  static String applyRuleList(
    String text,
    Iterable<ReplaceRule> rules, {
    String? bookTitle,
    String? sourceUrl,
  }) {
    if (text.isEmpty) return text;
    final sorted = [...rules]..sort(_compare);
    var out = text;
    for (final rule in sorted) {
      if (!rule.isEnabled || rule.pattern.isEmpty) continue;
      if (!rule.matchesScope(bookTitle: bookTitle, sourceUrl: sourceUrl)) {
        continue;
      }
      out = rule.applyTo(out);
    }
    return out;
  }

  /// 将当前仓库中启用且命中作用域的规则依次应用到正文。
  String apply(String text, {String? bookTitle, String? sourceUrl}) =>
      applyRuleList(text, _rules, bookTitle: bookTitle, sourceUrl: sourceUrl);

  /// 试测净化并返回命中的规则清单（用于「净化试测」面板）。
  ReplaceRuleApplyTrace previewApply(
    String text, {
    String? bookTitle,
    String? sourceUrl,
  }) {
    if (text.isEmpty) {
      return const ReplaceRuleApplyTrace(output: '', matchedRules: []);
    }
    var out = text;
    final matched = <ReplaceRule>[];
    for (final rule in _rules) {
      if (!rule.isEnabled || rule.pattern.isEmpty) continue;
      if (!rule.matchesScope(bookTitle: bookTitle, sourceUrl: sourceUrl)) {
        continue;
      }
      final next = rule.applyTo(out);
      if (next != out) {
        matched.add(rule);
        out = next;
      }
    }
    return ReplaceRuleApplyTrace(output: out, matchedRules: matched);
  }

  // ---------- 持久化 CRUD ----------

  Future<void> load() async {
    final db = _db;
    if (db != null) {
      final rows = await db.loadReplaceRules();
      _rules
        ..clear()
        ..addAll(rows.map(ReplaceRule.fromRow))
        ..sort(_compare);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> upsert(ReplaceRule rule) async {
    final idx = _rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      _rules[idx] = rule;
    } else {
      _rules.add(rule);
    }
    _rules.sort(_compare);
    await _db?.upsertReplaceRule(rule.toRow());
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final before = _rules.length;
    _rules.removeWhere((r) => r.id == id);
    if (_rules.length != before) {
      await _db?.deleteReplaceRule(id);
      notifyListeners();
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final idx = _rules.indexWhere((r) => r.id == id);
    if (idx < 0 || _rules[idx].isEnabled == enabled) return;
    _rules[idx] = _rules[idx].copyWith(isEnabled: enabled);
    await _db?.setReplaceRuleEnabled(id, enabled);
    notifyListeners();
  }

  Future<void> clearAll() async {
    final ids = _rules.map((r) => r.id).toList();
    _rules.clear();
    for (final id in ids) {
      await _db?.deleteReplaceRule(id);
    }
    notifyListeners();
  }

  // ---------- Legado JSON 导入 / 导出 ----------

  Future<ReplaceRuleImportReport> importFromJson(String raw) async {
    final trimmed = raw.trim().replaceFirst('\uFEFF', '');
    if (trimmed.isEmpty) {
      return const ReplaceRuleImportReport(error: '粘贴内容为空');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return const ReplaceRuleImportReport(
        error: '不是合法的 JSON（需要 Legado 替换规则对象或数组）',
      );
    }
    final total = decoded is List ? decoded.length : (decoded is Map ? 1 : 0);
    final parsed = ReplaceRule.listFromJson(decoded);
    if (parsed.isEmpty) {
      return const ReplaceRuleImportReport(
        error: '未解析到有效净化规则（每条规则至少需包含 pattern 字段）',
      );
    }
    var added = 0;
    var updated = 0;
    for (final rule in parsed) {
      final exists = _rules.any((r) => r.id == rule.id);
      if (exists) {
        updated++;
      } else {
        added++;
      }
      await upsert(rule);
    }
    return ReplaceRuleImportReport(
      added: added,
      updated: updated,
      skipped: (total - parsed.length).clamp(0, total),
    );
  }

  /// 导出为 Legado 3.0 兼容 JSON 数组。
  String exportJson() =>
      const JsonEncoder.withIndent('  ')
          .convert(_rules.map((r) => r.toJson()).toList());

  /// 内置常用净水模板（用户可在界面一键添加）。
  static List<ReplaceRule> builtinPresets() => [
    ReplaceRule(
      id: 'preset_site_watermark',
      name: '去除常见网址广告',
      pattern: r'(?:请记住本书首发域名|手机版阅读网址|最新网址|本章未完，点击下一页继续阅读)[^\n]*',
      replacement: '',
      isRegex: true,
      order: 10,
    ),
    ReplaceRule(
      id: 'preset_extra_blank_lines',
      name: '合并连续空行',
      pattern: r'\n{3,}',
      replacement: '\n\n',
      isRegex: true,
      order: 20,
    ),
    ReplaceRule(
      id: 'preset_chapter_brackets',
      name: '清除【求月票/求推荐】作者尾注',
      pattern: r'【[^】]{0,40}(?:月票|推荐票|求订阅|求收藏|加群)[^】]{0,40}】',
      replacement: '',
      isRegex: true,
      order: 30,
    ),
  ];

  static int _compare(ReplaceRule a, ReplaceRule b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.id.compareTo(b.id);
  }
}
