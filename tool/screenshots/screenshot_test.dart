// 樱读 README 截图生成器（**人工执行**，不进常规测试集）。
//
// 原理：用 Flutter 测试环境的离屏渲染能力，把**真实界面**渲染成 PNG，
// 不需要启动手机 App（不干扰用户）。
//
// 运行：
//   flutter test tool/screenshots/screenshot_test.dart
//
// 产物：`docs/images/*.png`
//
// 测试环境与真机的两大差异（本工具做了对齐）：
//   ① 字体：测试环境没有系统字体回退链，未显式指定字体族的文字会渲染成方框。
//      这里把内置「霞鹜文楷」同时注册为 Roboto / LXGWWenKai / MaterialIcons
//      三类族名，保证中文、默认样式与图标都能正确绘制。
//   ② 异步：文件 IO / isolate 需要 runAsync 驱动真实时间，分页循环需要
//      多帧 pump 推进；本工具用 `_cycle()` 反复交替执行两者。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/app.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/reader/reader_page.dart';
import 'package:sakura_read/src/ui/widgets/pet_overlay.dart';

// ---------- 基本参数 ----------

const double _logicalW = 400;
const double _logicalH = 866;
const double _dpr = 2.5;

const String _outDir = 'docs/images';

final GlobalKey _shotKey = GlobalKey();

/// 一套已加载的 store。
class _Ctx {
  _Ctx({
    required this.prefs,
    required this.store,
    required this.sources,
    required this.stats,
    required this.pet,
    required this.bookIds,
  });

  final AppPrefs prefs;
  final BookStore store;
  final SourceStore sources;
  final StatsStore stats;
  final PetStore pet;

  /// 导入的书籍 id（按导入顺序）。
  final List<String> bookIds;
}

// ---------- 字体 ----------

Future<void> _loadFonts() async {
  final kaiBytes = await rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf');
  final iconBytes = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  // 中文字体：显式族名 + 兜底族名（覆盖 App 默认样式 / 阅读器设置）
  for (final family in ['LXGWWenKai', 'Roboto']) {
    final loader = FontLoader(family)..addFont(Future.value(kaiBytes));
    await loader.load();
  }
  // 图标字体：Material Icons
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(iconBytes));
  await icons.load();
}

// ---------- 环境与数据 ----------

/// 演示书籍清单（文件名即书架标题）。
const List<String> _demoBooks = [
  '星夜下的约定.txt',
  '春日告白练习.txt',
  '雨巷书店的夏天.txt',
  '深海图书馆.txt',
  '花火与纸飞机.txt',
];

Future<_Ctx> _setup(WidgetTester tester) async {
  late _Ctx ctx;
  await tester.runAsync(() async {
    final tmp = await Directory.systemTemp.createTemp('sakura_shots');
    final dirs = AppDirs(files: tmp.path, cache: tmp.path);

    final prefs = AppPrefs(dirsOverride: dirs);
    await prefs.load();
    prefs.setGuideSeen(true); // 不显示新手引导
    prefs.setAgreementAccepted(true); // 不显示首启条款页

    final store = BookStore(dirsOverride: dirs);
    await store.load();

    final sources = SourceStore(dirsOverride: dirs);
    await sources.load();
    try {
      await sources.ensureBuiltinSources();
    } catch (_) {
      // 资产缺失时忽略
    }

    final stats = StatsStore(dirsOverride: dirs);
    await stats.load();

    final pet = PetStore(dirsOverride: dirs);
    await pet.load();

    // 导入演示书籍（复制夹具 → 逐本导入）
    final ids = <String>[];
    final fixture = File('test/fixtures/novel_utf8.txt');
    if (fixture.existsSync()) {
      final bytes = fixture.readAsBytesSync();
      for (final fileName in _demoBooks) {
        final dst = File('${tmp.path}/$fileName');
        dst.writeAsBytesSync(bytes);
        final r = await store.importFile(dst.path);
        if (r.success) ids.add(r.book!.id);
      }
      // 一本 EPUB（带真实封面）
      final epub = File('test/fixtures/novel_epub3.epub');
      if (epub.existsSync()) {
        final dst = File('${tmp.path}/轻小说样例.epub');
        dst.writeAsBytesSync(epub.readAsBytesSync());
        final r = await store.importFile(dst.path);
        if (r.success) ids.add(r.book!.id);
      }
    }
    // 给前几本设置阅读进度（书架更有"人气"）
    if (ids.isNotEmpty) store.updateProgress(ids[0], chapter: 1, offset: 420);
    if (ids.length > 1) store.updateProgress(ids[1], chapter: 2, offset: 980);
    if (ids.length > 2) store.updateProgress(ids[2], chapter: 0, offset: 120);

    ctx = _Ctx(
      prefs: prefs,
      store: store,
      sources: sources,
      stats: stats,
      pet: pet,
      bookIds: ids,
    );
  });
  return ctx;
}

