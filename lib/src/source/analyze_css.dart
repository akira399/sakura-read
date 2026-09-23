// CSS 分析器：把 Legado 风格的 CSS 规则应用到 HTML 文档 / 元素上。
//
// 规则语法（对照 Legado 的公开行为，用 `@` 串联多个阶段）：
//   `class.book-list@tag.li`           在 .book-list 内选 li（返回元素）
//   `class.book-list@tag.li@tag.a@href` 逐级深入，最后取 href 属性
//   `id.content@text`                  取 #content 的文本
//   `class.novel.0@text`               取第 0 个匹配（支持 `.N` / `N` 索引）
//   `@css:` 前缀由上层引擎剥离
//
// 兼容旧写法：`tag.li` → `li`、`class.xx` → `.xx`、`id.xx` → `#xx`。
// 提取器关键字：text / textNodes / ownText / html / all；其余单词视为属性名。
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'rule_analyzer.dart';

/// 阶段类型。
enum CssStageType { selector, position, extractor }

/// 单个阶段。
class CssStage {
  const CssStage(this.type, this.value);

  final CssStageType type;
  final String value;
}

/// 把规则拆分为阶段列表（`@` 分隔）。解析失败时返回空列表。
List<CssStage> parseCssStages(String rule) {
  final parts = rule.split('@');
  final stages = <CssStage>[];
  for (var raw in parts) {
    final p = raw.trim();
    if (p.isEmpty) continue;
    if (_isIndex(p)) {
      stages.add(CssStage(CssStageType.position, _indexValue(p).toString()));
    } else if (_suffixIndex.hasMatch(p) &&
        !RegExp(r'^[A-Za-z_][\w:-]*$').hasMatch(p)) {
      // 形如 `class.item.0` / `.item.1` 的“选择器 + 索引”合并写法
      final m = _suffixIndex.firstMatch(p)!;
      stages.add(
        CssStage(CssStageType.selector, _normalizeSelector(m.group(1)!)),
      );
      stages.add(CssStage(CssStageType.position, m.group(2)!));
    } else if (_isExtractor(p)) {
      stages.add(CssStage(CssStageType.extractor, p));
    } else {
      stages.add(CssStage(CssStageType.selector, _normalizeSelector(p)));
    }
  }
  return stages;
}

bool _isIndex(String p) =>
    RegExp(r'^\d+$').hasMatch(p) || RegExp(r'^\.\d+$').hasMatch(p);

final _suffixIndex = RegExp(r'^(.+)\.(\d+)$');

int _indexValue(String p) => int.parse(p.startsWith('.') ? p.substring(1) : p);

const _extractorKeywords = {'text', 'textNodes', 'ownText', 'html', 'all'};

bool _isExtractor(String p) {
  if (_extractorKeywords.contains(p)) return true;
  // 属性名：字母/下划线开头，允许数字、连字符、冒号（如 data-src、xlink:href）
  return RegExp(r'^[A-Za-z_][\w:-]*$').hasMatch(p);
}

String _normalizeSelector(String p) {
  if (p.startsWith('tag.')) return p.substring(4);
  if (p.startsWith('class.')) return '.${p.substring(6)}';
  if (p.startsWith('id.')) return '#${p.substring(3)}';
  return p;
}

/// 解析 HTML 文本为文档对象（容错）。
dom.Document parseHtml(String html) => html_parser.parse(html);

/// 在上下文节点（Document 或 Element）内执行 CSS 元素选择。
List<dom.Element> selectElements(dom.Node context, String selector) {
  try {
    if (context is dom.Document) {
      return context.querySelectorAll(selector);
    }
    if (context is dom.Element) {
      return context.querySelectorAll(selector);
    }
    return const [];
  } catch (_) {
    // 选择器语法不支持：返回空结果（与“找不到元素”同语义）
    return const [];
  }
}

/// 按阶段求值。
///
/// [context] 为文档或元素；返回：
/// - 未到提取器：`List<dom.Element>`
/// - 已到提取器：`List<String>`
List<Object> evalCss(dom.Node context, List<CssStage> stages) {
  var current = <dom.Node>[context];
  for (final stage in stages) {
    switch (stage.type) {
      case CssStageType.selector:
        final next = <dom.Node>[];
        for (final node in current) {
          next.addAll(selectElements(node, stage.value));
        }
        current = next;
      case CssStageType.position:
        final idx = int.tryParse(stage.value) ?? 0;
        current = (idx >= 0 && idx < current.length)
            ? [current[idx]]
            : const <dom.Node>[];
      case CssStageType.extractor:
        return _extract(current, stage.value);
    }
    if (current.isEmpty) return const <Object>[];
  }
  return List<Object>.from(current);
}

List<String> _extract(List<dom.Node> nodes, String extractor) {
  final out = <String>[];
  for (final node in nodes) {
    final el = node is dom.Element ? node : null;
    switch (extractor) {
      case 'text':
        if (el != null) {
          final t = RuleAnalyzer.collapseSpaces(el.text);
          if (t.isNotEmpty) out.add(t);
        }
      case 'textNodes':
        if (el != null) {
          for (final n in el.nodes) {
            if (n is dom.Text) {
              final t = RuleAnalyzer.collapseSpaces(n.text);
              if (t.isNotEmpty) out.add(t);
            }
          }
        }
      case 'ownText':
        if (el != null) {
          final buf = StringBuffer();
          for (final n in el.nodes) {
            if (n is dom.Text) buf.write(n.text);
          }
          final t = RuleAnalyzer.collapseSpaces(buf.toString());
          if (t.isNotEmpty) out.add(t);
        }
      case 'html':
        if (el != null) {
          final t = el.innerHtml.trim();
          if (t.isNotEmpty) out.add(t);
        }
      case 'all':
        if (el != null) {
          final t = RuleAnalyzer.collapseSpaces(el.text);
          out.add(t);
        }
      default:
        if (el != null) {
          final v = el.attributes[extractor];
          if (v != null && v.trim().isNotEmpty) out.add(v.trim());
        }
    }
  }
  return out;
}
