// 一次性工具：把看板娘原图去背景 → 透明 PNG（裁剪到人物包围盒）。
// 用法：cd <工作区> && dart run tool/make_pet_cutouts.dart
// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const Map<String, String> _jobs = {
  'kanban_chibi.jpg': 'pet_chibi.png',
  'kanban_wave.jpg': 'pet_wave.png',
  'kanban_read.jpg': 'pet_read.png',
  'kanban_cheer.jpg': 'pet_cheer.png',
  'kanban_sleep.jpg': 'pet_sleep.png',
  'kanban_shy.jpg': 'pet_shy.png',
  // AI 生成的生气 / 阴沉差分（源在 tool/artwork/candidates/）
  'pet_angry_source.jpg': 'pet_angry.png',
  'pet_rage_source.jpg': 'pet_rage.png',
};

const int _tHard = 26; // 与背景色差 ≤ 此值视为背景（洪泛入队）
const int _tSoft = 72; // 边缘羽化上限（超过则完全不透明）
const int _outMax = 512; // 输出最长边

void main() {
  for (final job in _jobs.entries) {
    _process('assets/images/${job.key}', 'assets/images/${job.value}');
  }
  print('CUTOUT_DONE');
}

void _process(String inPath, String outPath) {
  final file = File(inPath);
  if (!file.existsSync()) {
    print('MISS $inPath');
    return;
  }
  final im = img.decodeImage(file.readAsBytesSync());
  if (im == null) {
    print('DECODE_FAIL $inPath');
    return;
  }
  // JPEG 解码后无 alpha 通道；先转 4 通道，否则透明度写入会被忽略
  final rgba = im.convert(numChannels: 4);
  final w = rgba.width;
  final h = rgba.height;

  // 背景参考色 = 四角 12×12 均值
  var sr = 0, sg = 0, sb = 0, sn = 0;
  void acc(int x0, int y0) {
    for (var y = y0; y < y0 + 12; y++) {
      for (var x = x0; x < x0 + 12; x++) {
        final p = rgba.getPixel(x, y);
        sr += p.r.toInt();
        sg += p.g.toInt();
        sb += p.b.toInt();
        sn++;
      }
    }
  }

  acc(0, 0);
  acc(w - 12, 0);
  acc(0, h - 12);
  acc(w - 12, h - 12);
  final br = sr ~/ sn, bgc = sg ~/ sn, bb = sb ~/ sn;

  double dist(num r, num g, num b) {
    final dr = r - br, dg = g - bgc, db = b - bb;
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  final total = w * h;
  final visited = List<bool>.filled(total, false);
  final queue = ListQueue<int>();
  void tryPush(int x, int y) {
    final i = y * w + x;
    if (visited[i]) return;
    final p = rgba.getPixel(x, y);
    if (dist(p.r, p.g, p.b) <= _tHard) {
      visited[i] = true;
      queue.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    tryPush(x, 0);
    tryPush(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    tryPush(0, y);
    tryPush(w - 1, y);
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w;
    final y = i ~/ w;
    if (x > 0) tryPush(x - 1, y);
    if (x < w - 1) tryPush(x + 1, y);
    if (y > 0) tryPush(x, y - 1);
    if (y < h - 1) tryPush(x, y + 1);
  }

  var bgCount = 0;
  for (var i = 0; i < total; i++) {
    if (visited[i]) bgCount++;
  }

  // 背景 → 透明（RGB 设为背景色，缩放时不会出现深色描边）
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (visited[y * w + x]) {
        rgba.setPixelRgba(x, y, br, bgc, bb, 0);
      }
    }
  }

  // 边缘羽化：贴着背景的像素按色差给部分透明度
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (visited[i]) continue;
      var near = false;
      for (var dy = -1; dy <= 1 && !near; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (visited[ny * w + nx]) {
            near = true;
            break;
          }
        }
      }
      if (!near) continue;
      final p = rgba.getPixel(x, y);
      final d = dist(p.r, p.g, p.b);
      if (d >= _tSoft) continue;
      final a = ((d - _tHard) / (_tSoft - _tHard)).clamp(0.0, 1.0);
      final alpha = (a * 255).round();
      if (alpha >= 255) continue;
      rgba.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), alpha);
    }
  }

  // 裁剪到人物包围盒（alpha > 8）
  var minX = w, minY = h, maxX = -1, maxY = -1, opaque = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba.getPixel(x, y).a > 8) {
        opaque++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) {
    print('EMPTY $inPath');
    return;
  }

  final pad = ((maxX - minX + 1) * 0.05).round().clamp(4, 40);
  final cx = math.max(0, minX - pad);
  final cy = math.max(0, minY - pad);
  final cw = math.min(w - cx, (maxX - minX + 1) + pad * 2);
  final ch = math.min(h - cy, (maxY - minY + 1) + pad * 2);
  var out = img.copyCrop(rgba, x: cx, y: cy, width: cw, height: ch);
  if (math.max(cw, ch) > _outMax) {
    out = cw >= ch
        ? img.copyResize(out, width: _outMax)
        : img.copyResize(out, height: _outMax);
  }
  File(outPath).writeAsBytesSync(img.encodePng(out));
  print(
    'OK $outPath ${out.width}x${out.height} '
    'person=${(opaque * 100 / total).toStringAsFixed(1)}% '
    'bg=${(bgCount * 100 / total).toStringAsFixed(1)}%',
  );
}