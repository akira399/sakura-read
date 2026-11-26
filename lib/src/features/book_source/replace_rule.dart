import 'dart:convert';

/// 正文净化 / 替换规则（兼容 Legado 3.0 ReplaceRule JSON 格式）。
///
/// 支持字段：
/// - [id]: 唯一标识（导入时若为数字或缺失会自动归一化为字符串）
/// - [name]: 规则名称
/// - [pattern]: 匹配模式（正则或普通文本）
/// - [replacement]: 替换结果（正则模式支持 `$1`..`$9` 与 `$&` 捕获组）
/// - [isRegex]: 是否按正则表达式匹配
/// - [scope]: 作用范围（空串 = 全局生效；多个书名/书源 URL 用逗号/分号/换行分隔）
/// - [isEnabled]: 是否启用
/// - [order]: 排序权重（越小越先执行）
class ReplaceRule {
  const ReplaceRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.replacement = '',
    this.isRegex = true,
    this.scope = '',
    this.isEnabled = true,
    this.order = 0,
  });

  final String id;
  final String name;
  final String pattern;
  final String replacement;
  final bool isRegex;
  final String scope;
  final bool isEnabled;
  final int order;

  static int _idCounter = 0;

  /// 生成唯一规则 ID。
  static String newId() {
    _idCounter++;
    return 'rr_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  ReplaceRule copyWith({
    String? id,
    String? name,
    String? pattern,
    String? replacement,
    bool? isRegex,
    String? scope,
    bool? isEnabled,
    int? order,
  }) => ReplaceRule(
    id: id ?? this.id,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    replacement: replacement ?? this.replacement,
    isRegex: isRegex ?? this.isRegex,
    scope: scope ?? this.scope,
    isEnabled: isEnabled ?? this.isEnabled,
    order: order ?? this.order,
  );

  /// 从 Legado 3.0 JSON 对象解析。
  factory ReplaceRule.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final pattern = (json['pattern'] ?? '').toString();
    final replacement = (json['replacement'] ?? '').toString();
    final isRegex = _parseBool(json['isRegex'] ?? json['is_regex'], true);
    final scope = (json['scope'] ?? '').toString().trim();
    final isEnabled = _parseBool(json['isEnabled'] ?? json['enabled'], true);
    final order = _parseInt(
      json['order'] ?? json['sortOrder'] ?? json['sort_order'],
      0,
    );
    return ReplaceRule(
      id: (rawId == null || rawId.isEmpty) ? newId() : rawId,
      name: name.isEmpty ? _fallbackName(pattern) : name,
      pattern: pattern,
      replacement: replacement,
      isRegex: isRegex,
      scope: scope,
      isEnabled: isEnabled,
      order: order,
    );
  }

  /// 导出为 Legado 3.0 兼容 JSON。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'replacement': replacement,
    'isRegex': isRegex,
    'scope': scope,
    'isEnabled': isEnabled,
    'order': order,
  };

  /// 从 SQLite `replace_rules` 行构建。
  factory ReplaceRule.fromRow(Map<String, Object?> row) {
    return ReplaceRule(
      id: (row['id'] as String?) ?? newId(),
      name: (row['name'] as String?) ?? '',
      pattern: (row['pattern'] as String?) ?? '',
      replacement: (row['replacement'] as String?) ?? '',
      isRegex: (row['is_regex'] as num? ?? 1).toInt() != 0,
      scope: (row['scope'] as String?) ?? '',
      isEnabled: (row['enabled'] as num? ?? 1).toInt() != 0,
      order: (row['sort_order'] as num? ?? 0).toInt(),
    );
  }

  /// 转为 SQLite `replace_rules` 行。
  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'replacement': replacement,
    'is_regex': isRegex ? 1 : 0,
    'scope': scope,
    'enabled': isEnabled ? 1 : 0,
    'sort_order': order,
  };

  /// 从 Legado JSON 文本（单个对象或数组）批量解析规则。
  static List<ReplaceRule> listFromJsonText(String raw) {
    final trimmed = raw.trim().replaceFirst('\uFEFF', '');
    if (trimmed.isEmpty) return const [];
    final decoded = jsonDecode(trimmed);
    return listFromJson(decoded);
  }

  /// 从已解码 JSON（单个对象或数组）解析规则列表。
  static List<ReplaceRule> listFromJson(dynamic json) {
    final items = json is List ? json : [json];
    final out = <ReplaceRule>[];
    for (final item in items) {
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final rule = ReplaceRule.fromJson(map);
      if (rule.pattern.isEmpty) continue;
      out.add(rule);
    }
    return out;
  }

  /// 判断当前规则是否作用于指定书籍 / 书源。
  ///
  /// - [scope] 为空 → 全局生效；
  /// - 非空时按 `,` / `，` / `;` / `；` / 换行 / `|` 拆分作用域条目：
  ///   - 以 `!` 开头视为排除条目（命中则不生效）；
  ///   - 其余为包含条目（命中书名或书源 URL 即生效）。
  bool matchesScope({String? bookTitle, String? sourceUrl}) {
    final raw = scope.trim();
    if (raw.isEmpty) return true;
    final tokens = raw
        .split(RegExp(r'[,，;；\r\n|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;

    final title = (bookTitle ?? '').trim().toLowerCase();
    final url = (sourceUrl ?? '').trim().toLowerCase();

    final includes = <String>[];
    final excludes = <String>[];
    for (final t in tokens) {
      if (t.startsWith('!') && t.length > 1) {
        excludes.add(t.substring(1).trim().toLowerCase());
      } else {
        includes.add(t.toLowerCase());
      }
    }

    bool matchToken(String token) {
      if (token.isEmpty) return false;
      if (title.isNotEmpty && (title == token || title.contains(token))) {
        return true;
      }
      if (url.isNotEmpty && (url == token || url.contains(token))) {
        return true;
      }
      return false;
    }

    for (final ex in excludes) {
      if (matchToken(ex)) return false;
    }
    if (includes.isEmpty) return true;
    return includes.any(matchToken);
  }

  /// 将单条规则应用到正文（非法正则自动容错跳过）。
  String applyTo(String text) {
    if (!isEnabled || pattern.isEmpty || text.isEmpty) return text;
    if (!isRegex) {
      return text.replaceAll(pattern, replacement);
    }
    try {
      final re = RegExp(pattern, multiLine: true);
      if (!replacement.contains(r'$')) {
        return text.replaceAll(re, replacement);
      }
      return text.replaceAllMapped(re, (m) {
        return replacement.replaceAllMapped(RegExp(r'\$(\d+|&)'), (ref) {
          final key = ref.group(1)!;
          if (key == '&') return m.group(0) ?? '';
          final idx = int.tryParse(key);
          if (idx == null || idx < 0 || idx > m.groupCount) {
            return ref.group(0)!;
          }
          return m.group(idx) ?? '';
        });
      });
    } catch (_) {
      return text;
    }
  }

  /// 校验正则表达式是否合法；合法返回 `null`，否则返回错误信息。
  String? validatePattern() {
    if (pattern.isEmpty) return '匹配规则不能为空';
    if (!isRegex) return null;
    try {
      RegExp(pattern, multiLine: true);
      return null;
    } on FormatException catch (e) {
      return '正则表达式语法错误：${e.message}';
    }
  }

  static bool _parseBool(dynamic v, bool fallback) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  static int _parseInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  static String _fallbackName(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return '未命名规则';
    return trimmed.length <= 18 ? trimmed : '${trimmed.substring(0, 18)}…';
  }
}