// ---------- 截图 ----------

Widget _wrap(Widget child) => RepaintBoundary(key: _shotKey, child: child);

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('$_outDir/$name.png');
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $name.png  (${(data.lengthInBytes / 1024).round()} KB)');
  });
}

/// 推进若干帧（虚拟时钟）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 一轮「真实异步 + 虚拟时钟」交替推进：
/// 真实等待让文件 IO / isolate 完成，pump 让 setState / 分页循环落地。
Future<void> _cycle(
  WidgetTester tester, {
  int ms = 250,
  int frames = 12,
}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await _pumpFrames(tester, frames: frames);
}

/// 阅读器等重异步页面的推进（多轮）。
Future<void> _drain(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await _cycle(tester, ms: 250, frames: 16);
  }
}

/// 等待真实异步（图片解码）完成 + 推进渲染帧。
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

/// 把磁盘图片全部预热进缓存（否则首帧渲染时来不及解码 → 空白）。
Future<void> _precacheAll(WidgetTester tester, List<String> assetPaths) async {
  await tester.runAsync(() async {
    for (final p in assetPaths) {
      final data = await rootBundle.load(p);
      final provider = MemoryImage(data.buffer.asUint8List());
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, sync) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
        onError: (e, s) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    }
  });
}

/// 测试收尾：销毁渲染树 + 耗尽防抖定时器（否则测试尾断言会报 pending timer）。
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 30)); // 桌宠乱跑 / 打瞌睡的巡检定时器
  kPetEggActive.value = false;
  _hidePet();
}

/// 桌宠显隐：光改 `kPetHostReady.value` 会被 `SplashGate` / `HomePage`
/// 的 `petMarkSplashDone()` / `petMarkHomeReady()` 重新覆盖；
/// 必须走这两个官方入口设置底层标志。
void _hidePet() {
  petMarkSplashDone();
  petMarkHomeReady(false);
}

void _showPet() {
  petMarkSplashDone();
  petMarkHomeReady(true);
}

