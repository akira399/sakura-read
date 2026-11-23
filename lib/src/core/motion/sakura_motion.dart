import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sakura Read 2.0 统一动效曲线。
abstract final class SakuraCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve springCurve = Curves.easeOutBack;
}

/// 触感按压反馈容器：按下轻缩至 0.97，松手弹簧回弹。
class SakuraPressable extends StatefulWidget {
  const SakuraPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.97,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final BorderRadius borderRadius;

  @override
  State<SakuraPressable> createState() => _SakuraPressableState();
}

class _SakuraPressableState extends State<SakuraPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scale = (!reduceMotion && _pressed) ? widget.scaleDown : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null && widget.onLongPress == null
          ? null
          : (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: scale,
        duration: reduceMotion
            ? Duration.zero
            : Duration(milliseconds: _pressed ? 90 : 210),
        curve: _pressed ? SakuraCurves.standard : SakuraCurves.springCurve,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 轻量交错入场动效（纯 AnimationController + Interval，无 Timer 残留）。
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final delayMs = math.min(widget.index, 8) * 28;
    const baseMs = 260;
    final totalMs = baseMs + delayMs;
    final begin = delayMs / totalMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, 1.0, curve: SakuraCurves.standard),
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// 统一路由转场：支持 Hero 封面的轻盈缩放淡入，以及子页水平滑入。
class SakuraPageRoute<T> extends PageRouteBuilder<T> {
  SakuraPageRoute({
    required WidgetBuilder builder,
    this.slideHorizontal = false,
  }) : super(
         transitionDuration: const Duration(milliseconds: 320),
         reverseTransitionDuration: const Duration(milliseconds: 260),
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (MediaQuery.disableAnimationsOf(context)) return child;
           final curved = CurvedAnimation(
             parent: animation,
             curve: SakuraCurves.emphasized,
             reverseCurve: SakuraCurves.standard,
           );
           if (slideHorizontal) {
             return FadeTransition(
               opacity: curved,
               child: SlideTransition(
                 position: Tween<Offset>(
                   begin: const Offset(0.06, 0),
                   end: Offset.zero,
                 ).animate(curved),
                 child: child,
               ),
             );
           }
           return FadeTransition(
             opacity: curved,
             child: ScaleTransition(
               scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
               child: child,
             ),
           );
         },
       );

  final bool slideHorizontal;
}
