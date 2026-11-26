import 'dart:async';

import '../source/subscription_link.dart';
import '../source/http_client.dart';

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/icons/sakura_icons.dart';
import '../core/motion/sakura_motion.dart';
import '../core/theme/sakura_layout.dart';
import '../core/theme/sakura_tokens.dart';
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
import 'source/discover_page.dart';
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
    this.initialStorageGranted,
    this.storagePermissionFuture,
  });

  final BookStore store;
  final AppPrefs prefs;
  final SourceStore sourceStore;
  final StatsStore statsStore;
  final bool? initialStorageGranted;
  final Future<bool>? storagePermissionFuture;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  late bool? _granted = widget.initialStorageGranted;
  bool _usedInitialPermFuture = false;

  /// 懒加载页签：启动时仅构建首屏书架（0），其余页签首次切换时再挂载。
  final Set<int> _mountedTabs = <int>{0};

  /// 启动后自动检查更新的延迟任务（见 [_scheduleAutoUpdateCheck]）。
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 「重看新手引导」：切回书架页（引导从书架开始，后续锚点也在书架 / 导航栏）
    kPetGuideReplay.addListener(_onGuideReplay);
    kPetGuideStepId.addListener(_onGuideStepChanged);
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
    if (path.startsWith('legado:')) {
      try {
        final url = subscriptionUrl(path);
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导入书源订阅'),
            content: Text('是否获取并导入以下订阅？\n$url'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('导入'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        final client = SourceHttpClient();
        try {
          final response = await client.get(url, retries: 0);
          if (!response.ok) throw StateError('请求失败');
          final report = widget.sourceStore.importFromText(response.body);
          await widget.sourceStore.flush();
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(report.summary)));
          }
        } finally {
          client.close();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('订阅导入失败，请检查地址与网络')));
        }
      }
      return;
    }
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
      SakuraPageRoute(
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

  void _selectTab(int i) {
    _mountedTabs.add(i);
    if (_index != i) setState(() => _index = i);
  }

  /// 收到「重看新手引导」请求：把底部导航切回书架（第 1 格）。
  void _onGuideReplay() {
    if (mounted) _selectTab(0);
  }

  Future<void> _check() async {
    final future =
        (!_usedInitialPermFuture && widget.storagePermissionFuture != null)
        ? widget.storagePermissionFuture!
        : NativeBridge.hasStoragePermission();
    _usedInitialPermFuture = true;
    final granted = await future;
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
    kPetGuideStepId.removeListener(_onGuideStepChanged);
    _updateCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 引导走到「发现 / 最近 / 设置」时，底栏跟着切过去。
  ///
  /// 引导遮罩参与手势竞争：用户点底栏时引导虽然推进了，底栏自己的点击
  /// 偶尔会被竞技场取消，于是「点一下『发现』」看起来没反应。让引导驱动
  /// 切页后，高亮的页面与实际页面永远是同一个。
  void _onGuideStepChanged() {
    const tabs = {'shelf': 0, 'discover': 1, 'recent': 2, 'settings': 3};
    final target = tabs[kPetGuideStepId.value];
    if (target == null) return;

    void apply() {
      if (!mounted) return;
      // 步骤可能已经被推进/跳过，别把用户又拽回旧页面。
      if (tabs[kPetGuideStepId.value] != target) return;
      if (_index != target) _selectTab(target);
    }

    apply();
    // 同一次点击里底栏自己也会处理 onSelect（引导推进 + 底栏点击会竞争），
    // 它可能在本方法之后才写回旧下标，所以这一帧结束后再对一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
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
      // 底栏要「毛玻璃」观感：正文滚动到栏底下时能被模糊透出来，
      // 所以主体延伸到栏后面（用户反馈：底栏玻璃没效果、全是透明）。
      extendBody: true,
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
              statsStore: widget.statsStore,
            ),
            // 发现页（原在书架右上角，改到常驻底栏；仅首次切入时挂载，避免冷启动即扫源发请求）
            if (_mountedTabs.contains(1))
              DiscoverPage(
                bookStore: widget.store,
                prefs: widget.prefs,
                sourceStore: widget.sourceStore,
              )
            else
              const SizedBox.shrink(),
            if (_mountedTabs.contains(2))
              RecentPage(
                store: widget.store,
                prefs: widget.prefs,
                statsStore: widget.statsStore,
              )
            else
              const SizedBox.shrink(),
            if (_mountedTabs.contains(3))
              SettingsPage(
                store: widget.store,
                prefs: widget.prefs,
                sourceStore: widget.sourceStore,
                statsStore: widget.statsStore,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: widget.prefs,
        builder: (context, _) => _GuidedNavBar(
          index: _index,
          floatingDock: widget.prefs.floatingGlassDock,
          visualStyle: widget.prefs.visualStyle,
          onSelect: _selectTab,
        ),
      ),
    );
  }
}

