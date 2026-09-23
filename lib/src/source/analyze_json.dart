// JSONPath 分析器（Legado 书源使用的实用子集，独立实现）。
//
// 支持：
//   $.a.b            子字段
//   $['a']["b"]      带引号子字段
//   $.a[0]           数组下标
//   $.a[*]           数组通配
//   $.a.* / $.a[*]   对象/数组通配
//   $..name          递归后代查找（深度优先）
//   $[0].name        顶层数组
//
// 暂不支持：过滤表达式 `[?(...)]`、切片 `[1:3]`（M4 按真实源需要再评估）。
// 解析失败时返回空列表（与“查无结果”同语义），不抛异常。

import 'dart:convert';

/// 解析路径为段列表（非法路径返回 null）。
List<_Seg>? _parseJsonPath(String path) {
  var p = path.trim();
  if (p.startsWith(r'$')) p = p.substring(1);
  final segs = <_Seg>[];
  var i = 0;
  while (i < p.length) {
    final c = p[i];
    if (c == '.') {
      if (i + 1 < p.length && p[i + 1] == '.') {
        // 递归后代：..name 或 ..*
        var j = i + 2;
        if (j >= p.length) return null;
        if (p[j] == '*') {
          segs.add(const _Seg(_SegKind.recursive, '*'));
          i = j + 1;
        } else if (p[j] == '[') {
          final close = p.indexOf(']', j);
          if (close < 0) return null;
          final inner = p.substring(j + 1, close).trim();
          final name = _unquote(inner);
          if (name == null) return null;
          segs.add(_Seg(_SegKind.recursive, name));
          i = close + 1;
        } else {
          final m = RegExp(r'^[A-Za-z_$][\w$\-]*').firstMatch(p.substring(j));
          if (m == null) return null;
          segs.add(_Seg(_SegKind.recursive, m.group(0)!));
          i = j + m.group(0)!.length;
        }
        continue;
      }
      // 普通子字段：.name 或 .*
      i++;
      if (i >= p.length) break;
      if (p[i] == '*') {
        segs.add(const _Seg(_SegKind.wildcard, '*'));
        i++;
      } else {
        final m = RegExp(r'^[A-Za-z_$][\w$\-]*').firstMatch(p.substring(i));
        if (m == null) return null;
        segs.add(_Seg(_SegKind.child, m.group(0)!));
        i += m.group(0)!.length;
      }
    } else if (c == '[') {
      final close = p.indexOf(']', i);
      if (close < 0) return null;
      final inner = p.substring(i + 1, close).trim();
      if (inner == '*') {
        segs.add(const _Seg(_SegKind.wildcard, '*'));
      } else if (RegExp(r'^\d+$').hasMatch(inner)) {
        segs.add(_Seg(_SegKind.idx, inner));
      } else {
        final name = _unquote(inner);
        if (name == null) return null;
        segs.add(_Seg(_SegKind.child, name));
      }
      i = close + 1;
    } else {
      // 隐式根字段（宽松写法：省略开头的 `$.`）
      final m = RegExp(r'^[A-Za-z_$][\w$\-]*').firstMatch(p.substring(i));
      if (m == null) return null;
      segs.add(_Seg(_SegKind.child, m.group(0)!));
      i += m.group(0)!.length;
    }
  }
  return segs;
}

String? _unquote(String s) {
  if (s.length >= 2) {
    final a = s[0], b = s[s.length - 1];
    if ((a == "'" && b == "'") || (a == '"' && b == '"')) {
      return s.substring(1, s.length - 1);
    }
  }
  // 无引号：允许裸字段名（宽松兜底）
  if (RegExp(r'^[A-Za-z_$][\w$\-]*$').hasMatch(s)) return s;
  return null;
}

enum _SegKind { child, idx, wildcard, recursive }

class _Seg {
  const _Seg(this.kind, this.name);

  final _SegKind kind;
  final String name;
}

/// 在 JSON 数据上执行路径查询；返回命中的原始值列表。
List<dynamic> jsonSelect(dynamic root, String path) {
  final segs = _parseJsonPath(path);
  if (segs == null) return const [];
  var current = <dynamic>[root];
  for (final seg in segs) {
    final next = <dynamic>[];
    switch (seg.kind) {
      case _SegKind.child:
        for (final v in current) {
          if (v is Map && v.containsKey(seg.name)) next.add(v[seg.name]);
        }
      case _SegKind.idx:
        final idx = int.parse(seg.name);
        for (final v in current) {
          if (v is List && idx >= 0 && idx < v.length) next.add(v[idx]);
        }
      case _SegKind.wildcard:
        for (final v in current) {
          if (v is List) {
            next.addAll(v);
          } else if (v is Map) {
            next.addAll(v.values);
          }
        }
      case _SegKind.recursive:
        for (final v in current) {
          _collectRecursive(v, seg.name, next);
        }
    }
    current = next;
    if (current.isEmpty) break;
  }
  return current;
}

void _collectRecursive(dynamic node, String name, List<dynamic> out) {
  if (node is Map) {
    for (final e in node.entries) {
      if (name == '*' || e.key == name) out.add(e.value);
      _collectRecursive(e.value, name, out);
    }
  } else if (node is List) {
    for (final v in node) {
      _collectRecursive(v, name, out);
    }
  }
}

/// 把查询结果转成字符串列表（对照书源规则的常见用法）：
/// - String → 原样（去首尾空白，空串丢弃）
/// - num / bool → toString
/// - Map / List → JSON 文本
/// - null → 丢弃
List<String> jsonSelectStrings(dynamic root, String path) {
  final out = <String>[];
  for (final v in jsonSelect(root, path)) {
    final s = jsonValueToString(v);
    if (s != null && s.isNotEmpty) out.add(s);
  }
  return out;
}

/// 单个值 → 字符串（null / 空串 → null）。
String? jsonValueToString(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is num || v is bool) return v.toString();
  // Map / List：编码为 JSON（书源里多见于 kind / 扩展字段）
  return jsonEncodeValue(v);
}

/// JSON 编码（用于 Map / List 结果）。
String jsonEncodeValue(dynamic v) => jsonEncode(v);
