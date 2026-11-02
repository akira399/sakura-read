import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 阅读页顶栏 / 底栏的底板。
///
/// 用户反馈「这里透明那里透明的，都整嘛了，调来调去都没有磨砂」——所以给了
/// 一个明确的「磨砂玻璃」开关：打开时用 [BackdropFilter] 实时模糊下面透出的
/// 正文，关闭时退回原来的实色底板（低端机更省电）。
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.frosted,
    required this.tint,
    required this.radius,
    required this.child,
    this.dark = false,
    this.shadow,
    this.sigma = 22,
  });

  /// 是否启用实时模糊。
  final bool frosted;

  /// 底板颜色（一般取阅读背景色）。
  final Color tint;

  final BorderRadius radius;
  final Widget child;

  /// 深色主题下透明度更高一点，避免文字看起来发灰。
  final bool dark;

  final List<BoxShadow>? shadow;

  /// 模糊半径，默认 22。
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: frosted ? tint.withValues(alpha: dark ? .62 : .72) : tint,
      borderRadius: radius,
      boxShadow: shadow,
    );
    final box = DecoratedBox(decoration: decoration, child: child);
    if (!frosted) return box;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: box,
      ),
    );
  }
}
