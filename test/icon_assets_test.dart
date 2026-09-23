// App 图标完整性回归：三层资源齐全、monochrome 是自绘剪影（不是 Flutter 模板占位图）。
//
// 背景：Android 13+ 的「主题化图标」会取 monochrome 层。若该层仍是脚手架自带的
// Flutter 标志，系统主题图标就会显示错内容（历史 bug，见 CHANGELOG 1.3.3）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _densities = {
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

String _resPath(String density, String layer) =>
    'android/app/src/main/res/$density/$layer.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自适应图标三层（前景 / 背景 / 主题剪影）在各密度均存在', () {
    for (final d in _densities.keys) {
      for (final layer in [
        'ic_launcher',
        'ic_launcher_foreground',
        'ic_launcher_background',
        'ic_launcher_monochrome',
      ]) {
        final f = File(_resPath(d, layer));
        expect(f.existsSync(), isTrue, reason: '缺少 $d/$layer.png');
        expect(f.lengthSync(), greaterThan(200), reason: '$d/$layer.png 可疑地小');
      }
    }
  });

  test('adaptive-icon XML 引用了 monochrome 层', () {
    final xml = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(xml, contains('ic_launcher_foreground'));
    expect(xml, contains('ic_launcher_background'));
    expect(xml, contains('monochrome'));
    expect(xml, contains('ic_launcher_monochrome'));
  });

  test('monochrome 是纯白人物剪影（非模板占位图）', () async {
    final bytes = File(
      _resPath('mipmap-xxxhdpi', 'ic_launcher_monochrome'),
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();

    var opaque = 0;
    var white = 0;
    var colored = 0;
    for (var i = 0; i < px.length; i += 4) {
      final r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3];
      if (a <= 16) continue;
      opaque++;
      // 单色判据：三通道一致（灰度）。注意 rawRgba 是预乘 alpha，
      // 抗锯齿边缘的 RGB 会随 alpha 缩放，因此不能用「颜色种数」判断。
      final mx = [r, g, b].reduce((x, y) => x > y ? x : y);
      final mn = [r, g, b].reduce((x, y) => x < y ? x : y);
      if (mx - mn > 6) {
        colored++;
      }
      if (a > 200 && mx >= 250) white++;
    }

    expect(opaque, greaterThan(0), reason: '剪影不应为空');
    final ratio = opaque * 100.0 / (image.width * image.height);
    // 剪影应占据画面一部分（不是空白，也不是铺满整块底色）
    expect(
      ratio,
      inInclusiveRange(5, 60),
      reason: '非透明像素占比异常（${ratio.toStringAsFixed(1)}%），可能不是人物剪影',
    );
    expect(
      colored,
      lessThan(opaque * 0.02),
      reason: '存在明显彩色像素（$colored / $opaque），monochrome 应为单色剪影',
    );
    expect(
      white,
      greaterThan(opaque * 0.5),
      reason: '主体应为纯白（主题图标由系统着色），实际纯白 $white / $opaque',
    );
  });
}
