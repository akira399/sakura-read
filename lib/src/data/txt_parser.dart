import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// TXT 解析结果。
class TxtParseResult {
  TxtParseResult({
    required this.text,
    required this.encoding,
    required this.chapters,
  });

  final String text;
  final String encoding;

  /// 章节引用（含 start / end 字符偏移）。
  final List<ChapterRefLike> chapters;
}

/// 轻量章节结构（解析阶段使用，导入时转换为模型层 ChapterRef）。
class ChapterRefLike {
  ChapterRefLike({required this.title, required this.start, required this.end});

  final String title;
  final int start;
  final int end;
}

/// TXT 小说解析：编码探测（UTF-8 / UTF-16 / GBK）+ 章节切分。
class TxtParser {
  TxtParser._();

  /// 单章最大标题长度（超过视为正文行，不当作章节标题）。
  static const int maxTitleLength = 50;

  /// 判定标题时允许的最大行长（比 [maxTitleLength] 更严）。
  ///
  /// 用户反馈「目录识别过于松垮」：正文里以「第 N 章」开头的整句也会被当成
  /// 章节标题，目录里就会多出大量假条目。真正的标题很少超过 32 个字。
  static const int _maxHeadingLineLength = 32;

  /// 标题里不应出现的句读符号（出现即认为是正文句子，不是标题）。
  static const String _sentencePunct = '。，、；：！？…—""''《》（）()[]{}<>';

  static List<RegExp>? _patterns;

  static List<RegExp> get _chapterPatterns => _patterns ??= [
    // 第1章 / 第一百二十三回 / 第 2 节 …（可带标题）
    RegExp(r'^[ \t　]*第[0-9零一二三四五六七八九十百千万两〇]{1,12}[章回节卷篇集话部][^\n]{0,40}$'),
    // 序章 / 楔子 / 尾声 / 番外 等
    RegExp(
      r'^[ \t　]*(?:序章|序言|序|楔子|引子|前言|开篇|后记|尾声|终章|尾章|番外[0-9一二三四五六七八九十]*|外传[0-9一二三四五六七八九十]*|附录[0-9一二三四五六七八九十]*)[^\n]{0,40}$',
    ),
    // Chapter 1 / CHAPTER 12
    RegExp(
      r'^[ \t　]*(?:Chapter|CHAPTER|chapter|Chap\.?|CHAP\.?)\s*[0-9IVXLCivxlc]{1,8}[^\n]{0,40}$',
    ),
    // 【第一章 标题】
    RegExp(r'^[ \t　]*【[^】\n]{1,40}】[ \t　]*$'),
  ];

  /// 从文件字节解析。
  static TxtParseResult parseBytes(Uint8List bytes) {
    final decoded = decodeBytes(bytes);
    return parseText(decoded.text, encoding: decoded.encoding);
  }

  /// 从已解码文本解析（text 为内容，encoding 仅作记录）。
  static TxtParseResult parseText(String text, {String encoding = 'utf-8'}) {
    final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final chapters = splitChapters(clean);
    return TxtParseResult(text: clean, encoding: encoding, chapters: chapters);
  }

  /// 章节切分：按行匹配常见章节标题模式。
  static List<ChapterRefLike> splitChapters(String text) {
    final markers = <_Marker>[];

    var lineStart = 0;
    while (lineStart <= text.length) {
      var lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd == -1) lineEnd = text.length;
      final line = text.substring(lineStart, lineEnd);
      final trimmed = line.trim();

      if (trimmed.isNotEmpty &&
          trimmed.length <= _maxHeadingLineLength &&
          // 带首行缩进的通常是正文（注意：trim 会把行首缩进吃掉，
          // 所以必须用未 trim 的原始行判断，之前这里有 bug → 目录过松）
          !_hasBodyIndent(line) &&
          _looksLikeTitle(trimmed)) {
        markers.add(_Marker(title: _normalizeTitle(trimmed), start: lineStart));
      }

      if (lineEnd >= text.length) break;
      lineStart = lineEnd + 1;
    }

    if (markers.length < 2) {
      // 没识别出章节：整篇一章
      return [ChapterRefLike(title: '全文', start: 0, end: text.length)];
    }

