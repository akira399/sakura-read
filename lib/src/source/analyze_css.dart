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
enum CssStageType { selector, position, extractor, textSearch }

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
    if (_isTextSelector(p)) {
      // `text.下一页` / `text=下一页`：按文本内容定位元素（Legado 常用写法，
      // 站点翻页/目录链接基本都靠它，不支持会导致「下一页」类书源整条规则失效）
      stages.add(CssStage(CssStageType.textSearch, _textSelectorValue(p)));
    } else if (_isIndex(p)) {
      stages.add(CssStage(CssStageType.position, _indexValue(p).toString()));
    } else if (_isExcludeIndex(p)) {
      // `!0`：排除第 0 个元素（全本 `#content@p!0@html` 去掉首段）
      stages.add(CssStage(CssStageType.position, p));
    } else if (_excludeSuffix.hasMatch(p)) {
      // `p!0` / `li!-1`：整段写法「选择器 + 排除索引」
      final m = _excludeSuffix.firstMatch(p)!;
      stages.add(
        CssStage(CssStageType.selector, _normalizeSelector(m.group(1)!)),
      );
      stages.add(CssStage(CssStageType.position, '!${m.group(2)!}'));
    } else if (_suffixIndex.hasMatch(p) &&
        !RegExp(r'^[A-Za-z_][\w:-]*$').hasMatch(p)) {
      // 形如 `class.item.0` / `.item.1` 的“选择器 + 索引”合并写法
      final m = _suffixIndex.firstMatch(p)!;
      stages.add(
        CssStage(CssStageType.selector, _normalizeSelector(m.group(1)!)),
      );
      stages.add(CssStage(CssStageType.position, m.group(2)!));
    } else if (_isBareTag(p)) {
      // 裸标签名（`h3@text` / `span@text`）是选择器，不是属性名。
      // 真实书源里这种写法极常见（如得奇 `ruleExplore.name = "h3@text"`），
      // 若不识别会把 h3 当成属性名，导致整条规则取不到值、发现页空白。
      stages.add(CssStage(CssStageType.selector, _normalizeSelector(p)));
    } else if (_isExtractor(p)) {
      stages.add(CssStage(CssStageType.extractor, p));
    } else {
      stages.add(CssStage(CssStageType.selector, _normalizeSelector(p)));
    }
  }
  return stages;
}

/// `text.xxx` / `text=xxx` / `text!xxx` → 文本选择器。
bool _isTextSelector(String p) {
  final lower = p.toLowerCase();
  return lower.startsWith('text.') ||
      lower.startsWith('text=') ||
      lower.startsWith('text!');
}

String _textSelectorValue(String p) => p.substring(5).trim();

/// `!0` 形式的排除索引。
bool _isExcludeIndex(String p) => RegExp(r'^!\d+$').hasMatch(p);

bool _isIndex(String p) =>
    RegExp(r'^-?\d+$').hasMatch(p) || RegExp(r'^\.\d+$').hasMatch(p);

final _suffixIndex = RegExp(r'^(.+)\.(\d+)$');

/// 「选择器 + 排除索引」合并写法：`p!0`、`li!-1`。
final _excludeSuffix = RegExp(r'^([A-Za-z#.\[][^!]*)!(-?\d+)$');

int _indexValue(String p) => int.parse(p.startsWith('.') ? p.substring(1) : p);

const _extractorKeywords = {'text', 'textNodes', 'ownText', 'html', 'all'};

/// 常见 HTML 标签名。用于区分「裸标签选择器」与「属性名」：
/// `h3@text` 里的 h3 是标签，`@href` 里的 href 是属性。
///
/// 刻意不收 `title` / `meta` / `link` / `html`：它们在书源里几乎总是
/// 属性名（`a@title`）或提取器关键字（`@html`），收进来会误判。
const _bareTags = {
  'a',
  'abbr',
  'article',
  'aside',
  'audio',
  'b',
  'blockquote',
  'body',
  'br',
  'button',
  'canvas',
  'caption',
  'center',
  'code',
  'dd',
  'del',
  'details',
  'dialog',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'font',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'i',
  'iframe',
  'img',
  'input',
  'ins',
  'label',
  'legend',
  'li',
  'main',
  'mark',
  'nav',
  'ol',
  'option',
  'p',
  'picture',
  'pre',
  'progress',
  'q',
  's',
  'section',
  'select',
  'small',
  'source',
  'span',
  'strike',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'textarea',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'u',
  'ul',
  'video',
};

