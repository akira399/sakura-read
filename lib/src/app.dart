import 'package:flutter/material.dart';
import 'data/book_store.dart';
import 'data/pet_guide.dart';
import 'data/pet_store.dart';
import 'data/prefs.dart';
import 'data/stats_store.dart';
import 'source/source_store.dart';
import 'source/webview_engine.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';
import 'ui/splash_gate.dart';
import 'ui/widgets/pet_egg.dart';
import 'ui/widgets/pet_guide_overlay.dart';
import 'ui/widgets/pet_overlay.dart';

class SakuraApp extends StatelessWidget {
  const SakuraApp({
    super.key,
    required this.prefs,
    required this.store,
    required this.sourceStore,
    required this.statsStore,
    required this.petStore,
  });

  final AppPrefs prefs;
  final BookStore store;
  final SourceStore sourceStore;
  final StatsStore statsStore;
  final PetStore petStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        return MaterialApp(
          title: '樱读',
          debugShowCheckedModeBanner: false,
          // 根导航键：全局覆盖层（桌宠）用它打开面板（覆盖层 context 无 Navigator）
          navigatorKey: kRootNavigatorKey,
          // 路由观察者：引导锚点靠它感知「被其它页面盖住 / 重新露出」，
          // 从而支持跨页引导（放大镜 → 搜索页 → 返回 → 书架「＋」）
          navigatorObservers: [guideRouteObserver],
          theme: SakuraTheme.build(prefs.accent, Brightness.light),
          darkTheme: SakuraTheme.build(prefs.accent, Brightness.dark),
          themeMode: prefs.themeMode,
          // 隐藏 WebView 宿主：在线书正文渲染用（1×1 像素，仅被使用时构建）；
          // 全局悬浮桌宠叠加在所有页面之上（开屏 / 权限页隐藏，阅读器内自动隐藏）；
          // 彩蛋层（全黑锁定）在最顶层；激活时拦截返回键，只有重启才能恢复
          builder: (context, child) => WebViewEngineHost(
            child: ValueListenableBuilder<bool>(
              valueListenable: kPetEggActive,
              builder: (context, eggOn, _) => PopScope(
                // 彩蛋激活时禁止返回 / 手势退出 → 真正的"锁定"
                canPop: !eggOn,
                child: Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    // 新手引导进行中时隐藏常规桌宠（由引导层自己摆位）
                    ValueListenableBuilder<bool>(
                      valueListenable: kPetGuideActive,
                      builder: (context, guiding, _) => guiding
                          ? const SizedBox.shrink()
                          : PetOverlay(pet: petStore, hostReady: kPetHostReady),
                    ),
                    // 新手引导（首次启动）：自我介绍 + 指引点击
                    PetGuideHost(
                      pet: petStore,
                      hostReady: kPetHostReady,
                      seen: prefs.guideSeen,
                      onSeen: () => prefs.setGuideSeen(true),
                    ),
                    PetEggOverlay(active: kPetEggActive),
                  ],
                ),
              ),
            ),
          ),
          home: SplashGate(
            child: HomePage(
              store: store,
              prefs: prefs,
              sourceStore: sourceStore,
              statsStore: statsStore,
            ),
          ),
        );
      },
    );
  }
}
