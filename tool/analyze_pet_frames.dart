// 一次性工具：分析看板娘图片的背景纯度（判断能否算法抠图）。
// 运行：dart run tool/analyze_pet_frames.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final dir = Directory('assets/images');
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('kanban_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final im = img.decodeImage(f.readAsBytesSync());
    if (im == null) {
      print('$name: DECODE FAIL');
      continue;
    }
    final w = im.width, h = im.height;
    print('==== $name  ${w}x$h ====');

    // 四角 12x12 平均色
    void corner(String label, int x0, int y0) {
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = y0; y < y0 + 12; y++) {
        for (var x = x0; x < x0 + 12; x++) {
          final p = im.getPixel(x, y);
          r += p.r.toInt();
          g += p.g.toInt();
          b += p.b.toInt();
          n++;
        }
      }
      print('  $label: rgb(${r ~/ n},${g ~/ n},${b ~/ n})');
    }

    corner('TL', 0, 0);
    corner('TR', w - 12, 0);
    corner('BL', 0, h - 12);
    corner('BR', w - 12, h - 12);

    // 四条边（各取中段 40 个点）的颜色方差：若方差小 → 背景均匀
    double edgeVariance(bool horizontal, bool top) {
      final colors = <List<int>>[];
      final mid = horizontal ? w ~/ 2 : h ~/ 2;
      for (var i = mid - 20; i < mid + 20; i++) {
        final p = horizontal
            ? im.getPixel(i.clamp(0, w - 1), top ? 1 : h - 2)
            : im.getPixel(top ? 1 : w - 2, i.clamp(0, h - 1));
        colors.add([p.r.toInt(), p.g.toInt(), p.b.toInt()]);
      }
      var vr = 0.0, vg = 0.0, vb = 0.0;
      var mr = 0.0, mg = 0.0, mb = 0.0;
      for (final c in colors) {
        mr += c[0];
        mg += c[1];
        mb += c[2];
      }
      mr /= colors.length;
      mg /= colors.length;
      mb /= colors.length;
      for (final c in colors) {
        vr += (c[0] - mr) * (c[0] - mr);
        vg += (c[1] - mg) * (c[1] - mg);
        vb += (c[2] - mb) * (c[2] - mb);
      }
      vr /= colors.length;
      vg /= colors.length;
      vb /= colors.length;
      return (vr + vg + vb) / 3;
    }

    print(
      '  top    edge variance: ${edgeVariance(true, true).toStringAsFixed(1)}',
    );
    print(
      '  bottom edge variance: ${edgeVariance(true, false).toStringAsFixed(1)}',
    );
    print(
      '  left   edge variance: ${edgeVariance(false, true).toStringAsFixed(1)}',
    );
    print(
      '  right  edge variance: ${edgeVariance(false, false).toStringAsFixed(1)}',
    );

    // 中心 40x40 平均色（人物区域）
    var cr = 0, cg = 0, cb = 0, cn = 0;
    for (var y = h ~/ 2 - 20; y < h ~/ 2 + 20; y++) {
      for (var x = w ~/ 2 - 20; x < w ~/ 2 + 20; x++) {
        final p = im.getPixel(x, y);
        cr += p.r.toInt();
        cg += p.g.toInt();
        cb += p.b.toInt();
        cn++;
      }
    }
    print('  center: rgb(${cr ~/ cn},${cg ~/ cn},${cb ~/ cn})');
    print('');
  }
  print('ANALYZE_DONE');
}
