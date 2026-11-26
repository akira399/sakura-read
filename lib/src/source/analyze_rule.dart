// 规则求值引擎：把「规则字符串 + 文档」的完整求值流程串起来。
//
// 求值顺序（对照 Legado 3.0 的公开行为，独立实现）：
//   0. 若规则含 `@js:` / `<js>...</js>`，按段顺序串行执行（前段输出作为下段 `result`）；
//      若基础规则含内联 `{{...}}` 模板，逐个展开为 JS / 子规则求值结果；
//   1. `||` 拆分备选：从左到右求值，取第一个非空结果（兜底）；
//   2. 每条备选内 `&&` 串联：各段结果用换行拼接；
//   3. 每段规则先拆 `##` 替换链（只作用于字符串结果）；
//   4. 按模式分派：`@json:` / `@xpath:` / `@css:` / `@regex:`，
//      无前缀时：JSON 文档 → JSONPath；HTML 文档 → CSS（疑似正则才走正则）。
//
// 引擎无状态、可重复求值；文档只解析一次并缓存。
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart' as xml;

import 'analyze_css.dart';
import 'analyze_json.dart';
import 'analyze_regex.dart';
import 'analyze_xpath.dart';
import 'js_engine.dart';
import 'rule_analyzer.dart';

/// HTML → XML 宽松解析（容错常见的不合法写法，供 XPath 使用）。
xml.XmlDocument? parseXmlLoose(String html) {
  if (html.trim().isEmpty) return null;
  try {
    return xml.XmlDocument.parse(html);
  } catch (_) {
    // 继续尝试清洗
  }
  var s = html;
  // 自闭合常见的空元素
  s = s.replaceAllMapped(
    RegExp(r'<(br|hr|img|input|meta|link)([^<>]*?)(/?)>', caseSensitive: false),
    (m) {
      final name = m.group(1)!;
      final attrs = m.group(2) ?? '';
      final slash = m.group(3) ?? '';
      if (slash.isNotEmpty) return m.group(0)!;
      return '<$name$attrs/>';
    },
  );
  // 裸 & 转义
  s = s.replaceAll(
    RegExp(r'&(?!(#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);)'),
    '&amp;',
  );
  try {
    return xml.XmlDocument.parse(s);
  } catch (_) {
    return null;
  }
}

/// 规则求值器（支持 CSS / JSONPath / XPath / Regex / Legado 3.0 JS）。
class AnalyzeRule {
  AnalyzeRule(
    this.document, {
    this.baseUrl = '',
    this.vars = const {},
    this.sourceKey = '',
    this.key = '',
    this.page = 1,
    LegadoJsEngine? jsEngine,
    this.cookieBridge,
    this.variableStore,
    this.httpSync,
    this.httpAsync,
    List<String>? jsLogs,
  }) : _jsEngine = jsEngine ?? LegadoJsEngine.shared,
       jsLogs = jsLogs ?? <String>[];

  /// 文档文本（HTML 或 JSON；也可为普通文本）。
  final String? document;

  /// 书源主地址或当前页 URL（补全相对链接与 JS `baseUrl` 用）。
  final String baseUrl;

  /// 替换串里的变量（`{{chapter.title}}` 这类）。
  final Map<String, String> vars;

  /// 书源唯一标识（通常为 `bookSourceUrl`，用于 `source.getVariable()`）。
  final String sourceKey;

  /// 搜索关键词（JS 全局 `key`）。
  final String key;

  /// 当前页码（JS 全局 `page`）。
  final int page;

  final LegadoJsEngine _jsEngine;
  final JsCookieBridge? cookieBridge;
  final SourceVariableStore? variableStore;
  final JsSyncHttpCallback? httpSync;
  final JsAsyncHttpCallback? httpAsync;

  /// 执行 JS 过程中收集的 `console.log` / `java.log` 输出（供调试器展示）。
  final List<String> jsLogs;

  dom.Document? _htmlDoc;
  bool _jsonTried = false;
  dynamic _jsonDoc;
  bool _xmlTried = false;
  xml.XmlDocument? _xmlDoc;

  /// 惰性解析 HTML。
  dom.Document get htmlDoc => _htmlDoc ??= parseHtml(document ?? '');

