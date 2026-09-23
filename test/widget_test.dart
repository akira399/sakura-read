import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/app.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  testWidgets('应用可以启动并显示书架页', (tester) async {
    late AppPrefs prefs;
    late BookStore store;
    late SourceStore sourceStore;
    late StatsStore statsStore;
    late PetStore petStore;

    // 真实文件 IO 需要在 runAsync 中执行（测试环境是模拟时钟）。
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('sakura_read_test');
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('书架'), findsWidgets);
    expect(find.text('樱读'), findsWidgets);
    expect(find.text('书架还空着呢'), findsWidgets);
  });
}
