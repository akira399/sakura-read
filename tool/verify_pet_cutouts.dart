// 验证抠图产物：统计透明/半透明/不透明像素占比。
// 运行：dart run tool/verify_pet_cutouts.dart
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
      print('$name: DECODE FAIL');
      continue;
    }
    var transparent = 0, translucent = 0, solid = 0;
    for (final p in im) {
      final a = p.a.toInt();
      if (a <= 8) {
        transparent++;
      } else if (a < 247) {
        translucent++;
      } else {
        solid++;
      }
    }
    final total = im.width * im.height;
    print(
      '$name ${im.width}x${im.height}: '
      '透明 ${(transparent * 100 / total).toStringAsFixed(1)}% / '
      '半透明 ${(translucent * 100 / total).toStringAsFixed(1)}% / '
      '实心 ${(solid * 100 / total).toStringAsFixed(1)}%',
    );
  }
  print('VERIFY_DONE');
}