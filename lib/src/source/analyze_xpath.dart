// XPath 分析器（纯 Dart 迷你实现，覆盖书源规则常用子集）。
//
// 支持：
//   /a/b/c                  子节点路径（绝对 / 相对）
//   //a//b                  后代查找（任意深度）
//   *                       任意元素
//   [@attr] [@attr='v'] [@attr="v"]   属性断言
//   [N] [last()]            位置筛选（1 起，作用于同父分组）
//   @attr                   取属性（最终步）
//   text()                  取文本（最终步）
//
// 解析失败 / 文档不是合法 XML → 返回空结果（不抛异常）。
// 注：真实网页 HTML 常不合法（未闭合标签），上层会在解析失败时降级处理。
import 'package:xml/xml.dart';

/// XPath 求值结果：元素列表或字符串列表。
class XPathResult {
  const XPathResult.elements(this.elements) : strings = const [];
  const XPathResult.strings(this.strings) : elements = const [];

  final List<XmlElement> elements;
  final List<String> strings;

  bool get isEmpty => elements.isEmpty && strings.isEmpty;
}

// ---------- 表达式解析 ----------

class _Step {
  _Step({
    required this.descendant,
    required this.name,
    required this.isAttr,
    required this.isText,
  });

  final bool descendant; // `//` 轴；false = 子节点轴
  final String name; // 元素名、'*' 或属性名
  final bool isAttr;
  final bool isText;
  final preds = <_Pred>[];
}

class _Pred {
  String? attr;
  String? value;
  int? index;
  bool isLast = false;
}

List<_Step>? _parseSteps(String expr) {
  var s = expr.trim();
  if (s.isEmpty) return null;
  final steps = <_Step>[];
  var i = 0;
  var pendingDescendant = false;
  var sawSlash = false;
  while (i < s.length) {
    final c = s[i];
    if (c == '/') {
      sawSlash = true;
      if (i + 1 < s.length && s[i + 1] == '/') {
        pendingDescendant = true;
        i += 2;
      } else {
        pendingDescendant = false;
        i++;
      }
      continue;
    }
    // 读一个 step，直到下一个 '/'（不含谓词中的 '/' —— 谓词里通常没有斜杠）
    var j = i;
    var bracket = 0;
    while (j < s.length) {
      final cj = s[j];
      if (cj == '[') bracket++;
      if (cj == ']') bracket--;
      if (cj == '/' && bracket == 0) break;
      j++;
    }
    final raw = s.substring(i, j).trim();
    if (raw.isEmpty) return null;
    final step = _parseStep(
      raw,
      pendingDescendant || (!sawSlash && steps.isEmpty && false),
    );
    if (step == null) return null;
    steps.add(step);
    i = j;
    pendingDescendant = false;
  }
  return steps;
}

_Step? _parseStep(String raw, bool descendant) {
  // 分离谓词
  final preds = <_Pred>[];
  var name = raw;
  final firstBracket = raw.indexOf('[');
  if (firstBracket >= 0) {
    name = raw.substring(0, firstBracket);
    var i = firstBracket;
    while (i < raw.length) {
      if (raw[i] != '[') return null;
      final close = raw.indexOf(']', i);
      if (close < 0) return null;
      final inner = raw.substring(i + 1, close).trim();
      final pred = _parsePred(inner);
      preds.add(pred);
      i = close + 1;
    }
  }
  name = name.trim();
  if (name.isEmpty) return null;
  _Step step;
  if (name.startsWith('@')) {
    step = _Step(
      descendant: descendant,
      name: name.substring(1),
      isAttr: true,
      isText: false,
    );
  } else if (name == 'text()') {
    step = _Step(
      descendant: descendant,
      name: 'text()',
      isAttr: false,
      isText: true,
    );
  } else {
    step = _Step(
      descendant: descendant,
      name: name,
      isAttr: false,
      isText: false,
    );
  }
  step.preds.addAll(preds);
  return step;
}

_Pred _parsePred(String inner) {
  final p = _Pred();
  if (inner.startsWith('@')) {
    final eq = inner.indexOf('=');
    if (eq < 0) {
      p.attr = inner.substring(1).trim();
      return p;
    }
    p.attr = inner.substring(1, eq).trim();
    var v = inner.substring(eq + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith("'") && v.endsWith("'")) ||
            (v.startsWith('"') && v.endsWith('"')))) {
      v = v.substring(1, v.length - 1);
    }
    p.value = v;
    return p;
  }
  if (inner == 'last()') {
    p.isLast = true;
    return p;
  }
  final n = int.tryParse(inner);
  if (n != null) {
    p.index = n;
    return p;
  }
  // 不支持的谓词：当作“保留全部”的空操作（宽松兜底）
  return p;
}

