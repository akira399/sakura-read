import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/credential_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/home_page.dart';
import 'package:sakura_read/src/ui/recent_page.dart';
import 'package:sakura_read/src/ui/settings_page.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';
import 'package:sakura_read/src/ui/source/discover_page.dart';
import 'package:sakura_read/src/ui/splash_gate.dart';

class _MockCreds extends CredentialStore {
  String? stored;
  int writeCount = 0;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async {
    writeCount++;
    stored = value;
  }
}

void main() {
  test('AppPrefs.load(deferHeavyInit: true) 在无遗留明文时零重写，在有旧明文时完成迁移剥离', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_pref_defer_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final file = File('${dir.path}/settings.json');

    // 1) 已迁入 Keystore 的现代配置文件：defer 加载 + completeDeferredLoad 不应重写 settings.json
    await file.writeAsString(jsonEncode({'v': 2, 'fontSize': 20}));
    await file.setLastModified(DateTime(2020, 1, 1));
    final cleanCreds = _MockCreds()
      ..stored = jsonEncode({
        'credentialVersion': 1,
        'aiApiKey': 'sk-modern',
        'webdavPass': '',
      });
    final prefs = AppPrefs(dirsOverride: dirs, credentials: cleanCreds);
    await prefs.load(deferHeavyInit: true);
    expect(prefs.fontSize, 20);
    expect(prefs.aiApiKey, isEmpty);

    await prefs.completeDeferredLoad();
    expect(prefs.aiApiKey, 'sk-modern');
    expect(cleanCreds.writeCount, 0);
    expect(file.lastModifiedSync().year, 2020);

    // 2) 含旧明文密钥：completeDeferredLoad 后迁移进 Keystore 并从 JSON 剥离
    await file.writeAsString(
      jsonEncode({'v': 1, 'aiApiKey': 'sk-legacy', 'webdavPass': 'dav-pw'}),
    );
    final legacyCreds = _MockCreds();
    final legacyPrefs = AppPrefs(dirsOverride: dirs, credentials: legacyCreds);
    await legacyPrefs.load(deferHeavyInit: true);
    await legacyPrefs.completeDeferredLoad();
    expect(legacyCreds.writeCount, 2);
    final decoded = jsonDecode(await file.readAsString()) as Map;
    expect(decoded.containsKey('aiApiKey'), isFalse);
    expect(decoded.containsKey('webdavPass'), isFalse);
  });

  test('SourceStore.ensureBuiltinSources 二次调用在内置源无变更时零写盘、零通知', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('sakura_builtin_noop_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final store = SourceStore(dirsOverride: dirs);
    await store.load();

    final firstChanged = await store.ensureBuiltinSources();
    expect(firstChanged, greaterThan(0));
    final sourcesFile = File('${dir.path}/book_sources.json');
    expect(sourcesFile.existsSync(), isTrue);
    await sourcesFile.setLastModified(DateTime(2021, 5, 1));

    var notifyCount = 0;
    store.addListener(() => notifyCount++);

    final secondChanged = await store.ensureBuiltinSources();
    expect(secondChanged, 0);
    expect(notifyCount, 0);
    expect(sourcesFile.lastModifiedSync().year, 2021);
  });

  testWidgets('HomePage 懒加载次级页签：启动仅构建书架，切页后再按需挂载发现/最近/设置', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('sakura_lazy_tabs_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final prefs = AppPrefs(dirsOverride: dirs);
    final store = BookStore(dirsOverride: dirs);
    final sourceStore = SourceStore(dirsOverride: dirs);
    final statsStore = StatsStore(dirsOverride: dirs);
    await tester.runAsync(() async {
      await prefs.load();
      await store.load();
      await sourceStore.load();
      await statsStore.load();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: HomePage(
          store: store,
          prefs: prefs,
          sourceStore: sourceStore,
          statsStore: statsStore,
          initialStorageGranted: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShelfPage), findsOneWidget);
    expect(find.byType(DiscoverPage), findsNothing);
    expect(find.byType(RecentPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentPage), findsOneWidget);
    expect(find.byType(DiscoverPage), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('SplashGate 支持自定义短时长并支持点击轻触跳过', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(
          forcePlay: true,
          duration: Duration(milliseconds: 950),
          child: Scaffold(body: Text('已进入书架')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('樱 读'), findsOneWidget);

    await tester.tap(find.text('樱 读'));
    await tester.pump();
    // 跳过直接挂起下层并从 82% 淡出（余约 170ms）
    expect(find.text('已进入书架'), findsOneWidget);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('樱 读'), findsNothing);
  });
}
