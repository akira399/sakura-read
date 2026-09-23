// 一次性工具：消除 pet_*.png 在深色背景上的「白边 / 灰晕」。
//
// 背景（为什么会白边）：
// 抠图工具 `make_pet_cutouts.dart` 只把背景像素的 alpha 设为 0，
// 留下两个坑，在彩蛋那种纯黑底上会连成一圈白边：
//   ① 轮廓外缘残留「背景色」像素：羽化只动了 alpha、没修 RGB，
//      于是这些像素是「近白/米色 + 半透明」→ 叠到黑底 = 灰白圈；
//   ② 完全透明像素仍保留白色 RGB（254,254,254）：Flutter 放大时
//      做 cubic 插值，会把周围这些白色混进人物边缘 → 白边。
//
// 本工具的两步修复：
//   ① 污染边缘修正：外缘像素若明显比「内侧」亮，把颜色替换为内侧平均色；
//   ② 透明区渗色填充（bleed）：把主体颜色向外扩散几像素，盖掉白 RGB，
//      这样无论放大还是缩小，插值都不会再引入白色。
//
// 运行：dart run tool/fix_pet_edges.dart
// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 需要修边的看板娘素材（顺序无关）。
const List<String> _faces = [
  'pet_chibi.png',
  'pet_wave.png',
  'pet_read.png',
  'pet_cheer.png',
  'pet_sleep.png',
  'pet_shy.png',
  'pet_angry.png',
  'pet_rage.png',
];

const List<int> _dx8 = [1, -1, 0, 0, 1, 1, -1, -1];
const List<int> _dy8 = [0, 0, 1, -1, 1, -1, 1, -1];

const int _distCap = 6; // 距透明区的最大测距
const int _edgeBand = 3; // 深度 ≤ 此值算「外缘」
const double _lumGap = 45; // 外缘比内侧亮多少算背景污染
const int _bleedSteps = 4; // 透明区渗色扩散步数
const int _minAlpha = 40; // 太透明的像素不值得修

void main() {
  for (final f in _faces) {
    _fix('assets/images/$f');
  }
  print('EDGE_FIX_DONE');
}

