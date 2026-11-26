import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/sakura_tokens.dart';

/// 底部导航栏专属手绘双色调图标类型。
enum SakuraNavGlyph {
  /// 书架：展开书卷 + 垂落樱花丝绸书签
  shelf,

  /// 发现：和风罗盘 + 樱瓣指针
  discover,

  /// 最近：古典怀表表盘 + 花瓣指针
  recent,

  /// 设置：小樱蝴蝶结发带 + 五瓣樱花挂饰（告别刻板爱心）
  settings,
}

/// 全局功能与设置中心专属手绘双色调图标类型。
enum SakuraGlyph {
  /// AI 伴读（小樱发带 + 灵动星芒）
  aiCompanion,

  /// 搜索（和风放大镜 + 花瓣高光）
  search,

  /// 书架排列/视图（错落书册 + 韵律标尺）
  arrange,

  /// 批量管理（手账清单 + 樱花印记）
  manage,

  /// 添置新书（书册 + 绽放樱瓣加号）
  addBook,

  /// 外观与书房风格（调色折扇 + 樱瓣）
  appearance,

  /// 阅读与排版默认（毛笔/钢笔尖 + 稿纸格线）
  typography,

  /// 听书与离线语音（和风耳机 + 声波花瓣）
  audio,

  /// 小樱桌宠与看板娘（Q 版蝴蝶结发饰 + 樱花）
  mascot,

  /// 书源管理与调试（经纬书卷 + 节点脉冲）
  sources,

  /// 正文净化规则（羽毛掸/滤镜 + 净澈星芒）
  purify,

  /// 备份、同步与迁移（云端和纸匣 + 守护印章）
  backup,

  /// 性能、帧率与高刷（疾风流光羽翼）
  performance,

  /// 关于与更新（朱红藏书印章 + 樱花纹）
  about,
}

/// 底部导航栏手绘双色调图标组件。
class SakuraNavIcon extends StatelessWidget {
  const SakuraNavIcon({
    super.key,
    required this.glyph,
    required this.active,
    required this.color,
    this.accentColor,
    this.size = 24,
  });

  final SakuraNavGlyph glyph;
  final bool active;
  final Color color;
  final Color? accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SakuraNavGlyphPainter(
          glyph: glyph,
          active: active,
          color: color,
          accent: accent,
        ),
      ),
    );
  }
}

/// 通用手绘双色调图标组件。
class SakuraIcon extends StatelessWidget {
  const SakuraIcon({
    super.key,
    required this.glyph,
    required this.color,
    this.accent,
    this.size = 20,
    this.active = true,
  });

  final SakuraGlyph glyph;
  final Color color;
  final Color? accent;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SakuraGlyphPainter(
          glyph: glyph,
          color: color,
          accent: effectiveAccent,
          active: active,
        ),
      ),
    );
  }
}

/// 日系文具风双色调图标徽章（供设置中心分组卡片、工具栏与抽屉使用）。
class SakuraIconBadge extends StatelessWidget {
  const SakuraIconBadge({
    super.key,
    required this.glyph,
    this.color,
    this.backgroundColor,
    this.size = 40,
    this.iconSize = 21,
    this.borderRadius = 13,
    this.showPetalCorner = true,
  });

  final SakuraGlyph glyph;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final double borderRadius;
  final bool showPetalCorner;

  @override
  Widget build(BuildContext context) {
    final sakura = context.sakura;
    final primary = color ?? Theme.of(context).colorScheme.primary;
    final bg = backgroundColor ?? primary.withValues(alpha: 0.12);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, primary.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: primary.withValues(alpha: 0.22), width: 0.85),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showPetalCorner)
            Positioned(
              top: 3.5,
              right: 3.5,
              child: CustomPaint(
                size: const Size(7, 7),
                painter: _TinyPetalAccentPainter(
                  color: primary.withValues(alpha: 0.42),
                ),
              ),
            ),
          SakuraIcon(
            glyph: glyph,
            color: primary,
            accent: sakura.inkPrimary,
            size: iconSize,
          ),
        ],
      ),
    );
  }
}

void _drawSakuraBlossom(
  Canvas canvas,
  Offset center,
  double radius,
  Paint fillPaint, [
  Paint? strokePaint,
]) {
  for (var i = 0; i < 5; i++) {
    final angle = -math.pi / 2 + i * (2 * math.pi / 5);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(
        -radius * 0.45,
        -radius * 0.35,
        -radius * 0.52,
        -radius * 0.92,
        -radius * 0.16,
        -radius,
      )
      ..lineTo(0, -radius * 0.82)
      ..lineTo(radius * 0.16, -radius)
      ..cubicTo(
        radius * 0.52,
        -radius * 0.92,
        radius * 0.45,
        -radius * 0.35,
        0,
        0,
      )
      ..close();
    canvas.drawPath(path, fillPaint);
    if (strokePaint != null) {
      canvas.drawPath(path, strokePaint);
    }
    canvas.restore();
  }
}

