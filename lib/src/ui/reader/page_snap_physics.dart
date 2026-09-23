import 'package:flutter/widgets.dart';

/// 阅读 3.0（Legado）风格的翻页吸附物理。
///
/// 背景：Flutter 的 [PageScrollPhysics] 默认用
/// `SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.1)`
/// 的过阻尼弹簧做页对齐；实测该弹簧「尾巴」极长——整页翻完需 ~1s，
/// 仅最后 30 逻辑像素就要磨蹭 400~500ms，观感上就是「停住一下才归位」，
/// 覆盖模式下还会让「前缘阴影（一条缝）」长时间挂在屏幕上。
///
/// 本物理改为「固定速率」吸附（对照阅读 3.0 的 `defaultAnimationSpeed = 300ms/页`）：
/// - 整页距离 ≈ 300ms 完成；
/// - 距离越短耗时刻越短（下限 110ms，避免瞬移感）；
/// - easeOutCubic 曲线：起步带一点冲量、落点柔和停止；
/// - 结束时精确对齐到整页位置（容差 0.01 逻辑像素，杜绝二次微调循环）。
class PageSnapPhysics extends ScrollPhysics {
  const PageSnapPhysics({super.parent});

  @override
  PageSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      PageSnapPhysics(parent: buildParent(ancestor));

  @override
  bool get allowImplicitScrolling => false;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 越界且没有回归趋势：交给父级物理（回弹逻辑）
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final double viewport = position.viewportDimension;
    if (viewport <= 0) return null;
    // 目标页计算与 PageScrollPhysics 一致：超过半页 / 有速度时朝相邻页对齐
    final Tolerance tolerance = toleranceFor(position);
    double page = position.pixels / viewport;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final double target = page.roundToDouble() * viewport;
    // 已在目标页（含浮点残差）→ 不再生成动画，杜绝「微调循环」造成的尾巴
    if ((target - position.pixels).abs() <= 0.01) return null;
    return PageSnapSimulation(
      from: position.pixels,
      to: target,
      pageExtent: viewport,
    );
  }
}

/// 固定速率的页对齐模拟：`durationMs = clamp(300 * 距离/页宽, 110, 320)`，
/// 位置按 easeOutCubic 曲线推进，到时即止（见 [PageSnapPhysics] 文档）。
class PageSnapSimulation extends Simulation {
  PageSnapSimulation({
    required this.from,
    required this.to,
    required this.pageExtent,
  }) {
    final double distance = (to - from).abs();
    final double rawMs = pageExtent > 0 ? 300.0 * distance / pageExtent : 300.0;
    _duration = rawMs.clamp(_minMs, _maxMs) / 1000.0;
  }

  static const double _minMs = 110.0;
  static const double _maxMs = 320.0;

  final double from;
  final double to;
  final double pageExtent;

  late final double _duration;

  /// 动画时长（秒），测试用。
  double get duration => _duration;

  static double _easeOutCubic(double t) {
    final double d = 1 - t;
    return 1 - d * d * d;
  }

  @override
  double x(double timeInSeconds) {
    final double t = (timeInSeconds / _duration).clamp(0.0, 1.0);
    return from + (to - from) * _easeOutCubic(t);
  }

  @override
  double dx(double timeInSeconds) {
    final double t = (timeInSeconds / _duration).clamp(0.0, 1.0);
    final double d = 1 - t;
    return (to - from) * 3 * d * d / _duration;
  }

  @override
  bool isDone(double timeInSeconds) => timeInSeconds >= _duration;
}