double _lum(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

/// 黑底合成后的亮度（彩蛋界面就是纯黑底）。
double _onBlack(num r, num g, num b, int a) => _lum(r, g, b) * (a / 255.0);

void _fix(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    print('MISS $path');
    return;
  }
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    print('DECODE_FAIL $path');
    return;
  }
  final src = decoded.convert(numChannels: 4);
  final w = src.width;
  final h = src.height;
  final total = w * h;

  final a = List<int>.filled(total, 0);
  final r = List<double>.filled(total, 0);
  final g = List<double>.filled(total, 0);
  final b = List<double>.filled(total, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final p = src.getPixel(x, y);
      a[i] = p.a.toInt();
      r[i] = p.r.toDouble();
      g[i] = p.g.toDouble();
      b[i] = p.b.toDouble();
    }
  }

  final before = _metrics(w, h, a, r, g, b);

  // ---- 距透明区的距离（BFS，8 邻域） ----
  final dist = List<int>.filled(total, _distCap + 1);
  final queue = ListQueue<int>();
  for (var i = 0; i < total; i++) {
    if (a[i] == 0) {
      dist[i] = 0;
      queue.add(i);
    }
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    if (dist[i] >= _distCap) continue;
    final x = i % w;
    final y = i ~/ w;
    final nd = dist[i] + 1;
    for (var k = 0; k < 8; k++) {
      final nx = x + _dx8[k];
      final ny = y + _dy8[k];
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final j = ny * w + nx;
      if (nd < dist[j]) {
        dist[j] = nd;
        queue.add(j);
      }
    }
  }

  // ---- ① 污染边缘修正（迭代，让 2~3px 厚的边也能吃到内侧色） ----
  var fixed = 0;
  for (var pass = 0; pass < 3; pass++) {
    final nr = List<double>.from(r);
    final ng = List<double>.from(g);
    final nb = List<double>.from(b);
    var changed = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (a[i] < _minAlpha) continue;
        final d = dist[i];
        if (d < 1 || d > _edgeBand) continue;
        // 取「更内侧」（dist 更大）的邻居平均色作参考
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var n = 0;
        for (var k = 0; k < 8; k++) {
          final nx = x + _dx8[k];
          final ny = y + _dy8[k];
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (dist[j] <= d) continue;
          sr += r[j];
          sg += g[j];
          sb += b[j];
          n++;
        }
        if (n == 0) continue;
        final ar = sr / n, ag = sg / n, ab = sb / n;
        if (_lum(r[i], g[i], b[i]) - _lum(ar, ag, ab) > _lumGap) {
          nr[i] = ar;
          ng[i] = ag;
          nb[i] = ab;
          changed++;
        }
      }
    }
    r.setAll(0, nr);
    g.setAll(0, ng);
    b.setAll(0, nb);
    fixed += changed;
    if (changed == 0) break;
  }

  // ---- ② 透明区渗色填充（bleed）：盖掉透明像素上的白 RGB ----
  final bleedDone = List<bool>.filled(total, false);
  for (var i = 0; i < total; i++) {
    if (a[i] > 0) bleedDone[i] = true;
  }
  var bled = 0;
  for (var step = 0; step < _bleedSteps; step++) {
    final nr = List<double>.from(r);
    final ng = List<double>.from(g);
    final nb = List<double>.from(b);
    final newly = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (a[i] != 0 || bleedDone[i]) continue;
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var n = 0;
        for (var k = 0; k < 8; k++) {
          final nx = x + _dx8[k];
          final ny = y + _dy8[k];
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (!bleedDone[j]) continue;
          sr += nr[j];
          sg += ng[j];
          sb += nb[j];
          n++;
        }
        if (n == 0) continue;
        nr[i] = sr / n;
        ng[i] = sg / n;
        nb[i] = sb / n;
        newly.add(i);
      }
    }
    if (newly.isEmpty) break;
    r.setAll(0, nr);
    g.setAll(0, ng);
    b.setAll(0, nb);
    for (final i in newly) {
      bleedDone[i] = true;
    }
    bled += newly.length;
  }

  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      out.setPixelRgba(
        x,
        y,
        r[i].round().clamp(0, 255),
        g[i].round().clamp(0, 255),
        b[i].round().clamp(0, 255),
        a[i],
      );
    }
  }
  file.writeAsBytesSync(img.encodePng(out));

  final after = _metrics(w, h, a, r, g, b);
  print(
    '$path ${w}x$h\n'
    '   修正污染边缘=$fixed  渗色填充=$bled\n'
    '   黑底可见亮边: ${before.bright} -> ${after.bright} '
    '(最亮 ${before.maxLum.toStringAsFixed(0)} -> ${after.maxLum.toStringAsFixed(0)})\n'
    '   透明区白 RGB: ${before.white} -> ${after.white}\n'
    '   → ${after.bright == 0
        ? '✅ 黑底上不再有白边'
        : after.bright * 100 / math.max(1, before.bright) < 15
        ? '✅ 已基本消除'
        : '⚠️ 仍有残留'}',
  );
}

class _Metrics {
  _Metrics(this.bright, this.maxLum, this.white);

  final int bright; // 外缘 3px 内、黑底合成亮度 ≥ 90 的像素数
  final double maxLum; // 上述像素的最亮值
  final int white; // 完全透明但仍保留亮 RGB 的像素数
}

_Metrics _metrics(
  int w,
  int h,
  List<int> a,
  List<double> r,
  List<double> g,
  List<double> b,
) {
  final total = w * h;
  final dist = List<int>.filled(total, 4);
  final queue = ListQueue<int>();
  for (var i = 0; i < total; i++) {
    if (a[i] == 0) {
      dist[i] = 0;
      queue.add(i);
    }
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    if (dist[i] >= 3) continue;
    final x = i % w;
    final y = i ~/ w;
    final nd = dist[i] + 1;
    for (var k = 0; k < 8; k++) {
      final nx = x + _dx8[k];
      final ny = y + _dy8[k];
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final j = ny * w + nx;
      if (nd < dist[j]) {
        dist[j] = nd;
        queue.add(j);
      }
    }
  }

  var bright = 0;
  var maxLum = 0.0;
  var white = 0;
  for (var i = 0; i < total; i++) {
    if (a[i] == 0) {
      if (_lum(r[i], g[i], b[i]) > 200) white++;
      continue;
    }
    if (dist[i] < 1 || dist[i] > 3) continue;
    final l = _onBlack(r[i], g[i], b[i], a[i]);
    if (l >= 90) {
      bright++;
      maxLum = math.max(maxLum, l);
    }
  }
  return _Metrics(bright, maxLum, white);
}
