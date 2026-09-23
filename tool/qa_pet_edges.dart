// 修边 QA：直接度量「轮廓最外层环带」在黑底上的亮度，并对比修复前后差异。
//
// 判据（白边的直接定义）：
//   把透明 PNG 叠到纯黑底上，取所有 alpha>0 像素里**最外层那一圈**
//   （即紧邻透明区、dist==1）。若这圈像素合成后仍明显发亮，
//   放大时就会在人物外侧显出一圈白/灰描边。
//
// 同时检查「修边是否伤到人物」：统计颜色被改动的像素是否都落在边缘带内。
//
// 运行：dart run tool/qa_pet_edges.dart <备份目录>
// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

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

void main(List<String> args) {
  final backup = args.isNotEmpty ? args.first : '';
  for (final f in _faces) {
    _qa('assets/images/$f', backup.isEmpty ? null : '$backup/$f');
  }
  print('QA_DONE');
}

double _lum(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

class _Layer {
  _Layer(this.w, this.h, this.a, this.r, this.g, this.b);

  final int w, h;
  final List<int> a;
  final List<double> r, g, b;
}

_Layer? _load(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  final d = img.decodeImage(f.readAsBytesSync());
  if (d == null) return null;
  final s = d.convert(numChannels: 4);
  final w = s.width, h = s.height, n = w * h;
  final a = List<int>.filled(n, 0);
  final r = List<double>.filled(n, 0);
  final g = List<double>.filled(n, 0);
  final b = List<double>.filled(n, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final p = s.getPixel(x, y);
      a[i] = p.a.toInt();
      r[i] = p.r.toDouble();
      g[i] = p.g.toDouble();
      b[i] = p.b.toDouble();
    }
  }
  return _Layer(w, h, a, r, g, b);
}

/// 返回 (最外层环带黑底平均亮度, 最大亮度, 环带像素数)
(double, double, int) _outerRing(_Layer L) {
  final n = L.w * L.h;
  final dist = List<int>.filled(n, 99);
  final q = ListQueue<int>();
  for (var i = 0; i < n; i++) {
    if (L.a[i] == 0) {
      dist[i] = 0;
      q.add(i);
    }
  }
  while (q.isNotEmpty) {
    final i = q.removeFirst();
    if (dist[i] >= 5) continue;
    final x = i % L.w, y = i ~/ L.w, nd = dist[i] + 1;
    for (var k = 0; k < 8; k++) {
      final nx = x + _dx8[k], ny = y + _dy8[k];
      if (nx < 0 || ny < 0 || nx >= L.w || ny >= L.h) continue;
      final j = ny * L.w + nx;
      if (nd < dist[j]) {
        dist[j] = nd;
        q.add(j);
      }
    }
  }
  var sum = 0.0, mx = 0.0, cnt = 0;
  for (var i = 0; i < n; i++) {
    if (L.a[i] == 0 || dist[i] != 1) continue;
    final l = _lum(L.r[i], L.g[i], L.b[i]) * (L.a[i] / 255.0);
    sum += l;
    mx = math.max(mx, l);
    cnt++;
  }
  return (cnt == 0 ? 0.0 : sum / cnt, mx, cnt);
}

void _qa(String path, String? beforePath) {
  final L = _load(path);
  if (L == null) {
    print('MISS $path');
    return;
  }
  final (avg, mx, cnt) = _outerRing(L);
  var line =
      '${path.split('/').last.padRight(16)} ${L.w}x${L.h}  '
      '外环($cnt px) 黑底亮度 均值=${avg.toStringAsFixed(1)} 最亮=${mx.toStringAsFixed(0)}';

  if (beforePath != null) {
    final B = _load(beforePath);
    if (B != null && B.w == L.w && B.h == L.h) {
      final (bAvg, bMx, _) = _outerRing(B);
      // 颜色改动是否越界：找出颜色被改且距透明区 > 6 的像素（不该动的地方）
      final n = L.w * L.h;
      final dist = List<int>.filled(n, 99);
      final q = ListQueue<int>();
      for (var i = 0; i < n; i++) {
        if (L.a[i] == 0 || B.a[i] == 0) {
          dist[i] = 0;
          q.add(i);
        }
      }
      while (q.isNotEmpty) {
        final i = q.removeFirst();
        if (dist[i] >= 6) continue;
        final x = i % L.w, y = i ~/ L.w, nd = dist[i] + 1;
        for (var k = 0; k < 8; k++) {
          final nx = x + _dx8[k], ny = y + _dy8[k];
          if (nx < 0 || ny < 0 || nx >= L.w || ny >= L.h) continue;
          final j = ny * L.w + nx;
          if (nd < dist[j]) {
            dist[j] = nd;
            q.add(j);
          }
        }
      }
      var changed = 0, deepChanged = 0;
      for (var i = 0; i < n; i++) {
        if (L.a[i] < 40) continue;
        final d =
            (L.r[i] - B.r[i]).abs() +
            (L.g[i] - B.g[i]).abs() +
            (L.b[i] - B.b[i]).abs();
        if (d <= 12) continue;
        changed++;
        if (dist[i] > 6) deepChanged++;
      }
      line +=
          '\n${' ' * 17}修复前外环 均值=${bAvg.toStringAsFixed(1)} '
          '最亮=${bMx.toStringAsFixed(0)}  → 平均降 '
          '${((bAvg - avg) * 100 / math.max(1.0, bAvg)).toStringAsFixed(0)}%'
          '\n${' ' * 17}改动像素=$changed（越界改动=$deepChanged）'
          ' ${deepChanged == 0 ? '✅ 只动了边缘' : '❌ 动到了主体内部'}';
    }
  }
  print(line);
}