void _drawSinglePetal(
  Canvas canvas,
  Offset center,
  double radius,
  double rotation,
  Paint paint,
) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);
  final path = Path()
    ..moveTo(0, radius * 0.7)
    ..cubicTo(
      -radius * 0.65,
      radius * 0.2,
      -radius * 0.6,
      -radius * 0.75,
      -radius * 0.18,
      -radius * 0.95,
    )
    ..lineTo(0, -radius * 0.72)
    ..lineTo(radius * 0.18, -radius * 0.95)
    ..cubicTo(
      radius * 0.6,
      -radius * 0.75,
      radius * 0.65,
      radius * 0.2,
      0,
      radius * 0.7,
    )
    ..close();
  canvas.drawPath(path, paint);
  canvas.restore();
}

void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, paint);
}

class _TinyPetalAccentPainter extends CustomPainter {
  const _TinyPetalAccentPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    _drawSinglePetal(
      canvas,
      Offset(size.width / 2, size.height / 2),
      size.width * 0.48,
      -0.45,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TinyPetalAccentPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SakuraNavGlyphPainter extends CustomPainter {
  const _SakuraNavGlyphPainter({
    required this.glyph,
    required this.active,
    required this.color,
    required this.accent,
  });

  final SakuraNavGlyph glyph;
  final bool active;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * (active ? 0.082 : 0.074)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final duotoneFill = Paint()
      ..color = (active ? accent : color).withValues(
        alpha: active ? 0.22 : 0.08,
      )
      ..style = PaintingStyle.fill;

    final accentFill = Paint()
      ..color = active ? accent : color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case SakuraNavGlyph.shelf:
        // 展开的精装书册 + 中缝垂落樱花书签
        final leftPage = Path()
          ..moveTo(s * 0.5, s * 0.25)
          ..quadraticBezierTo(s * 0.31, s * 0.18, s * 0.14, s * 0.24)
          ..lineTo(s * 0.14, s * 0.74)
          ..quadraticBezierTo(s * 0.31, s * 0.68, s * 0.5, s * 0.76)
          ..close();
        final rightPage = Path()
          ..moveTo(s * 0.5, s * 0.25)
          ..quadraticBezierTo(s * 0.69, s * 0.18, s * 0.86, s * 0.24)
          ..lineTo(s * 0.86, s * 0.74)
          ..quadraticBezierTo(s * 0.69, s * 0.68, s * 0.5, s * 0.76)
          ..close();
        canvas.drawPath(leftPage, duotoneFill);
        if (active) {
          canvas.drawPath(rightPage, duotoneFill);
        }
        canvas.drawPath(leftPage, stroke);
        canvas.drawPath(rightPage, stroke);

        // 垂落丝绸书签 + 末端小樱瓣
        final ribbon = Path()
          ..moveTo(s * 0.5, s * 0.26)
          ..lineTo(s * 0.5, s * 0.87)
          ..moveTo(s * 0.64, s * 0.36)
          ..lineTo(s * 0.64, s * 0.58);
        canvas.drawPath(ribbon, stroke);
        _drawSinglePetal(
          canvas,
          Offset(s * 0.5, s * 0.88),
          s * 0.11,
          0.25,
          accentFill,
        );

      case SakuraNavGlyph.discover:
        // 和风星芒罗盘 + 樱瓣指针
        final center = Offset(s * 0.5, s * 0.5);
        final r = s * 0.36;
        canvas.drawCircle(center, r, duotoneFill);
        canvas.drawCircle(center, r, stroke);
        // 东南西北刻度
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          canvas.drawLine(
            center + Offset(math.cos(a) * r * 0.74, math.sin(a) * r * 0.74),
            center + Offset(math.cos(a) * r * 0.95, math.sin(a) * r * 0.95),
            stroke,
          );
        }
        // 斜向樱瓣罗盘针
        final needle = Path()
          ..moveTo(s * 0.64, s * 0.36)
          ..lineTo(s * 0.55, s * 0.55)
          ..lineTo(s * 0.36, s * 0.64)
          ..lineTo(s * 0.45, s * 0.45)
          ..close();
        canvas.drawPath(needle, accentFill);
        canvas.drawPath(needle, stroke);
        _drawSparkle(canvas, Offset(s * 0.77, s * 0.22), s * 0.08, accentFill);

      case SakuraNavGlyph.recent:
        // 古典怀表 + 顶部挂环 + 樱瓣时针
        final center = Offset(s * 0.5, s * 0.54);
        final r = s * 0.33;
        canvas.drawCircle(center, r, duotoneFill);
        canvas.drawCircle(center, r, stroke);
        // 怀表顶环
        canvas.drawLine(
          Offset(s * 0.5, s * 0.14),
          Offset(s * 0.5, s * 0.21),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.41, s * 0.14),
          Offset(s * 0.59, s * 0.14),
          stroke,
        );
        // 指针
        final hands = Path()
          ..moveTo(center.dx, center.dy - r * 0.54)
          ..lineTo(center.dx, center.dy)
          ..lineTo(center.dx + r * 0.46, center.dy + r * 0.22);
        canvas.drawPath(hands, stroke);
        _drawSinglePetal(
          canvas,
          Offset(s * 0.76, s * 0.26),
          s * 0.11,
          -0.6,
          accentFill,
        );

