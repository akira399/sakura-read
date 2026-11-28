import 'dart:math';

import 'package:flutter/painting.dart';

/// Page layout block inside a paginated reader page.
sealed class PageBlock {
  const PageBlock();
}

/// Prose slice belonging to `[start, end)` inside the chapter text.
class PageTextBlock extends PageBlock {
  const PageTextBlock({
    required this.start,
    required this.end,
    required this.text,
    this.bottomGap = 0,
  });

  final int start;
  final int end;
  final String text;
  final double bottomGap;
}

/// Embedded illustration block corresponding to `\u0001IMG:<imageName>\u0001`.
class PageImageBlock extends PageBlock {
  const PageImageBlock({
    required this.offset,
    required this.endOffset,
    required this.imageName,
    required this.width,
    required this.height,
    this.standalone = false,
  });

  final int offset;
  final int endOffset;
  final String imageName;
  final double width;
  final double height;
  final bool standalone;
}

/// 一页的字符范围 `[start, end)` 与可选的图文混排 / 段间距块列表。
class PageSlice {
  const PageSlice(this.start, this.end, {this.blocks = const []});

  final int start;
  final int end;
  final List<PageBlock> blocks;

  bool get hasImages => blocks.any((b) => b is PageImageBlock);
}

/// Resolves the pixel dimensions of an illustration filename, or `null` if unknown.
typedef ImageSizeResolver = Size? Function(String imageName);

/// 阅读分页器：用 TextPainter 按实际排版测量每页可容纳的字符范围，支持段间距与图文混排分页。
class Paginator {
  Paginator._();

  static const String _imgPrefix = '\u0001IMG:';
  static const String _imgSuffix = '\u0001';

  /// 把整章文本分页。
  ///
  /// [size] 是正文区域的可用尺寸；[style] 必须与渲染时完全一致，
  /// 保证测量与展示的换行、行高、段间距一致。
  static List<PageSlice> paginate({
    required String text,
    required TextStyle style,
    required Size size,
    TextAlign align = TextAlign.left,
    TextDirection direction = TextDirection.ltr,
    double paragraphSpacing = 0,
    ImageSizeResolver? imageSizeResolver,
  }) {
    final pages = <PageSlice>[];
    if (text.isEmpty || size.width <= 1 || size.height <= 1) return pages;
    final session = PaginatorSession(
      style: style,
      size: size,
      align: align,
      direction: direction,
      paragraphSpacing: paragraphSpacing,
      imageSizeResolver: imageSizeResolver,
    );
    var offset = 0;
    while (offset < text.length) {
      final slice = session.nextPage(text, offset);
      pages.add(slice);
      final next = slice.end <= offset ? offset + 1 : slice.end;
      offset = _skipNewlines(text, next);
    }
    session.dispose();
    return pages;
  }

  static int _skipNewlines(String text, int offset) {
    while (offset < text.length && text.codeUnitAt(offset) == 0x0A) {
      offset++;
    }
    return offset;
  }
}

/// 可复用的分页会话：分块计算下一页的结束位置（支持真实段间距与图文混排）。
class PaginatorSession {
  PaginatorSession({
    required this.style,
    required this.size,
    this.align = TextAlign.left,
    this.direction = TextDirection.ltr,
    this.paragraphSpacing = 0,
    this.imageSizeResolver,
  }) : _painter = TextPainter(
         textDirection: direction,
         textAlign: align,
         textScaler: TextScaler.noScaling,
       ) {
    final fontSize = style.fontSize ?? 16;
    final lineHeight = fontSize * (style.height ?? 1.6);
    _charsPerLine = max(
      1,
      (size.width / (fontSize + (style.letterSpacing ?? 0))).floor(),
    );
    _linesPerPage = max(1, (size.height / lineHeight).floor());
  }

  final TextStyle style;
  final Size size;
  final TextAlign align;
  final TextDirection direction;
  final double paragraphSpacing;
  final ImageSizeResolver? imageSizeResolver;
  final TextPainter _painter;
  late final int _charsPerLine;
  late final int _linesPerPage;

  static const double _imageBlockGap = 8.0;

  int get _maxChars => _charsPerLine * _linesPerPage + _charsPerLine;

