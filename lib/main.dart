import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/data/book_store.dart';
import 'src/data/local_llm.dart';
import 'src/data/pet_store.dart';
import 'src/data/prefs.dart';
import 'src/data/stats_store.dart';
import 'src/platform/perf_probe.dart';
import 'src/platform/display_service.dart';
import 'src/source/source_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfProbe.start();
  // 系统栏模式不阻塞启动：晚几帧生效也没人看得出来
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final prefs = AppPrefs();
  // 设置要先读：主题/刷新率/本地模型都依赖它，本身是一次很小的 JSON 读
  await prefs.load();
  // 恢复上次选的本地小模型（id 失效时管理器自动回落第一档）
  localModels.selectedId = prefs.aiLocalModelId;
  // 默认按屏幕支持的最高刷新率出帧（可在设置 → 性能里关掉）
  DisplayService.setHighRefresh(prefs.highRefreshRate);
  // 各 store 互不依赖：并行读盘，省掉「一个读完再读下一个」的串行等待
  final store = BookStore();
  final sourceStore = SourceStore();
  final bookmarkStore = BookmarkStore();
  final statsStore = StatsStore();
  final petStore = PetStore();
  await Future.wait(<Future<void>>[
    store.load(),
    sourceStore.load(),
    bookmarkStore.load(),
    statsStore.load(),
    petStore.load(),
  ]);
  await sourceStore.ensureBuiltinSources();
  SourceStore.shared = sourceStore;
  BookmarkStore.shared = bookmarkStore;
  StatsStore.shared = statsStore;
  PetStore.shared = petStore;
  runApp(
    SakuraApp(
      prefs: prefs,
      store: store,
      sourceStore: sourceStore,
      statsStore: statsStore,
      petStore: petStore,
    ),
  );
}
