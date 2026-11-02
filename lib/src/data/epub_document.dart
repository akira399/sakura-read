import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html;

/// Read-only publication resources. No archive entry is written to an arbitrary path.
Map<String, Uint8List> unpackEpubDocument(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: false);
  final resources = <String, Uint8List>{};
  var total = 0;
  for (final file in archive.files.where((f) => f.isFile)) {
    if (file.size > 40 * 1024 * 1024) {
      throw const FormatException('EPUB 单项资源过大');
    }
    total += file.size;
    if (total > 250 * 1024 * 1024) {
      throw const FormatException('EPUB 解压资源超过 250 MB');
    }
    final path = file.name.replaceAll('\\', '/');
    if (path.startsWith('/') || path.split('/').contains('..')) continue;
    resources[path] = Uint8List.fromList(file.content as List<int>);
  }
  return resources;
}

String prepareEpubHtml(
  String source, {
  required double fontSize,
  required String background,
  required String foreground,
}) {
  final doc = html.parse(source);
  for (final node in doc.querySelectorAll(
    'script, iframe, object, embed, base, form',
  )) {
    node.remove();
  }
  for (final node in doc.querySelectorAll('*')) {
    node.attributes.removeWhere(
      (key, _) => key.toString().toLowerCase().startsWith('on'),
    );
  }
  for (final svg in doc.querySelectorAll('svg')) {
    if (!svg.attributes.containsKey('viewBox')) {
      final width = double.tryParse(svg.attributes['width'] ?? '');
      final height = double.tryParse(svg.attributes['height'] ?? '');
      if (width != null && height != null && width > 0 && height > 0) {
        svg.attributes['viewBox'] = '0 0 $width $height';
      }
    }
  }
  doc.head?.append(
    html.parseFragment(
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>html{background:$background;color:$foreground}body{font-size:${fontSize}px;line-height:1.8;margin:20px;overflow-wrap:anywhere}img,svg{max-width:100%;height:auto}a{color:inherit;text-decoration:underline}pre{white-space:pre-wrap}</style>',
    ),
  );
  return doc.outerHtml;
}

String? epubNote(String source, String fragment) {
  final doc = html.parse(source);
  final target = doc.getElementById(fragment);
  if (target == null) return null;
  var node = target;
  if (node.text.trim().length < 8 && node.parent != null) node = node.parent!;
  final text = node.text.trim();
  return text.isEmpty ? null : text;
}

String epubResourceText(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);
