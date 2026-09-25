// 樱读 README 头图（banner）生成器（**人工执行**，不进常规测试集）。
//
// 运行：flutter test tool/screenshots/banner_test.dart
// 产物：docs/images/banner.png（1200×520）与 docs/images/icon_showcase.png
//
// 设计：
//   - 背景 = 开屏立绘铺底 + 樱粉→深紫渐变压暗；
//   - 左侧 = 圆角 App 图标 + 标题「樱读 / Sakura Read」+ 标语 + 特性标签；
//   - 右侧 = 三张手机截图（书架 / 阅读器 / 彩蛋）倾斜排布。
//
// 注意：docs/images 与 tool/artwork 不在 pubspec assets 清单里，
// 必须用 `Image.memory` 直接从磁盘读字节（不能走 `Image.asset`）。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

const String _outDir = 'docs/images';
final GlobalKey _key = GlobalKey();

const double _bannerW = 1200;
const double _bannerH = 520;

/// 截图宽高比（截图生成器产出 1000×2165）。
const double _phoneAspect = 1000 / 2165;

Future<void> _loadFonts() async {
  final kai = await rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf');
  final icon = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  for (final family in ['LXGWWenKai', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(kai))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(Future.value(icon))).load();
  // 再空转一圈，确保字体注册的异步回调全部落地
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

Widget _wrap(Widget child) => RepaintBoundary(key: _key, child: child);

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('BANNER $name.png (${(data.lengthInBytes / 1024).round()} KB)');
  });
}

/// 等待真实异步（图片解码 / 字体注册）完成后，再推进若干渲染帧。
Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    for (var f = 0; f < 4; f++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }
}

/// 把磁盘图片全部预热进缓存（否则首帧渲染时来不及解码 → 黑屏）。
Future<void> _precacheAll(WidgetTester tester, List<String> paths) async {
  await tester.runAsync(() async {
    for (final p in paths) {
      final provider = MemoryImage(File(p).readAsBytesSync());
      final stream = provider.resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, synchronousCall) {
          if (!done.isCompleted) done.complete();
          stream.removeListener(listener);
        },
        onError: (e, s) {
          if (!done.isCompleted) done.complete();
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
  });
}

/// 磁盘图片 → Image（内存）。
Image _file(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  return Image.memory(
    File(path).readAsBytesSync(),
    width: width,
    height: height,
    fit: fit,
    gaplessPlayback: true,
  );
}

/// 手机截图（固定宽高，圆角 + 描边 + 阴影）。
Widget _phone(String path, double height) {
  final width = height * _phoneAspect;
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(height * 0.055),
      border: Border.all(color: Colors.white.withValues(alpha: .38), width: 3),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .50),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: _file(path),
  );
}

/// 特性小标签。
Widget _chip(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: .16),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: Colors.white.withValues(alpha: .32)),
  ),
  child: Text(
    text,
    style: const TextStyle(
      fontFamily: 'LXGWWenKai',
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: .5,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 字体注册必须在 setUpAll（假异步区之外）完成，测试体内调用不会真正生效
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('banner', (tester) async {
    tester.view.physicalSize = const Size(_bannerW, _bannerH);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 文件存在性兜底（缺失时给个占位，避免测试直接炸）
    String pick(String preferred, String fallback) =>
        File(preferred).existsSync() ? preferred : fallback;
    final mascot = pick('docs/images/mascot.png', 'docs/images/shelf.png');
    final reader = pick('docs/images/reader_day.png', 'docs/images/shelf.png');
    final egg = pick('docs/images/egg.png', 'docs/images/shelf.png');
    final icon = pick(
      'tool/artwork/icon_rounded_512.png',
      'tool/artwork/icon_square_512.png',
    );

    // 预热所有图片（避免首帧黑屏）
    await _precacheAll(tester, [
      'assets/images/splash_girl.jpg',
      mascot,
      reader,
      egg,
      icon,
    ]);

    await tester.pumpWidget(
      _wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          // 主题级字体：一次指定，全局生效（测试环境没有字体回退链，
          // 不指定的话中文会渲染成方框）
          theme: ThemeData(fontFamily: 'LXGWWenKai'),
          home: SizedBox(
            width: _bannerW,
            height: _bannerH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1) 立绘铺底 + 压暗
                _file('assets/images/splash_girl.jpg'),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF0170F1E),
                        Color(0xC7231526),
                        Color(0x992E1A33),
                      ],
                      stops: [0.0, 0.52, 1.0],
                    ),
                  ),
                ),
                // 2) 右侧三张截图（倾斜排布，右边部分出界更有张力）
                Positioned(
                  right: -48,
                  top: 46,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.rotate(
                        angle: -0.07,
                        child: _phone(mascot, 320),
                      ),
                      const SizedBox(width: 20),
                      Transform.translate(
                        offset: const Offset(0, 42),
                        child: Transform.rotate(
                          angle: 0.015,
                          child: _phone(reader, 320),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Transform.rotate(angle: 0.09, child: _phone(egg, 320)),
                    ],
                  ),
                ),
                // 3) 左侧文案
                Padding(
                  padding: const EdgeInsets.fromLTRB(54, 0, 0, 0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: _file(icon, width: 86, height: 86),
                          ),
                          const SizedBox(width: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '樱读',
                                style: TextStyle(
                                  fontFamily: 'LXGWWenKai',
                                  color: Colors.white,
                                  fontSize: 54,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8,
                                  height: 1.05,
                                ),
                              ),
                              Text(
                                'Sakura Read',
                                style: TextStyle(
                                  fontFamily: 'LXGWWenKai',
                                  color: Colors.white.withValues(alpha: .82),
                                  fontSize: 17,
                                  letterSpacing: 4,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '在樱花树下，慢慢读完一本书',
                        style: TextStyle(
                          fontFamily: 'LXGWWenKai',
                          color: Colors.white.withValues(alpha: .94),
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '二次元风格 · 开源 Android 小说阅读器',
                        style: TextStyle(
                          fontFamily: 'LXGWWenKai',
                          color: Colors.white.withValues(alpha: .70),
                          fontSize: 15,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _chip('TXT / EPUB'),
                          _chip('阅读 3.0 书源'),
                          _chip('在线搜书'),
                          _chip('看板娘桌宠'),
                          _chip('语音朗读'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    await _save(tester, 'banner');
  });

  // 图标展示图：三种形态并排（方形 / 圆角 / 圆形），模拟桌面观感
  testWidgets('icon showcase', (tester) async {
    const w = 1080.0;
    const h = 420.0;
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget tile(String path, String label) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _file(path, width: 200, height: 200, fit: BoxFit.contain),
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 17,
            color: Color(0xFF6B5B72),
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );

    // 预热图片
    await _precacheAll(tester, [
      'tool/artwork/icon_square_512.png',
      'tool/artwork/icon_rounded_512.png',
      'tool/artwork/icon_round_512.png',
    ]);

    await tester.pumpWidget(
      _wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'LXGWWenKai'),
          home: Container(
            width: w,
            height: h,
            color: const Color(0xFFFFF6FA),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '樱读 App 图标',
                  style: TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A2B3D),
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    tile('tool/artwork/icon_square_512.png', '方形'),
                    tile('tool/artwork/icon_rounded_512.png', '圆角（默认桌面）'),
                    tile('tool/artwork/icon_round_512.png', '圆形'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    await _save(tester, 'icon_showcase');
  });
}