  /// 惰性解析 JSON（文档不是 JSON 时返回 null）。
  dynamic get jsonDoc {
    if (!_jsonTried) {
      _jsonTried = true;
      final d = (document ?? '').trim();
      if (d.startsWith('{') || d.startsWith('[')) {
        try {
          _jsonDoc = jsonDecode(d);
        } catch (_) {
          _jsonDoc = null;
        }
      }
    }
    return _jsonDoc;
  }

  /// 惰性解析 XML（供 XPath；失败返回 null）。
  xml.XmlDocument? get xmlDoc {
    if (!_xmlTried) {
      _xmlTried = true;
      _xmlDoc = parseXmlLoose(document ?? '');
    }
    return _xmlDoc;
  }

  AnalyzeRule _childWithDoc(String nextDoc) => AnalyzeRule(
    nextDoc,
    baseUrl: baseUrl,
    vars: vars,
    sourceKey: sourceKey,
    key: key,
    page: page,
    jsEngine: _jsEngine,
    cookieBridge: cookieBridge,
    variableStore: variableStore,
    httpSync: httpSync,
    httpAsync: httpAsync,
    jsLogs: jsLogs,
  );

  // ---------- 对外同步 API ----------

  /// 取单个字符串结果（`||` 兜底取第一个非空）。
  String? getString(String rule, {Object? ctx}) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return null;
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = _evalJsPipelineSync(trimmed, ctx: ctx, asList: false);
      return _dynamicToString(val);
    }
    if (_hasInlineTemplateOutsideReplace(trimmed)) {
      return _evalInlineTemplateSync(trimmed, ctx: ctx);
    }
    for (final alt in RuleAnalyzer.splitAlternatives(trimmed)) {
      final parts = RuleAnalyzer.splitConcat(alt);
      final buf = <String>[];
      for (final piece in parts) {
        final v = _evalStringPiece(piece, ctx);
        if (v != null && v.isNotEmpty) buf.add(v);
      }
      if (buf.isNotEmpty) return buf.join('\n');
    }
    return null;
  }

  /// 取字符串列表（`||` 兜底取第一个非空列表）。
  List<String> getStrings(String rule, {Object? ctx}) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = _evalJsPipelineSync(trimmed, ctx: ctx, asList: true);
      return _dynamicToStringList(val);
    }
    if (_hasInlineTemplateOutsideReplace(trimmed)) {
      final s = _evalInlineTemplateSync(trimmed, ctx: ctx);
      return (s == null || s.isEmpty) ? const [] : [s];
    }
    for (final alt in RuleAnalyzer.splitAlternatives(trimmed)) {
      final parts = RuleAnalyzer.splitConcat(alt);
      final out = <String>[];
      for (final piece in parts) {
        out.addAll(_evalStringListPiece(piece, ctx));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// 取元素列表（用于 bookList 这类“再迭代”的规则；CSS / XPath / JS 皆可）。
  List<Object> getElements(String rule, {Object? ctx}) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (LegadoJsEngine.containsJs(trimmed)) {
      final raw = _evalJsPipelineSync(trimmed, ctx: ctx, asList: true);
      return _dynamicToElements(raw);
    }
    for (final alt in RuleAnalyzer.splitAlternatives(trimmed)) {
      final raw = _evalPiece(alt, ctx);
      final els = raw
          .where((o) => o is dom.Element || o is xml.XmlElement)
          .toList();
      if (els.isNotEmpty) return els;
    }
    return const [];
  }

  /// 取原始结果列表（保留原型：DOM 元素 / XML 节点 / JSON 值 / 字符串）。
  List<Object> getRawList(String rule, {Object? ctx}) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = _evalJsPipelineSync(trimmed, ctx: ctx, asList: true);
      return _dynamicToRawList(val);
    }
    for (final alt in RuleAnalyzer.splitAlternatives(trimmed)) {
      final raw = _evalPiece(alt, ctx);
      if (raw.isNotEmpty) return raw;
    }
    return const [];
  }

  // ---------- 对外异步 API（支持 JS 内调用 `java.ajax` / `java.get` / `java.post`） ----------

  Future<String?> getStringAsync(String rule, {Object? ctx}) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return null;
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = await _evalJsPipelineAsync(trimmed, ctx: ctx, asList: false);
      return _dynamicToString(val);
    }
    if (_hasInlineTemplateOutsideReplace(trimmed)) {
      return _evalInlineTemplateAsync(trimmed, ctx: ctx);
    }
    return getString(trimmed, ctx: ctx);
  }

  Future<List<String>> getStringsAsync(String rule, {Object? ctx}) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = await _evalJsPipelineAsync(trimmed, ctx: ctx, asList: true);
      return _dynamicToStringList(val);
    }
    if (_hasInlineTemplateOutsideReplace(trimmed)) {
      final s = await _evalInlineTemplateAsync(trimmed, ctx: ctx);
      return (s == null || s.isEmpty) ? const [] : [s];
    }
    return getStrings(trimmed, ctx: ctx);
  }

  Future<List<Object>> getRawListAsync(String rule, {Object? ctx}) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (LegadoJsEngine.containsJs(trimmed)) {
      final val = await _evalJsPipelineAsync(trimmed, ctx: ctx, asList: true);
      return _dynamicToRawList(val);
    }
    return getRawList(trimmed, ctx: ctx);
  }

  // ---------- JS 管线求值 ----------

  JsEvalContext _buildJsContext(dynamic currentResult, {Object? ctx}) {
    final activeEngine = currentResult is String && currentResult != document
        ? _childWithDoc(currentResult)
        : this;
    final activeCtx = currentResult is String && currentResult != document
        ? null
        : ctx;
    return JsEvalContext(
      result: currentResult,
      baseUrl: baseUrl,
      src: document ?? '',
      key: key,
      page: page,
      sourceKey: sourceKey.isNotEmpty ? sourceKey : baseUrl,
      getStringCallback: (r) => activeEngine.getString(r, ctx: activeCtx) ?? '',
      getElementsCallback: (r) => activeEngine.getRawList(r, ctx: activeCtx),
      cookieBridge: cookieBridge,
      variableStore: variableStore,
      httpSync: httpSync,
      httpAsync: httpAsync,
      logs: jsLogs,
    );
  }

  dynamic _evalJsPipelineSync(
    String rule, {
    Object? ctx,
    required bool asList,
  }) {
    final segments = LegadoJsEngine.splitRuleSegments(rule);
    if (segments.isEmpty) return null;

    dynamic current = _initialJsInput(ctx);
    var hasTransformed = false;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (!seg.isJs) {
        final target = hasTransformed && current is String
            ? _childWithDoc(current)
            : this;
        final targetCtx = hasTransformed && current is String ? null : ctx;
        final isLast = i == segments.length - 1;
        if (asList && isLast) {
          current = target.getRawList(seg.content, ctx: targetCtx);
        } else if (asList) {
          final list = target.getStrings(seg.content, ctx: targetCtx);
          current = list.length == 1 ? list.first : list.join('\n');
        } else {
          current = target.getString(seg.content, ctx: targetCtx) ?? '';
        }
        hasTransformed = true;
      } else {
        final jsCtx = _buildJsContext(current, ctx: ctx);
        final res = _jsEngine.eval(seg.content, context: jsCtx);
        if (!res.ok) {
          jsLogs.add('[js error] ${res.error}');
          return null;
        }
        current = res.value;
        hasTransformed = true;
      }
    }
    return current;
  }

  Future<dynamic> _evalJsPipelineAsync(
    String rule, {
    Object? ctx,
    required bool asList,
  }) async {
    final segments = LegadoJsEngine.splitRuleSegments(rule);
    if (segments.isEmpty) return null;

    dynamic current = _initialJsInput(ctx);
    var hasTransformed = false;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (!seg.isJs) {
        final target = hasTransformed && current is String
            ? _childWithDoc(current)
            : this;
        final targetCtx = hasTransformed && current is String ? null : ctx;
        final isLast = i == segments.length - 1;
        if (asList && isLast) {
          current = target.getRawList(seg.content, ctx: targetCtx);
        } else if (asList) {
          final list = target.getStrings(seg.content, ctx: targetCtx);
          current = list.length == 1 ? list.first : list.join('\n');
        } else {
          current = target.getString(seg.content, ctx: targetCtx) ?? '';
        }
        hasTransformed = true;
      } else {
        final jsCtx = _buildJsContext(current, ctx: ctx);
        final res = await _jsEngine.evalAsync(seg.content, context: jsCtx);
        if (!res.ok) {
          jsLogs.add('[js error] ${res.error}');
          return null;
        }
        current = res.value;
        hasTransformed = true;
      }
    }
    return current;
  }

  dynamic _initialJsInput(Object? ctx) {
    if (ctx == null) return document ?? '';
    if (ctx is String ||
        ctx is num ||
        ctx is bool ||
        ctx is Map ||
        ctx is List) {
      return ctx;
    }
    if (ctx is dom.Element) return ctx.outerHtml;
    if (ctx is xml.XmlElement) return ctx.toXmlString();
    return ctx.toString();
  }

  // ---------- 内联 `{{...}}` 模板求值 ----------

  static final RegExp _inlineTplRe = RegExp(r'\{\{([\s\S]+?)\}\}');

  /// 仅在基础规则段（`##` 替换链之前）包含 `{{...}}` 时走内联模板求值，
  /// 避免影响 `##{{chapter.title}}` 这类替换链变量语法。
  static bool _hasInlineTemplateOutsideReplace(String rule) {
    if (!rule.contains('{{') || !rule.contains('}}')) return false;
    final replaceIdx = rule.indexOf('##');
    final basePart = replaceIdx >= 0 ? rule.substring(0, replaceIdx) : rule;
    return _inlineTplRe.hasMatch(basePart);
  }

  String? _evalInlineTemplateSync(String rule, {Object? ctx}) {
    final parts = RuleAnalyzer.splitReplaces(rule);
    final rendered = parts.base.replaceAllMapped(_inlineTplRe, (m) {
      final expr = m.group(1)!.trim();
      return _evalSingleInlineExprSync(expr, ctx: ctx);
    });
    final applied = parts.chains.isEmpty
        ? rendered
        : RuleAnalyzer.applyReplaces(rendered, parts.chains, vars: vars);
    final trimmed = applied.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> _evalInlineTemplateAsync(String rule, {Object? ctx}) async {
    final parts = RuleAnalyzer.splitReplaces(rule);
    final matches = _inlineTplRe.allMatches(parts.base).toList();
    if (matches.isEmpty) return null;
    final sb = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      sb.write(parts.base.substring(cursor, m.start));
      final expr = m.group(1)!.trim();
      sb.write(await _evalSingleInlineExprAsync(expr, ctx: ctx));
      cursor = m.end;
    }
    sb.write(parts.base.substring(cursor));
    final rendered = sb.toString();
    final applied = parts.chains.isEmpty
        ? rendered
        : RuleAnalyzer.applyReplaces(rendered, parts.chains, vars: vars);
    final trimmed = applied.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _evalSingleInlineExprSync(String expr, {Object? ctx}) {
    if (expr.isEmpty) return '';
    if (vars.containsKey(expr)) return vars[expr] ?? '';
    if (_looksLikeSelectorExpr(expr)) {
      return getString(expr, ctx: ctx) ?? '';
    }
    final jsCtx = _buildJsContext(_initialJsInput(ctx), ctx: ctx);
    final res = _jsEngine.eval(expr, context: jsCtx);
    if (res.ok && res.value != null) {
      return res.asString;
    }
    // JS 失败时尝试按普通规则求值（兼容 Legado `{{class.x@text}}` 写法）
    return getString(expr, ctx: ctx) ?? '';
  }

  Future<String> _evalSingleInlineExprAsync(String expr, {Object? ctx}) async {
    if (expr.isEmpty) return '';
    if (vars.containsKey(expr)) return vars[expr] ?? '';
    if (_looksLikeSelectorExpr(expr)) {
      return getString(expr, ctx: ctx) ?? '';
    }
    final jsCtx = _buildJsContext(_initialJsInput(ctx), ctx: ctx);
    final res = await _jsEngine.evalAsync(expr, context: jsCtx);
    if (res.ok && res.value != null) {
      return res.asString;
    }
    return getString(expr, ctx: ctx) ?? '';
  }

  static bool _looksLikeSelectorExpr(String expr) =>
      expr.startsWith(r'$.') ||
      expr.startsWith(r'$[') ||
      expr.startsWith(r'$..') ||
      expr.startsWith('@css:') ||
      expr.startsWith('@xpath:') ||
      expr.startsWith('@json:') ||
      expr.startsWith('@regex:') ||
      expr.startsWith('class.') ||
      expr.startsWith('id.') ||
      expr.startsWith('tag.');

  // ---------- 动态结果转换 ----------

  String? _dynamicToString(dynamic val) {
    if (val == null) return null;
    if (val is String) {
      final t = val.trim();
      return t.isEmpty ? null : t;
    }
    if (val is List) {
      final strs = _dynamicToStringList(val);
      return strs.isEmpty ? null : strs.join('\n');
    }
    if (val is dom.Element || val is xml.XmlElement) {
      return _toStr(val);
    }
    if (val is Map) return jsonEncode(val);
    final s = val.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<String> _dynamicToStringList(dynamic val) {
    if (val == null) return const [];
    if (val is List) {
      final out = <String>[];
      for (final item in val) {
        if (item == null) continue;
        final s = item is Object ? _toStr(item) : item.toString();
        if (s != null && s.isNotEmpty) out.add(s);
      }
      return out;
    }
    final s = _dynamicToString(val);
    return s == null ? const [] : [s];
  }

  List<Object> _dynamicToRawList(dynamic val) {
    if (val == null) return const [];
    if (val is List) {
      return val.whereType<Object>().toList();
    }
    if (val is String) {
      final t = val.trim();
      if (t.isEmpty) return const [];
      if (t.startsWith('[')) {
        try {
          final decoded = jsonDecode(t);
          if (decoded is List) return decoded.whereType<Object>().toList();
        } catch (_) {}
      }
      return [t];
    }
    return [val as Object];
  }

  List<Object> _dynamicToElements(dynamic val) {
    final raw = _dynamicToRawList(val);
    final els = raw
        .where((o) => o is dom.Element || o is xml.XmlElement)
        .toList();
    if (els.isNotEmpty) return els;
    // 若 JS 返回了 HTML 片段字符串，自动解析为其顶层元素
    if (val is String && val.contains('<')) {
      final doc = parseHtml(val);
      return List<Object>.from(doc.body?.children ?? const []);
    }
    return raw;
  }

  // ---------- 内部求值 ----------

  List<Object> _evalPiece(String piece, Object? ctx) {
    if (LegadoJsEngine.containsJs(piece)) {
      return _dynamicToRawList(
        _evalJsPipelineSync(piece, ctx: ctx, asList: true),
      );
    }
    final parts = RuleAnalyzer.splitReplaces(piece);
    var rawBase = parts.base.trim();
    // 结果切片：`[1]` 取第 2 个、`[0,2]` 取前三段（Legado 的列表写法）
    final sliceMatch = RegExp(r'\[(-?\d+)(?:,(-?\d+))?\]$').firstMatch(rawBase);
    final slice = sliceMatch == null
        ? null
        : (
            int.parse(sliceMatch.group(1)!),
            sliceMatch.group(2) == null
                ? null
                : int.parse(sliceMatch.group(2)!),
          );
    if (sliceMatch != null) {
      rawBase = rawBase.substring(0, sliceMatch.start).trim();
    }
    final (mode, base) = RuleAnalyzer.parsePrefix(rawBase);
    List<Object> res;
    if (base.isEmpty) {
      final t = _ctxText(ctx);
      res = t == null ? const [] : [t];
    } else {
      res = _evalBase(base, mode, ctx);
    }
    if (slice != null) {
      final (a, b) = slice;
      if (b == null) {
        final i = a < 0 ? res.length + a : a;
        res = (i >= 0 && i < res.length) ? <Object>[res[i]] : const [];
      } else {
        final s = a < 0 ? res.length + a : a;
        final e = b < 0 ? res.length + b : b;
        res = (s >= 0 && s <= e && e < res.length)
            ? res.sublist(s, e + 1)
            : const [];
      }
    }
    if (parts.chains.isEmpty) return res;
    return res
        .map(
          (o) => RuleAnalyzer.applyReplaces(
            _toStr(o) ?? '',
            parts.chains,
            vars: vars,
          ),
        )
        .toList();
  }

  String? _evalStringPiece(String piece, Object? ctx) {
    for (final o in _evalPiece(piece, ctx)) {
      final s = _toStr(o);
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  List<String> _evalStringListPiece(String piece, Object? ctx) {
    final out = <String>[];
    for (final o in _evalPiece(piece, ctx)) {
      final s = _toStr(o);
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out;
  }

  List<Object> _evalBase(String rule, RuleMode mode, Object? ctx) {
    var m = mode;
    if (m == RuleMode.auto) {
      if (rule.startsWith(r'$.') ||
          rule.startsWith(r'$[') ||
          rule.startsWith(r'$..')) {
        m = RuleMode.json;
      } else if (jsonDoc != null) {
        m = RuleMode.json;
      } else if (looksLikeRegex(rule)) {
        m = RuleMode.regex;
      } else {
        m = RuleMode.css;
      }
    }
    switch (m) {
      case RuleMode.css:
        final node = _ctxDomNode(ctx);
        final stages = parseCssStages(rule);
        final result = evalCss(node, stages);
        if (result.isNotEmpty) return result;
        // 规则写成 `a@href`，但上下文元素**本身就是那个 <a>**（书源里很常见：
        // bookList 是 `a.m-book-row`，bookUrl 却写 `a@href`）。
        // 严格按「后代选择器」解析会得到空值，这里补一次「自身也参与匹配」的兜底。
        if (ctx is dom.Element && stages.length > 1) {
          final first = stages.first;
          if (first.type == CssStageType.selector && first.value.isNotEmpty) {
            final parent = ctx.parent;
            if (parent != null &&
                selectElements(parent, first.value).contains(ctx)) {
              return evalCss(ctx, stages.sublist(1));
            }
          }
        }
        return result;
      case RuleMode.json:
        final root = _ctxJson(ctx);
        if (root == null) return const [];
        return List<Object>.from(jsonSelect(root, rule));
      case RuleMode.xpath:
        final doc = xmlDoc;
        if (doc == null) return const [];
        final xmlCtx = _ctxXml(ctx) ?? doc;
        final r = evalXPath(xmlCtx, rule);
        return r.strings.isEmpty
            ? List<Object>.from(r.elements)
            : List<Object>.from(r.strings);
      case RuleMode.regex:
        final text = _ctxText(ctx) ?? document ?? '';
        return regexExtract(text, rule);
      case RuleMode.auto:
        return const [];
    }
  }

  // ---------- 上下文适配 ----------

  dom.Node _ctxDomNode(Object? ctx) {
    if (ctx is dom.Node) return ctx;
    return htmlDoc;
  }

  dynamic _ctxJson(Object? ctx) {
    if (ctx is Map || ctx is List) return ctx;
    return jsonDoc;
  }

  xml.XmlNode? _ctxXml(Object? ctx) {
    if (ctx is xml.XmlNode) return ctx;
    return null;
  }

  String? _ctxText(Object? ctx) {
    if (ctx == null) return null;
    if (ctx is String) return ctx;
    if (ctx is dom.Element) {
      final t = RuleAnalyzer.collapseSpaces(ctx.text);
      return t.isEmpty ? null : t;
    }
    if (ctx is xml.XmlElement) {
      final t = RuleAnalyzer.collapseSpaces(ctx.innerText);
      return t.isEmpty ? null : t;
    }
    if (ctx is num || ctx is bool) return ctx.toString();
    return null;
  }

  String? _toStr(Object o) {
    if (o is String) {
      final t = RuleAnalyzer.collapseSpaces(o);
      return t.isEmpty ? null : t;
    }
    if (o is dom.Element) {
      final t = RuleAnalyzer.collapseSpaces(o.text);
      return t.isEmpty ? null : t;
    }
    if (o is xml.XmlElement) {
      final t = RuleAnalyzer.collapseSpaces(o.innerText);
      return t.isEmpty ? null : t;
    }
    final v = jsonValueToString(o);
    return v;
  }
}
