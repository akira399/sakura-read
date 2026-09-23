import 'package:flutter/material.dart';

/// 覆盖翻页的「钉住页」装饰器：对照阅读 3.0（Legado）CoverPageDelegate 逐行移植。
///
/// [delta] = 该条目相对当前页的偏移（index - page）：
/// - `0 < delta < 1`：该页被"钉住"在视口原位（抵消 PageView 的自然位移），
///   只显示已揭示的部分（显式 [ClipRect] 裁剪，等价原版 `canvas.clipRect`），
///   并在前缘绘制渐变投影（0x66111111 → 透明，即原版 shadowDrawableR）；
/// - 其余情况原样绘制（跟手平移由 PageView 自身完成）。
///
/// 注意：这里必须使用**显式** ClipRect——Flutter 的 Stack 只对 Positioned
/// 子级检测溢出裁剪，非定位子级的平移不会被自动裁剪。
class CoverTurnItem extends StatelessWidget {
  const CoverTurnItem({
    super.key,
    required this.delta,
    required this.width,
    required this.shadowWidth,
    required this.child,
  });

  /// 相对当前页的偏移（index - page），范围含义见类文档。
  final double delta;

  /// 条目宽度（视口宽度，逻辑像素）。
  final double width;

  /// 前缘投影宽度（对应原版 30 物理像素换算后的逻辑像素）。
  final double shadowWidth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (delta <= 0 || delta >= 1) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          clipper: CoverEdgeClipper((1 - delta) * width),
          child: Transform.translate(
            offset: Offset(-delta * width, 0),
            child: child,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: shadowWidth,
          child: IgnorePointer(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x66111111), Color(0x00111111)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 覆盖翻页的显式裁剪器：只保留条目左侧 `[0, width]` 区域
/// （对应阅读 3.0 中 canvas.clipRect 的裁剪范围）。
class CoverEdgeClipper extends CustomClipper<Rect> {
  const CoverEdgeClipper(this.width);

  final double width;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, width.clamp(0.0, size.width), size.height);

  @override
  bool shouldReclip(CoverEdgeClipper oldClipper) => oldClipper.width != width;
}
