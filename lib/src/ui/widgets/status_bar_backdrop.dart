import 'package:flutter/material.dart';

/// 不透明状态栏底块：盖在页面最上层，遮住从状态栏区域下方穿过的滚动内容。
///
/// 背景：应用运行在「边到边（edge-to-edge）」模式下（Android 15 默认强制），
/// 滚动内容会从透明状态栏下方经过，状态栏图标与页面文字相互叠压、观感很乱。
/// 本组件在状态栏高度内铺一块**不透明色块**，把经过的内容完全遮住
/// （IgnorePointer 不拦截手势），实现「状态栏不透明」的效果。
///
/// 用法：放在页面 Stack 的**最后一个子级**（最上层）：
/// ```dart
/// body: Stack(children: [
///   content,
///   Positioned(top: 0, left: 0, right: 0, child: StatusBarBackdrop()),
/// ]),
/// ```
class StatusBarBackdrop extends StatelessWidget {
  const StatusBarBackdrop({super.key, this.color});

  /// 底块颜色；不传则取当前主题的页面底色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (top <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        height: top,
        child: ColoredBox(
          color: color ?? Theme.of(context).scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
