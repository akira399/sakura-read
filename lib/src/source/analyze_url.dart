// URL 模板分析器：把书源里的 URL 模板渲染成实际请求地址。
//
// 支持（对照 Legado AnalyzeUrl 的公开行为，独立实现）：
//   {{key}} / {{searchKey}} / {{keyword}}   搜索词（UTF-8 百分号编码）
//   {{page}}                                页码
//   {{任意键}}                              从 vars 传入的自定义变量
//   `,{...}` 尾缀                            请求选项 JSON（method / body / charset / headers）
//   相对路径                                 以书源 bookSourceUrl 为基准补全为绝对地址
import 'dart:convert';

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

/// 渲染模板变量。
///
/// [vars] 至少应包含 `key` 与 `page`；`searchKey` / `keyword` 会映射到 `key`。
String renderUrlTemplate(String template, Map<String, dynamic> vars) {
  return template.replaceAllMapped(_varPattern, (m) {
    final name = m.group(1)!.trim();
    dynamic v;
    switch (name) {
      case 'key':
      case 'searchKey':
      case 'keyword':
        v = vars['key'] ?? '';
      case 'page':
        v = vars['page'] ?? '1';
      default:
        v = vars[name] ?? '';
    }
    final s = v.toString();
    // 搜索词与自定义值都做 URL 编码；page 是数字，编码后不变。
    return Uri.encodeComponent(s);
  });
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

/// 一步到位：解析 + 渲染 + 补全。
///
/// [baseUrl] 通常是书源的 `bookSourceUrl`。
UrlTemplate buildRequest(
  String rawTemplate,
  String baseUrl,
  Map<String, dynamic> vars,
) {
  final t = parseUrlTemplate(rawTemplate);
  final rendered = renderUrlTemplate(t.url, vars);
  return UrlTemplate(resolveUrl(rendered, baseUrl), t.options);
}
