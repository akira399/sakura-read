// 黑底合成检查：把透明 PNG 叠到纯黑背景上，检查人物轮廓外围
// 是否出现异常「亮环 / 灰边」——彩蛋界面是纯黑底，白背景残留会非常显眼。
//
// 运行：dart run tool/check_on_black.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  for (final path in [
    'assets/images/pet_rage.png',
    'assets/images/pet_chibi.png',
  ]) {
    final f = File(path);
    if (!f.existsSync()) {
      print('MISS $path');
      continue;
    }
    final im = img.decodeImage(f.readAsBytesSync());
    if (im == null) {
      print('DECODE_FAIL $path');
      continue;
    }
    _inspect(path, im);
  }
  print('BLACK_CHECK_DONE');
}

void _inspect(String path, img.Image im) {
  final w = im.width, h = im.height;

  // 黑底合成后，逐像素亮度（黑底上，透明区域 = 0）
  double lumAt(int x, int y) {
    final p = im.getPixel(x, y);
    final a = p.a / 255.0;
    // 预乘：叠到黑底上 => 颜色 * alpha
    final r = p.r * a, g = p.g * a, b = p.b * a;
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  // 人物主体的平均亮度（不透明区域）
  var sum = 0.0, n = 0;
  for (final p in im) {
    if (p.a > 200) {
      sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      n++;
    }
  }
  final bodyLum = n == 0 ? 0.0 : sum / n;

  // 关键：找「人物外缘的半透明像素」——它们在黑底上会形成一圈光晕。
  // 判定方式：alpha 在 (30..230) 之间、且紧邻完全透明像素。
  var haloCount = 0;
  var maxHalo = 0.0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = im.getPixel(x, y);
      final a = p.a.toInt();
      if (a <= 30 || a >= 230) continue;
      var nearEmpty = false;
      for (var k = 0; k < 8 && !nearEmpty; k++) {
        final dx = [1, -1, 0, 0, 1, 1, -1, -1][k];
        final dy = [0, 0, 1, -1, 1, -1, 1, -1][k];
        if (im.getPixel(x + dx, y + dy).a <= 8) nearEmpty = true;
      }
      if (!nearEmpty) continue;
      haloCount++;
      final l = lumAt(x, y);
      maxHalo = math.max(maxHalo, l);
    }
  }

  // 半透明边缘的平均亮度：如果接近主体亮度，说明过渡自然；
  // 如果明显更亮（比如接近 200+），说明残留了白色背景。
  var edgeSum = 0.0;
  var edgeN = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final a = p.a.toInt();
      if (a > 30 && a < 230) {
        edgeSum += lumAt(x, y);
        edgeN++;
      }
    }
  }
  final edgeLum = edgeN == 0 ? 0.0 : edgeSum / edgeN;
  final diff = edgeLum - bodyLum;

  final ok = haloCount == 0 || diff < 40;
  print(
    '$path ${w}x$h\n'
    '   主体亮度=${bodyLum.toStringAsFixed(1)}  '
    '边缘亮度=${edgeLum.toStringAsFixed(1)}  差=${diff.toStringAsFixed(1)}\n'
    '   外缘半透明像素=$haloCount  最亮光晕=${maxHalo.toStringAsFixed(0)}\n'
    '   → ${ok ? '✅ 黑底上不会出现明显亮环' : '❌ 黑底上可能出现白色光晕（需重新抠图）'}',
  );
}
