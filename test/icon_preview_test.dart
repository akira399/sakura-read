// 一次性工具：把 Q 版图标原图（chibi_icon.jpg）加工成多形态预览 PNG。
// 输出：icon_square_512.png / icon_round_512.png / icon_rounded_512.png
// 运行：flutter test test/icon_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 项目根（flutter test 的工作目录即项目根）。
final String _ws = Directory.current.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'make icon previews',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final src = File('$_ws/tool/artwork/src/chibi_icon.jpg');
      expect(src.existsSync(), isTrue, reason: '缺少源图 chibi_icon.jpg');
      final bytes = await src.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      await _save(
        img,
        '$_ws/tool/artwork/icon_square_512.png',
        512,
        _MaskKind.none,
      );
      await _save(
        img,
        '$_ws/tool/artwork/icon_round_512.png',
        512,
        _MaskKind.circle,
      );
      await _save(
        img,
        '$_ws/tool/artwork/icon_rounded_512.png',
        512,
        _MaskKind.rounded,
      );
      // ignore: avoid_print
      print('ICON_PREVIEWS_DONE');
    },
  );
}

enum _MaskKind { none, circle, rounded }

Future<void> _save(ui.Image src, String path, int out, _MaskKind mask) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final size = out.toDouble();
  final rect = ui.Rect.fromLTWH(0, 0, size, size);
  if (mask == _MaskKind.circle) {
    canvas.clipPath(ui.Path()..addOval(rect));
  } else if (mask == _MaskKind.rounded) {
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(size * 0.225)),
    );
  }
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    rect,
    paint,
  );
  final pic = recorder.endRecording();
  final image = await pic.toImage(out, out);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  _writeIfChanged(path, png!.buffer.asUint8List());
}

/// 内容与现有文件一致时跳过写入（避免每次跑测试都刷新文件时间戳）。
void _writeIfChanged(String path, List<int> bytes) {
  final file = File(path);
  if (file.existsSync()) {
    final old = file.readAsBytesSync();
    if (old.length == bytes.length) {
      var same = true;
      for (var i = 0; i < old.length; i++) {
        if (old[i] != bytes[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
  }
  file.writeAsBytesSync(bytes);
}
