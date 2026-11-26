import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/features/settings/appearance_studio_page.dart';
import 'package:sakura_read/src/features/settings/reading_defaults_page.dart';
import 'package:sakura_read/src/features/settings/system_about_page.dart';
import 'package:sakura_read/src/features/settings/tts_settings_page.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/settings_page.dart';

void main() {
  late Directory tmpDir;
  late AppPrefs prefs;
  late BookStore store;
  late SourceStore sourceStore;
  late StatsStore statsStore;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('sakura_settings_hub_');
    final dirs = AppDirs(files: tmpDir.path, cache: tmpDir.path);
    prefs = AppPrefs(dirsOverride: dirs);
    await prefs.load();
    store = BookStore(dirsOverride: dirs);
    await store.load();
    sourceStore = SourceStore(dirsOverride: dirs);
    await sourceStore.load();
    statsStore = StatsStore(dirsOverride: dirs);
    await statsStore.load();

    store.addOnline(
      Book(
        id: 'sample-book',
        title: '樱花茶屋',
        author: '作者A',
        format: BookFormat.txt,
        path: '/tmp/tea.txt',
        chapters: [ChapterRef(title: '序章', charCount: 400)],
      ),
    );
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  Widget buildHub({double topPadding = 32}) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        return MaterialApp(
          theme: SakuraTheme.build(prefs.accent, Brightness.light),
          darkTheme: SakuraTheme.build(prefs.accent, Brightness.dark),
          themeMode: prefs.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: EdgeInsets.only(top: topPadding),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: SettingsPage(
            store: store,
            prefs: prefs,
            sourceStore: sourceStore,
            statsStore: statsStore,
          ),
        );
      },
    );
  }

  testWidgets('Settings 2.5 主控台分组清爽渲染，顶栏安全区不重叠，日夜间一键切换', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const statusBarTop = 36.0;
    await tester.pumpWidget(buildHub(topPadding: statusBarTop));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    final titleRect = tester.getRect(find.text('书房设置'));
    expect(titleRect.top, greaterThanOrEqualTo(statusBarTop));

    expect(find.text('书房视觉与排版'), findsOneWidget);
    expect(find.text('小樱与 AI 伴读'), findsOneWidget);
    expect(find.text('书源与阅读记录'), findsOneWidget);

    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.dark);
    expect(find.text('日间'), findsOneWidget);

    await tester.tap(find.text('日间'));
    await tester.pumpAndSettle();
    expect(prefs.themeMode, ThemeMode.light);

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('可从设置枢纽进入外观风格工坊并切换 Style B / Style C / 独立开关', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildHub());
    await tester.pumpAndSettle();

    await tester.tap(find.text('书房风格与外观'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceStudioPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    // 切换到「京都和纸 · 樱木层板」（Style B）
    await tester.tap(find.text('京都和纸'));
    await tester.pumpAndSettle();
    expect(prefs.visualStyle, VisualStylePreset.kyotoWashi);
    expect(prefs.shelfPlankStyle, ShelfPlankStyle.warmWood);

    // 切换到「蔚蓝轻漫」（Style C）
    await tester.tap(find.text('蔚蓝轻漫'));
    await tester.pumpAndSettle();
    expect(prefs.visualStyle, VisualStylePreset.animePop);
    expect(prefs.shelfPlankStyle, ShelfPlankStyle.obiBand);

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('可正常进入阅读排版、听书与系统关于二级页面', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildHub());
    await tester.pumpAndSettle();

    await tester.tap(find.text('阅读默认排版'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingDefaultsPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    Navigator.of(tester.element(find.byType(ReadingDefaultsPage))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('听书与离线语音'));
    await tester.pumpAndSettle();
    expect(find.byType(TtsSettingsPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    Navigator.of(tester.element(find.byType(TtsSettingsPage))).pop();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('性能、存储与关于'), 250);
    await tester.ensureVisible(find.text('性能、存储与关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('性能、存储与关于'));
    await tester.pumpAndSettle();
    expect(find.byType(SystemAboutPage), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
  });
}