      case SakuraNavGlyph.settings:
        // 小樱标志性蝴蝶结发带 + 五瓣樱花中心挂饰（完全取代原版爱心）
        final center = Offset(s * 0.5, s * 0.48);
        // 左右蝴蝶结翼
        final leftLoop = Path()
          ..moveTo(center.dx, center.dy)
          ..cubicTo(s * 0.28, s * 0.20, s * 0.11, s * 0.32, s * 0.15, s * 0.50)
          ..cubicTo(
            s * 0.18,
            s * 0.64,
            s * 0.34,
            s * 0.62,
            center.dx,
            center.dy,
          );
        final rightLoop = Path()
          ..moveTo(center.dx, center.dy)
          ..cubicTo(s * 0.72, s * 0.20, s * 0.89, s * 0.32, s * 0.85, s * 0.50)
          ..cubicTo(
            s * 0.82,
            s * 0.64,
            s * 0.66,
            s * 0.62,
            center.dx,
            center.dy,
          );
        // 垂落缎带尾
        final tails = Path()
          ..moveTo(center.dx - s * 0.04, center.dy + s * 0.05)
          ..quadraticBezierTo(s * 0.36, s * 0.72, s * 0.27, s * 0.86)
          ..moveTo(center.dx + s * 0.04, center.dy + s * 0.05)
          ..quadraticBezierTo(s * 0.64, s * 0.72, s * 0.73, s * 0.86);

        canvas.drawPath(leftLoop, duotoneFill);
        canvas.drawPath(rightLoop, duotoneFill);
        canvas.drawPath(leftLoop, stroke);
        canvas.drawPath(rightLoop, stroke);
        canvas.drawPath(tails, stroke);

        // 中心五瓣樱花扣
        _drawSakuraBlossom(canvas, center, s * 0.16, accentFill);
        canvas.drawCircle(
          center,
          s * 0.045,
          Paint()..color = active ? Colors.white : color,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraNavGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.active != active ||
      oldDelegate.color != color ||
      oldDelegate.accent != accent;
}

class _SakuraGlyphPainter extends CustomPainter {
  const _SakuraGlyphPainter({
    required this.glyph,
    required this.color,
    required this.accent,
    required this.active,
  });

  final SakuraGlyph glyph;
  final Color color;
  final Color accent;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.082
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final softFill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    final solidFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case SakuraGlyph.aiCompanion:
        // 五瓣樱花 + 灵动双星芒
        _drawSakuraBlossom(
          canvas,
          Offset(s * 0.44, s * 0.54),
          s * 0.30,
          softFill,
          stroke,
        );
        _drawSparkle(canvas, Offset(s * 0.78, s * 0.24), s * 0.13, solidFill);
        _drawSparkle(canvas, Offset(s * 0.22, s * 0.22), s * 0.07, solidFill);

      case SakuraGlyph.search:
        // 和风圆镜 + 樱花枝握柄
        final c = Offset(s * 0.43, s * 0.43);
        canvas.drawCircle(c, s * 0.26, softFill);
        canvas.drawCircle(c, s * 0.26, stroke);
        canvas.drawLine(
          Offset(s * 0.62, s * 0.62),
          Offset(s * 0.84, s * 0.84),
          stroke,
        );
        _drawSinglePetal(
          canvas,
          Offset(s * 0.43, s * 0.43),
          s * 0.11,
          -0.5,
          solidFill,
        );

