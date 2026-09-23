import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/data/book_store.dart';
import 'src/data/pet_store.dart';
import 'src/data/prefs.dart';
import 'src/data/stats_store.dart';
import 'src/source/source_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = AppPrefs();
  await prefs.load();
  final store = BookStore();
  await store.load();
  final sourceStore = SourceStore();
  await sourceStore.load();
  await sourceStore.ensureBuiltinSources();
  SourceStore.shared = sourceStore;
  final bookmarkStore = BookmarkStore();
  await bookmarkStore.load();
  BookmarkStore.shared = bookmarkStore;
  final statsStore = StatsStore();
  await statsStore.load();
  StatsStore.shared = statsStore;
  final petStore = PetStore();
  await petStore.load();
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
