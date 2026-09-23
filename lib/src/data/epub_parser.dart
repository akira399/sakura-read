import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// EPUB 元数据。
class EpubMeta {
  EpubMeta({this.title = '', this.author = '', this.intro = ''});

  String title;
  String author;
  String intro;
}

/// EPUB 章节（已完成 HTML → 纯文本提取）。
class EpubChapter {
  EpubChapter({required this.href, required this.title, required this.text});

  final String href;
  final String title;
  final String text;

  int get charCount => text.length;
}

class EpubParseResult {
  EpubParseResult({
    required this.meta,
    required this.chapters,
    this.coverBytes,
    this.coverExtension = 'png',
  });

  final EpubMeta meta;
  final List<EpubChapter> chapters;
  final Uint8List? coverBytes;
  final String coverExtension;
}

class EpubException implements Exception {
  EpubException(this.message);

  final String message;

  @override
  String toString() => 'EPUB 解析失败：$message';
}

/// EPUB 解析器：container.xml → OPF（元数据 / manifest / spine）→ 目录（nav / ncx）→ 章节纯文本。
class EpubParser {
  EpubParser._();

  static const Set<String> _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'section',
    'article',
    'header',
    'footer',
    'td',
    'th',
    'tr',
    'table',
    'figure',
    'figcaption',
    'hr',
    'center',
    'main',
    'aside',
    'nav',
    'dt',
    'dd',
    'body',
  };

  /// 解析 EPUB 全量内容（导入时调用一次）。
  static EpubParseResult parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (_) {
      throw EpubException('不是有效的压缩包');
    }

    // 1. container.xml → OPF 路径
    final container = _readString(archive, 'META-INF/container.xml');
    if (container == null) throw EpubException('缺少 META-INF/container.xml');
    final opfPath = _rootFilePath(container);
    if (opfPath == null) throw EpubException('container.xml 中找不到 rootfile');
    final opfStr = _readString(archive, opfPath);
    if (opfStr == null) throw EpubException('找不到 OPF 文件：$opfPath');
    final opfDir = _dirName(opfPath);

    // 2. OPF：元数据 / manifest / spine
    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(opfStr);
    } catch (_) {
      throw EpubException('OPF 文件格式错误');
    }
    final meta = _parseMetadata(opf);

    final manifest = <String, _ManifestItem>{};
    for (final e in opf.descendants.whereType<XmlElement>()) {
      if (e.name.local != 'item') continue;
      final id = e.getAttribute('id');
      final href = e.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        id: id,
        href: _resolvePath(opfDir, href),
        mediaType: e.getAttribute('media-type') ?? '',
        properties: e.getAttribute('properties') ?? '',
      );
    }

    XmlElement? spineEl;
    for (final e in opf.descendants.whereType<XmlElement>()) {
      if (e.name.local == 'spine') {
        spineEl = e;
        break;
      }
    }
    final tocId = spineEl?.getAttribute('toc');
    final spineRefs = <String>[];
    if (spineEl != null) {
      for (final e in spineEl.descendants.whereType<XmlElement>()) {
        if (e.name.local != 'itemref') continue;
        final idref = e.getAttribute('idref');
        if (idref != null && manifest.containsKey(idref)) {
          spineRefs.add(manifest[idref]!.href);
        }
      }
    }

    // 3. 目录标题：优先 EPUB3 nav，其次 EPUB2 NCX，再次任意 ncx
    final tocTitles = <String, String>{};
    _ManifestItem? navItem;
    for (final item in manifest.values) {
      if (_props(item).contains('nav')) {
        navItem = item;
        break;
      }
    }
    if (navItem != null) {
      final navStr = _readString(archive, navItem.href);
      if (navStr != null) {
        _collectNavTitles(navStr, _dirName(navItem.href), tocTitles);
      }
    }
    if (tocTitles.isEmpty && tocId != null && manifest.containsKey(tocId)) {
      final ncx = manifest[tocId]!;
      final ncxStr = _readString(archive, ncx.href);
      if (ncxStr != null) {
        _collectNcxTitles(ncxStr, _dirName(ncx.href), tocTitles);
      }
    }
    if (tocTitles.isEmpty) {
      for (final item in manifest.values) {
        final lower = item.href.toLowerCase();
        if (item.mediaType.contains('dtbncx') || lower.endsWith('.ncx')) {
          final s = _readString(archive, item.href);
          if (s != null) {
            _collectNcxTitles(s, _dirName(item.href), tocTitles);
            if (tocTitles.isNotEmpty) break;
          }
        }
      }
    }

    // 4. 封面
    Uint8List? coverBytes;
    var coverExt = 'png';
    String? coverId;
    for (final e in opf.descendants.whereType<XmlElement>()) {
      if (e.name.local == 'meta' && e.getAttribute('name') == 'cover') {
        coverId = e.getAttribute('content');
      }
    }
    _ManifestItem? coverItem = coverId != null ? manifest[coverId] : null;
    if (coverItem == null) {
      for (final item in manifest.values) {
        if (_props(item).contains('cover-image')) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem == null) {
      for (final item in manifest.values) {
        final lower = item.href.toLowerCase();
        if (item.mediaType.startsWith('image/') &&
            (lower.contains('cover') || lower.contains('front'))) {
          coverItem = item;
          break;
        }
      }
    }
    if (coverItem != null) {
      final entry = _findEntry(archive, coverItem.href);
      if (entry != null && entry.isFile) {
        coverBytes = _entryBytes(entry);
        coverExt = _extension(coverItem.href);
      }
    }

    // 5. 章节正文
    final chapters = <EpubChapter>[];
    var index = 0;
    for (final href in spineRefs) {
      final entry = _findEntry(archive, href);
      if (entry == null || !entry.isFile) continue;
      final lower = href.toLowerCase();
      final isHtml =
          lower.endsWith('.xhtml') ||
          lower.endsWith('.html') ||
          lower.endsWith('.htm') ||
          lower.endsWith('.xml');
      if (!isHtml) continue;
      final htmlStr = _entryString(entry);
      if (htmlStr == null || htmlStr.trim().isEmpty) continue;
      final text = extractText(htmlStr);
      if (text.trim().isEmpty) continue;
      index++;
      final title = tocTitles[href] ?? _fallbackTitle(htmlStr) ?? '第 $index 章';
      chapters.add(EpubChapter(href: href, title: title, text: text));
    }
    if (chapters.isEmpty) throw EpubException('没有找到可阅读的章节');

    // 补全未匹配的目录标题（导航 href 带锚点时用前缀匹配）
    final fixed = <EpubChapter>[];
    for (final ch in chapters) {
      var title = ch.title;
      if (title.startsWith('第 ') && title.endsWith(' 章')) {
        for (final entry in tocTitles.entries) {
          if (entry.key == ch.href) {
            title = entry.value;
            break;
          }
        }
      }
      fixed.add(EpubChapter(href: ch.href, title: title, text: ch.text));
    }

    return EpubParseResult(
      meta: meta,
      chapters: fixed,
      coverBytes: coverBytes,
      coverExtension: coverExt,
    );
  }

  // ---------- 正文提取 ----------

  /// 从 EPUB 源文件按条目路径提取单章文本（缓存丢失时的回退路径）。
  static String? extractChapterTextFromFile(String epubPath, String href) {
    try {
      final bytes = File(epubPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final entry = _findEntry(archive, href);
      if (entry == null) return null;
      final htmlStr = _entryString(entry);
      if (htmlStr == null) return null;
      return extractText(htmlStr);
    } catch (_) {
      return null;
    }
  }

  /// HTML → 纯文本（段落用 \n 分隔，保留基本分段结构）。
  static String extractText(String htmlSource) {
    dom.Document doc;
    try {
      doc = html_parser.parse(htmlSource);
    } catch (_) {
      return '';
    }
    final out = <String>[];
    final buf = StringBuffer();

    void flush() {
      final s = buf
          .toString()
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n')
          .trim();
      buf.clear();
      if (s.isNotEmpty) out.add(s);
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        buf.write(node.text);
        return;
      }
      if (node is dom.Element) {
        final name = node.localName?.toLowerCase() ?? '';
        if (name == 'script' || name == 'style' || name == 'head') return;
        if (name == 'br') {
          buf.write('\n');
          return;
        }
        if (name == 'img') {
          buf.write('［插图］');
          return;
        }
        final isBlock = _blockTags.contains(name);
        if (isBlock) flush();
        for (final child in node.nodes) {
          walk(child);
        }
        if (isBlock) flush();
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    walk(doc);
    flush();
    return out.join('\n');
  }

  // ---------- OPF / 目录解析 ----------

  static EpubMeta _parseMetadata(XmlDocument opf) {
    final meta = EpubMeta();
    for (final e in opf.descendants.whereType<XmlElement>()) {
      final local = e.name.local;
      if (local == 'title' && meta.title.isEmpty) {
        meta.title = e.innerText.trim();
      } else if (local == 'creator' && meta.author.isEmpty) {
        meta.author = e.innerText.trim();
      } else if (local == 'description' && meta.intro.isEmpty) {
        meta.intro = e.innerText.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
      }
    }
    return meta;
  }

  static void _collectNavTitles(
    String navStr,
    String navDir,
    Map<String, String> out,
  ) {
    final doc = html_parser.parse(navStr);
    final anchors = <dom.Element>[];
    for (final nav in doc.querySelectorAll('nav')) {
      final type =
          nav.attributes['epub:type'] ??
          nav.attributes['type'] ??
          nav.attributes['role'] ??
          '';
      if (type.contains('toc')) anchors.addAll(nav.querySelectorAll('a'));
    }
    if (anchors.isEmpty) anchors.addAll(doc.querySelectorAll('a'));
    for (final a in anchors) {
      final href = a.attributes['href'];
      final title = a.text.trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      out.putIfAbsent(_resolvePath(navDir, href), () => title);
    }
  }

  static void _collectNcxTitles(
    String ncxStr,
    String ncxDir,
    Map<String, String> out,
  ) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(ncxStr);
    } catch (_) {
      return;
    }
    for (final np in doc.descendants.whereType<XmlElement>()) {
      if (np.name.local != 'navPoint') continue;
      String? title;
      String? src;
      for (final d in np.descendants.whereType<XmlElement>()) {
        if (title == null && d.name.local == 'text') title = d.innerText.trim();
        if (src == null && d.name.local == 'content') {
          src = d.getAttribute('src');
        }
      }
      if (title != null && title.isNotEmpty && src != null && src.isNotEmpty) {
        final t = title;
        out.putIfAbsent(_resolvePath(ncxDir, src), () => t);
      }
    }
  }

  static String? _fallbackTitle(String htmlStr) {
    final doc = html_parser.parse(htmlStr);
    for (final tag in ['h1', 'h2', 'h3', 'title']) {
      final el = doc.querySelector(tag);
      final text = el?.text.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  // ---------- zip / 路径工具 ----------

  static String? _rootFilePath(String containerXml) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(containerXml);
    } catch (_) {
      return null;
    }
    for (final e in doc.descendants.whereType<XmlElement>()) {
      if (e.name.local == 'rootfile') {
        final path = e.getAttribute('full-path');
        if (path != null && path.isNotEmpty) return path;
      }
    }
    return null;
  }

  static List<String> _props(_ManifestItem item) =>
      item.properties.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

  static ArchiveFile? _findEntry(Archive archive, String path) {
    final target = path.startsWith('./') ? path.substring(2) : path;
    for (final f in archive.files) {
      if (f.name == target) return f;
    }
    final lower = target.toLowerCase();
    for (final f in archive.files) {
      if (f.name.toLowerCase() == lower) return f;
    }
    final decoded = Uri.decodeComponent(target);
    if (decoded != target) {
      for (final f in archive.files) {
        if (f.name == decoded) return f;
      }
    }
    return null;
  }

  static Uint8List _entryBytes(ArchiveFile entry) {
    final dynamic raw = entry.content;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return Uint8List(0);
  }

  static String? _readString(Archive archive, String path) {
    final entry = _findEntry(archive, path);
    if (entry == null || !entry.isFile) return null;
    return _entryString(entry);
  }

  static String? _entryString(ArchiveFile entry) {
    final bytes = _entryBytes(entry);
    if (bytes.isEmpty) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static String _dirName(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _extension(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'png' : name.substring(dot + 1).toLowerCase();
  }

  /// 解析相对路径并做 ../ 归一化。
  static String _resolvePath(String baseDir, String href) {
    var h = Uri.decodeComponent(href);
    final fragment = h.indexOf('#');
    if (fragment != -1) h = h.substring(0, fragment);
    if (h.startsWith('/')) return h.substring(1);
    final combined = baseDir.isEmpty ? h : '$baseDir/$h';
    final parts = <String>[];
    for (final seg in combined.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join('/');
  }
}

class _ManifestItem {
  _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
}
