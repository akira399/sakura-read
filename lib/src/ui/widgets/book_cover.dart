import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/sakura_tokens.dart';
import '../../data/models.dart';

/// 书籍封面：优先真实封面图；无封面时使用日式轻编辑插画封面。
///
/// 2.0 重构：
/// - 左侧增加真实书脊折痕高光与暗影，提升实体书质感；
/// - 格式角标固定在右上角半透明胶囊，彻底消除底部文字重叠；
/// - 支持 `showTextOnGenerated: false`（由外层卡片在封面下方展示书名）。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.radius = 14,
    this.strong = false,
    this.elevated = false,
    this.showFormatBadge = true,
    this.showTextOnGenerated = true,
  });

  final Book book;
  final double radius;

  /// 详情页放大使用。
  final bool strong;

  /// 是否附加封面立体投影。
  final bool elevated;

  /// 是否显示右上角格式胶囊。
  final bool showFormatBadge;

  /// 自动生成封面上是否叠加书名与作者（外部卡片下方已有书名时可关闭）。
  final bool showTextOnGenerated;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    Widget content;
    if (!book.generatedCover && path != null && path.isNotEmpty) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final logical =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 320.0;
          final cacheWidth = (logical * dpr).clamp(120.0, 1080.0).round();
          return _RealCoverFrame(
            book: book,
            showFormatBadge: showFormatBadge,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => GeneratedCover(
                book: book,
                showFormatBadge: showFormatBadge,
                showText: showTextOnGenerated,
              ),
            ),
          );
        },
      );
    } else {
      content = GeneratedCover(
        book: book,
        showFormatBadge: showFormatBadge,
        showText: showTextOnGenerated,
      );
    }

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );

    if (!elevated) return clipped;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: context.sakura.coverShadow,
            blurRadius: strong ? 22 : 14,
            offset: Offset(0, strong ? 10 : 6),
          ),
        ],
      ),
      child: clipped,
    );
  }
}

class _RealCoverFrame extends StatelessWidget {
  const _RealCoverFrame({
    required this.book,
    required this.showFormatBadge,
    required this.child,
  });

  final Book book;
  final bool showFormatBadge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxHeight < 76;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            const _BookSpineCrease(),
            if (showFormatBadge && !tiny)
              Positioned(
                top: 6,
                right: 6,
                child: _FormatPill(label: book.formatLabel),
              ),
          ],
        );
      },
    );
  }
}

/// 程序生成的渐变插画封面（按书名稳定取色与配图）。
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({
    super.key,
    required this.book,
    this.showFormatBadge = true,
    this.showText = true,
  });

  final Book book;
  final bool showFormatBadge;
  final bool showText;

  static const List<List<Color>> _pairs = [
    [Color(0xFFF6A9C5), Color(0xFFA799EF)],
    [Color(0xFF9ACCF7), Color(0xFFA799EF)],
    [Color(0xFF8FD9BC), Color(0xFF6DB7EB)],
    [Color(0xFFF5BE9E), Color(0xFFF39EC0)],
    [Color(0xFFAAB4F8), Color(0xFFD9A6F2)],
    [Color(0xFFF3B0C5), Color(0xFFF3D38D)],
  ];

  /// 默认封面插画库（6 张日系场景，按书名稳定选取）。
  static const List<String> _coverAssets = [
    'assets/images/cover_1.jpg',
    'assets/images/cover_2.jpg',
    'assets/images/cover_3.jpg',
    'assets/images/cover_4.jpg',
    'assets/images/cover_5.jpg',
    'assets/images/cover_6.jpg',
  ];

  int get _titleHash {
    var hash = 0;
    for (final unit in book.title.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  List<Color> get _colors => _pairs[_titleHash % _pairs.length];

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final compact = h < 140;
          final tiny = h < 76;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final logicalW =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 200.0;
          final cacheWidth = (logicalW * dpr).clamp(120.0, 540.0).round();
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.asset(
                  _coverAssets[_titleHash % _coverAssets.length],
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              if (showText)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .06),
                          Colors.black.withValues(alpha: .28),
                          Colors.black.withValues(alpha: .64),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              const _BookSpineCrease(),
              if (showFormatBadge && !tiny)
                Positioned(
                  top: compact ? 5 : 8,
                  right: compact ? 5 : 8,
                  child: _FormatPill(label: book.formatLabel, compact: compact),
                ),
              if (showText)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 12,
                    tiny ? 4 : (compact ? 24 : 32),
                    compact ? 8 : 12,
                    compact ? 8 : 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          book.title,
                          maxLines: tiny ? 1 : (compact ? 2 : 3),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: tiny ? 10 : (compact ? 11.5 : 14),
                            fontWeight: FontWeight.w800,
                            height: tiny ? 1.15 : 1.3,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: .35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (book.author.isNotEmpty && !compact && !tiny) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: 18,
                          height: 1.2,
                          color: Colors.white.withValues(alpha: .55),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .9),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 书脊左侧折痕与微高光，营造实体书脊立体感。
class _BookSpineCrease extends StatelessWidget {
  const _BookSpineCrease();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 10,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: .28),
                Colors.black.withValues(alpha: .18),
                Colors.transparent,
              ],
              stops: const [0.0, 0.35, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatPill extends StatelessWidget {
  const _FormatPill({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1.5 : 2.5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: .22),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 8.5 : 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
          height: 1.1,
        ),
      ),
    );
  }
}
