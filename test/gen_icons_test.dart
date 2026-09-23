// 一次性工具：从 Q 版看板娘源图生成 App 图标全套 Android 资源。
//  - legacy:  ic_launcher.png（圆角方形，各密度）
//  - 自适应: ic_launcher_foreground.png（内容 72% 居中，留安全区）
//           ic_launcher_background.png（源图对角取样渐变，与前景边缘同色系）
//           ic_launcher_monochrome.png（Android 13+ 主题图标：人物剪影转纯白）
// 运行：flutter test test/gen_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 项目根（flutter test 的工作目录即项目根）。
final String _ws = Directory.current.path;
final String _res = '$_ws/android/app/src/main/res';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generate app icons',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final bytes = File(
        '$_ws/tool/artwork/src/chibi_icon.jpg',
      ).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      // 采样源图对角颜色（用于背景渐变，与前景边缘同色系）
      final bd = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = bd.buffer.asUint8List();
      ui.Color sample(int x, int y) {
        final i = (y * src.width + x) * 4;
        return ui.Color.fromARGB(255, px[i], px[i + 1], px[i + 2]);
      }

      final c1 = sample(60, 60);
      final c2 = sample(src.width - 60, src.height - 60);

      // 主题图标（monochrome）用「已抠好背景的人物立绘」做剪影：
      // 直接复用桌宠的透明 PNG，切成纯白不透明区域。
      final cutout = await _loadCutout();

      final dirs = {
        'mipmap-mdpi': [48, 108],
        'mipmap-hdpi': [72, 162],
        'mipmap-xhdpi': [96, 216],
        'mipmap-xxhdpi': [144, 324],
        'mipmap-xxxhdpi': [192, 432],
      };

      for (final e in dirs.entries) {
        final base = '$_res/${e.key}';
        final legacy = e.value[0];
        final adaptive = e.value[1];

        // legacy：圆角方形整图
        await _render('$base/ic_launcher.png', legacy, (canvas, size) {
          canvas.clipRRect(
            ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(0, 0, size, size),
              ui.Radius.circular(size * 0.225),
            ),
          );
          _drawImg(canvas, src, 0, 0, size, size);
        });

        // 前景：整图缩到 72%，居中，四周透明（由背景层兜底）
        await _render('$base/ic_launcher_foreground.png', adaptive, (
          canvas,
          size,
        ) {
          final inner = size * 0.72;
          final off = (size - inner) / 2;
          _drawImg(canvas, src, off, off, inner, inner);
        });

        // 背景：对角线性渐变
        await _render('$base/ic_launcher_background.png', adaptive, (
          canvas,
          size,
        ) {
          final paint = ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset(0, 0),
              ui.Offset(size, size),
              [c1, c2],
            );
          canvas.drawRect(ui.Rect.fromLTWH(0, 0, size, size), paint);
        });

        // 主题图标：人物剪影（纯白，居中 62%，留出安全区）
        await _render('$base/ic_launcher_monochrome.png', adaptive, (
          canvas,
          size,
        ) {
          if (cutout == null) {
            // 没有抠图素材时至少保证不是模板占位图：退化为前景剪影
            _drawImg(canvas, src, 0, 0, size, size);
            return;
          }
          final h = size * 0.62;
          final w = h * cutout.width / cutout.height;
          final offY = (size - h) / 2;
          final offX = (size - w) / 2;
          _drawSilhouette(canvas, cutout, offX, offY, w, h);
        });
      }
      // ignore: avoid_print
      print('ICONS_DONE');
    },
  );
}

/// 加载桌宠人物抠图（透明背景 PNG）。
Future<ui.Image?> _loadCutout() async {
  for (final p in [
    '$_ws/assets/images/pet_chibi.png',
    '$_ws/assets/images/pet_wave.png',
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final codec = await ui.instantiateImageCodec(await f.readAsBytes());
    return (await codec.getNextFrame()).image;
  }
  return null;
}

/// 把带透明通道的立绘画成纯白剪影（alpha 不变，RGB 置白）。
void _drawSilhouette(
  ui.Canvas canvas,
  ui.Image img,
  double l,
  double t,
  double w,
  double h,
) {
  canvas.saveLayer(ui.Rect.fromLTWH(l, t, w, h), ui.Paint());
  // 先画原图（仅用于取 alpha）
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    ui.Rect.fromLTWH(l, t, w, h),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  // 再用 srcIn 把整块染白 → 得到白色剪影
  canvas.drawRect(
    ui.Rect.fromLTWH(l, t, w, h),
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..blendMode = ui.BlendMode.srcIn,
  );
  canvas.restore();
}

void _drawImg(
  ui.Canvas canvas,
  ui.Image img,
  double l,
  double t,
  double w,
  double h,
) {
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    ui.Rect.fromLTWH(l, t, w, h),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
}

Future<void> _render(
  String path,
  int size,
  void Function(ui.Canvas, double) body,
) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  body(canvas, size.toDouble());
  final pic = rec.endRecording();
  final img = await pic.toImage(size, size);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
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
