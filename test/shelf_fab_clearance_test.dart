// 回归：书架的「＋」按钮被底栏「设置」格子压住（线上反馈的误触 / 引导点不到）。
//
// 底栏用 extendBody 盖在正文之上，Scaffold 默认的 endFloat 会把 FAB 摆进
// 底栏区域：视觉上按钮与最右侧的「设置」重叠，点击时命中的是底栏，
// 新手引导因此永远点不到目标，还会连续劝导。
// 本用例把「FAB 必须完整位于底栏上方」钉死，并顺带校验引导锚点位置正确。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';
import 'package:sakura_read/src/theme/app_theme.dart';
import 'package:sakura_read/src/ui/shelf_page.dart';

void main() {
  testWidgets('书架「＋」完整位于底栏上方，且不会被底栏命中', (tester) async {
    late AppPrefs prefs;
    late BookStore store;
    late SourceStore sourceStore;
    late StatsStore statsStore;

    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('sakura_fab_clear');
      final dirs = AppDirs(files: tmp.path, cache: tmp.path);
      prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      store = BookStore(dirsOverride: dirs);
      await store.load();
      sourceStore = SourceStore(dirsOverride: dirs);
      await sourceStore.load();
      statsStore = StatsStore(dirsOverride: dirs);
      await statsStore.load();
    });

    // 引导锚点在挂载时注册，所以控制器必须早于 pumpWidget 存在。
    final controller = PetGuideController();
    addTearDown(controller.dispose);
    PetGuideController.current = controller;
    kPetGuideActive.value = true;
    addTearDown(() => kPetGuideActive.value = false);

    // 与 home_page 的装配一致：extendBody + 底栏（NavigationBar 默认 80 高）。
    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraTheme.build(prefs.accent, Brightness.light),
        home: Scaffold(
          extendBody: true,
          body: ShelfPage(
            store: store,
            prefs: prefs,
            sourceStore: sourceStore,
            statsStore: statsStore,
          ),
          bottomNavigationBar: const SizedBox(
            height: 80,
            child: ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final navTop = size.height - 80;
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(
      fab.bottom,
      lessThanOrEqualTo(navTop + 0.5),
      reason: '「＋」不能压到底栏上（否则点它命中的是「设置」）',
    );

    // 引导指向的锚点必须与按钮本身重合
    final anchor = controller.rectOf('shelf_add');
    expect(anchor, isNotNull, reason: '书架必须上报「＋」锚点');
    expect(
      (anchor!.center - fab.center).distance,
      lessThan(2),
      reason: '引导高亮框要和按钮对齐',
    );
  });
}
