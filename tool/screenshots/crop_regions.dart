// 一次性工具：把截图裁剪成若干区域，便于逐块检查渲染质量。
// 用法：dart run tool/screenshots/crop_regions.dart <图片> [输出目录]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final src = args.isNotEmpty ? args[0] : 'docs/images/settings.png';
  final outDir = args.isNotEmpty && args.length > 1 ? args[1] : '/tmp/crops';
  final im = img.decodeImage(File(src).readAsBytesSync());
  if (im == null) {
    print('DECODE_FAIL $src');
    return;
  }
  Directory(outDir).createSync(recursive: true);
  final w = im.width;
  final h = im.height;
  // 切成纵向 4 段（每段等高），并额外输出左半缩略（看图标列）
  for (var i = 0; i < 4; i++) {
    final y0 = (h * i / 4).floor();
    final y1 = (h * (i + 1) / 4).ceil();
    final crop = img.copyCrop(im, x: 0, y: y0, width: w, height: y1 - y0);
    File('$outDir/part${i + 1}.png').writeAsBytesSync(img.encodePng(crop));
  }
  print('CROP_DONE -> $outDir  (${w}x$h)');
}