      case SakuraGlyph.arrange:
        // 错落双书册 + 韵律标尺
        final r1 = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.15, s * 0.18, s * 0.28, s * 0.64),
          Radius.circular(s * 0.07),
        );
        final r2 = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.54, s * 0.26, s * 0.30, s * 0.56),
          Radius.circular(s * 0.07),
        );
        canvas.drawRRect(r1, softFill);
        canvas.drawRRect(r1, stroke);
        canvas.drawRRect(r2, stroke);
        _drawSparkle(canvas, Offset(s * 0.69, s * 0.16), s * 0.07, solidFill);

      case SakuraGlyph.manage:
        // 手账书签夹 + 勾选印记
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.18, s * 0.16, s * 0.64, s * 0.68),
          Radius.circular(s * 0.12),
        );
        canvas.drawRRect(rect, softFill);
        canvas.drawRRect(rect, stroke);
        final check = Path()
          ..moveTo(s * 0.34, s * 0.52)
          ..lineTo(s * 0.46, s * 0.63)
          ..lineTo(s * 0.67, s * 0.39);
        canvas.drawPath(check, stroke);

      case SakuraGlyph.addBook:
        // 书册轮廓 + 右下绽放樱花加号
        final book = Path()
          ..moveTo(s * 0.22, s * 0.20)
          ..lineTo(s * 0.66, s * 0.20)
          ..lineTo(s * 0.66, s * 0.46)
          ..moveTo(s * 0.48, s * 0.78)
          ..lineTo(s * 0.22, s * 0.78)
          ..lineTo(s * 0.22, s * 0.20);
        canvas.drawPath(book, stroke);
        canvas.drawLine(
          Offset(s * 0.34, s * 0.36),
          Offset(s * 0.54, s * 0.36),
          stroke,
        );
        // 加号
        canvas.drawLine(
          Offset(s * 0.70, s * 0.56),
          Offset(s * 0.70, s * 0.84),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.56, s * 0.70),
          Offset(s * 0.84, s * 0.70),
          stroke,
        );
        _drawSinglePetal(
          canvas,
          Offset(s * 0.36, s * 0.56),
          s * 0.11,
          0.4,
          solidFill,
        );

      case SakuraGlyph.appearance:
        // 和风折扇 + 樱花色点
        final fan = Path()
          ..moveTo(s * 0.50, s * 0.78)
          ..lineTo(s * 0.14, s * 0.38)
          ..quadraticBezierTo(s * 0.50, s * 0.08, s * 0.86, s * 0.38)
          ..close();
        canvas.drawPath(fan, softFill);
        canvas.drawPath(fan, stroke);
        canvas.drawLine(
          Offset(s * 0.50, s * 0.78),
          Offset(s * 0.50, s * 0.23),
          stroke,
        );
        _drawSinglePetal(
          canvas,
          Offset(s * 0.65, s * 0.42),
          s * 0.10,
          0.5,
          solidFill,
        );

      case SakuraGlyph.typography:
        // 书法钢笔尖 + 原稿格线
        final nib = Path()
          ..moveTo(s * 0.50, s * 0.15)
          ..lineTo(s * 0.74, s * 0.52)
          ..lineTo(s * 0.62, s * 0.82)
          ..lineTo(s * 0.38, s * 0.82)
          ..lineTo(s * 0.26, s * 0.52)
          ..close();
        canvas.drawPath(nib, softFill);
        canvas.drawPath(nib, stroke);
        canvas.drawLine(
          Offset(s * 0.50, s * 0.16),
          Offset(s * 0.50, s * 0.52),
          stroke,
        );
        canvas.drawCircle(Offset(s * 0.50, s * 0.55), s * 0.055, solidFill);

      case SakuraGlyph.audio:
        // 和风头戴耳机 + 中心花瓣声波
        final arc = Path()
          ..addArc(
            Rect.fromCircle(
              center: Offset(s * 0.50, s * 0.52),
              radius: s * 0.32,
            ),
            math.pi,
            math.pi,
          );
        canvas.drawPath(arc, stroke);
        final leftCup = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.14, s * 0.50, s * 0.14, s * 0.26),
          Radius.circular(s * 0.06),
        );
        final rightCup = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.72, s * 0.50, s * 0.14, s * 0.26),
          Radius.circular(s * 0.06),
        );
        canvas.drawRRect(leftCup, softFill);
        canvas.drawRRect(rightCup, softFill);
        canvas.drawRRect(leftCup, stroke);
        canvas.drawRRect(rightCup, stroke);
        _drawSinglePetal(
          canvas,
          Offset(s * 0.50, s * 0.56),
          s * 0.13,
          0.2,
          solidFill,
        );

      case SakuraGlyph.mascot:
        // 小樱双翼蝴蝶结发饰 + 花蕊
        final center = Offset(s * 0.50, s * 0.48);
        final bow = Path()
          ..moveTo(center.dx, center.dy)
          ..cubicTo(s * 0.24, s * 0.18, s * 0.12, s * 0.34, s * 0.16, s * 0.54)
          ..cubicTo(
            s * 0.20,
            s * 0.68,
            s * 0.36,
            s * 0.62,
            center.dx,
            center.dy,
          )
          ..moveTo(center.dx, center.dy)
          ..cubicTo(s * 0.76, s * 0.18, s * 0.88, s * 0.34, s * 0.84, s * 0.54)
          ..cubicTo(
            s * 0.80,
            s * 0.68,
            s * 0.64,
            s * 0.62,
            center.dx,
            center.dy,
          );
        canvas.drawPath(bow, softFill);
        canvas.drawPath(bow, stroke);
        canvas.drawLine(center, Offset(s * 0.30, s * 0.84), stroke);
        canvas.drawLine(center, Offset(s * 0.70, s * 0.84), stroke);
        canvas.drawCircle(center, s * 0.09, solidFill);

      case SakuraGlyph.sources:
        // 经纬星轨网络 + 书卷节点
        final c = Offset(s * 0.50, s * 0.50);
        canvas.drawCircle(c, s * 0.33, softFill);
        canvas.drawCircle(c, s * 0.33, stroke);
        canvas.drawOval(
          Rect.fromCenter(center: c, width: s * 0.34, height: s * 0.66),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.18, s * 0.50),
          Offset(s * 0.82, s * 0.50),
          stroke,
        );

      case SakuraGlyph.purify:
        // 净澈魔棒 + 双星芒与花瓣
        canvas.drawLine(
          Offset(s * 0.20, s * 0.80),
          Offset(s * 0.66, s * 0.34),
          stroke,
        );
        _drawSparkle(canvas, Offset(s * 0.72, s * 0.28), s * 0.15, solidFill);
        _drawSparkle(canvas, Offset(s * 0.30, s * 0.28), s * 0.09, solidFill);
        _drawSinglePetal(
          canvas,
          Offset(s * 0.74, s * 0.68),
          s * 0.11,
          0.6,
          solidFill,
        );

      case SakuraGlyph.backup:
        // 和纸云匣 + 向上守护箭头
        final cloud = Path()
          ..moveTo(s * 0.26, s * 0.68)
          ..lineTo(s * 0.74, s * 0.68)
          ..cubicTo(s * 0.88, s * 0.68, s * 0.88, s * 0.46, s * 0.74, s * 0.44)
          ..cubicTo(s * 0.72, s * 0.24, s * 0.44, s * 0.20, s * 0.36, s * 0.38)
          ..cubicTo(s * 0.14, s * 0.38, s * 0.12, s * 0.68, s * 0.26, s * 0.68)
          ..close();
        canvas.drawPath(cloud, softFill);
        canvas.drawPath(cloud, stroke);
        final arrow = Path()
          ..moveTo(s * 0.50, s * 0.78)
          ..lineTo(s * 0.50, s * 0.46)
          ..moveTo(s * 0.40, s * 0.55)
          ..lineTo(s * 0.50, s * 0.45)
          ..lineTo(s * 0.60, s * 0.55);
        canvas.drawPath(arrow, stroke);

      case SakuraGlyph.performance:
        // 高刷仪表盘 + 疾风指针
        final c = Offset(s * 0.50, s * 0.58);
        final arc = Path()
          ..addArc(
            Rect.fromCircle(center: c, radius: s * 0.34),
            math.pi * 0.85,
            math.pi * 1.3,
          );
        canvas.drawPath(arc, stroke);
        canvas.drawLine(c, Offset(s * 0.68, s * 0.34), stroke);
        canvas.drawCircle(c, s * 0.07, solidFill);
        _drawSparkle(canvas, Offset(s * 0.76, s * 0.24), s * 0.08, solidFill);

      case SakuraGlyph.about:
        // 朱红藏书印章（外方内樱）
        final stamp = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.18, s * 0.18, s * 0.64, s * 0.64),
          Radius.circular(s * 0.14),
        );
        canvas.drawRRect(stamp, softFill);
        canvas.drawRRect(stamp, stroke);
        _drawSakuraBlossom(
          canvas,
          Offset(s * 0.50, s * 0.50),
          s * 0.20,
          solidFill,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.accent != accent ||
      oldDelegate.active != active;
}
