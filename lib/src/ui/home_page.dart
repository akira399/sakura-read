import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_store.dart';
import '../data/pet_guide.dart';
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
    // 「重看新手引导」：切回书架页（引导从书架开始，后续锚点也在书架 / 导航栏）
    kPetGuideReplay.addListener(_onGuideReplay);
    _check();
  }

  /// 收到「重看新手引导」请求：把底部导航切回书架（第 1 格）。
  void _onGuideReplay() {
    if (mounted && _index != 0) setState(() => _index = 0);
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
    kPetGuideReplay.removeListener(_onGuideReplay);
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
      bottomNavigationBar: _GuidedNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 底部导航 + 每格独立的引导锚点（书架 / 最近 / 设置）。
///
/// 三格都在**常驻导航栏**上，因此引导要求用户点击时不会导致页面结构失效——
/// 这是引导设计的硬约束（指向会跳页的按钮会让后续步骤锚点消失）。
class _GuidedNavBar extends StatelessWidget {
  const _GuidedNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  /// 把整条栏按三等分切成三格（每格 = 1/3 宽）。
  Rect Function(Size) _cell(int slot) =>
      (size) =>
          Rect.fromLTWH(size.width * slot / 3, 0, size.width / 3, size.height);

  @override
  Widget build(BuildContext context) {
    return PetGuideTarget(
      id: 'nav_shelf',
      rectOf: _cell(0),
      child: PetGuideTarget(
        id: 'nav_recent',
        rectOf: _cell(1),
        child: PetGuideTarget(
          id: 'nav_settings',
          rectOf: _cell(2),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onSelect,
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
      ),
    );
  }
}
