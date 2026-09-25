import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models.dart';

/// 书籍封面：优先真实封面图；无封面时生成樱粉渐变封面。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.radius = 16,
    this.strong = false,
  });

  final Book book;
  final double radius;

  /// 详情页放大使用。
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    Widget content;
    if (!book.generatedCover && path != null && File(path).existsSync()) {
      content = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => GeneratedCover(book: book),
      );
    } else {
      content = GeneratedCover(book: book);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }
}

/// 程序生成的渐变封面（按书名取色，稳定不随机）。
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.book});

  final Book book;

  static const List<List<Color>> _pairs = [
    [Color(0xFFFF9EC7), Color(0xFF9D8CFF)],
    [Color(0xFF8FD3FF), Color(0xFF9D8CFF)],
    [Color(0xFF9BE8C0), Color(0xFF5BB8F5)],
    [Color(0xFFFFC59E), Color(0xFFFF9EC7)],
    [Color(0xFFA5B4FF), Color(0xFFE4A1FF)],
    [Color(0xFFFFB3C8), Color(0xFFFFD98A)],
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 小尺寸封面（列表缩略图 44×60 等）自适应：
          // 压缩行数 / 字号并收紧内边距，避免文字把封面撑爆（RenderFlex 溢出）
          final h = constraints.maxHeight;
          final compact = h < 140;
          final tiny = h < 76;
          return Stack(
            fit: StackFit.expand,
            children: [
              // 默认封面插画（按书名稳定选取；加载失败则退回渐变底）
              Positioned.fill(
                child: Image.asset(
                  _coverAssets[_titleHash % _coverAssets.length],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              // 底部渐暗遮罩，保证书名可读
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: compact ? 64 : 108,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x73000000)],
                    ),
                  ),
                ),
              ),
              // 书名 / 作者
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 6 : 12,
                  0,
                  compact ? 6 : 12,
                  compact ? 8 : 16,
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
                          fontSize: tiny ? 10 : (compact ? 12 : 15),
                          fontWeight: FontWeight.w900,
                          height: tiny ? 1.1 : 1.35,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: .18),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (book.author.isNotEmpty && !tiny) ...[
                      SizedBox(height: compact ? 3 : 6),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .88),
                          fontSize: compact ? 9 : 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 格式角标（超小封面不显示，避免拥挤）
              if (!tiny)
                Positioned(
                  left: compact ? 6 : 10,
                  bottom: compact ? 6 : 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      book.formatLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
