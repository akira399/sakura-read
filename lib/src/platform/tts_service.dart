import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统朗读（TTS）服务：封装原生 TextToSpeech。
///
/// - 自动挑选可用引擎（优先中文可用者）；
/// - 「按段落」朗读：一次播报一段，播完自动播下一段，便于跳段 / 调速；
/// - 播放器状态通过 [ChangeNotifier] 暴露给 UI。
class TtsService extends ChangeNotifier {
  TtsService._();

  static final TtsService instance = TtsService._();

  /// 与原生共用的通道名（见 MainActivity.kt）。
  static const MethodChannel _channel = MethodChannel('sakuramanga/native');

  bool _supported = false;
  bool _ready = false;
  bool _speaking = false;
  bool _paused = false;
  String? _lastError;

  /// 当前朗读的段落序号（-1 = 未开始）。
  int _index = -1;

  /// 待朗读的段落列表。
  List<String> _paragraphs = const [];

  /// 播完一段后的回调（用于翻页 / 滚动跟随）。
  void Function(int index)? onParagraph;

  /// 全部播完的回调。
  VoidCallback? onFinished;

  bool get supported => _supported;
  bool get ready => _ready;
  bool get speaking => _speaking;
  bool get paused => _paused;
  String? get lastError => _lastError;
  int get index => _index;
  int get total => _paragraphs.length;

  /// 初始化（惰性）：探测引擎并尝试建立 TTS 连接。
  ///
  /// 返回 true = 可用；false = 设备无可用引擎（调用方应提示用户去安装）。
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_supported && _lastError != null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('ttsInit', {'engine': null});
      _supported = true;
      _ready = ok == true;
      if (!_ready) _lastError = '系统未安装可用的语音引擎';
    } on PlatformException catch (e) {
      _supported = false;
      _ready = false;
      _lastError = e.message ?? '朗读初始化失败';
    } on MissingPluginException {
      _supported = false;
      _ready = false;
      _lastError = '当前平台不支持系统朗读';
    }
    notifyListeners();
    return _ready;
  }

  /// 设备上可用的 TTS 引擎包名列表。
  Future<List<String>> engines() async {
    try {
      final list = await _channel.invokeListMethod<String>('ttsEngines');
      return list ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 开始朗读一组段落（从 [from] 段开始）。
  Future<void> start(
    List<String> paragraphs, {
    int from = 0,
    double rate = 1.0,
    double pitch = 1.0,
  }) async {
    if (!await ensureReady()) return;
    _paragraphs = paragraphs.where((p) => p.trim().isNotEmpty).toList();
    if (_paragraphs.isEmpty) return;
    _index = from.clamp(0, _paragraphs.length - 1);
    _paused = false;
    _speaking = true;
    await _setRate(rate);
    await _setPitch(pitch);
    _listenNative();
    await _speakCurrent(flush: true);
    notifyListeners();
  }

  /// 继续朗读（暂停后恢复 / 从头开始）。
  Future<void> resume({double rate = 1.0, double pitch = 1.0}) async {
    if (_paragraphs.isEmpty) return;
    if (!await ensureReady()) return;
    _paused = false;
    _speaking = true;
    await _setRate(rate);
    await _setPitch(pitch);
    await _speakCurrent(flush: true);
    notifyListeners();
  }

  /// 暂停（停止当前播报，保留进度）。
  Future<void> pause() async {
    _paused = true;
    _speaking = false;
    try {
      await _channel.invokeMethod('ttsStop');
    } catch (_) {}
    notifyListeners();
  }

  /// 停止并清空。
  Future<void> stop() async {
    _paused = false;
    _speaking = false;
    _index = -1;
    _paragraphs = const [];
    try {
      await _channel.invokeMethod('ttsStop');
    } catch (_) {}
    notifyListeners();
  }

  /// 跳到指定段落。
  Future<void> seek(int index, {double rate = 1.0}) async {
    if (_paragraphs.isEmpty) return;
    _index = index.clamp(0, _paragraphs.length - 1);
    if (!_speaking) {
      notifyListeners();
      return;
    }
    await _setRate(rate);
    await _speakCurrent(flush: true);
    notifyListeners();
  }

  /// 下一段 / 上一段。
  Future<void> next({double rate = 1.0}) => seek(_index + 1, rate: rate);

  Future<void> previous({double rate = 1.0}) => seek(_index - 1, rate: rate);

  /// 调整语速（立即生效于后续段落）。
  Future<void> setRate(double rate) async {
    await _setRate(rate);
    if (_speaking) {
      // 重新播报当前段以应用新语速
      await _speakCurrent(flush: true);
    }
  }

  Future<void> setPitch(double pitch) => _setPitch(pitch);

  Future<void> _setRate(double rate) async {
    try {
      await _channel.invokeMethod('ttsSetRate', {'rate': rate});
    } catch (_) {}
  }

  Future<void> _setPitch(double pitch) async {
    try {
      await _channel.invokeMethod('ttsSetPitch', {'pitch': pitch});
    } catch (_) {}
  }

  Future<void> _speakCurrent({bool flush = true}) async {
    final i = _index;
    if (i < 0 || i >= _paragraphs.length) return;
    try {
      await _channel.invokeMethod('ttsSpeak', {
        'text': _paragraphs[i],
        'utteranceId': 'p$i',
        'flush': flush,
      });
    } catch (_) {}
  }

  bool _listening = false;

  /// 监听原生侧的播报进度事件（start / done / error）。
  void _listenNative() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'ttsState') return;
      final args = (call.arguments as Map?) ?? {};
      final state = args['state'] as String?;
      switch (state) {
        case 'done':
          if (!_speaking || _paused) return;
          final next = _index + 1;
          if (next >= _paragraphs.length) {
            _speaking = false;
            _index = -1;
            onFinished?.call();
            notifyListeners();
            return;
          }
          _index = next;
          onParagraph?.call(next);
          notifyListeners();
          await _speakCurrent(flush: true);
          break;
        case 'error':
          _speaking = false;
          _lastError = '朗读出错，请检查语音引擎';
          notifyListeners();
          break;
      }
    });
  }

  /// 释放原生资源（App 退出时调用）。
  Future<void> shutdown() async {
    try {
      await _channel.invokeMethod('ttsShutdown');
    } catch (_) {}
    _ready = false;
    _speaking = false;
    _index = -1;
  }
}