    // 标题前的序言内容
    final first = markers.first;
    final refs = <ChapterRefLike>[];
    if (first.start > 400) {
      refs.add(ChapterRefLike(title: '开始', start: 0, end: first.start));
    }

    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      final end = i + 1 < markers.length ? markers[i + 1].start : text.length;
      refs.add(ChapterRefLike(title: m.title, start: m.start, end: end));
    }
    return refs;
  }

  static bool _looksLikeTitle(String line) {
    for (final re in _chapterPatterns) {
      if (!re.hasMatch(line)) continue;
      // 排除误匹配：标题里不含句读 / 不以句号收尾（正文被当成标题）。
      // 用户反馈「目录识别过于松垮」：以句号收尾的整句一律不是标题，
      // 不管多短（「第三章正文，故事继续往下走。」就是正文）。
      if (line.endsWith('。') || line.endsWith('.')) return false;
      if (_sentencePunctCount(line) > 2) return false;
      if (line.endsWith('！') || line.endsWith('？')) {
        // 短标题偶尔带问号（「第一章 谁在那里？」），长句基本是正文
        return line.length <= 16;
      }
      return true;
    }
    return false;
  }

  /// 行首是否带「正文缩进」（2 个全角空格 / 4 个半角空格起步）。
  ///
  /// 必须用未 trim 的原始行判断：正文首行缩进在 `trim()` 后就看不出来了，
  /// 这正是旧实现「目录过于松垮」的原因。
  static bool _hasBodyIndent(String line) {
    var fullWidth = 0;
    var halfWidth = 0;
    for (var i = 0; i < line.length && i < 8; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x3000) {
        fullWidth++;
      } else if (c == 0x20 || c == 0x09) {
        halfWidth++;
      } else {
        break;
      }
    }
    return fullWidth >= 2 || halfWidth >= 4;
  }

  static int _sentencePunctCount(String line) {
    var n = 0;
    for (var i = 0; i < line.length; i++) {
      if (_sentencePunct.contains(line[i])) n++;
    }
    return n;
  }

  static String _normalizeTitle(String line) {
    var t = line.replaceAll(RegExp(r'[ \t　]+'), ' ').trim();
    if (t.length > maxTitleLength) t = t.substring(0, maxTitleLength);
    return t;
  }

  // ---------- 编码探测 ----------

  /// 探测并解码字节：BOM → UTF-8 → GBK → 兜底 UTF-8(容错)。
  static ({String text, String encoding}) decodeBytes(Uint8List bytes) {
    // BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return (
        text: utf8.decode(bytes.sublist(3), allowMalformed: true),
        encoding: 'utf-8',
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (
        text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
        encoding: 'utf-16le',
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (
        text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
        encoding: 'utf-16be',
      );
    }

    // 严格 UTF-8
    try {
      return (text: utf8.decode(bytes), encoding: 'utf-8');
    } catch (_) {
      // 继续探测
    }

    // UTF-16 无 BOM（大量 \x00 交替）
    if (_looksLikeUtf16(bytes)) {
      final le = _decodeUtf16(bytes, littleEndian: true);
      final be = _decodeUtf16(bytes, littleEndian: false);
      final leBad = _badRatio(le);
      final beBad = _badRatio(be);
      if (leBad <= beBad) return (text: le, encoding: 'utf-16le');
      return (text: be, encoding: 'utf-16be');
    }

    // GBK
    try {
      final text = gbk.decode(bytes);
      if (!text.contains('\uFFFD')) {
        return (text: text, encoding: 'gbk');
      }
    } catch (_) {
      // 继续兜底
    }

    return (text: utf8.decode(bytes, allowMalformed: true), encoding: 'utf-8');
  }

  static bool _looksLikeUtf16(Uint8List bytes) {
    if (bytes.length < 16) return false;
    final sample = bytes.length > 512 ? 512 : bytes.length;
    var zeros = 0;
    for (var i = 0; i < sample; i++) {
      if (bytes[i] == 0) zeros++;
    }
    return zeros > sample * 0.25;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(codeUnits);
  }

  static double _badRatio(String text) {
    if (text.isEmpty) return 1;
    var bad = 0;
    final len = text.length > 500 ? 500 : text.length;
    for (var i = 0; i < len; i++) {
      final c = text.codeUnitAt(i);
      // 控制字符（除常见空白）视为坏字符
      if (c < 0x20 && c != 0x0A && c != 0x0D && c != 0x09) bad++;
    }
    return bad / len;
  }
}

class _Marker {
  _Marker({required this.title, required this.start});

  final String title;
  final int start;
}
