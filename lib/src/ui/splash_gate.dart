import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/pet_store.dart';
import 'widgets/sakura_petals.dart';

/// 冷启动开屏动画：樱花 logo「绽放」+ 标题浮现 + 花瓣飘落，最后淡出进入应用。
///
/// - 前面不再有静态 logo 阶段（原生闪屏只保留纯色底），直接进入绽放动画；
/// - 仅在进程首次启动时播放一次，时长约 1.5s。
///
/// 性能要点（「开屏太卡」的修复）：
/// - 开屏播放期间**不构建**下层页面：书架、封面解码、毛玻璃都在开屏结束前
///   才挂载，避免首帧把整屏 UI 的构建/布局/光栅化都压在开屏的帧预算里；
/// - 立绘不再逐帧改 `Opacity`（整屏 saveLayer 很贵），改成「不透明立绘 + 逐帧
///   淡出的纯色/渐变蒙版」，蒙版是一块纯色 quad，混合成本极低；
/// - 立绘的缩放变换放在 `RepaintBoundary` 外层，光栅缓存可复用；
/// - 三个阶段各自只刷新自己的 [ValueNotifier]（绽放 / 文字 / 淡出），互不牵连。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.forcePlay = false});

  final Widget child;

  /// 忽略「进程内只播一次」的限制，强制播一遍（测试 / 调试用）。
  @visibleForTesting
  final bool forcePlay;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  /// 每个进程只播放一次。
  static bool _played = false;

  /// 开屏总时长。
  static const int _durationMs = 1500;

  /// 单帧最多推进多少毫秒。
  ///
  /// 冷启动第一帧通常很慢（解码立绘、读设置、建库），引擎会把这段停顿一次性
  /// 算进下一次帧回调的时间戳里 —— 下一帧直接跳 1 秒以上。AnimationController
  /// 拿这个跳变去算进度，就会「一帧把整段动画播完」，表现出来就是开屏动画没了。
  /// 所以这里不用 AnimationController 的帧时间戳，改为自己累加，并把单帧增量
  /// 截断在 250ms 内：哪怕遇到再大的跳变，动画也只按正常速度往前走。
  static const int _maxFrameStepMs = 250;

  /// 播到这个进度就把下层页面挂上来。
  ///
  /// 下层页面（书架 + 封面 + 毛玻璃导航栏）的首次构建/光栅化实测要 150ms 以上，
  /// 所以卡在「文字已浮现完、还没开始淡出」的静止窗口里挂载：这段被占掉的
  /// 时间屏幕上基本只有立绘和花瓣，看不出停顿。
  static const double _childMountAt = .62;

  late bool _show = widget.forcePlay || !_played;
  bool _childMounted = false;

  /// 绽放进度（0 → 1）：只在前 30% 的时间段里更新。
  final ValueNotifier<double> _bloom = ValueNotifier<double>(1);

  /// 文字浮现用的原始进度 t：只在 20% ~ 70% 之间更新。
  final ValueNotifier<double> _text = ValueNotifier<double>(0);

  /// 淡出进度（0 → 1）：只在最后 24% 的时间段里更新。
  final ValueNotifier<double> _fade = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker(_onTick);

  int _accMs = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (_show) {
      _played = true;
      _bloom.value = 0;
      _ticker.start();
    } else {
      // 进程内二次进入（没播开屏）：直接放行
      petMarkSplashDone();
    }
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastElapsed).inMilliseconds;
    _lastElapsed = elapsed;
    if (delta <= 0) return;
    _accMs += delta > _maxFrameStepMs ? _maxFrameStepMs : delta;
    final t = (_accMs / _durationMs).clamp(0.0, 1.0);

    // 分阶段刷新：同一时刻只有一个 ValueNotifier 在变，避免整屏重建。
    if (t < .32) {
      _bloom.value = Curves.easeOutBack.transform((t / .30).clamp(0.0, 1.0));
    } else if (_bloom.value < 1) {
      _bloom.value = 1;
    }
    if (t > .20 && t < .70) {
      _text.value = t;
    }
    if (t >= .80) {
      _fade.value = Curves.easeInOut.transform(
        ((t - .80) / .20).clamp(0.0, 1.0),
      );
    }
    if (!_childMounted && t >= _childMountAt) {
      _childMounted = true;
      setState(() {});
    }
    if (t >= 1) {
      _ticker.stop();
      _finish();
    }
  }

  void _finish() {
    if (mounted) {
      setState(() => _show = false);
    }
    // 开屏结束：通知桌宠宿主（桌宠要等开屏结束后才允许出现）
    petMarkSplashDone();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _bloom.dispose();
    _text.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 开屏期间不构建应用本体：首帧只画开屏，帧预算全部给它。
        if (_childMounted || !_show) widget.child,
        if (_show)
          Positioned.fill(
            // 开屏文字必须处于 Material 内：否则会继承 MaterialApp 的兜底文本
            // 样式（该样式自带黄色双下划线，用于提示“文字未包在 Material 中”），
            // 导致标题与副标题下方出现突兀的“双黄线”。透明 Material 不绘制内容。
            child: Material(
              type: MaterialType.transparency,
              child: _SplashView(bloom: _bloom, text: _text, fade: _fade),
            ),
          ),
      ],
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({
    required this.bloom,
    required this.text,
    required this.fade,
  });

  final ValueListenable<double> bloom;
  final ValueListenable<double> text;
  final ValueListenable<double> fade;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    // 立绘按屏幕像素宽解码即可：整张 900x1600 的原图解码更久、占内存更多。
    final cacheWidth = math.min(
      (mq.size.width * mq.devicePixelRatio).round(),
      1600,
    );

    return ValueListenableBuilder<double>(
      valueListenable: fade,
      builder: (context, f, child) =>
          f <= 0 ? child! : Opacity(opacity: 1 - f, child: child),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 底色（立绘未解码完成时可见）
          const Positioned.fill(child: _SplashBackdrop()),
          Positioned.fill(
            child: _SplashPhoto(
              bloom: bloom,
              cacheWidth: cacheWidth,
              isDark: isDark,
            ),
          ),
          // 夜间模式：给立绘罩一层暗色，保持全局一致的暗色体验
          if (isDark)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: .40)),
              ),
            ),
          // 飘落的樱花
          const Positioned.fill(
            child: IgnorePointer(child: SakuraPetals(count: 12, opacity: .5)),
          ),
          Align(
            alignment: const Alignment(0, -0.62),
            child: _SplashText(text: text, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

/// 纯渐变底色：静态内容，只光栅化一次。
class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1A1322), Color(0xFF241A33), Color(0xFF1E1526)]
              : const [_kLightTop, _kLightMid, _kLightBottom],
        ),
      ),
    );
  }
}

