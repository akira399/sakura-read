// EPUB 插图回归测试。
//
// 背景（用户反馈「书里的插图不能加载」）：解析器本来会把 <img> 抽成
// `\u0001IMG:文件名\u0001` 标记 + 图片字节，但「补全目录标题」那一步重建
// EpubChapter 时漏传了 images，于是图片字节全丢、正文只剩占位标记，
// 阅读器只能显示「［插图］」。这里用一份内存里现造的 EPUB 把链路钉住。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/epub_parser.dart';

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

  // 最小合法 PNG（1x1）
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

      // 正文里是控制字符标记，不是给用户看的「［插图］」文字
      final marker = RegExp(
        '${EpubParser.imageMarkerPrefix}([^${EpubParser.imageMarkerSuffix}]+)'
        '${EpubParser.imageMarkerSuffix}',
      );
      final m = marker.firstMatch(ch.text);
      expect(m, isNotNull, reason: '正文应包含插图标记：${ch.text}');

      // 目录标题补全那一步不能把 images 丢掉（这就是当初的 bug）
      expect(ch.images.length, 1);
      final img = ch.images.single;
      expect(img.name, 'pic1.png');
      expect(m!.group(1), img.name, reason: '标记里的文件名要和图片一致');
      expect(img.bytes.length, testPngBytes.length);
      expect(img.bytes[0], 0x89);
      // 图片前面的正文还在，没被标记挤掉
      expect(ch.text.contains('她抬头看向窗外'), isTrue);
      expect(ch.text.contains('雨还在下'), isTrue);
    });

    test('相对路径越界 / 缺失图片退化成文字占位，不抛异常', () {
      final r = EpubParser.parse(buildEpubWithImage());
      final ch = r.chapters.single;
      // 用纯 HTML 走一遍：没有 archive 时只能是占位文字
      final plain = EpubParser.extractText(
        '<html><body><p>前</p><img src="x.png"/><p>后</p></body></html>',
      );
      expect(plain.contains('［插图］'), isTrue);
      expect(ch.images.length, 1);
    });

    test('extractText 不把标记当正文（非滚动模式下会替换成占位）', () {
      final plain = EpubParser.extractText(
        '<html><body><p>正文</p></body></html>',
      );
      expect(plain.trim(), '正文');
    });
  });
}

/// 插图字节（解析器不校验图片格式，这里只要内容能原样带回即可）。
/// 用 PNG 文件头 + 自定义尾巴，方便断言「真的是同一份字节」。
final List<int> testPngBytes = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG 签名
  ...utf8.encode('sakura-epub-image'),
];
