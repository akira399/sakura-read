// 检查抠图立绘边缘是否残留深色半透明像素（会渲染成黑边/黑圈）。
// 运行：dart run tool/check_pet_fringe.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final dir = Directory('assets/images');
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('pet_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final im = img.decodeImage(f.readAsBytesSync());
    if (im == null) {
      print('$name DECODE_FAIL');
      continue;
    }
    final w = im.width, h = im.height;

    var translucent = 0; // 全部半透明像素
    var darkTranslucent = 0; // 半透明且偏暗：羽化出错的典型症状

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final a = p.a.toInt();
        if (a > 0 && a < 250) {
          translucent++;
          final lum = (p.r + p.g + p.b) / 3;
          if (lum < 110 && a > 32) darkTranslucent++;
        }
      }
    }
    final total = w * h;
    print(
      '$name: 半透明 ${(translucent * 100 / total).toStringAsFixed(2)}% · '
      '其中偏暗 ${(darkTranslucent * 100 / total).toStringAsFixed(3)}%',
    );
  }
  print('FRINGE_DONE');
}
