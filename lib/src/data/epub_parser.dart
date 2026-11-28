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
  EpubChapter({
    required this.href,
    required this.title,
    required this.text,
    this.images = const [],
  });

  final String href;
  final String title;
  final String text;

  /// 本章引用的插图（文件名 + 原始字节）。
  final List<EpubImage> images;

  int get charCount => text.length;
}

/// EPUB 里的一张插图（原始字节 + 建议文件名）。
class EpubImage {
  EpubImage({required this.name, required this.bytes});

  /// 建议文件名（已去掉目录，保留扩展名，用于本地落盘）。
  final String name;

  /// 图片原始字节。
  final Uint8List bytes;
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

/// EPUB 解析器：container.xml → OPF（元数据 / manifest / spine）→ 目录（nav / ncx）→ 章节纯文本 + 插图。
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

  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'svg',
  };

  static const Set<String> _genericHtmlTitles = {
    '未知',
    'unknown',
    'untitled',
    'cover',
    'titlepage',
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
        final lower = coverItem.href.toLowerCase();
        if (_isHtmlHref(lower) && !coverItem.mediaType.startsWith('image/')) {
          final htmlStr = _entryString(entry);
          if (htmlStr != null) {
            final coverExtracted = _extractTextWithImages(
              htmlStr,
              chapterDir: _dirName(coverItem.href),
              opfDir: opfDir,
              archive: archive,
            );
            if (coverExtracted.images.isNotEmpty) {
              coverBytes = coverExtracted.images.first.bytes;
              coverExt = _extension(coverExtracted.images.first.name);
            }
          }
        } else {
          coverBytes = _entryBytes(entry);
          coverExt = _extension(coverItem.href);
        }
      }
    }

    // 5. 章节正文（含插图提取）
    final chapters = <EpubChapter>[];
    var index = 0;
    for (final href in spineRefs) {
      final entry = _findEntry(archive, href);
      if (entry == null || !entry.isFile) continue;
      if (!_isHtmlHref(href.toLowerCase())) continue;
      final htmlStr = _entryString(entry);
      if (htmlStr == null || htmlStr.trim().isEmpty) continue;
      final chapterDir = _dirName(href);
      final extracted = _extractTextWithImages(
        htmlStr,
        chapterDir: chapterDir,
        opfDir: opfDir,
        archive: archive,
      );
      if (extracted.text.trim().isEmpty && extracted.images.isEmpty) continue;
      index++;
      final title = tocTitles[href] ?? _fallbackTitle(htmlStr) ?? '第 $index 章';
      chapters.add(
        EpubChapter(
          href: href,
          title: title,
          text: extracted.text,
          images: extracted.images,
        ),
      );
    }
    if (chapters.isEmpty) throw EpubException('没有找到可阅读的章节');

    return EpubParseResult(
      meta: meta,
      chapters: chapters,
      coverBytes: coverBytes,
      coverExtension: coverExt,
    );
  }

  /// 从 EPUB 源文件按条目路径快速提取单章正文与插图（缓存修复 / 按章回退用，不解析全书章节）。
  static ({String text, List<EpubImage> images})? extractChapterFromFile(
    String epubPath,
    String href,
  ) {
    try {
      final bytes = File(epubPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      var opfDir = '';
      final container = _readString(archive, 'META-INF/container.xml');
      if (container != null) {
        final opfPath = _rootFilePath(container);
        if (opfPath != null) opfDir = _dirName(opfPath);
      }
      var entry = _findEntry(archive, href);
      if (entry == null && opfDir.isNotEmpty) {
        entry = _findEntry(archive, _resolvePath(opfDir, href));
      }
      if (entry == null || !entry.isFile) return null;
      final htmlStr = _entryString(entry);
      if (htmlStr == null) return null;
      return _extractTextWithImages(
        htmlStr,
        chapterDir: _dirName(entry.name),
        opfDir: opfDir,
        archive: archive,
      );
    } catch (_) {
      return null;
    }
  }

  /// 从 EPUB 源文件按条目路径提取单章文本（缓存丢失时的回退路径）。
  static String? extractChapterTextFromFile(String epubPath, String href) {
    return extractChapterFromFile(epubPath, href)?.text;
  }

  /// HTML → 纯文本（段落用 \n 分隔，保留基本分段结构）。
  static String extractText(String htmlSource) {
    return _extractTextWithImages(htmlSource).text;
  }

  /// 插图占位标记前缀：`\u0001IMG:<文件名>\u0001`。
  ///
  /// 为什么用控制字符：正文里几乎不可能出现，解析/清洗时不会被当作正文
  /// 处理，也不会在朗读（TTS）时念出来；阅读器按它把图片插入排版。
  static const String imageMarkerPrefix = '\u0001IMG:';
  static const String imageMarkerSuffix = '\u0001';

  /// HTML → 纯文本，同时把 `<img>` / `<svg><image>` / 内联 data URI 抽成「图片 + 占位标记」。
  static ({String text, List<EpubImage> images}) _extractTextWithImages(
    String htmlSource, {
    String chapterDir = '',
    String opfDir = '',
    Archive? archive,
    bool skipHidden = true,
  }) {
    dom.Document doc;
    try {
      doc = html_parser.parse(htmlSource);
    } catch (_) {
      return (text: '', images: const []);
    }
    final result = _walkDocument(
      doc,
      chapterDir: chapterDir,
      opfDir: opfDir,
      archive: archive,
      skipHidden: skipHidden,
    );
    if (skipHidden && result.text.trim().isEmpty && result.images.isEmpty) {
      return _walkDocument(
        doc,
        chapterDir: chapterDir,
        opfDir: opfDir,
        archive: archive,
        skipHidden: false,
      );
    }
    return result;
  }

  static ({String text, List<EpubImage> images}) _walkDocument(
    dom.Document doc, {
    required String chapterDir,
    required String opfDir,
    required Archive? archive,
    required bool skipHidden,
  }) {
    final out = <String>[];
    final images = <EpubImage>[];
    final usedNames = <String>{};
    final buf = StringBuffer();
    var preDepth = 0;
    final trCellCounts = <int>[];

    void flush() {
      var s = buf
          .toString()
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'[ \t]*\u0002[ \t]*'), '\n')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n')
          .trim();
      buf.clear();
      if (s.isEmpty) return;
      // 消除 HTML 源码换行导致的中文句中多余空格，以及中文与角标 [13] 之间多余空格
      if (preDepth == 0) {
        final cjkGap = RegExp(
          r'([\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]) +([\u4e00-\u9fff\u3000-\u303f\uff00-\uffef\[])',
        );
        final closeBracketCjk = RegExp(
          r'([\]）]) +([\u4e00-\u9fff\u3000-\u303f\uff00-\uffef])',
        );
        for (var pass = 0; pass < 2; pass++) {
          s = s
              .replaceAllMapped(cjkGap, (m) => '${m[1]}${m[2]}')
              .replaceAllMapped(closeBracketCjk, (m) => '${m[1]}${m[2]}');
        }
      }
      if (s.isNotEmpty) out.add(s);
    }

    String uniqueName(String rawName, {int? entryIndex}) {
      var name = rawName;
      if (archive != null &&
          entryIndex != null &&
          archive.files
                  .where((f) => f.isFile && _baseName(f.name) == name)
                  .length >
              1) {
        name = '${entryIndex}_$name';
      }
      if (!usedNames.add(name)) {
        name = '${usedNames.length}_$name';
        usedNames.add(name);
      }
      return name;
    }

    ArchiveFile? resolveImageEntry(String cleanSrc) {
      if (archive == null) return null;
      // 1. 相对章节目录
      final relChapter = _resolvePath(chapterDir, cleanSrc);
      final hit1 = _findEntry(archive, relChapter);
      if (hit1 != null && hit1.isFile) return hit1;
      // 2. 相对 OPF 目录（部分制作不规范的 EPUB 会直接写 OPF 相对路径）
      if (opfDir.isNotEmpty || cleanSrc.startsWith('/')) {
        final relOpf = _resolvePath(opfDir, cleanSrc);
        final hit2 = _findEntry(archive, relOpf);
        if (hit2 != null && hit2.isFile) return hit2;
      }
      // 3. 唯一文件名匹配兜底（如路径层级写错但图片文件名唯一）
      final targetBase = _baseName(cleanSrc.replaceAll('\\', '/'))
          .toLowerCase();
      if (targetBase.isNotEmpty) {
        final matches = archive.files
            .where(
              (f) =>
                  f.isFile &&
                  _baseName(f.name).toLowerCase() == targetBase &&
                  _imageExtensions.contains(_extension(f.name)),
            )
            .toList();
        if (matches.length == 1) return matches.first;
      }
      return null;
    }

    void emitImage(dom.Element node) {
      final src = _attrValue(node, const [
        'src',
        'xlink:href',
        'href',
        'data-src',
        'data-original',
        'data-lazy-src',
      ]);
      if (src == null || src.isEmpty) {
        buf.write('［插图］');
        return;
      }

      // 支持内嵌 base64 图片（data:image/png;base64,...）
      final inline = _decodeDataImageUri(src);
      if (inline != null) {
        final name = uniqueName(
          'inline_${images.length}_${inline.bytes.length}.${inline.ext}',
        );
        images.add(EpubImage(name: name, bytes: inline.bytes));
        flush();
        out.add('$imageMarkerPrefix$name$imageMarkerSuffix');
        return;
      }

      if (archive == null) {
        buf.write('［插图］');
        return;
      }

      final cleanSrc = src
          .replaceAll('\\', '/')
          .split('#')
          .first
          .split('?')
          .first
          .trim();
      if (cleanSrc.isEmpty) {
        buf.write('［插图］');
        return;
      }

      final entry = resolveImageEntry(cleanSrc);
      if (entry == null || !entry.isFile) {
        buf.write('［插图］');
        return;
      }
      final bytes = _entryBytes(entry);
      if (bytes.isEmpty) {
        buf.write('［插图］');
        return;
      }
      final name = uniqueName(
        _baseName(entry.name),
        entryIndex: archive.files.indexOf(entry),
      );
      images.add(EpubImage(name: name, bytes: bytes));
      flush();
      out.add('$imageMarkerPrefix$name$imageMarkerSuffix');
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        if (preDepth > 0) {
          buf.write(node.text);
        } else {
          buf.write(node.text.replaceAll(RegExp(r'[\r\n\t]+'), ' '));
        }
        return;
      }
      if (node is dom.Element) {
        final name = node.localName?.toLowerCase() ?? '';
        if (name == 'script' || name == 'style' || name == 'head') return;
        if (skipHidden && _isHiddenElement(node)) return;
        if (name == 'br') {
          buf.write(preDepth > 0 ? '\n' : '\u0002');
          return;
        }
        if (name == 'img' || name == 'image') {
          emitImage(node);
          return;
        }
        final isPre = name == 'pre';
        if (isPre) preDepth++;
        if (name == 'tr') trCellCounts.add(0);
        if ((name == 'td' || name == 'th') && trCellCounts.isNotEmpty) {
          final idx = trCellCounts.last;
          trCellCounts[trCellCounts.length - 1] = idx + 1;
          if (idx > 0 && buf.isNotEmpty) {
            buf.write('  ·  ');
          }
        }
        final isBlock = _blockTags.contains(name);
        if (isBlock) flush();
        for (final child in node.nodes) {
          walk(child);
        }
        if (isBlock) flush();
        if (name == 'tr' && trCellCounts.isNotEmpty) trCellCounts.removeLast();
        if (isPre && preDepth > 0) preDepth--;
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    walk(doc);
    flush();
    return (text: out.join('\n'), images: images);
  }

  static bool _isHiddenElement(dom.Element node) {
    if (node.attributes.containsKey('hidden')) return true;
    final style = node.attributes['style']?.toLowerCase();
    if (style != null && RegExp(r'display\s*:\s*none').hasMatch(style)) {
      return true;
    }
    return false;
  }

  static String? _attrValue(dom.Element node, List<String> names) {
    for (final want in names) {
      final wantLower = want.toLowerCase();
      final exactPrefixed = wantLower.contains(':');
      for (final entry in node.attributes.entries) {
        final key = entry.key;
        final String keyFull;
        final String keyLocal;
        if (key is dom.AttributeName) {
          keyLocal = key.name.toLowerCase();
          keyFull = key.prefix != null && key.prefix!.isNotEmpty
              ? '${key.prefix!.toLowerCase()}:$keyLocal'
              : keyLocal;
        } else {
          keyFull = key.toString().toLowerCase();
          final colon = keyFull.indexOf(':');
          keyLocal = colon >= 0 ? keyFull.substring(colon + 1) : keyFull;
        }
        if (keyFull == wantLower || (!exactPrefixed && keyLocal == wantLower)) {
          final v = entry.value.trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
    return null;
  }

  static ({Uint8List bytes, String ext})? _decodeDataImageUri(String uri) {
    final m = RegExp(
      r'^data:image/([a-zA-Z0-9.+-]+)(?:;[^,]*)?;base64,(.*)$',
      dotAll: true,
    ).firstMatch(uri.trim());
    if (m == null) return null;
    try {
      final rawSub = m.group(1)!.toLowerCase();
      final ext = switch (rawSub) {
        'jpeg' || 'jpg' => 'jpg',
        'png' => 'png',
        'gif' => 'gif',
        'webp' => 'webp',
        'bmp' => 'bmp',
        _ => 'png',
      };
      final payload = m.group(2)!.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) return null;
      return (bytes: bytes, ext: ext);
    } catch (_) {
      return null;
    }
  }

  static bool _isHtmlHref(String lowerHref) =>
      lowerHref.endsWith('.xhtml') ||
      lowerHref.endsWith('.html') ||
      lowerHref.endsWith('.htm') ||
      lowerHref.endsWith('.xml');

  /// 取路径的文件名（去目录）。
  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i < 0 ? normalized : normalized.substring(i + 1);
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
    final exactKeys = <String>{};
    for (final a in anchors) {
      final href = a.attributes['href'];
      final title = a.text.trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      final resolved = _resolvePath(navDir, href);
      if (resolved.isEmpty) continue;
      if (!href.contains('#')) {
        if (exactKeys.add(resolved)) {
          out[resolved] = title;
        }
      } else {
        out.putIfAbsent(resolved, () => title);
      }
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
    final exactKeys = <String>{};
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
        final resolved = _resolvePath(ncxDir, src);
        if (resolved.isEmpty) continue;
        if (!src.contains('#')) {
          if (exactKeys.add(resolved)) {
            out[resolved] = t;
          }
        } else {
          out.putIfAbsent(resolved, () => t);
        }
      }
    }
  }

  static String? _fallbackTitle(String htmlStr) {
    final doc = html_parser.parse(htmlStr);
    for (final tag in ['h1', 'h2', 'h3']) {
      final el = doc.querySelector(tag);
      final text = el?.text.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    final titleText = doc.querySelector('title')?.text.trim();
    if (titleText != null &&
        titleText.isNotEmpty &&
        !_genericHtmlTitles.contains(titleText.toLowerCase())) {
      return titleText;
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
    var target = path.replaceAll('\\', '/');
    if (target.startsWith('./')) target = target.substring(2);
    for (final f in archive.files) {
      if (f.name == target) return f;
    }
    final lower = target.toLowerCase();
    for (final f in archive.files) {
      if (f.name.toLowerCase() == lower) return f;
    }
    final decoded = _decodePath(target);
    if (decoded != target) {
      for (final f in archive.files) {
        if (f.name == decoded) return f;
      }
      final decodedLower = decoded.toLowerCase();
      for (final f in archive.files) {
        if (f.name.toLowerCase() == decodedLower) return f;
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

  static String _decodePath(String path) {
    try {
      return Uri.decodeComponent(
        path.replaceAll(RegExp(r'%(?![0-9a-fA-F]{2})'), '%25'),
      );
    } catch (_) {
      return path;
    }
  }

  static String _dirName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final i = normalized.lastIndexOf('/');
    return i < 0 ? '' : normalized.substring(0, i);
  }

  static String _extension(String path) {
    final name = _baseName(path);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'png' : name.substring(dot + 1).toLowerCase();
  }

  /// 解析相对路径并做 ../ 归一化。
  static String _resolvePath(String baseDir, String href) {
    var h = _decodePath(href.replaceAll('\\', '/').split('#').first);
    final fragment = h.indexOf('#');
    if (fragment != -1) h = h.substring(0, fragment);
    if (h.startsWith('/')) h = h.substring(1);
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
