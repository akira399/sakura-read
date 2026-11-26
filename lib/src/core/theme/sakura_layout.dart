import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 横屏 / 宽屏自适应布局辅助工具（响应式断点、安全挖孔边距与居中内容容器）。
class SakuraLayout {
  const SakuraLayout._();

  /// 主内容区域最大阅读/浏览宽度（避免横屏平板或桌面端卡片过度拉宽）。
  static const double contentMaxWidth = 1120;

  /// 设置明细页（单栏卡片列表）的最大宽度。
  static const double detailMaxWidth = 960;

  /// 当前是否处于宽屏横向视图（宽大于高且至少 600dp）。
  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.width >= 600;
  }

  /// 是否达到双栏分栏宽度（>= 720dp）。
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 720;

  /// 横屏高度较紧凑时收紧顶部留白，避免头部挤占首屏内容。
  static bool isShortLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.height < 520;
  }

  /// 计算横屏挖孔 / 刘海安全水平内边距（竖屏保持 [min] 像素不变）。
  static EdgeInsets horizontalInsets(BuildContext context, {double min = 16}) {
    final pad = MediaQuery.paddingOf(context);
    return EdgeInsets.only(
      left: pad.left > 0 ? math.max(min, pad.left + 6) : min,
      right: pad.right > 0 ? math.max(min, pad.right + 6) : min,
    );
  }

  /// 悬浮胶囊 Dock 在宽屏/横屏下的最大宽度。
  static double dockMaxWidth(double screenWidth) {
    if (screenWidth < 680) return double.infinity;
    return math.min(560.0, math.max(360.0, screenWidth - 160.0));
  }

  /// 将子组件水平居中并限制最大宽度，保留挖孔横向安全距。
  static Widget centeredMaxWidth({
    required BuildContext context,
    required Widget child,
    double maxWidth = contentMaxWidth,
    double minHorizontalPadding = 16,
  }) {
    final insets = horizontalInsets(context, min: minHorizontalPadding);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth + insets.left + insets.right,
        ),
        child: Padding(padding: insets, child: child),
      ),
    );
  }
}
