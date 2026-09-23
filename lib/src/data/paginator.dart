import 'dart:math';

import 'package:flutter/painting.dart';

/// 一页的字符范围 [start, end)。
class PageSlice {
  const PageSlice(this.start, this.end);

  final int start;
  final int end;
}

/// 阅读分页器：用 TextPainter 按实际排版测量每页可容纳的字符范围。
class Paginator {
  Paginator._();

  /// 把整章文本分页。
  ///
  /// [size] 是正文区域的可用尺寸；[style] 必须与渲染时完全一致，
  /// 保证测量与展示的换行、行高一致。
  static List<PageSlice> paginate({
    required String text,
    required TextStyle style,
    required Size size,
    TextAlign align = TextAlign.left,
    TextDirection direction = TextDirection.ltr,
  }) {
    final pages = <PageSlice>[];
    if (text.isEmpty || size.width <= 1 || size.height <= 1) return pages;
    final session = PaginatorSession(
      style: style,
      size: size,
      align: align,
      direction: direction,
    );
    var offset = 0;
    while (offset < text.length) {
      var end = session.fitEnd(text, offset);
      if (end <= offset) end = offset + 1;
      if (end > text.length) end = text.length;
      pages.add(PageSlice(offset, end));
      offset = _skipNewlines(text, end);
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

/// 可复用的分页会话：分块计算下一页的结束位置（避免一次性分页卡顿）。
class PaginatorSession {
  PaginatorSession({
    required this.style,
    required this.size,
    this.align = TextAlign.left,
    this.direction = TextDirection.ltr,
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
  final TextPainter _painter;
  late final int _charsPerLine;
  late final int _linesPerPage;

  int get _maxChars => _charsPerLine * _linesPerPage + _charsPerLine;

  /// 当前页结束位置（不含跳过的换行）。
  int fitEnd(String text, int offset) {
    return _fitEnd(
      painter: _painter,
      text: text,
      offset: offset,
      style: style,
      size: size,
      maxChars: _maxChars,
      align: align,
      direction: direction,
    );
  }

  /// 跳过页首换行。
  int skipLeadingNewlines(String text, int offset) =>
      Paginator._skipNewlines(text, offset);

  void dispose() {
    _painter.dispose();
  }
}

/// 二分查找当前页能容纳的最大结束位置。
int _fitEnd({
  required TextPainter painter,
  required String text,
  required int offset,
  required TextStyle style,
  required Size size,
  required int maxChars,
  required TextAlign align,
  required TextDirection direction,
}) {
  var lo = offset + 1;
  var hi = min(text.length, offset + maxChars);
  var best = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final h = _measure(painter, text.substring(offset, mid), style, size.width);
    if (h <= size.height) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (best <= offset) return offset + 1;
  return best;
}

double _measure(
  TextPainter painter,
  String text,
  TextStyle style,
  double width,
) {
  painter.text = TextSpan(text: text, style: style);
  painter.layout(maxWidth: width);
  return painter.height;
}