bool _isBareTag(String p) => _bareTags.contains(p.toLowerCase());

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
    if (!selector.contains(':contains(') && !selector.contains(':has(')) {
      if (context is dom.Document) {
        return context.querySelectorAll(selector);
      }
      if (context is dom.Element) {
        return context.querySelectorAll(selector);
      }
      return const [];
    }
    return _selectWithPseudo(context, selector);
  } catch (_) {
    // 选择器语法不支持：返回空结果（与“找不到元素”同语义）
    return const [];
  }
}

/// 支持 `:contains(文本)`（jQuery 写法）与 `:has(选择器)` 的选择。
///
/// `package:html` 的选择器引擎不支持这两个伪类，而真实书源里很常见：
///   - `a#next:contains(下一页)`            （下一页链接）
///   - `li:has(a)` / `li.res-book-item[data-bid]`
/// 这里拆成「前置选择器 + 伪类过滤 + 相对选择器尾缀」三步手工求值，
/// 只覆盖书源实际用到的形态（后代 / `>` / `~` / `+` 后续选择器）。
List<dom.Element> _selectWithPseudo(dom.Node context, String selector) {
  var work = selector.trim();
  // 逐个剥掉前置的 `:has(...)` —— 它们只做「后代存在性」过滤
  final hasFilters = <String>[];
  while (true) {
    final i = work.indexOf(':has(');
    if (i < 0) break;
    final close = _matchParen(work, i + 4);
    if (close < 0) break;
    hasFilters.add(work.substring(i + 5, close).trim());
    work = (work.substring(0, i) + work.substring(close + 1)).trim();
  }

  var containsText = '';
  final ci = work.indexOf(':contains(');
  if (ci >= 0) {
    final close = _matchParen(work, ci + 9);
    if (close > 0) {
      containsText = work.substring(ci + 10, close).trim();
      work = (work.substring(0, ci) + work.substring(close + 1)).trim();
    }
  }

  // work 现在是「基础选择器 + 可能的相对尾缀」（如 `dt ~ dd a`）
  final baseSel = _baseSelectorOf(work);
  final suffix = work.substring(baseSel.length).trim();

  var current = selectElements(context, baseSel.isEmpty ? '*' : baseSel);
  if (containsText.isNotEmpty) {
    current = current.where((el) => _textMatches(el, containsText)).toList();
  }
  for (final f in hasFilters) {
    current = current.where((el) => el.querySelectorAll(f).isNotEmpty).toList();
  }
  if (suffix.isEmpty || current.isEmpty) return current;
  return _applyRelative(current, suffix);
}

