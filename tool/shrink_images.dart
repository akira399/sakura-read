// 一次性工具：压缩 assets/images 下的插画（降采样 + 降质量），控制 APK 体积。
// 运行：cd <工作区> && dart run tool/shrink_images.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:image/image.dart' as img;

/// 项目根（在项目根目录运行：dart run tool/shrink_images.dart）。
final String _ws = Directory.current.path;

void main() {
  final dir = Directory('$_ws/assets/images');
  var beforeTotal = 0;
  var afterTotal = 0;
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.jpg')) continue;
    final targetWidth = name.startsWith('splash') ? 820 : 680;
    final before = f.lengthSync();
    if (before < 200 * 1024) continue; // 已压过的小文件跳过
    img.Image? decoded;
    try {
      // 注意：生成端存下来的文件虽然扩展名是 .jpg，实际可能是 PNG 内容，
      // 所以用 decodeImage 自动识别格式。
      decoded = img.decodeImage(f.readAsBytesSync());
    } catch (e) {
      print('FAIL $name: $e');
      continue;
    }
    if (decoded == null) {
      print('SKIP(decode failed) $name');
      continue;
    }
    final resized = decoded.width > targetWidth
        ? img.copyResize(
            decoded,
            width: targetWidth,
            interpolation: img.Interpolation.cubic,
          )
        : decoded;
    final out = img.encodeJpg(
      resized,
      quality: name.startsWith('splash') ? 86 : 82,
    );
    f.writeAsBytesSync(out);
    beforeTotal += before;
    afterTotal += out.length;
    print(
      '$name: ${(before / 1024).round()}KB -> ${(out.length / 1024).round()}KB',
    );
  }
  print(
    'TOTAL: ${(beforeTotal / 1024 / 1024).toStringAsFixed(1)}MB -> '
    '${(afterTotal / 1024 / 1024).toStringAsFixed(1)}MB',
  );
  print('SHRINK_DONE');
}
