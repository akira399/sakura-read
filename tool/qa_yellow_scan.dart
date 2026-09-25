// 一次性质检工具：扫描图片里是否残留「调试样式」的鲜艳黄色像素
// （Flutter _errorTextStyle 的下划线色 = 0xFFFFFF00，纯黄）。
//
// 用法：dart run tool/qa_yellow_scan.dart <图片1> [图片2 ...]
// 输出：每张图的显著黄色像素数 + 占比；数量多说明可能有"双黄线"残留。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.isEmpty) {
    print('usage: dart run tool/qa_yellow_scan.dart <png>...');
    return;
  }
  for (final path in args) {
    final f = File(path);
    if (!f.existsSync()) {
      print('MISSING $path');
      continue;
    }
    final im = img.decodeImage(f.readAsBytesSync());
    if (im == null) {
      print('DECODE_FAIL $path');
      continue;
    }
    // 纯黄判定：R、G 都很高且 B 很低（抗锯齿边缘会稍偏，放宽阈值）
    var count = 0;
    var minX = im.width, maxX = 0, minY = im.height, maxY = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        if (r > 200 && g > 200 && b < 90) {
          count++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    final total = im.width * im.height;
    final pct = (count * 10000 / total) / 100;
    final box = count > 0 ? ' bbox=($minX,$minY)-($maxX,$maxY)' : '';
    print(
      'SCAN $path  ${im.width}x${im.height}  '
      'yellow=$count (${pct.toStringAsFixed(4)}%)$box',
    );
  }
}