/// 找到与 [openIndex] 处 `(` 配对的 `)` 下标（无配对返回 -1）。
int _matchParen(String s, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < s.length; i++) {
    final c = s[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 取选择器里第一段「简单选择器」（到第一个组合符 ` ` `>` `~` `+` 为止）。
String _baseSelectorOf(String selector) {
  final m = RegExp(r'^[^ \t>~+]+').firstMatch(selector.trim());
  return m?.group(0) ?? '';
}

/// 文本命中：优先「自身文本完全相等」，其次「包含」。
bool _textMatches(dom.Element el, String keyword) {
  final own = el.nodes.whereType<dom.Text>().map((n) => n.text).join().trim();
  final all = el.text.trim();
  return own == keyword || all == keyword || all.contains(keyword);
}

/// 在 [elements] 上应用相对选择器尾缀（`~ dd a` / `> a` / `+ a` / ` a`）。
List<dom.Element> _applyRelative(List<dom.Element> elements, String suffix) {
  final s = suffix.trim();
  if (s.isEmpty) return elements;
  final combinator = s[0];
  final rest = (combinator == '>' || combinator == '~' || combinator == '+')
      ? s.substring(1).trim()
      : s;
  if (rest.isEmpty) return elements;
  final firstSel = _baseSelectorOf(rest);
  final tail = rest.substring(firstSel.length).trim();
  final out = <dom.Element>[];

  for (final el in elements) {
    Iterable<dom.Element> candidates;
    switch (combinator) {
      case '>':
        candidates = el.children.where((c) => _matchesSimple(c, firstSel));
      case '~':
        final siblings = el.parent?.children ?? const <dom.Element>[];
        final idx = siblings.indexOf(el);
        candidates = idx < 0
            ? const <dom.Element>[]
            : siblings.skip(idx + 1).where((c) => _matchesSimple(c, firstSel));
      case '+':
        final siblings = el.parent?.children ?? const <dom.Element>[];
        final idx = siblings.indexOf(el);
        candidates = (idx >= 0 && idx + 1 < siblings.length)
            ? <dom.Element>[siblings[idx + 1]]
            : const <dom.Element>[];
      default:
        candidates = el.querySelectorAll(firstSel);
    }
    if (tail.isEmpty) {
      out.addAll(candidates);
    } else {
      for (final c in candidates) {
        out.addAll(_applyRelative([c], tail));
      }
    }
  }
  return out;
}

/// 判断元素是否匹配「简单选择器」（tag / .class / #id / [attr] / 组合）。
bool _matchesSimple(dom.Element el, String selector) {
  final s = selector.trim();
  if (s.isEmpty || s == '*') return true;
  var rest = s;
  // 属性选择器
  final attrRe = RegExp(r'\[([\w:-]+)(?:([~|^$*]?=)"?([^\]"]*)"?)?\]');
  for (final m in attrRe.allMatches(s).toList()) {
    final name = m.group(1)!;
    final op = m.group(2);
    final want = m.group(3) ?? '';
    final have = el.attributes[name];
    if (have == null) return false;
    if (op == '=' && have != want) return false;
    rest = rest.replaceFirst(m.group(0)!, '');
  }
  // #id
  final idM = RegExp(r'#([\w:-]+)').firstMatch(rest);
  if (idM != null) {
    if (el.id != idM.group(1)) return false;
    rest = rest.replaceFirst(idM.group(0)!, '');
  }
  // .class
  final classM = RegExp(r'\.([\w:-]+)').firstMatch(rest);
  if (classM != null) {
    final classes = el.classes;
    for (final m in RegExp(r'\.([\w:-]+)').allMatches(rest)) {
      if (!classes.contains(m.group(1))) return false;
    }
    rest = rest.replaceAll(RegExp(r'\.[\w:-]+'), '');
  }
  // 标签名
  rest = rest.trim();
  if (rest.isNotEmpty && rest != '*') {
    if (el.localName?.toLowerCase() != rest.toLowerCase()) return false;
  }
  return true;
}

/// 按规则 [stages] 在 [context] 里查元素。

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
      case CssStageType.textSearch:
        final next = <dom.Node>[];
        for (final node in current) {
          next.addAll(findByText(node, stage.value));
        }
        current = next;
      case CssStageType.position:
        current = _applyPosition(current, stage.value);
      case CssStageType.extractor:
        return _extract(current, stage.value);
    }
    if (current.isEmpty) return const <Object>[];
  }
  return List<Object>.from(current);
}

/// 应用位置阶段：`0` / `.0` / `-1`（倒数第一）/ `!0`（排除第 0 个）。
List<dom.Node> _applyPosition(List<dom.Node> current, String value) {
  if (value.startsWith('!')) {
    final rawIdx = int.tryParse(value.substring(1));
    if (rawIdx == null) return const <dom.Node>[];
    final i = rawIdx < 0 ? current.length + rawIdx : rawIdx;
    if (i < 0 || i >= current.length) return current;
    return [...current]..removeAt(i);
  }
  final raw = int.tryParse(value);
  if (raw == null) return const <dom.Node>[];
  final idx = raw < 0 ? current.length + raw : raw;
  return (idx >= 0 && idx < current.length)
      ? <dom.Node>[current[idx]]
      : const <dom.Node>[];
}

/// 按文本内容查找元素（`text.下一页`）。
///
/// 优先「自身文本完全相等」的元素；没有完全相等的再退回「包含」。
/// 这是 Legado 书源里定位「下一页 / 下一章 / 上一章」链接的标准写法。
List<dom.Element> findByText(dom.Node context, String keyword) {
  final kw = keyword.trim();
  if (kw.isEmpty) return const [];
  final all = selectElements(context, '*');
  final exact = <dom.Element>[];
  final loose = <dom.Element>[];
  for (final el in all) {
    final own = el.nodes.whereType<dom.Text>().map((n) => n.text).join().trim();
    final full = el.text.trim();
    if (own == kw || full == kw) {
      exact.add(el);
    } else if (full.contains(kw) && full.length <= kw.length + 40) {
      loose.add(el);
    }
  }
  if (exact.isNotEmpty) return exact;
  return loose;
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
