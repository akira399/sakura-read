import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_store.dart';
import '../data/pet_store.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../platform/native_bridge.dart';
import '../source/source_store.dart';
import 'recent_page.dart';
import 'settings_page.dart';
import 'shelf_page.dart';
import 'storage_permission_page.dart';
import 'widgets/pet_guide_overlay.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.prefs,
    required this.sourceStore,
    required this.statsStore,
  });

  final BookStore store;
  final AppPrefs prefs;
  final SourceStore sourceStore;
  final StatsStore statsStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final granted = await NativeBridge.hasStoragePermission();
    if (mounted) {
      setState(() => _granted = granted);
      // 权限就绪状态通知桌宠宿主（桌宠 = 开屏结束 + 权限就绪 才显示）
      petMarkHomeReady(granted);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    if (granted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!granted) {
      return StoragePermissionPage(onRecheck: _check);
    }
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: IndexedStack(
          index: _index,
          children: [
            ShelfPage(
              store: widget.store,
              prefs: widget.prefs,
              sourceStore: widget.sourceStore,
            ),
            RecentPage(
              store: widget.store,
              prefs: widget.prefs,
              statsStore: widget.statsStore,
            ),
            SettingsPage(
              store: widget.store,
              prefs: widget.prefs,
              sourceStore: widget.sourceStore,
              statsStore: widget.statsStore,
            ),
          ],
        ),
      ),
      bottomNavigationBar: PetGuideTarget(
        id: 'nav_settings',
        // 只高亮第三格（设置）那一块
        rectOf: (size) =>
            Rect.fromLTWH(size.width * 2 / 3, 0, size.width / 3, size.height),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories),
              label: '书架',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: '最近',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
