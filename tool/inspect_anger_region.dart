// 诊断：把 pet_rage.png 右上角区域打成 ASCII 图，确认残留的"星号黑色描边"。
//
// 背景：用颜色筛选擦除 AI 画的星号时只删了橙色填充，
// 星号的**黑色描边**留了下来（用户截图里的"黑色星号"）。
//
// 运行：dart run tool/inspect_anger_region.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final f = File('assets/images/pet_rage.png');
  final im = img.decodeImage(f.readAsBytesSync());
  if (im == null) {
    print('DECODE FAIL');
    return;
  }

  // 原星号 bbox 约 (226..297, 24..97)，取大一圈看外围
  const x0 = 200, x1 = 319, y0 = 0, y1 = 120;
  var dark = 0, red = 0, other = 0;

  print('图例: . 透明  # 暗(描边)  R 红橙  o 其它');
  print('区域 x=$x0..$x1 y=$y0..$y1 （每 2x2 取样）');
  print('');

  for (var y = y0; y < y1; y += 2) {
    final row = StringBuffer();
    for (var x = x0; x < x1; x += 2) {
      final p = im.getPixel(x, y);
      final a = p.a.toInt();
      if (a <= 20) {
        row.write('.');
        continue;
      }
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (lum < 110) {
        row.write('#');
        dark++;
      } else if (r >= 150 && (r - g) > 45 && b < r * 0.7) {
        row.write('R');
        red++;
      } else {
        row.write('o');
        other++;
      }
    }
    print(row.toString());
  }

  print('');
  print('统计: 暗色描边=$dark  红橙=$red  其它=$other');
  if (dark > 100) {
    print('❌ 仍然残留大量暗色像素 —— 星号黑描边没清掉');
  } else {
    print('✅ 该区域没有明显残留');
  }
  print('INSPECT_DONE');
}