// 正则分析器：把规则作为正则表达式在文本中提取结果。
//
// 行为（对照书源规则的常见用法）：
// - 有捕获组：每个匹配取第 1 个捕获组；无捕获组：取整个匹配；
// - 结果去首尾空白，空串丢弃；
// - 非法正则 / 空输入 → 返回空列表（不抛异常）。
//
// 注意：Dart 的 RegExp 基于 ECMAScript 语义，不支持 `(?s)` 等内联旗标；
// 遇到这类写法会安全地返回空（后续里程碑按真实源需要再增强）。
import 'rule_analyzer.dart';

/// 在 [text] 上执行 [pattern] 正则提取。
List<String> regexExtract(String text, String pattern) {
  if (text.isEmpty || pattern.isEmpty) return const [];
  try {
    final re = RegExp(pattern);
    final out = <String>[];
    for (final m in re.allMatches(text)) {
      final v = (m.groupCount >= 1 ? m.group(1) : m.group(0)) ?? '';
      final t = v.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// 与 [regexExtract] 相同，但额外做空白折叠（用于标题 / 作者这类短文本）。
List<String> regexExtractClean(String text, String pattern) =>
    regexExtract(text, pattern).map(RuleAnalyzer.collapseSpaces).toList();

/// 判断一个规则串“长得像正则”的宽松启发（用于 auto 模式下 HTML 文本的兜底）。
///
/// 说明：只做保守判断，避免把普通选择器误判为正则。
bool looksLikeRegex(String rule) {
  if (rule.startsWith('^') || rule.endsWith(r'$')) return true;
  if (rule.contains('(?') || rule.contains(r'\d') || rule.contains(r'\w')) {
    return true;
  }
  return false;
}
