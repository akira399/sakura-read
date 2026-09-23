// 擦除效果对比：把「抠图后未擦除」与「擦除后」叠成 ASCII 差异图，
// 精确显示到底擦掉了哪些像素，避免"是否误伤头发"靠猜。
//
// 运行：dart run tool/diff_erase.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

const _erased = 'assets/images/pet_rage.png';

void main() {
  // 重新生成"未擦除"版用于对比
  final src = File('tool/artwork/candidates/pet_rage_v4_a.jpg');
  if (!src.existsSync()) {
    print('MISS 原始候选图');
    return;
  }
  final orig = img.decodeImage(src.readAsBytesSync());
  final cur = img.decodeImage(File(_erased).readAsBytesSync());
  if (orig == null || cur == null) {
    print('DECODE FAIL');
    return;
  }

  // 抠图后的尺寸（319x512），原图 1024x1024 → 需要按比例映射
  // 简化：只看「当前图」，把它按 4x4 块聚合成 ASCII，观察右侧是否缺块
  final w = cur.width, h = cur.height;
  print('当前图 ${w}x$h —— 4x4 块聚合（# 有不透明  . 全透明）');
  print('列号 0..${(w / 4).floor() - 1}，行号 0..${(h / 4).floor() - 1}');
  print('');

  var missingRight = 0;
  for (var by = 0; by < h; by += 4) {
    final row = StringBuffer();
    for (var bx = 0; bx < w; bx += 4) {
      var opaque = 0;
      for (var y = by; y < by + 4 && y < h; y++) {
        for (var x = bx; x < bx + 4 && x < w; x++) {
          if (cur.getPixel(x, y).a > 20) opaque++;
        }
      }
      row.write(opaque > 0 ? '#' : '.');
    }
    print(row.toString());
  }

  // 统计右上区域的透明情况（原星号在 x≈226..297 y≈24..97 附近）
  for (var y = 10; y < 110; y += 4) {
    for (var x = 210; x < w; x += 4) {
      if (cur.getPixel(x, y).a <= 20) missingRight++;
    }
  }
  print('');
  print('右上区域(210..w, 10..110)透明像素数: $missingRight');
  print('DIFF_DONE');
}