Widget _app(_Ctx ctx) => SakuraApp(
  prefs: ctx.prefs,
  store: ctx.store,
  sourceStore: ctx.sources,
  statsStore: ctx.stats,
  petStore: ctx.pet,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  /// 统一视口（接近真机：顶部状态栏 + 底部手势条留白）。
  void configureView(WidgetTester tester) {
    tester.view.physicalSize = const Size(_logicalW * _dpr, _logicalH * _dpr);
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = FakeViewPadding(top: 40 * _dpr, bottom: 20 * _dpr);
    addTearDown(tester.view.reset);
  }

  // ---------- 1. 开屏（须第一个跑：SplashGate 每进程只播一次） ----------
  testWidgets('shot: 开屏', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    _hidePet();
    // 停在动画中段：立绘已淡入、标题已出现、尚未淡出
    await tester.pump(const Duration(milliseconds: 820));
    _hidePet();
    await _capture(tester, 'splash');
    await _finish(tester);
  });

  // ---------- 2. 空书架（看板娘特写） ----------
  testWidgets('shot: 空书架', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    for (final b in ctx.store.books.toList()) {
      ctx.store.removeById(b.id);
    }
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    await _pumpFrames(tester, frames: 8);
    _hidePet();
    await _capture(tester, 'shelf_empty');
    await _finish(tester);
  });

  // ---------- 3. 书架（带书 + 桌宠） ----------
  testWidgets('shot: 书架', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    // 桌宠挪到左下角，避免遮挡右下角「＋」
    ctx.pet.petX = 0.02;
    ctx.pet.petY = 0.66;
    _showPet();
    await _pumpFrames(tester, frames: 12);
    // 注意：截图前**不要**隐藏桌宠（用桌宠展示看板娘）
    await _capture(tester, 'shelf');
    await _finish(tester);
  });

  // ---------- 4. 阅读器（日间） ----------
  testWidgets('shot: 阅读器（日间）', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    if (ctx.bookIds.isEmpty) {
      markTestSkipped('没有可用的演示书籍');
      return;
    }
    ctx.prefs.setReaderBgIndex(0); // 纸白
    _hidePet();

    await tester.pumpWidget(
      _wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SakuraTheme.build(ctx.prefs.accent, Brightness.light),
          home: ReaderPage(
            store: ctx.store,
            prefs: ctx.prefs,
            bookId: ctx.bookIds.first,
          ),
        ),
      ),
    );
    await _drain(tester);
    await _capture(tester, 'reader_day');
    await _finish(tester);
  });

  // ---------- 5. 阅读器（夜间） ----------
  testWidgets('shot: 阅读器（夜间）', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    if (ctx.bookIds.isEmpty) {
      markTestSkipped('没有可用的演示书籍');
      return;
    }
    ctx.prefs.setReaderBgIndex(4); // 夜间
    _hidePet();

    await tester.pumpWidget(
      _wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SakuraTheme.build(ctx.prefs.accent, Brightness.dark),
          home: ReaderPage(
            store: ctx.store,
            prefs: ctx.prefs,
            bookId: ctx.bookIds.first,
          ),
        ),
      ),
    );
    await _drain(tester);
    await _capture(tester, 'reader_night');
    await _finish(tester);
  });

  // ---------- 6. 最近阅读 ----------
  testWidgets('shot: 最近阅读', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    await tester.tap(find.byIcon(Icons.history_outlined));
    await _pumpFrames(tester, frames: 10);
    _hidePet();
    await _capture(tester, 'recent');
    await _finish(tester);
  });
  // ---------- 7. 设置 ----------
  testWidgets('shot: 设置', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await _pumpFrames(tester, frames: 10);
    _hidePet();
    await _capture(tester, 'settings');
    await _finish(tester);
  });

  // ---------- 7b. 设置（底部：开源信息 / Made by akira399） ----------
  testWidgets('shot: 设置-开源信息', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await _pumpFrames(tester, frames: 10);
    _hidePet();
    // 滚到底部：把「开源信息」区块滚进视野
    await tester.scrollUntilVisible(
      find.text('开源信息'),
      260,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pump(const Duration(milliseconds: 120));
    await _pumpFrames(tester, frames: 10);
    _hidePet();
    await _capture(tester, 'settings_about');
    await _finish(tester);
  });

  // ---------- 8. 在线搜书（待输入） ----------
  testWidgets('shot: 在线搜书', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await _pumpFrames(tester, frames: 14);
    _hidePet();
    await _capture(tester, 'search_idle');
    await _finish(tester);
  });

  // ---------- 9. 彩蛋（全屏锁定） ----------
  testWidgets('shot: 彩蛋', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();
    kPetEggActive.value = true;
    await _pumpFrames(tester, frames: 14);
    _hidePet();
    await _capture(tester, 'egg');
    kPetEggActive.value = false;
    await _finish(tester);
  });

  // ---------- 10. 桌宠特写（书架留白处，用于 README「看板娘」区） ----------
  testWidgets('shot: 看板娘', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    _hidePet();

    await tester.pumpWidget(_wrap(_app(ctx)));
    await _cycle(tester);
    _hidePet();

    // 直接摆一个「看板娘立绘 + 台词气泡」，不依赖悬浮桌宠的显示条件
    // （悬浮桌宠的显隐由开屏/权限/阅读状态共同决定，截图场景下容易抖动）
    // 位置：画面中右偏下，落在书籍卡片之间的空白处
    ctx.pet.petX = 0.72;
    ctx.pet.petY = 0.30;
    _showPet();
    await _pumpFrames(tester, frames: 20);

    // 调试输出：确认桌宠层实际状态
    // ignore: avoid_print
    print(
      'DEBUG pet: hostReady=${kPetHostReady.value} '
      'guideActive=${kPetGuideActive.value} '
      'readerActive=${ctx.pet.readerActive} '
      'showPetInReader=${ctx.pet.showPetInReader} '
      'overlayFound=${find.byType(PetOverlay).evaluate().isNotEmpty} '
      'petImageFound=${find.image(const AssetImage('assets/images/pet_wave.png')).evaluate().length}',
    );

    await _capture(tester, 'mascot');
    await _finish(tester);
  });

  // ---------- 11. 桌宠立绘合集（六种表情，README 用） ----------
  testWidgets('shot: 表情合集', (tester) async {
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 预热图片
    await _precacheAll(tester, [
      'assets/images/pet_chibi.png',
      'assets/images/pet_wave.png',
      'assets/images/pet_read.png',
      'assets/images/pet_cheer.png',
      'assets/images/pet_sleep.png',
      'assets/images/pet_shy.png',
      'assets/images/pet_angry.png',
    ]);

    await tester.pumpWidget(
      _wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            // Material 底：避免裸 Text 继承 MaterialApp 最外层的调试用
            // DefaultTextStyle（红字 + 黄色双下划线，即"双黄线"）
            backgroundColor: const Color(0xFFFFF6FA),
            body: Container(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '看板娘表情差分',
                    style: TextStyle(
                      fontFamily: 'LXGWWenKai',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3A2B3D),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final face in [
                          ('assets/images/pet_chibi.png', '常态'),
                          ('assets/images/pet_wave.png', '挥手'),
                          ('assets/images/pet_read.png', '看书'),
                          ('assets/images/pet_cheer.png', '开心'),
                          ('assets/images/pet_sleep.png', '打瞌睡'),
                          ('assets/images/pet_shy.png', '害羞'),
                          ('assets/images/pet_angry.png', '生气'),
                        ])
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 用 Image.memory 直接读磁盘：
                              // Image.asset 在测试环境的首次解码时机不可控，
                              // 会出现「部分立绘空白」的问题
                              Image.memory(
                                File(face.$1).readAsBytesSync(),
                                height: 150,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                face.$2,
                                style: const TextStyle(
                                  fontFamily: 'LXGWWenKai',
                                  fontSize: 13,
                                  color: Color(0xFF6B5B72),
                                ),
                              ),
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
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);
    await _capture(tester, 'faces');
    await _finish(tester);
  });

  // ---------- 12. 首启条款页（同意后进新手引导） ----------
  testWidgets('shot: 首启条款', (tester) async {
    configureView(tester);
    final ctx = await _setup(tester);
    ctx.prefs.setAgreementAccepted(false); // 展示首启条款页
    _hidePet();

    await _precacheAll(tester, ['assets/images/pet_chibi.png']);

    await tester.pumpWidget(_wrap(_app(ctx)));
    _hidePet();
    await _settle(tester, rounds: 8);
    _hidePet();
    await _capture(tester, 'agreement');
    await _finish(tester);
  });
}
