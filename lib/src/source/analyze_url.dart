// URL 模板分析器：把书源里的 URL 模板渲染成实际请求地址。
//
// 支持（对照 Legado 3.0 AnalyzeUrl 的公开行为，独立实现）：
//   {{key}} / {{searchKey}} / {{keyword}}   搜索词（UTF-8 百分号编码）
//   {{page}}                                页码
//   {{任意键}}                              从 vars 传入的自定义变量
//   {{JS 表达式}}                           通过 LegadoJsEngine 动态求值
//   @js:... / <js>...</js>                  整段 JS 动态生成 URL 与请求选项
//   `,{...}` 尾缀                            请求选项 JSON（method / body / charset / headers）
//   相对路径                                 以书源 bookSourceUrl 为基准补全为绝对地址
import 'dart:convert';

import 'js_engine.dart';

/// 模板解析结果：纯 URL 模板 + 请求选项。
class UrlTemplate {
  const UrlTemplate(this.url, this.options);

  /// URL 模板（未渲染）。
  final String url;

  /// `,{...}` 尾缀解析出的选项（无则空 Map）。
  final Map<String, dynamic> options;
}

/// 拆分 URL 与选项 JSON 尾缀。
///
/// 例：`/search?q={{key}},{"method":"POST","body":"q={{key}}"}` →
/// url=`/search?q={{key}}`，options={"method":"POST", ...}
UrlTemplate parseUrlTemplate(String raw) {
  final s = raw.trim();
  final idx = s.indexOf(',{');
  if (idx < 0) return UrlTemplate(s, const {});
  final head = s.substring(0, idx).trim();
  final tail = s.substring(idx + 1);
  try {
    final decoded = jsonDecode(tail);
    if (decoded is Map) {
      return UrlTemplate(
        head,
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
  } catch (_) {
    // 尾缀不是合法 JSON：视为 URL 的一部分（保持原样）
  }
  return UrlTemplate(s, const {});
}

final _varPattern = RegExp(r'\{\{(.+?)\}\}');

/// 渲染模板变量与 `{{...}}` 内联 JS 表达式。
///
/// [vars] 至少应包含 `key` 与 `page`；`searchKey` / `keyword` 会映射到 `key`。
String renderUrlTemplate(
  String template,
  Map<String, dynamic> vars, {
  String baseUrl = '',
  String sourceKey = '',
  LegadoJsEngine? jsEngine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  List<String>? jsLogs,
}) {
  final engine = jsEngine ?? LegadoJsEngine.shared;
  return template.replaceAllMapped(_varPattern, (m) {
    final expr = m.group(1)!.trim();
    switch (expr) {
      case 'key':
      case 'searchKey':
      case 'keyword':
        return Uri.encodeComponent((vars['key'] ?? '').toString());
      case 'page':
        return Uri.encodeComponent((vars['page'] ?? '1').toString());
    }
    if (vars.containsKey(expr)) {
      return Uri.encodeComponent((vars[expr] ?? '').toString());
    }
    // 非简单变量名：按 Legado 内联 JS 表达式求值
    if (_looksLikeJsExpression(expr)) {
      final ctx = JsEvalContext(
        result: vars['result'] ?? '',
        baseUrl: baseUrl,
        key: (vars['key'] ?? '').toString(),
        page: _asIntPage(vars['page']),
        sourceKey: sourceKey.isNotEmpty ? sourceKey : baseUrl,
        cookieBridge: cookieBridge,
        variableStore: variableStore,
        httpSync: httpSync,
        logs: jsLogs,
      );
      final res = engine.eval(expr, context: ctx);
      if (res.ok && res.value != null) {
        return res.asString;
      }
    }
    return '';
  });
}

/// 异步渲染模板变量与 `{{...}}` 内联 JS 表达式（支持表达式内调用 `java.ajax` 等）。
Future<String> renderUrlTemplateAsync(
  String template,
  Map<String, dynamic> vars, {
  String baseUrl = '',
  String sourceKey = '',
  LegadoJsEngine? jsEngine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  JsAsyncHttpCallback? httpAsync,
  List<String>? jsLogs,
}) async {
  if (!template.contains('{{')) return template;
  final engine = jsEngine ?? LegadoJsEngine.shared;
  final matches = _varPattern.allMatches(template).toList();
  if (matches.isEmpty) return template;

  final sb = StringBuffer();
  var cursor = 0;
  for (final m in matches) {
    sb.write(template.substring(cursor, m.start));
    final expr = m.group(1)!.trim();
    if (expr == 'key' || expr == 'searchKey' || expr == 'keyword') {
      sb.write(Uri.encodeComponent((vars['key'] ?? '').toString()));
    } else if (expr == 'page') {
      sb.write(Uri.encodeComponent((vars['page'] ?? '1').toString()));
    } else if (vars.containsKey(expr)) {
      sb.write(Uri.encodeComponent((vars[expr] ?? '').toString()));
    } else if (_looksLikeJsExpression(expr)) {
      final ctx = JsEvalContext(
        result: vars['result'] ?? '',
        baseUrl: baseUrl,
        key: (vars['key'] ?? '').toString(),
        page: _asIntPage(vars['page']),
        sourceKey: sourceKey.isNotEmpty ? sourceKey : baseUrl,
        cookieBridge: cookieBridge,
        variableStore: variableStore,
        httpSync: httpSync,
        httpAsync: httpAsync,
        logs: jsLogs,
      );
      final res = await engine.evalAsync(expr, context: ctx);
      if (res.ok && res.value != null) {
        sb.write(res.asString);
      }
    }
    cursor = m.end;
  }
  sb.write(template.substring(cursor));
  return sb.toString();
}

/// 把（已渲染的）地址补全为绝对地址。
///
/// - 已是 `http(s)://` → 原样返回；
/// - 以 `/` 开头或相对路径 → 以 [baseUrl] 为基准解析。
String resolveUrl(String url, String baseUrl) {
  final u = url.trim();
  if (u.isEmpty) return u;
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  try {
    if (baseUrl.isEmpty) return u;
    return Uri.parse(baseUrl).resolve(u).toString();
  } catch (_) {
    return u;
  }
}

/// 一步到位：执行可选 JS + 解析 + 渲染 + 补全（同步版）。
///
/// [baseUrl] 通常是书源的 `bookSourceUrl`。
UrlTemplate buildRequest(
  String rawTemplate,
  String baseUrl,
  Map<String, dynamic> vars, {
  String sourceKey = '',
  LegadoJsEngine? jsEngine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  List<String>? jsLogs,
}) {
  final engine = jsEngine ?? LegadoJsEngine.shared;
  var effective = rawTemplate.trim();
  if (LegadoJsEngine.containsJs(effective)) {
    effective = _evalUrlJsSync(
      effective,
      baseUrl: baseUrl,
      vars: vars,
      sourceKey: sourceKey,
      engine: engine,
      cookieBridge: cookieBridge,
      variableStore: variableStore,
      httpSync: httpSync,
      jsLogs: jsLogs,
    );
  }
  final t = parseUrlTemplate(effective);
  final rendered = renderUrlTemplate(
    t.url,
    vars,
    baseUrl: baseUrl,
    sourceKey: sourceKey,
    jsEngine: engine,
    cookieBridge: cookieBridge,
    variableStore: variableStore,
    httpSync: httpSync,
    jsLogs: jsLogs,
  );
  return UrlTemplate(resolveUrl(rendered, baseUrl), t.options);
}

/// 一步到位：支持 `java.ajax` / `java.get` / `java.post` 的异步 URL 构建器。
Future<UrlTemplate> buildRequestAsync(
  String rawTemplate,
  String baseUrl,
  Map<String, dynamic> vars, {
  String sourceKey = '',
  LegadoJsEngine? jsEngine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  JsAsyncHttpCallback? httpAsync,
  List<String>? jsLogs,
}) async {
  final engine = jsEngine ?? LegadoJsEngine.shared;
  var effective = rawTemplate.trim();
  if (LegadoJsEngine.containsJs(effective)) {
    effective = await _evalUrlJsAsync(
      effective,
      baseUrl: baseUrl,
      vars: vars,
      sourceKey: sourceKey,
      engine: engine,
      cookieBridge: cookieBridge,
      variableStore: variableStore,
      httpSync: httpSync,
      httpAsync: httpAsync,
      jsLogs: jsLogs,
    );
  }
  final t = parseUrlTemplate(effective);
  final rendered = await renderUrlTemplateAsync(
    t.url,
    vars,
    baseUrl: baseUrl,
    sourceKey: sourceKey,
    jsEngine: engine,
    cookieBridge: cookieBridge,
    variableStore: variableStore,
    httpSync: httpSync,
    httpAsync: httpAsync,
    jsLogs: jsLogs,
  );
  return UrlTemplate(resolveUrl(rendered, baseUrl), t.options);
}

String _evalUrlJsSync(
  String rawTemplate, {
  required String baseUrl,
  required Map<String, dynamic> vars,
  required String sourceKey,
  required LegadoJsEngine engine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  List<String>? jsLogs,
}) {
  final segments = LegadoJsEngine.splitRuleSegments(rawTemplate);
  var current = '';
  for (final seg in segments) {
    if (!seg.isJs) {
      current = current.isEmpty ? seg.content : '$current${seg.content}';
    } else {
      final ctx = JsEvalContext(
        result: current.isEmpty ? (vars['result'] ?? '') : current,
        baseUrl: baseUrl,
        key: (vars['key'] ?? '').toString(),
        page: _asIntPage(vars['page']),
        sourceKey: sourceKey.isNotEmpty ? sourceKey : baseUrl,
        cookieBridge: cookieBridge,
        variableStore: variableStore,
        httpSync: httpSync,
        logs: jsLogs,
      );
      final res = engine.eval(seg.content, context: ctx);
      if (res.ok && res.value != null) {
        current = res.asString;
      }
    }
  }
  return current;
}

Future<String> _evalUrlJsAsync(
  String rawTemplate, {
  required String baseUrl,
  required Map<String, dynamic> vars,
  required String sourceKey,
  required LegadoJsEngine engine,
  JsCookieBridge? cookieBridge,
  SourceVariableStore? variableStore,
  JsSyncHttpCallback? httpSync,
  JsAsyncHttpCallback? httpAsync,
  List<String>? jsLogs,
}) async {
  final segments = LegadoJsEngine.splitRuleSegments(rawTemplate);
  var current = '';
  for (final seg in segments) {
    if (!seg.isJs) {
      current = current.isEmpty ? seg.content : '$current${seg.content}';
    } else {
      final ctx = JsEvalContext(
        result: current.isEmpty ? (vars['result'] ?? '') : current,
        baseUrl: baseUrl,
        key: (vars['key'] ?? '').toString(),
        page: _asIntPage(vars['page']),
        sourceKey: sourceKey.isNotEmpty ? sourceKey : baseUrl,
        cookieBridge: cookieBridge,
        variableStore: variableStore,
        httpSync: httpSync,
        httpAsync: httpAsync,
        logs: jsLogs,
      );
      final res = await engine.evalAsync(seg.content, context: ctx);
      if (res.ok && res.value != null) {
        current = res.asString;
      }
    }
  }
  return current;
}

bool _looksLikeJsExpression(String expr) {
  if (expr.isEmpty) return false;
  return expr.contains('(') ||
      expr.contains('+') ||
      expr.contains('-') ||
      expr.contains('*') ||
      expr.contains('/') ||
      expr.contains('.') ||
      expr.contains('?') ||
      expr.contains('[') ||
      expr.startsWith('java') ||
      expr.startsWith('source') ||
      expr.startsWith('cookie') ||
      expr.startsWith('key') ||
      expr.startsWith('page') ||
      expr.startsWith('baseUrl');
}

int _asIntPage(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 1;
}
