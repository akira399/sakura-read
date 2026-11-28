import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/app_info.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/features/settings/about_page.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/theme/app_theme.dart';

void main() {
  testWidgets('关于页面渲染标语、版本号、检查更新、GitHub/酷安主页、GPL-3.0 协议与免责声明', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late Directory tmpDir;
    late AppPrefs prefs;
    await tester.runAsync(() async {
      tmpDir = Directory.systemTemp.createTempSync('sakura_about_test_');
      prefs = AppPrefs(
        dirsOverride: AppDirs(files: tmpDir.path, cache: tmpDir.path),
      );
      await prefs.load();
    });
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        home: AboutPage(prefs: prefs),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('关于樱读'), findsOneWidget);
    expect(find.text('樱读 · Sakura Read'), findsOneWidget);
    expect(find.text(AppInfo.slogan), findsOneWidget);
    expect(find.text('v${AppInfo.version}'), findsWidgets);
    expect(find.text('检查新版本'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('GitHub 开源仓库'), 250);
    expect(find.text(AppInfo.repo), findsOneWidget);
    expect(find.text(AppInfo.coolapk), findsOneWidget);

    await tester.scrollUntilVisible(find.text('开源协议：GNU GPL-3.0'), 250);
    expect(find.text('开源协议：GNU GPL-3.0'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('引用致谢'), 250);
    expect(find.text('引用致谢'), findsOneWidget);
    // 默认折叠，点击后才展开个人开源项目与主页致谢
    expect(find.text('AzukiReader'), findsNothing);
    await tester.tap(find.text('引用致谢'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('AzukiReader'), 250);
    expect(find.text('AzukiReader'), findsOneWidget);
    expect(find.text('Wenku8_Flutter'), findsOneWidget);
    expect(find.text('米安第一深情'), findsOneWidget);
    expect(find.textContaining('ilanzou'), findsNothing);
    expect(find.text('Google LiteRT-LM'), findsNothing);

    await tester.scrollUntilVisible(find.text('免责声明'), 250);
    expect(find.text('免责声明'), findsOneWidget);
    expect(find.textContaining('GNU GPL-3.0'), findsWidgets);
  });
}