/// 一段可朗读文本 + 它在原文中的起始偏移（用于朗读自动跟随）。
class SpeechParagraph {
  const SpeechParagraph(this.text, this.offset);

  final String text;

  /// 在传入原文中的字符起始位置。
  final int offset;
}

/// 把章节正文切成适合朗读的段落（带原文偏移）。
///
/// 规则：按行切 → 去空行 → 合并相邻短行到 [maxLen] 以内；超长行按标点断句。
List<SpeechParagraph> splitForSpeechWithOffsets(
  String text, {
  int maxLen = 200,
  int minLen = 40,
}) {
  final out = <SpeechParagraph>[];
  final buf = StringBuffer();
  var bufStart = -1;

  void flush() {
    final s = buf.toString().trim();
    if (s.isNotEmpty && bufStart >= 0) out.add(SpeechParagraph(s, bufStart));
    buf.clear();
    bufStart = -1;
  }

  var lineStart = 0;
  for (final rawLine in text.split('\n')) {
    final start = lineStart;
    lineStart += rawLine.length + 1; // +1 为换行符
    final line = rawLine.replaceAll('　', ' ').replaceAll('\r', '').trim();
    if (line.isEmpty) continue;

    if (line.length > maxLen) {
      flush();
      for (final seg in _splitLongLineWithOffsets(
        rawLine,
        start,
        maxLen,
        minLen,
      )) {
        out.add(seg);
      }
      continue;
    }
    if (buf.isEmpty) {
      bufStart = start;
      buf.write(line);
    } else if (buf.length + line.length + 1 <= maxLen) {
      buf.write(' ');
      buf.write(line);
    } else {
      flush();
      bufStart = start;
      buf.write(line);
    }
    if (buf.length >= maxLen) flush();
  }
  flush();
  return out;
}

/// 把超长行按标点切成 [maxLen] 以内的片段（保留原行内偏移）。
List<SpeechParagraph> _splitLongLineWithOffsets(
  String rawLine,
  int lineStart,
  int maxLen,
  int minLen,
) {
  final out = <SpeechParagraph>[];
  final line = rawLine;
  var start = 0;
  while (start < line.length) {
    var end = (start + maxLen).clamp(0, line.length);
    if (end < line.length) {
      final window = line.substring(start, end);
      final cut = window.lastIndexOf(RegExp(r'[。！？；，、…]'));
      if (cut >= minLen) end = start + cut + 1;
    }
    final seg = line.substring(start, end).trim();
    if (seg.isNotEmpty) {
      out.add(SpeechParagraph(seg, lineStart + start));
    }
    start = end;
  }
  return out;
}

/// 把章节正文切成适合朗读的段落（只要文本）。
List<String> splitForSpeech(String text, {int maxLen = 200, int minLen = 40}) =>
    splitForSpeechWithOffsets(
      text,
      maxLen: maxLen,
      minLen: minLen,
    ).map((p) => p.text).toList();
