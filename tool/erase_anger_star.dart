// 定位并移除 pet_rage.png 右上角的 AI 画歪的"怒气星号"。
//
// 问题：AI 画的 💢 经常变成六角星/星号（用户截图证实）。
// 方案：像素扫描右上角象限的「孤立橙红像素簇」→ 整簇置透明。
// （真正的生气标记由 pet_egg.dart 的 _AngerMark 用代码绘制，
//   位置、形状完全可控。）
//
// 运行：dart run tool/erase_anger_star.dart
// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _src = 'assets/images/pet_rage.png';
const _bak = 'assets/images/pet_rage_bak.png';

/// 橙红系判定：暖色、偏红橙、饱和度较高（与粉色头发/皮肤区分）。
bool _isOrangeRed(int r, int g, int b) {
  if (r < 150) return false; // 足够红
  if (g > r * 0.85) return false; // 不能太黄/太浅
  if (b > r * 0.7) return false; // 不能偏粉紫（皮肤/腮红的 b 较高）
  // 排除深色描边
  return (r - g) > 45 || (r - b) > 60;
}

void main() {
  final file = File(_src);
  if (!file.existsSync()) {
    print('MISS $_src');
    return;
  }
  // 备份原始（幂等：已有备份就不覆盖）
  final bak = File(_bak);
  if (!bak.existsSync()) {
    bak.writeAsBytesSync(file.readAsBytesSync());
    print('BACKUP -> $_bak');
  }

  final im = img.decodeImage(bak.readAsBytesSync());
  if (im == null) {
    print('DECODE FAIL');
    return;
  }
  final w = im.width, h = im.height;
  print('SIZE ${w}x$h');

  // ── 第 1 步：在右上象限（x > 0.55w, y < 0.45h）找橙红像素簇 ──
  final inZone = <int>[];
  for (var y = 0; y < (h * 0.45).round(); y++) {
    for (var x = (w * 0.55).round(); x < w; x++) {
      final p = im.getPixel(x, y);
      if (_isOrangeRed(p.r.toInt(), p.g.toInt(), p.b.toInt())) {
        inZone.add(y * w + x);
      }
    }
  }
  print('右上象限橙红像素: ${inZone.length}');
  if (inZone.isEmpty) {
    print('没有找到星号，保持原样');
    return;
  }

  // ── 第 2 步：聚类（4 连通），找最大的簇 ──
  final seen = <int>{};
  List<int> biggest = [];
  for (final start in inZone) {
    if (seen.contains(start)) continue;
    final cluster = <int>[];
    final queue = Queue<int>()..add(start);
    seen.add(start);
    while (queue.isNotEmpty) {
      final i = queue.removeFirst();
      cluster.add(i);
      final x = i % w, y = i ~/ w;
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (seen.contains(ni)) continue;
        final q = im.getPixel(nx, ny);
        if (_isOrangeRed(q.r.toInt(), q.g.toInt(), q.b.toInt())) {
          seen.add(ni);
          queue.add(ni);
        }
      }
    }
    if (cluster.length > biggest.length) biggest = cluster;
    if (cluster.length > 20) {
      print('  簇: ${cluster.length}px  '
          'bbox=(${cluster.map((e) => e % w).reduce(math.min)}'
          '..${cluster.map((e) => e % w).reduce(math.max)}, '
          '${cluster.map((e) => e ~/ w).reduce(math.min)}'
          '..${cluster.map((e) => e ~/ w).reduce(math.max)})');
    }
  }
  print('最大簇: ${biggest.length}px');
  if (biggest.length < 30) {
    print('簇太小，可能是真实发色/描边，保持原样');
    return;
  }

  // ── 第 3 步：把最大簇连同 2px 外扩（清掉描边）置透明 ──
  final kill = <int>{...biggest};
  for (final i in biggest) {
    final x = i % w, y = i ~/ w;
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        kill.add(ny * w + nx);
      }
    }
  }
  for (final i in kill) {
    final x = i % w, y = i ~/ w;
    im.setPixelRgba(x, y, 0, 0, 0, 0);
  }
  print('擦除像素: ${kill.length}');

  File(_src).writeAsBytesSync(img.encodePng(im));
  print('OK -> $_src');
  print('ERASE_DONE');
}