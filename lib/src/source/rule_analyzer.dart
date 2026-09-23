// 规则字符串解析工具（独立实现，语义对照 Legado 书源规则的公开行为）。
//
// 书源规则字符串的通用结构：
//   `A || B || C`         多个备选规则，从左到右取第一个非空结果（兜底）
//   `A && B`              串联拼接（两段结果直接相连）
//   `base##regex##rep`    结果替换链（可多组依次执行；末尾单段 = 删除匹配）
//   `@json: / @xpath: / @css:`  显式指定求值模式（无前缀时按文档类型自动分派）
//
// 注意：与 Legado 一致，`||` / `&&` / `##` 不做转义处理。

/// 求值模式。
enum RuleMode {
  /// 自动：按文档类型推断（JSON 文档 → JSONPath；其余 → CSS）。
  auto,
  css,
  json,
  xpath,
  regex,
}

/// 单条替换链：`pattern` 匹配 → 替换为 `replacement`（支持 `$1` 捕获组）。
class ReplaceChain {
  const ReplaceChain(this.pattern, this.replacement);

  final String pattern;
  final String replacement;
}

/// 规则拆解结果：基础规则 + 替换链。
class RuleParts {
  const RuleParts(this.base, this.chains);

  final String base;
  final List<ReplaceChain> chains;

  bool get hasChains => chains.isNotEmpty;
}

/// 规则字符串的解析工具集。
abstract final class RuleAnalyzer {
  static const String jsonPrefix = '@json:';
  static const String xpathPrefix = '@xpath:';
  static const String cssPrefix = '@css:';
  static const String regexPrefix = '@regex:';

  /// 顶层拆分 `||` 备选（去空白、忽略空段）。
  static List<String> splitAlternatives(String rule) =>
      rule.split('||').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// 拆分 `&&` 串联（去空白、忽略空段）。
  static List<String> splitConcat(String rule) =>
      rule.split('&&').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// 拆出 `##` 替换链。
  ///
  /// `a##p1##r1##p2##r2` → base=`a`, chains=[(p1,r1),(p2,r2)]
  /// 末尾落单的一段视为“删除该匹配”（replacement 为空串）。
  static RuleParts splitReplaces(String rule) {
    if (!rule.contains('##')) {
      return RuleParts(rule.trim(), const []);
    }
    final parts = rule.split('##');
    final base = parts.first.trim();
    final chains = <ReplaceChain>[];
    for (var i = 1; i < parts.length; i += 2) {
      final pattern = parts[i];
      final replacement = (i + 1 < parts.length) ? parts[i + 1] : '';
      if (pattern.isEmpty) continue;
      chains.add(ReplaceChain(pattern, replacement));
    }
    return RuleParts(base, chains);
  }

  /// 解析模式前缀，返回（模式, 剩余规则）。无前缀时模式为 [RuleMode.auto]。
  static (RuleMode, String) parsePrefix(String rule) {
    final r = rule.trim();
    if (r.startsWith(jsonPrefix)) {
      return (RuleMode.json, r.substring(jsonPrefix.length).trim());
    }
    if (r.startsWith(xpathPrefix)) {
      return (RuleMode.xpath, r.substring(xpathPrefix.length).trim());
    }
    if (r.startsWith(cssPrefix)) {
      return (RuleMode.css, r.substring(cssPrefix.length).trim());
    }
    if (r.startsWith(regexPrefix)) {
      return (RuleMode.regex, r.substring(regexPrefix.length).trim());
    }
    return (RuleMode.auto, r);
  }

  /// 应用替换链（容错：非法正则跳过该链）。
  ///
  /// 替换串支持 `$1`..`$9` 与 `$&` 引用捕获组（手动展开，跨版本一致）。
  static String applyReplaces(String input, List<ReplaceChain> chains) {
    final refPattern = RegExp(r'\$(\d|&)');
    var out = input;
    for (final chain in chains) {
      try {
        out = out.replaceAllMapped(RegExp(chain.pattern), (m) {
          if (!chain.replacement.contains(r'$')) return chain.replacement;
          return chain.replacement.replaceAllMapped(refPattern, (r) {
            final k = r.group(1)!;
            if (k == '&') return m.group(0) ?? '';
            final idx = int.parse(k);
            return m.group(idx) ?? '';
          });
        });
      } catch (_) {
        // 非法正则：跳过，不影响其它链
      }
    }
    return out;
  }

  /// 规范空白：折叠连续空白为单个空格并去首尾（用于把 HTML 文本变干净）。
  static String collapseSpaces(String s) =>
      s.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim();
}
