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
import 'src/ui/splash_gate.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  PerfProbe.start();
  // 系统栏模式与原生通道查询不阻塞首帧：runApp 立即同步触发首帧渲染
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final appDirsFuture = NativeBridge.appDirs();
  final permFuture = NativeBridge.hasStoragePermission();

  final prefs = AppPrefs()..markInitialLoadPending();
  final store = BookStore()..markLoadingPending();
  final sourceStore = SourceStore();
  final bookmarkStore = BookmarkStore();
  final statsStore = StatsStore();
  final petStore = PetStore();

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

  // 首帧画出前先异步预解码开屏插画（不卡住同步建树，有 350ms 兜底超时）
  unawaited(_prewarmSplashArt(binding));

  // 首帧画出后分两级在后台并行水合，避免与首屏和书架抢占主线程资源
  unawaited(
    _bootstrapAndHydrate(
      appDirsFuture: appDirsFuture,
      prefs: prefs,
      store: store,
      sourceStore: sourceStore,
      bookmarkStore: bookmarkStore,
      statsStore: statsStore,
      petStore: petStore,
    ),
  );
}

Future<void> _prewarmSplashArt(WidgetsBinding binding) async {
  try {
    final view = binding.platformDispatcher.views.firstOrNull;
    final dpr = (view != null && view.devicePixelRatio > 0)
        ? view.devicePixelRatio
        : 2.0;
    final logicalSize = view != null
        ? view.physicalSize / dpr
        : const Size(400, 800);
    final cacheWidth = splashArtCacheWidth(logicalSize, dpr);
    final provider = ResizeImage(
      const AssetImage(kSplashArtAsset),
      width: cacheWidth,
    );
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_, _) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    try {
      await completer.future.timeout(const Duration(milliseconds: 350));
    } finally {
      stream.removeListener(listener);
    }
  } catch (_) {
    // 兜底：任何异常都不阻塞首帧放行
  } finally {
    binding.allowFirstFrame();
  }
}

Future<void> _bootstrapAndHydrate({
  required Future<AppDirs> appDirsFuture,
  required AppPrefs prefs,
  required BookStore store,
  required SourceStore sourceStore,
  required BookmarkStore bookmarkStore,
  required StatsStore statsStore,
  required PetStore petStore,
}) async {
  final appDirs = await appDirsFuture;
  SourceHttpClient.defaultCookieDir = p.join(appDirs.files, 'cookies');

  // 阶段 1（书架主路径）：优先加载设置、数据库、书架书单与桌宠
  await prefs.load(dirs: appDirs, deferHeavyInit: true);
  DisplayService.setHighRefresh(prefs.highRefreshRate);

  final db = await SakuraDatabase.open(
    dbPath: p.join(appDirs.files, 'sakura_read_v2.db'),
  );
  SakuraDatabase.shared = db;
  store.attachDatabase(db);
  ReplaceRuleStore.shared.attachDatabase(db);

  await Future.wait(<Future<void>>[store.load(), petStore.load()]);
  PerfProbe.mark('shelfReady');

  // 阶段 2（次要数据）：后台静默补齐凭据/字体/净化规则/书源/书签/统计
  await Future.wait(<Future<void>>[
    prefs.completeDeferredLoad(),
    ReplaceRuleStore.shared.load(),
    sourceStore.load().then((_) => sourceStore.ensureBuiltinSources()),
    bookmarkStore.load(),
    statsStore.load(),
  ]);
  localModels.selectedId = prefs.aiLocalModelId;
  PerfProbe.mark('hydrated');
}
