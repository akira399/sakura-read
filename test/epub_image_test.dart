// EPUB 插图与图文混排回归测试。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size, TextAlign;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/epub_document.dart';
import 'package:sakura_read/src/data/epub_parser.dart';
import 'package:sakura_read/src/data/image_header.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/paginator.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';
import 'package:sakura_read/src/platform/tts_service.dart';

/// 构造一份带一张插图的 EPUB3（图片放在 OEBPS/images/ 下）。
Uint8List buildEpubWithImage() {
  const container =
      '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

  const opf =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bookid">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>插图书</dc:title><dc:creator>小樱</dc:creator>'
      '<dc:language>zh-CN</dc:language></metadata>'
      '<manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
      'properties="nav"/>'
      '<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="images/pic1.png" media-type="image/png"/>'
      '</manifest>'
      '<spine page-progression-direction="ltr">'
      '<itemref idref="c1"/></spine></package>';

  const nav =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
      '<title>目录</title></head><body>'
      '<nav epub:type="toc"><ol>'
      '<li><a href="text/c1.xhtml">第一章 有插图的章节</a></li>'
      '</ol></nav></body></html>';

  const chapter =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c1</title>'
      '</head><body><h1>第一章 有插图的章节</h1>'
      '<p>她抬头看向窗外。</p>'
      '<img src="../images/pic1.png" alt="插图"/>'
      '<p>雨还在下。</p></body></html>';

  final png = Uint8List.fromList(testPngBytes);

  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('META-INF/container.xml', container);
  add('OEBPS/content.opf', opf);
  add('OEBPS/nav.xhtml', nav);
  add('OEBPS/text/c1.xhtml', chapter);
  archive.addFile(ArchiveFile('OEBPS/images/pic1.png', png.length, png));

  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

void main() {
  group('EPUB 插图', () {
    test('图片被抽出：正文保留占位标记，bytes 随章节返回', () {
      final r = EpubParser.parse(buildEpubWithImage());
      expect(r.chapters.length, 1);
      final ch = r.chapters.single;
      expect(ch.title, '第一章 有插图的章节');

      final marker = RegExp(
        '${EpubParser.imageMarkerPrefix}([^${EpubParser.imageMarkerSuffix}]+)'
        '${EpubParser.imageMarkerSuffix}',
      );
      final m = marker.firstMatch(ch.text);
      expect(m, isNotNull, reason: '正文应包含插图标记：${ch.text}');

      expect(ch.images.length, 1);
      final img = ch.images.single;
      expect(img.name, 'pic1.png');
      expect(m!.group(1), img.name, reason: '标记里的文件名要和图片一致');
      expect(img.bytes.length, testPngBytes.length);
      expect(img.bytes[0], 0x89);
      expect(ch.text.contains('她抬头看向窗外'), isTrue);
      expect(ch.text.contains('雨还在下'), isTrue);
    });

    test('支持 SVG <image xlink:href> 与内联 data:image/png;base64', () {
      const container =
          '<?xml version="1.0"?>'
          '<container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles></container>';
      const opf =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
          'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:title>SVG图</dc:title></metadata><manifest>'
          '<item id="t" href="titlepage.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="cov" href="cover.jpeg" media-type="image/jpeg"/>'
          '</manifest><spine><itemref idref="t"/></spine></package>';
      final b64 = base64Encode(testPngBytes);
      final titleHtml =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head>'
          '<body><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">'
          '<image width="400" height="600" xlink:href="cover.jpeg"/>'
          '</svg>'
          '<p>附带内联图：<img src="data:image/png;base64,$b64"/></p>'
          '</body></html>';
      final opfBytes = utf8.encode(opf);
      final titleBytes = utf8.encode(titleHtml);
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            container.length,
            utf8.encode(container),
          ),
        )
        ..addFile(ArchiveFile('content.opf', opfBytes.length, opfBytes))
        ..addFile(ArchiveFile('titlepage.xhtml', titleBytes.length, titleBytes))
        ..addFile(
          ArchiveFile(
            'cover.jpeg',
            testJpegBytes.length,
            Uint8List.fromList(testJpegBytes),
          ),
        );
      final parsed = EpubParser.parse(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(parsed.chapters.single.images.length, 2);
      expect(parsed.chapters.single.images.first.name, 'cover.jpeg');
      expect(
        parsed.chapters.single.text,
        contains('${EpubParser.imageMarkerPrefix}cover.jpeg'),
      );
      expect(parsed.chapters.single.text.contains('［插图］'), isFalse);
    });

    test('HTML 源码换行（含角标 sup）不在中文句中强行断行', () {
      const html =
          '<html><body><p>比如，3英尺<sup>\n'
          '<a href="p.html#fn">[13]</a>\n'
          '</sup>\n以外的物体更暗淡。</p></body></html>';
      final text = EpubParser.extractText(html);
      expect(text, '比如，3英尺[13]以外的物体更暗淡。');
    });

    test('readImageSizeFromBytes 解析 PNG / JPEG / GIF 宽高', () {
      expect(
        readImageSizeFromBytes(Uint8List.fromList(testPngBytes)),
        const Size(120, 80),
      );
      expect(
        readImageSizeFromBytes(Uint8List.fromList(testJpegBytes)),
        const Size(501, 161),
      );
      final gif = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
        0x40, 0x01, // 320 LE
        0xC8, 0x00, // 200 LE
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(readImageSizeFromBytes(gif), const Size(320, 200));
    });

    test('Paginator 图文混排分页不丢失正文或截断插图标记', () {
      const prefix = EpubParser.imageMarkerPrefix;
      const suffix = EpubParser.imageMarkerSuffix;
      final chapterText =
          '第一段正文内容在这里用于测试图文混排分页效果。\n'
          '${prefix}00004.jpeg$suffix\n'
          '插图后面的第二段文字也必须完整出现在分页结果里。';
      final pages = Paginator.paginate(
        text: chapterText,
        style: const TextStyle(fontSize: 18, height: 1.6),
        size: const Size(340, 560),
        imageSizeResolver: (_) => const Size(501, 161),
      );
      expect(pages, isNotEmpty);
      expect(pages.any((p) => p.hasImages), isTrue);
      final combinedText = pages
          .expand((p) => p.blocks.whereType<PageTextBlock>().map((b) => b.text))
          .join('\n');
      expect(combinedText, contains('第一段正文内容'));
      expect(combinedText, contains('插图后面的第二段文字'));
      final images = pages
          .expand((p) => p.blocks.whereType<PageImageBlock>())
          .toList();
      expect(images.single.imageName, '00004.jpeg');
      expect(images.single.width, greaterThan(100));
      expect(images.single.height, greaterThan(40));
    });

    test('实书《平面国》全书所有插图均可提取且无降级占位', () {
      final path =
          r'c:\Users\xiy\Downloads\平面国多维空间传奇往事(多维空间“启蒙书”,阿西莫夫称它是理解维度.epub';
      final file = File(path);
      if (!file.existsSync()) return;
      final parsed = EpubParser.parse(file.readAsBytesSync());
      final totalImages = parsed.chapters.fold<int>(
        0,
        (sum, c) => sum + c.images.length,
      );
      expect(parsed.coverBytes, isNotNull);
      expect(totalImages, 13);
      for (final ch in parsed.chapters) {
        expect(
          ch.text.contains('［插图］'),
          isFalse,
          reason: '${ch.href} 仍存在降级占位符',
        );
      }
    });

    test('相对路径越界 / 缺失图片退化成文字占位，不抛异常', () {
      final r = EpubParser.parse(buildEpubWithImage());
      final ch = r.chapters.single;
      final plain = EpubParser.extractText(
        '<html><body><p>前</p><img src="x.png"/><p>后</p></body></html>',
      );
      expect(plain.contains('［插图］'), isTrue);
      expect(ch.images.length, 1);
    });

    test('Paginator 分页支持真实段间距与两端对齐', () {
      const text = '第一段中文正文测试，第一段结尾。\n第二段中文正文测试，第二段结尾。\n第三段中文正文测试。';
      final spaced = Paginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 18, height: 1.6),
        size: const Size(320, 480),
        align: TextAlign.justify,
        paragraphSpacing: 16,
      );
      expect(spaced, isNotEmpty);
      final blocks = spaced.first.blocks.whereType<PageTextBlock>().toList();
      expect(blocks.length, 3);
      expect(blocks.first.bottomGap, 16);
    });

    test('prepareEpubHtml 支持强制统一阅读主题文字颜色', () {
      const html =
          '<html><head></head><body><p style="color:#ff00ff">'
          '<font color="red">花哨文字</font></p></body></html>';
      final forced = prepareEpubHtml(
        html,
        fontSize: 18,
        background: '#fffaf0',
        foreground: '#222222',
        forceThemeColors: true,
      );
      expect(forced, contains('color:#222222 !important'));
      final original = prepareEpubHtml(
        html,
        fontSize: 18,
        background: '#fffaf0',
        foreground: '#222222',
        forceThemeColors: false,
      );
      expect(original, isNot(contains('!important')));
    });

    test('ShelfSortMode.manual 按自定义顺序排列书架', () {
      final a = Book(
        id: 'a',
        title: 'A',
        format: BookFormat.txt,
        path: '/a.txt',
        chapters: const [],
        addedAt: 1,
      );
      final b = Book(
        id: 'b',
        title: 'B',
        format: BookFormat.txt,
        path: '/b.txt',
        chapters: const [],
        addedAt: 2,
      );
      final c = Book(
        id: 'c',
        title: 'C',
        format: BookFormat.txt,
        path: '/c.txt',
        chapters: const [],
        addedAt: 3,
      );
      final books = [a, b, c];
      sortBooksForShelf(
        books,
        ShelfSortMode.manual,
        ascending: true,
        manualOrder: const ['c', 'a', 'b'],
      );
      expect(books.map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('TtsService 定时停播与读完本章停止状态切换', () {
      final tts = TtsService.instance;
      expect(tts.hasSleepTimer, isFalse);
      tts.setSleepTimer(const Duration(minutes: 15));
      expect(tts.hasSleepTimer, isTrue);
      expect(tts.sleepRemaining, isNotNull);
      tts.setStopAfterChapter(true);
      expect(tts.stopAfterChapter, isTrue);
      expect(tts.sleepRemaining, isNull);
      tts.cancelSleepTimer();
      expect(tts.hasSleepTimer, isFalse);
    });
  });
}

final List<int> testPngBytes = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
  0x00, 0x00, 0x00, 0x0d, // IHDR len
  0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x78, // width = 120
  0x00, 0x00, 0x00, 0x50, // height = 80
  0x08, 0x06, 0x00, 0x00, 0x00,
  ...utf8.encode('sakura-epub-image'),
];

final List<int> testJpegBytes = <int>[
  0xFF, 0xD8, // SOI
  0xFF, 0xC0, // SOF0
  0x00, 0x0B, // len
  0x08, // precision
  0x00, 0xA1, // height = 161
  0x01, 0xF5, // width = 501
  0x03, 0x01, 0x11, 0x00,
  0xFF, 0xD9, // EOI
];