  /// 计算从 [offset] 开始的下一页（无段距且无插图走快速切片，其余走段/图块精确排版）。
  PageSlice nextPage(String text, int offset) {
    if (offset >= text.length) {
      return PageSlice(text.length, text.length);
    }
    final nextMarker = text.indexOf(Paginator._imgPrefix, offset);
    if (nextMarker < 0 && paragraphSpacing <= 0) {
      var end = fitEnd(text, offset);
      if (end <= offset) end = offset + 1;
      if (end > text.length) end = text.length;
      return PageSlice(offset, end);
    }

    final blocks = <PageBlock>[];
    var cursor = offset;
    var remH = size.height;
    var hasImage = false;
    final pGap = paragraphSpacing > 0 ? paragraphSpacing : 0.0;

    while (cursor < text.length && remH > 4) {
      final markerStart = text.indexOf(Paginator._imgPrefix, cursor);
      if (markerStart == cursor) {
        final suffixAt = text.indexOf(
          Paginator._imgSuffix,
          cursor + Paginator._imgPrefix.length,
        );
        if (suffixAt < 0) {
          final end = _fitEndInHeight(text, cursor, text.length, remH);
          if (end > cursor) {
            blocks.add(
              PageTextBlock(
                start: cursor,
                end: end,
                text: text.substring(cursor, end),
              ),
            );
            cursor = end;
          }
          break;
        }
        final imgName = text.substring(
          cursor + Paginator._imgPrefix.length,
          suffixAt,
        );
        final afterMarker = Paginator._skipNewlines(text, suffixAt + 1);
        final afterTrimmed = _hasNoMoreProseBeforeNextImage(text, afterMarker);
        final standalone = blocks.isEmpty && afterTrimmed;

        final box = _fitImageBox(
          imgName: imgName,
          standalone: standalone,
          availHeight: remH,
          isEmptyPage: blocks.isEmpty,
        );
        if (box == null) {
          break;
        }

        hasImage = true;
        blocks.add(
          PageImageBlock(
            offset: cursor,
            endOffset: suffixAt + 1,
            imageName: imgName,
            width: box.width,
            height: box.height,
            standalone: standalone,
          ),
        );
        cursor = afterMarker;
        remH -= box.height + _imageBlockGap;
        continue;
      }

      final segmentEnd = markerStart < 0 ? text.length : markerStart;
      if (pGap <= 0) {
        // 无段距纯段拟合（插图前置正文快速走整块测量）
        var trimmedEnd = segmentEnd;
        while (trimmedEnd > cursor && text.codeUnitAt(trimmedEnd - 1) == 0x0A) {
          trimmedEnd--;
        }
        if (trimmedEnd <= cursor) {
          cursor = segmentEnd;
          continue;
        }
        final fittedEnd = _fitEndInHeight(text, cursor, trimmedEnd, remH);
        if (fittedEnd <= cursor) {
          if (blocks.isEmpty) {
            final forced = cursor + 1;
            blocks.add(
              PageTextBlock(
                start: cursor,
                end: forced,
                text: text.substring(cursor, forced),
              ),
            );
            cursor = forced;
          }
          break;
        }
        final chunk = text.substring(cursor, fittedEnd);
        final h = _measure(_painter, chunk, style, size.width, align: align);
        blocks.add(PageTextBlock(start: cursor, end: fittedEnd, text: chunk));
        remH -= h + _imageBlockGap;
        if (fittedEnd < trimmedEnd) {
          cursor = fittedEnd;
          break;
        }
        cursor = segmentEnd;
        continue;
      }

      // 段间距 > 0：逐段测算并保留段落之间的真实间距
      var brokeMidSegment = false;
      while (cursor < segmentEnd && remH > 4) {
        cursor = _skipNewlinesBounded(text, cursor, segmentEnd);
        if (cursor >= segmentEnd) break;

        final nl = text.indexOf('\n', cursor);
        final paraEnd = (nl >= 0 && nl < segmentEnd) ? nl : segmentEnd;
        if (paraEnd <= cursor) {
          cursor++;
          continue;
        }

        final para = text.substring(cursor, paraEnd);
        final paraH = _measure(_painter, para, style, size.width, align: align);
        if (paraH <= remH) {
          blocks.add(
            PageTextBlock(
              start: cursor,
              end: paraEnd,
              text: para,
              bottomGap: pGap,
            ),
          );
          remH -= paraH + pGap;
          cursor = _skipNewlinesBounded(text, paraEnd, segmentEnd);
        } else {
          final fitted = _fitEndInHeight(text, cursor, paraEnd, remH);
          if (fitted > cursor) {
            blocks.add(
              PageTextBlock(
                start: cursor,
                end: fitted,
                text: text.substring(cursor, fitted),
                bottomGap: 0,
              ),
            );
            cursor = fitted;
          } else if (blocks.isEmpty) {
            final forced = cursor + 1;
            blocks.add(
              PageTextBlock(
                start: cursor,
                end: forced,
                text: text.substring(cursor, forced),
                bottomGap: 0,
              ),
            );
            cursor = forced;
          }
          brokeMidSegment = true;
          break;
        }
      }
      if (brokeMidSegment) break;
    }

    if (cursor <= offset) {
      cursor = min(text.length, offset + 1);
    }
    if (!hasImage && pGap <= 0) {
      return PageSlice(offset, cursor);
    }
    return PageSlice(offset, cursor, blocks: blocks);
  }

