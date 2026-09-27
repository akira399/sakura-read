// 一次性诊断：测量书架截图里「状态栏条」与「头部渐变」的实际颜色。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

String hex(img.Pixel p) =>
    '#${p.r.toInt().toRadixString(16).padLeft(2, '0')}'
    '${p.g.toInt().toRadixString(16).padLeft(2, '0')}'
    '${p.b.toInt().toRadixString(16).padLeft(2, '0')}';

img.Pixel? px(img.Image im, int x, int y) => im.getPixel(x, y);

num delta(img.Pixel a, img.Pixel b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

void main() {
  final f = File('tool/_shot_debug/shelf.jpg');
  if (!f.existsSync()) {
    print('MISSING ${f.path}');
    return;
  }
  final im = img.decodeImage(f.readAsBytesSync());
  if (im == null) {
    print('DECODE_FAIL');
    return;
  }
  print('SIZE ${im.width}x${im.height}');

  final xs = [im.width * 2 ~/ 100, im.width ~/ 2, im.width * 98 ~/ 100];
  for (final y in [8, 20, 40, 60, 80, 100, 120, 140, 170, 200, 240, 280, 320, 360]) {
    final parts = xs.map((x) => '${x}px=${hex(px(im, x, y)!)}').join('  ');
    print('y=$y  $parts');
  }

  // 中心列扫描：找「状态栏条」下边界（颜色开始显著变化的位置）
  final cx = im.width ~/ 2;
  final topColor = px(im, cx, 10)!;
  var boundary = -1;
  for (var y = 10; y < 500; y++) {
    final p = px(im, cx, y)!;
    if (delta(p, topColor) > 45) {
      boundary = y;
      break;
    }
  }
  print('CENTER top=${hex(topColor)} first_big_change_at_y=$boundary');
  if (boundary > 0) {
    for (final y in [boundary - 6, boundary - 2, boundary + 4, boundary + 30, boundary + 80]) {
      final p = px(im, cx, y)!;
      print('  near-boundary y=$y ${hex(p)}');
    }
  }

  // 顶部两个角落对比（判断渐变方向：纵向 → 左右同色；对角 → 左右不同色）
  final l = px(im, 20, 300)!;
  final r = px(im, im.width - 20, 300)!;
  print('MID-HEADER y=300  left=${hex(l)}  right=${hex(r)}  delta=${delta(l, r)}');
}