// ---------- 求值 ----------

/// 在 [context]（文档或元素）上执行 [expr]。
XPathResult evalXPath(XmlNode context, String expr) {
  final steps = _parseSteps(expr);
  if (steps == null || steps.isEmpty) return const XPathResult.elements([]);

  var current = <XmlElement>[];
  final first = steps.first;
  final isAbsolute =
      expr.trimLeft().startsWith('/') && !expr.trimLeft().startsWith('//');
  if (isAbsolute || expr.trimLeft().startsWith('//')) {
    final rootEl = context is XmlDocument
        ? context.rootElement
        : (context is XmlElement ? context : context.firstElementChild);
    if (rootEl == null) return const XPathResult.elements([]);
    if (isAbsolute) {
      final matches = _matchOn([rootEl], first, includeSelf: true);
      current = matches;
    } else {
      final all = rootEl.descendantElements.toList();
      final matches = _matchOn(all, first, includeSelf: false);
      current = matches;
    }
  } else {
    // 相对路径：对上下文的所有后代做首步匹配（书源里最常见的是 .// 变体）
    final base = context is XmlElement ? context : context.firstElementChild;
    if (base == null) return const XPathResult.elements([]);
    final all = base.descendantElements.toList();
    final matches = _matchOn(all, first, includeSelf: false);
    current = matches;
  }

  for (var k = 1; k < steps.length; k++) {
    final step = steps[k];
    if (step.isAttr || step.isText) {
      return _terminal(current, step);
    }
    final next = <XmlElement>[];
    for (final el in current) {
      if (step.descendant) {
        next.addAll(
          _matchOn(el.descendantElements.toList(), step, includeSelf: false),
        );
      } else {
        next.addAll(
          _matchOn(el.childElements.toList(), step, includeSelf: true),
        );
      }
    }
    current = next;
    if (current.isEmpty) break;
  }

  // 末步是普通元素步：若 expr 以 @/text() 结尾则已在上面返回
  if (steps.last.isAttr || steps.last.isText) {
    return _terminal(_resolveLastPreds(current, steps.last), steps.last);
  }
  return XPathResult.elements(current);
}

List<XmlElement> _resolveLastPreds(List<XmlElement> nodes, _Step step) =>
    _applyPreds(nodes, step);

List<XmlElement> _matchOn(
  List<XmlElement> candidates,
  _Step step, {
  required bool includeSelf,
}) {
  var matched = candidates.where((el) => _nameMatches(el, step.name)).toList();
  matched = _applyPreds(matched, step);
  return matched;
}

bool _nameMatches(XmlElement el, String name) {
  if (name == '*') return true;
  return el.name.local == name || el.name.toString() == name;
}

List<XmlElement> _applyPreds(List<XmlElement> nodes, _Step step) {
  var list = nodes;
  for (final p in step.preds) {
    if (p.attr != null) {
      final attr = p.attr!;
      if (p.value == null) {
        list = list.where((el) => el.getAttribute(attr) != null).toList();
      } else {
        list = list
            .where((el) => (el.getAttribute(attr) ?? '') == p.value)
            .toList();
      }
    } else if (p.index != null) {
      // 位置：按父节点分组，第 N 个（1 起）
      list = _pickByPosition(list, p.index! - 1, fromEnd: false);
    } else if (p.isLast) {
      list = _pickByPosition(list, 0, fromEnd: true);
    }
  }
  return list;
}

List<XmlElement> _pickByPosition(
  List<XmlElement> nodes,
  int idx, {
  required bool fromEnd,
}) {
  final grouped = <XmlNode?, List<XmlElement>>{};
  for (final el in nodes) {
    grouped.putIfAbsent(el.parent, () => []).add(el);
  }
  final out = <XmlElement>[];
  for (final group in grouped.values) {
    final i = fromEnd ? group.length - 1 : idx;
    if (i >= 0 && i < group.length) out.add(group[i]);
  }
  return out;
}

XPathResult _terminal(List<XmlElement> nodes, _Step step) {
  if (step.isAttr) {
    final out = <String>[];
    for (final el in nodes) {
      final v = el.getAttribute(step.name);
      if (v != null && v.trim().isNotEmpty) out.add(v.trim());
    }
    return XPathResult.strings(out);
  }
  // text()：取直接文本子节点；若没有直接文本，退化取整体文本
  final out = <String>[];
  for (final el in nodes) {
    final texts = el.children
        .whereType<XmlText>()
        .map((t) => t.value.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (texts.isEmpty) {
      final whole = el.innerText.trim();
      if (whole.isNotEmpty) out.add(whole);
    } else {
      out.addAll(texts);
    }
  }
  return XPathResult.strings(out);
}