  static int _skipNewlinesBounded(String text, int offset, int limit) {
    while (offset < limit && text.codeUnitAt(offset) == 0x0A) {
      offset++;
    }
    return offset;
  }

  bool _hasNoMoreProseBeforeNextImage(String text, int from) {
    if (from >= text.length) return true;
    final nextImg = text.indexOf(Paginator._imgPrefix, from);
    final slice = nextImg < 0
        ? text.substring(from)
        : text.substring(from, nextImg);
    return slice.trim().isEmpty;
  }

  Size? _fitImageBox({
    required String imgName,
    required bool standalone,
    required double availHeight,
    required bool isEmptyPage,
  }) {
    final natural = imageSizeResolver?.call(imgName) ?? const Size(480, 320);
    final natW = natural.width > 0 ? natural.width : 480.0;
    final natH = natural.height > 0 ? natural.height : 320.0;
    final aspect = natW / natH;

    final maxTargetW = natW < 180
        ? min(size.width, max(natW * 1.8, 180.0))
        : size.width;
    final maxTargetH = standalone
        ? max(48.0, size.height - 12.0)
        : max(48.0, size.height * 0.62);

    var w = maxTargetW;
    var h = w / aspect;
    if (h > maxTargetH) {
      h = maxTargetH;
      w = h * aspect;
    }
    if (w > size.width) {
      w = size.width;
      h = w / aspect;
    }

    final minAcceptableH = min(
      h,
      isEmptyPage ? max(40.0, size.height - 12.0) : h,
    );
    if (!isEmptyPage && (h + 8.0 > availHeight || availHeight < 72.0)) {
      return null;
    }
    if (isEmptyPage && h > availHeight - 8.0) {
      h = max(minAcceptableH, availHeight - 8.0).clamp(40.0, size.height);
      w = min(size.width, h * aspect);
    }
    return Size(w, h);
  }

  /// 当前页结束位置（不含跳过的换行）。
  int fitEnd(String text, int offset) {
    return _fitEndInHeight(text, offset, text.length, size.height);
  }

  int _fitEndInHeight(
    String text,
    int offset,
    int upperBound,
    double maxHeight,
  ) {
    final hardHi = min(upperBound, offset + _maxChars);
    if (offset >= hardHi || maxHeight <= 0) return offset;
    final singleCharH = _measure(
      _painter,
      text.substring(offset, offset + 1),
      style,
      size.width,
      align: align,
    );
    if (singleCharH > maxHeight) return offset;

    var lo = offset + 1;
    var hi = hardHi;
    var best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final h = _measure(
        _painter,
        text.substring(offset, mid),
        style,
        size.width,
        align: align,
      );
      if (h <= maxHeight) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best < offset ? offset : best;
  }

  /// 跳过页首换行。
  int skipLeadingNewlines(String text, int offset) =>
      Paginator._skipNewlines(text, offset);

  void dispose() {
    _painter.dispose();
  }
}

double _measure(
  TextPainter painter,
  String text,
  TextStyle style,
  double width, {
  TextAlign align = TextAlign.left,
}) {
  painter.textAlign = align;
  painter.text = TextSpan(text: text, style: style);
  painter.layout(maxWidth: width);
  return painter.height;
}
