import 'src/data/persistence.dart';
import 'src/ui/persistence_host.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'src/app.dart';
import 'src/core/database/sakura_database.dart';
import 'src/data/book_store.dart';
import 'src/data/local_llm.dart';
import 'src/data/pet_store.dart';
import 'src/data/prefs.dart';
import 'src/data/stats_store.dart';
import 'src/features/ai_companion/inline_ai_reader_sheet.dart';
import 'src/features/book_source/replace_rule_store.dart';
import 'src/platform/display_service.dart';
import 'src/platform/native_bridge.dart';
import 'src/platform/perf_probe.dart';
import 'src/source/http_client.dart';
import 'src/source/source_store.dart';
import 'src/ui/reader/reader_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfProbe.start();
  // 系统栏模式不阻塞启动：晚几帧生效也没人看得出来
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final appDirsFuture = NativeBridge.appDirs();
  final permFuture = NativeBridge.hasStoragePermission();
  final appDirs = await appDirsFuture;
  final prefs = AppPrefs(dirsOverride: appDirs);
  // 首帧仅需轻量读取 settings.json；Keystore 凭据与自定义字体在首帧后并行水合
  await prefs.load(deferHeavyInit: true);
  // 恢复上次选的本地小模型（id 失效时管理器自动回落第一档）
  localModels.selectedId = prefs.aiLocalModelId;
  // 默认按屏幕支持的最高刷新率出帧（可在设置 → 性能里关掉）
  DisplayService.setHighRefresh(prefs.highRefreshRate);
  SourceHttpClient.defaultCookieDir = p.join(appDirs.files, 'cookies');

  final store = BookStore(dirsOverride: appDirs)..markLoadingPending();
  final sourceStore = SourceStore(dirsOverride: appDirs);
  final bookmarkStore = BookmarkStore(dirsOverride: appDirs);
  final statsStore = StatsStore(dirsOverride: appDirs);
  final petStore = PetStore(dirsOverride: appDirs);

  SourceStore.shared = sourceStore;
  BookmarkStore.shared = bookmarkStore;
  StatsStore.shared = statsStore;
  PetStore.shared = petStore;
  ReaderPage.defaultTextPurifier = ReplaceRuleStore.applyRules;
  ReaderPage.defaultAskAiHandler =
      (
        context, {
        required bookId,
        required bookTitle,
        required chapterTitle,
        required excerpt,
      }) {
        final book = store.byId(bookId);
        if (book == null) return;
        showInlineAiReaderSheet(
          context,
          book: book,
          chapterIndex: book.safeChapterIndex,
          charOffset: book.charOffset,
          selectedText: excerpt,
          prefs: prefs,
          bookmarkStore: bookmarkStore,
        );
      };
  persistenceFlushers = [
    prefs.flush,
    store.flush,
    sourceStore.flush,
    bookmarkStore.flush,
    statsStore.flush,
    petStore.flush,
  ];

  PerfProbe.mark('runApp');
  runApp(
    PersistenceHost(
      flushers: persistenceFlushers,
      child: SakuraApp(
        prefs: prefs,
        store: store,
        sourceStore: sourceStore,
        statsStore: statsStore,
        petStore: petStore,
        storagePermissionFuture: permFuture,
      ),
    ),
  );

  // 首帧渲染与开屏同时推进后台水合：数据库、书库、书源、书签、统计、桌宠、凭据与字体全部并行加载
  unawaited(
    _hydrateInBackground(
      appDirs: appDirs,
      prefs: prefs,
      store: store,
      sourceStore: sourceStore,
      bookmarkStore: bookmarkStore,
      statsStore: statsStore,
      petStore: petStore,
    ),
  );
}

Future<void> _hydrateInBackground({
  required AppDirs appDirs,
  required AppPrefs prefs,
  required BookStore store,
  required SourceStore sourceStore,
  required BookmarkStore bookmarkStore,
  required StatsStore statsStore,
  required PetStore petStore,
}) async {
  final dbFuture =
      SakuraDatabase.open(dbPath: p.join(appDirs.files, 'sakura_read_v2.db'))
          .then((db) async {
            SakuraDatabase.shared = db;
            store.attachDatabase(db);
            ReplaceRuleStore.shared.attachDatabase(db);
            await Future.wait(<Future<void>>[
              store.load(),
              ReplaceRuleStore.shared.load(),
            ]);
          });

  await Future.wait(<Future<void>>[
    prefs.completeDeferredLoad(),
    dbFuture,
    sourceStore.load().then((_) => sourceStore.ensureBuiltinSources()),
    bookmarkStore.load(),
    statsStore.load(),
    petStore.load(),
  ]);
  PerfProbe.mark('hydrated');
}
