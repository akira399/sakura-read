// 生成「修复前 / 修复后」黑底对比图，供人工直观验收白边修复效果。
//
// 输出：/sdcard/Download/pet_edge_compare.png
//  左 = 修复前（备份素材）  右 = 修复后（当前素材）
//  背景纯黑，模拟彩蛋界面场景。
//
// 运行：dart run tool/make_edge_compare.dart <备份目录>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final backup = args.isNotEmpty ? args.first : '/tmp/pet_backup_1150';
  const target = 'pet_rage.png';

  final before = _load('$backup/$target');
  final after = _load('assets/images/$target');
  if (before == null || after == null) {
    print('MISS before=$before after=$after');
    return;
  }

  const pad = 24;
  final cellH = before.height;
  final cellW = before.width + after.width + pad * 3;
  final out = img.Image(width: cellW, height: cellH + pad * 2);

  // 纯黑底
  img.fill(out, color: img.ColorRgb8(0, 0, 0));

  _blend(out, before, pad, pad);
  _blend(out, after, before.width + pad * 2, pad);

  File(
    '/sdcard/Download/pet_edge_compare.png',
  ).writeAsBytesSync(img.encodePng(out));
  print(
    'SAVED /sdcard/Download/pet_edge_compare.png ${out.width}x${out.height}',
  );
  print('COMPARE_DONE');
}

img.Image? _load(String p) {
  final f = File(p);
  if (!f.existsSync()) return null;
  final d = img.decodeImage(f.readAsBytesSync());
  return d?.convert(numChannels: 4);
}

/// 把透明 PNG 按 alpha 混到黑底上。
void _blend(img.Image dst, img.Image src, int ox, int oy) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final a = p.a / 255.0;
      if (a == 0) continue;
      final dx = ox + x, dy = oy + y;
      if (dx < 0 || dy < 0 || dx >= dst.width || dy >= dst.height) continue;
      final d = dst.getPixel(dx, dy);
      dst.setPixelRgba(
        dx,
        dy,
        (p.r * a + d.r * (1 - a)).round(),
        (p.g * a + d.g * (1 - a)).round(),
        (p.b * a + d.b * (1 - a)).round(),
        255,
      );
    }
  }
}
