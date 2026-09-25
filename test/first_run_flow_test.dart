// 首启全流程回归：条款页 → 勾选同意 → 新手引导自动开始 → 跳过落盘。
//
// 与 agreement_gate_render_test 的差别：这里跑的是**真实 App 装配**
// （SakuraApp + 真实的 prefs/骨架），验证「同意后引导自动开始」在真实的
// MaterialApp.builder 层级里确实生效——引导层挂在 Navigator 之外，
// 曾经出过 Positioned / 双黄线一类只在这种真实层级下暴露的问题。
//
// 回归背景（用户反馈「我这里已经没有新手引导了」）：用户设备上残留了
// 旧版本的「已看过引导」标记（guideSeen=true），更新后同意了新条款，
// 但引导（设计上只看一次）不会重播。本测试把正确的时序钉死：
// 全新状态（guideSeen=false）下，同意条款 → 引导必须自动开始。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/app.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  testWidgets('首启全流程：同意条款后，新手引导自动开始', (tester) async {
    late AppPrefs prefs;
    late BookStore store;
    late SourceStore sourceStore;
    late StatsStore statsStore;
    late PetStore petStore;

    // 真实文件 IO 需要在 runAsync 中执行（测试环境是模拟时钟）。
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('sakura_first_run');
      final dirs = AppDirs(files: tmp.path, cache: tmp.path);
      prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      store = BookStore(dirsOverride: dirs);
      await store.load();
      sourceStore = SourceStore(dirsOverride: dirs);
      await sourceStore.load();
      statsStore = StatsStore(dirsOverride: dirs);
      await statsStore.load();
      petStore = PetStore(dirsOverride: dirs);
      await petStore.load();
    });

    await tester.pumpWidget(
      SakuraApp(
        prefs: prefs,
        store: store,
        sourceStore: sourceStore,
        statsStore: statsStore,
        petStore: petStore,
      ),
    );
    // 开屏动画（约 1.5s）+ 权限检查：跑过这些帧后引导宿主才「就绪」。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1600));

    // 全新状态：条款页在，引导还没开始。
    expect(find.text('欢迎来到樱读'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
    expect(kPetGuideActive.value, isFalse);

    // 勾选 + 同意。
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    // 同意后：条款页消失 + 引导自动开始（小樱出场）。
    expect(prefs.agreementAccepted, isTrue);
    expect(find.text('同意并继续'), findsNothing);
    expect(kPetGuideActive.value, isTrue, reason: '同意条款后引导应自动开始');
    expect(find.text('跳过引导'), findsOneWidget);

    // 跳过 → 引导关闭 + 「已看过」标记落在 prefs 上。
    await tester.tap(find.text('跳过引导'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(kPetGuideActive.value, isFalse);
    expect(prefs.guideSeen, isTrue);

    // 收尾：销毁渲染树并排空定时器。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('升级用户（旧版看过引导）同意条款后，引导也开始', (tester) async {
    late AppPrefs prefs;
    late BookStore store;
    late SourceStore sourceStore;
    late StatsStore statsStore;
    late PetStore petStore;

    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('sakura_upgrade_run');
      final dirs = AppDirs(files: tmp.path, cache: tmp.path);
      prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      // 模拟旧版本遗留状态：看过引导、但没同意过（本版本新增的）条款。
      prefs.setGuideSeen(true);
      store = BookStore(dirsOverride: dirs);
      await store.load();
      sourceStore = SourceStore(dirsOverride: dirs);
      await sourceStore.load();
      statsStore = StatsStore(dirsOverride: dirs);
      await statsStore.load();
      petStore = PetStore(dirsOverride: dirs);
      await petStore.load();
    });

    await tester.pumpWidget(
      SakuraApp(
        prefs: prefs,
        store: store,
        sourceStore: sourceStore,
        statsStore: statsStore,
        petStore: petStore,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1600));

    // 条款页在（未同意过）；引导没被旧标记之外的任何原因误触发。
    expect(find.text('同意并继续'), findsOneWidget);
    expect(kPetGuideActive.value, isFalse);

    // 同意 → 引导也必须开始（旧「已看过」标记被重置）。
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(prefs.agreementAccepted, isTrue);
    expect(prefs.guideSeen, isFalse, reason: '同意条款时应重置「已看过」旧标记');
    expect(kPetGuideActive.value, isTrue, reason: '升级用户同意条款后引导也应开始');
    expect(find.text('跳过引导'), findsOneWidget);

    await tester.tap(find.text('跳过引导'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(prefs.guideSeen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
  });
}
