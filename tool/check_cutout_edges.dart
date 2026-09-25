// 抠图边缘体检：检查透明 PNG 的边缘是否残留背景色（黑圈/白边/彩边）。
//
// 回归背景：v1.2.8 曾出现"桌宠周围一圈黑黑的"，根因是抠图边缘没处理好。
// 这里用「贴近不透明区域的边缘像素，其 RGB 是否与内部主体差异过大」来判定。
//
// 运行：dart run tool/check_cutout_edges.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final targets = [
    'assets/images/pet_rage.png',
    'assets/images/pet_chibi.png',
    'assets/images/pet_angry.png',
  ];
  for (final path in targets) {
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
  print('EDGE_CHECK_DONE');
}

void _inspect(String path, img.Image im) {
  final w = im.width, h = im.height;

  // 1) 不透明主体平均色（用于参照）
  var sr = 0.0, sg = 0.0, sb = 0.0, n = 0;
  for (final p in im) {
    if (p.a > 200) {
      sr += p.r;
      sg += p.g;
      sb += p.b;
      n++;
    }
  }
  if (n == 0) {
    print('$path: 没有不透明像素，抠图失败');
    return;
  }
  final mr = sr / n, mg = sg / n, mb = sb / n;

  // 2) 检查「贴着透明区域的半透明边缘像素」
  //    这些像素最容易残留背景色 → 表现为一圈脏边
  var darkEdge = 0, brightEdge = 0, edge = 0;
  double worstDark = 0, worstBright = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = im.getPixel(x, y);
      final a = p.a.toInt();
      if (a <= 20 || a >= 250) continue;
      // 是否紧邻完全透明像素
      var nearTransparent = false;
      for (var dy = -1; dy <= 1 && !nearTransparent; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final q = im.getPixel(
            (x + dx).clamp(0, w - 1),
            (y + dy).clamp(0, h - 1),
          );
          if (q.a <= 20) {
            nearTransparent = true;
            break;
          }
        }
      }
      if (!nearTransparent) continue;
      edge++;
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      final mLum = 0.299 * mr + 0.587 * mg + 0.114 * mb;
      if (lum < mLum - 60) {
        darkEdge++;
        worstDark = math.max(worstDark, mLum - lum);
      } else if (lum > mLum + 60) {
        brightEdge++;
        worstBright = math.max(worstBright, lum - mLum);
      }
    }
  }

  final ratio = edge == 0 ? 0.0 : (darkEdge + brightEdge) * 100.0 / edge;
  final verdict = edge == 0
      ? '⚠️ 没有半透明边缘（可能抠得太硬，边缘会有锯齿）'
      : (ratio < 15 ? '✅ 边缘干净' : '❌ 边缘残留明显（暗边 $darkEdge / 亮边 $brightEdge）');

  print(
    '$path ${w}x$h  主体色=(${mr.round()},${mg.round()},${mb.round()})\n'
    '   边缘像素=$edge  暗边=$darkEdge(最深${worstDark.round()})  '
    '亮边=$brightEdge(最亮${worstBright.round()})  → $verdict',
  );
}
