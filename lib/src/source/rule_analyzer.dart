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
  /// 替换串支持 `$1`..`$9` 与 `$&` 引用捕获组（手动展开，跨版本一致）；
  /// 还支持 `{{变量}}`（如 `{{chapter.title}}`，未提供的变量替换为空串）。
  static String applyReplaces(
    String input,
    List<ReplaceChain> chains, {
    Map<String, String> vars = const {},
  }) {
    final refPattern = RegExp(r'\$(\d|&)');
    var out = input;
    for (final chain in chains) {
      final withVars = _substituteVars(chain.replacement, vars);
      // Legado 的 `{{变量}}` 在模式段里同样会展开（如 `##{{chapter.title}}`
      // 表示「把章节标题这行删掉」），所以模式段也要先做变量替换。
      final pattern = _substituteVars(chain.pattern, vars);
      if (pattern.isEmpty) continue;
      RegExp re;
      try {
        re = RegExp(pattern);
      } catch (_) {
        // 模式不是合法正则（如花括号残留）：按字面量处理，
        // 比直接跳过更接近书源作者的意图。
        try {
          re = RegExp(RegExp.escape(pattern));
        } catch (_) {
          continue;
        }
      }
      try {
        out = out.replaceAllMapped(re, (m) {
          if (!withVars.contains(r'$')) return withVars;
          return withVars.replaceAllMapped(refPattern, (r) {
            final k = r.group(1)!;
            if (k == '&') return m.group(0) ?? '';
            final idx = int.parse(k);
            return m.group(idx) ?? '';
          });
        });
      } catch (_) {
        // 替换过程异常：跳过该链，不影响其它链
      }
    }
    return out;
  }

  /// 替换 `{{name}}` / `{{chapter.title}}` 变量；未定义变量按空串处理。
  static String _substituteVars(String s, Map<String, String> vars) {
    if (!s.contains('{{')) return s;
    return s.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (m) {
      final key = m.group(1)!.trim();
      return vars[key] ?? '';
    });
  }

  /// 规范空白：折叠连续空白为单个空格并去首尾（用于把 HTML 文本变干净）。
  static String collapseSpaces(String s) =>
      s.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim();
}
