// 规则求值引擎：把「规则字符串 + 文档」的完整求值流程串起来。
//
// 求值顺序（对照 Legado 的公开行为，独立实现）：
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

/// 规则求值器。
class AnalyzeRule {
  AnalyzeRule(this.document, {this.baseUrl = ''});

  /// 文档文本（HTML 或 JSON；也可为普通文本）。
  final String? document;

  /// 书源主地址（补全相对链接用，引擎内部暂不消费，M2 使用）。
  final String baseUrl;

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

  // ---------- 对外 API ----------

  /// 取单个字符串结果（`||` 兜底取第一个非空）。
  String? getString(String rule, {Object? ctx}) {
    for (final alt in RuleAnalyzer.splitAlternatives(rule)) {
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
    for (final alt in RuleAnalyzer.splitAlternatives(rule)) {
      final parts = RuleAnalyzer.splitConcat(alt);
      final out = <String>[];
      for (final piece in parts) {
        out.addAll(_evalStringListPiece(piece, ctx));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  /// 取元素列表（用于 bookList 这类“再迭代”的规则；CSS / XPath 皆可）。
  List<Object> getElements(String rule, {Object? ctx}) {
    for (final alt in RuleAnalyzer.splitAlternatives(rule)) {
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
    for (final alt in RuleAnalyzer.splitAlternatives(rule)) {
      final raw = _evalPiece(alt, ctx);
      if (raw.isNotEmpty) return raw;
    }
    return const [];
  }

  // ---------- 内部求值 ----------

  List<Object> _evalPiece(String piece, Object? ctx) {
    final parts = RuleAnalyzer.splitReplaces(piece);
    final (mode, base) = RuleAnalyzer.parsePrefix(parts.base);
    List<Object> res;
    if (base.isEmpty) {
      final t = _ctxText(ctx);
      res = t == null ? const [] : [t];
    } else {
      res = _evalBase(base, mode, ctx);
    }
    if (parts.chains.isEmpty) return res;
    return res
        .map((o) => RuleAnalyzer.applyReplaces(_toStr(o) ?? '', parts.chains))
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
        return evalCss(node, parseCssStages(rule));
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