/// 底部导航 + 每格独立的引导锚点（书架 / 发现 / 最近 / 设置）。
///
/// 2.5 升级：使用自绘双色图标 [SakuraNavIcon]，支持悬浮液态玻璃胶囊 Dock、
/// 蔚蓝轻漫斜切 HUD Dock，或全宽磨砂底栏。
class _GuidedNavBar extends StatelessWidget {
  const _GuidedNavBar({
    required this.index,
    required this.floatingDock,
    required this.visualStyle,
    required this.onSelect,
  });

  final int index;
  final bool floatingDock;
  final VisualStylePreset visualStyle;
  final ValueChanged<int> onSelect;

  /// 格数（与导航目标数量保持一致）。
  static const int _slots = 4;

  static const _tabs = [
    (SakuraNavGlyph.shelf, '书架'),
    (SakuraNavGlyph.discover, '发现'),
    (SakuraNavGlyph.recent, '最近'),
    (SakuraNavGlyph.settings, '设置'),
  ];

  /// 把整条栏按等分切成 [_slots] 格。
  Rect Function(Size) _cell(int slot) =>
      (size) => Rect.fromLTWH(
        size.width * slot / _slots,
        0,
        size.width / _slots,
        size.height,
      );

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isAnime = visualStyle == VisualStylePreset.animePop;
    final borderCol = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0F172A);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dockMaxWidth = SakuraLayout.dockMaxWidth(screenWidth);
    final shortLandscape = SakuraLayout.isShortLandscape(context);

    final row = SizedBox(
      height: shortLandscape ? 54 : 62,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _DockNavItem(
                glyph: _tabs[i].$1,
                label: _tabs[i].$2,
                selected: index == i,
                accent: isAnime ? const Color(0xFF38BDF8) : accent,
                inactiveColor: sakura.inkSecondary,
                isAnime: isAnime,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );

    final guidedRow = PetGuideTarget(
      id: 'nav_shelf',
      rectOf: _cell(0),
      child: PetGuideTarget(
        id: 'nav_discover',
        rectOf: _cell(1),
        child: PetGuideTarget(
          id: 'nav_recent',
          rectOf: _cell(2),
          child: PetGuideTarget(
            id: 'nav_settings',
            rectOf: _cell(3),
            child: row,
          ),
        ),
      ),
    );

    if (isAnime && floatingDock) {
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dockMaxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              bottomPad + (shortLandscape ? 6 : 10),
            ),
            child: Transform(
              transform: Matrix4.skewX(-0.08),
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF182235) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderCol, width: 1.8),
                  boxShadow: [
                    BoxShadow(color: borderCol, offset: const Offset(3.5, 4)),
                  ],
                ),
                child: Transform(
                  transform: Matrix4.skewX(0.08),
                  alignment: Alignment.center,
                  child: guidedRow,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (floatingDock) {
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dockMaxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              bottomPad + (shortLandscape ? 6 : 10),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: sakura.coverShadow.withValues(
                      alpha: isDark ? 0.45 : 0.20,
                    ),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xFF231E30).withValues(alpha: 0.78),
                                const Color(0xFF161320).withValues(alpha: 0.68),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.82),
                                const Color(0xFFFFF4F8).withValues(alpha: 0.68),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.90),
                        width: 1.0,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: guidedRow,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _GlassBar(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dockMaxWidth),
            child: guidedRow,
          ),
        ),
      ),
    );
  }
}

class _DockNavItem extends StatelessWidget {
  const _DockNavItem({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.accent,
    required this.inactiveColor,
    required this.isAnime,
    required this.onTap,
  });

  final SakuraNavGlyph glyph;
  final String label;
  final bool selected;
  final Color accent;
  final Color inactiveColor;
  final bool isAnime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTextColor = isAnime
        ? const Color(0xFF0F172A)
        : (isDark ? Colors.white : const Color(0xFF241B25));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? (isAnime
                      ? const Color(0xFF38BDF8)
                      : accent.withValues(alpha: isDark ? 0.22 : 0.14))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(isAnime ? 10 : 999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SakuraNavIcon(
                glyph: glyph,
                active: selected,
                color: selected ? activeTextColor : inactiveColor,
                accentColor: isAnime ? const Color(0xFFEC4899) : accent,
                size: 22,
              ),
              const SizedBox(height: 2.5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? activeTextColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏毛玻璃：真实模糊底下的内容 + 半透明着色 + 顶部高光描边。
///
/// 用户反馈「底栏什么玻璃没效果啊都是透明」：原先底栏背景是不透明纯色
/// （主题里 `navigationBarTheme.backgroundColor`），既没有模糊也看不出玻璃质感。
/// 这里用 [ImageFiltered] 做真实高斯模糊，再叠一层半透明主题色与细描边，
/// 配合 [Scaffold.extendBody] 就能看到正文从底栏下面透出来的玻璃效果。
class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sakura.glassFill,
            border: Border(
              top: BorderSide(color: sakura.glassBorder, width: 0.8),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