/// 立绘 + 绽放。
///
/// 立绘始终不透明地画（省掉整屏 saveLayer），「绽放」用一块覆盖在立绘上的
/// 渐变蒙版淡出来实现——蒙版只是一次 quad 填充，成本远低于逐帧改透明度。
class _SplashPhoto extends StatelessWidget {
  const _SplashPhoto({
    required this.bloom,
    required this.cacheWidth,
    required this.isDark,
  });

  final ValueListenable<double> bloom;
  final int cacheWidth;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: bloom,
          builder: (context, b, child) {
            if (b >= 1) return child!;
            // 缩放放在边界外层：光栅缓存可复用，只有变换矩阵在变。
            return Transform.scale(scale: 1.07 - .07 * b, child: child);
          },
          child: RepaintBoundary(
            child: Image.asset(
              'assets/images/splash_girl.jpg',
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
            ),
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: bloom,
          builder: (context, b, _) {
            if (b >= 1) return const SizedBox.shrink();
            final alpha = isDark ? .78 * (1 - b) : .72 * (1 - b);
            return IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            Colors.black.withValues(alpha: alpha),
                            const Color(0xFF241A33).withValues(alpha: alpha),
                            const Color(0xFF1E1526).withValues(alpha: alpha),
                          ]
                        : [
                            _kLightTop.withValues(alpha: alpha),
                            _kLightMid.withValues(alpha: alpha),
                            _kLightBottom.withValues(alpha: alpha),
                          ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 标题 + 副标题：只重建这两个小部件，开销可忽略。
class _SplashText extends StatelessWidget {
  const _SplashText({required this.text, required this.isDark});

  final ValueListenable<double> text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: text,
      builder: (context, t, _) {
        final titleIn = Curves.easeOutCubic.transform(
          ((t - .22) / .26).clamp(0.0, 1.0),
        );
        final subIn = Curves.easeOutCubic.transform(
          ((t - .36) / .26).clamp(0.0, 1.0),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Opacity(
              opacity: titleIn,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - titleIn)),
                child: Text(
                  '樱 读',
                  style: TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF3A9CC) : _kTitleColor,
                    letterSpacing: 4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Opacity(
              opacity: subIn,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - subIn)),
                child: Text(
                  '在樱花树下，慢慢读完一本书',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xB3E8D5E8) : _kSubColor,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

const _kTitleColor = Color(0xFFD96A9E);
const _kSubColor = Color(0xB3A87E95);
const _kLightTop = Color(0xFFFFFAFC);
const _kLightMid = Color(0xFFFDEEF7);
const _kLightBottom = Color(0xFFF7EFFF);
