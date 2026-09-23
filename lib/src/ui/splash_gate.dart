import 'package:flutter/material.dart';

import '../data/pet_store.dart';
import 'widgets/sakura_petals.dart';

/// 冷启动开屏动画：樱花 logo「绽放」+ 标题浮现 + 花瓣飘落，最后淡出进入应用。
///
/// - 前面不再有静态 logo 阶段（原生闪屏只保留纯色底），直接进入绽放动画；
/// - 仅在进程首次启动时播放一次，时长约 1.5s。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  /// 每个进程只播放一次。
  static bool _played = false;

  late bool _show = !_played;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (_show) {
      _played = true;
      _controller.forward().whenComplete(() {
        if (mounted) setState(() => _show = false);
        // 开屏结束：通知桌宠宿主（桌宠要等开屏结束后才允许出现）
        petMarkSplashDone();
      });
    } else {
      // 进程内二次进入（没播开屏）：直接放行
      petMarkSplashDone();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_show)
          Positioned.fill(
            // 开屏文字必须处于 Material 内：否则会继承 MaterialApp 的兜底文本
            // 样式（该样式自带黄色双下划线，用于提示“文字未包在 Material 中”），
            // 导致标题与副标题下方出现突兀的“双黄线”。透明 Material 不绘制内容。
            child: Material(
              type: MaterialType.transparency,
              child: _SplashView(controller: _controller),
            ),
          ),
      ],
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({required this.controller});

  final AnimationController controller;

  static const _titleColor = Color(0xFFD96A9E);
  static const _subColor = Color(0xB3A87E95);

  @override
  Widget build(BuildContext context) {
    // （立绘版开屏：不再使用 splash_logo.png）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final bloom = Curves.easeOutBack.transform((t / .30).clamp(0.0, 1.0));
        final titleIn = Curves.easeOutCubic.transform(
          ((t - .22) / .26).clamp(0.0, 1.0),
        );
        final subIn = Curves.easeOutCubic.transform(
          ((t - .36) / .26).clamp(0.0, 1.0),
        );
        final out = Curves.easeInOut.transform(
          ((t - .76) / .24).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: 1 - out,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [
                        Color(0xFF1A1322),
                        Color(0xFF241A33),
                        Color(0xFF1E1526),
                      ]
                    : const [
                        Color(0xFFFFFAFC),
                        Color(0xFFFDEEF7),
                        Color(0xFFF7EFFF),
                      ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 全屏樱花树下立绘（缓推淡入）
                Positioned.fill(
                  child: Opacity(
                    opacity: (0.30 + 0.70 * bloom).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1.07 - 0.07 * bloom,
                      child: Image.asset(
                        'assets/images/splash_girl.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                // 夜间模式：给立绘罩一层暗色，保持全局一致的暗色体验
                if (isDark)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .40),
                      ),
                    ),
                  ),
                // 飘落的樱花
                const Positioned.fill(
                  child: IgnorePointer(
                    child: SakuraPetals(count: 12, opacity: .5),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.62),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              color: isDark
                                  ? const Color(0xFFF3A9CC)
                                  : _titleColor,
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
                              color: isDark
                                  ? const Color(0xB3E8D5E8)
                                  : _subColor,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
