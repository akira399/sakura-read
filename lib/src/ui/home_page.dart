import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_store.dart';
import '../data/pet_guide.dart';
import '../data/pet_store.dart';
import '../data/prefs.dart';
import '../data/stats_store.dart';
import '../platform/native_bridge.dart';
import '../platform/open_file_service.dart';
import '../platform/update_service.dart';
import '../source/source_store.dart';
import 'reader/reader_page.dart';
import 'recent_page.dart';
import 'settings_page.dart';
import 'shelf_page.dart';
import 'storage_permission_page.dart';
import 'update_dialog.dart';
import 'widgets/pet_guide_overlay.dart';
import 'widgets/pet_overlay.dart' show kPetEggActive;

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

  /// 启动后自动检查更新的延迟任务（见 [_scheduleAutoUpdateCheck]）。
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 「重看新手引导」：切回书架页（引导从书架开始，后续锚点也在书架 / 导航栏）
    kPetGuideReplay.addListener(_onGuideReplay);
    // 「用樱读打开文件」：接住系统文件打开事件（冷启动取一次 + 热启动持续监听）
    OpenFileService.instance
      ..onOpenFile = _handleOpenedFile
      ..listen();
    unawaited(_consumeLaunchFile());
    _scheduleAutoUpdateCheck();
    _check();
  }

  // ==================== 启动自动检查更新 ====================

  /// 启动后延迟几秒做一次静默更新检查。
  ///
  /// - 延迟的目的：避开开屏动画与首屏加载，不跟启动流程抢资源；
  /// - 失败静默：网络不好时不打扰用户（设置页可手动检查）；
  /// - 引导 / 彩蛋进行中不弹（避免打断首启流程与彩蛋体验）。
  void _scheduleAutoUpdateCheck() {
    // 测试环境：不发网络请求、不留 Timer（flutter test 的模拟时钟会有
    // 「pending timer」断言，且测试要完全离线可复现）。
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _updateCheckTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_autoCheckUpdate());
    });
  }

  Future<void> _autoCheckUpdate() async {
    if (!mounted) return;
    final prefs = widget.prefs;
    if (!prefs.autoCheckUpdate) return;
    // 还没同意条款（首启流程中）→ 不打扰；下次启动再查
    if (!prefs.agreementAccepted) return;
    // 新手引导 / 彩蛋进行中 → 不打断
    if (kPetGuideActive.value || kPetEggActive.value) return;

    final result = await UpdateService.instance.check();
    if (!mounted) return;
    if (result.status != UpdateCheckStatus.updateAvailable) return;
    final info = result.info!;
    // 用户对该版本点过「以后再说」→ 不再自动弹（设置页手动检查仍可见）
    if (prefs.skipUpdateVersion == info.version) return;
    // 检查期间状态可能又变了（开始引导等）
    if (kPetGuideActive.value || kPetEggActive.value) return;

    await showUpdateDialog(context, info: info, isAuto: true, prefs: prefs);
  }

  /// 冷启动：系统带文件启动时，取走路径并处理。
  Future<void> _consumeLaunchFile() async {
    final path = await OpenFileService.instance.consumeLaunchFile();
    if (path == null || !mounted) return;
    // 等首帧后再处理（书架页 / SnackBar 需要已挂载）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleOpenedFile(path);
    });
  }

  /// 分派被打开的文件：txt / epub → 导入书架并打开；json → 导入书源。
  Future<void> _handleOpenedFile(String path) async {
    if (!mounted) return;
    final ext = path.contains('.')
        ? path.substring(path.lastIndexOf('.') + 1).toLowerCase()
        : '';
    final messenger = ScaffoldMessenger.of(context);

    if (ext == 'json') {
      // 书源文件
      messenger.showSnackBar(const SnackBar(content: Text('正在导入书源…')));
      final report = await widget.sourceStore.importFromFile(path);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(report.summary)));
      setState(() => _index = 0); // 导入书源后停留书架无意义，回书架
      return;
    }

    if (ext == 'txt' || ext == 'epub') {
      // 已在书架：直接打开阅读器
      final existing = widget.store.books.where((b) => b.path == path).toList();
      if (existing.isNotEmpty && mounted) {
        setState(() => _index = 0);
        _openBook(existing.first.id);
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('正在导入…')));
      final result = await widget.store.importFile(path);
      if (!mounted) return;
      if (!result.success) {
        messenger.showSnackBar(SnackBar(content: Text(result.error ?? '导入失败')));
        return;
      }
      setState(() => _index = 0);
      _openBook(result.book!.id);
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text('不支持的文件类型：.$ext')));
  }

  /// 打开指定书籍的阅读器（从书架数据取进度）。
  void _openBook(String bookId) {
    final book = widget.store.byId(bookId);
    if (book == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          store: widget.store,
          prefs: widget.prefs,
          bookId: book.id,
          chapterIndex: book.safeChapterIndex,
          charOffset: book.charOffset,
        ),
      ),
    );
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
    _updateCheckTimer?.cancel();
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
