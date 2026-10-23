import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'offline_tts.dart';

/// 系统朗读（TTS）服务：封装原生 TextToSpeech。
///
/// - 自动挑选可用引擎（优先中文可用者）；
/// - 支持**手动指定引擎**（用户反馈：一加等机型自带引擎被忽略 → 朗读不可用）；
/// - 指定引擎失败时**自动回退**到其它可用引擎，避免「用不了」；
/// - 系统一个引擎都没有时，**兜底用内置离线语音**（sherpa-onnx 合成 +
///   原生 MediaPlayer 播放），彻底解决「系统未安装 TTS 引擎 → 听不了书」；
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

  /// 用户指定的引擎包名（null / 空 = 交给系统挑默认）。
  String? _preferredEngine;

  /// 当前实际生效的引擎（用于诊断提示）。
  String? _activeEngine;

  /// 当前朗读的段落序号（-1 = 未开始）。
  int _index = -1;

  /// 待朗读的段落列表。
  List<String> _paragraphs = const [];

  /// 是否正在用内置离线语音（系统引擎全都用不了时的兜底）。
  bool _usingOffline = false;

  /// 内置离线语音的合成目录（WAV 落地位置）。
  String? _offlineDir;

  /// 当前语速（内置离线语音合成时按它调速）。
  double _rate = 1.0;

  /// 合成请求序号：只播放「最新一次」合成结果，避免暂停后残留的音频抢播。
  int _speakSeq = 0;

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

  /// 用户指定的引擎（设置页展示用）。
  String? get preferredEngine => _preferredEngine;

  /// 实际生效的引擎（可能与指定值不同：指定失败时回退过）。
  String? get activeEngine => _activeEngine;

  /// 当前是否在用内置离线语音（设置页据此显示「内置语音」）。
  bool get usingOffline => _usingOffline;

  /// 设置页用的引擎候选列表：内置语音排在最前，避免用户「一个都装不了」。
  static const String builtinEngineId = OfflineTtsEngine.engineId;

  /// 指定朗读引擎（null / 空 = 系统默认）；会重置连接以便下次用新引擎。
  Future<void> setPreferredEngine(String? engine) async {
    final next = (engine == null || engine.isEmpty) ? null : engine;
    if (_preferredEngine == next) return;
    // 换引擎必须重建原生 TTS 实例（否则继续用旧引擎）
    await _teardown();
    _preferredEngine = next;
    notifyListeners();
  }

  /// 初始化（惰性）：探测引擎并尝试建立 TTS 连接。
  ///
  /// 返回 true = 可用；false = 设备无可用引擎（调用方应提示用户去安装）。
  ///
  /// 关键改进（用户反馈「一加15自带语音引擎，用不了朗读」）：
  /// 以前只试「指定引擎（默认 null → 系统默认）」一次，失败即放弃。
  /// 现在按「用户指定 → 系统默认 → 逐个可用引擎」依次尝试，
  /// 任一成功即可用——显著提高国产 ROM（自带引擎未注册为默认）的成功率。
  ///
  /// 最后还有一层兜底：系统引擎全都用不了时启动**内置离线语音**
  /// （用户反馈「朗读暂时不可用 · 系统未安装语音合成引擎」）。
  Future<bool> ensureReady() async {
    if (_ready) return true;
    if (_supported && _lastError != null && _preferredEngine == null) {
      return false;
    }
    _supported = true;

    // 用户显式选了内置语音 → 不走系统引擎，直接起离线引擎
    if (_preferredEngine == builtinEngineId) {
      return _ensureOffline();
    }

    final candidates = <String?>[
      if (_preferredEngine != null) _preferredEngine,
      null, // 系统默认（让系统自己挑）
      ...await engines(), // 兜底：逐个试设备上所有引擎
    ];

    for (final engine in candidates) {
      final ok = await _tryInit(engine);
      if (ok) {
        _ready = true;
        _usingOffline = false;
        _activeEngine = engine ?? _activeEngine ?? 'system';
        _lastError = null;
        notifyListeners();
        return true;
      }
    }

    // 系统引擎全军覆没 → 内置离线语音兜底
    if (await _ensureOffline()) return true;

    _ready = false;
    _lastError = OfflineTtsEngine.instance.lastError ?? '系统未安装可用的语音引擎，或引擎初始化失败';
    notifyListeners();
    return false;
  }

  /// 启动内置离线语音（失败返回 false）。
  Future<bool> _ensureOffline() async {
    final ok = await OfflineTtsEngine.instance.prepare();
    if (ok) {
      _ready = true;
      _usingOffline = true;
      _activeEngine = builtinEngineId;
      _lastError = null;
      notifyListeners();
    }
    return ok;
  }

  /// 用指定引擎尝试初始化（失败返回 false，不抛异常）。
  Future<bool> _tryInit(String? engine) async {
    try {
      final ok = await _channel.invokeMethod<bool>('ttsInit', {
        'engine': engine,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// 断开原生 TTS（换引擎 / 重试前调用）。
  Future<void> _teardown() async {
    try {
      await _channel.invokeMethod('ttsShutdown');
    } catch (_) {}
    _ready = false;
    _speaking = false;
    _index = -1;
    _usingOffline = false;
  }

  /// 重置错误状态并强制重新初始化（设置页「重试」用）。
  Future<bool> reinit() async {
    await _teardown();
    _lastError = null;
    _supported = false;
    notifyListeners();
    return ensureReady();
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
    // 内置离线语音在合成时按 _rate 调速，无需下发原生（系统引擎才会用到）
    _rate = rate;
    if (_usingOffline) return;
    try {
      await _channel.invokeMethod('ttsSetRate', {'rate': rate});
    } catch (_) {}
  }

  Future<void> _setPitch(double pitch) async {
    if (_usingOffline) return; // 内置 VITS 模型不支持音调调节
    try {
      await _channel.invokeMethod('ttsSetPitch', {'pitch': pitch});
    } catch (_) {}
  }

  Future<void> _speakCurrent({bool flush = true}) async {
    final i = _index;
    if (i < 0 || i >= _paragraphs.length) return;
    if (_usingOffline) {
      await _speakOffline(_paragraphs[i], i);
      return;
    }
    try {
      await _channel.invokeMethod('ttsSpeak', {
        'text': _paragraphs[i],
        'utteranceId': 'p$i',
        'flush': flush,
      });
    } catch (_) {}
  }

  /// 内置离线语音：合成 → 交给原生播放 → 走和系统引擎一样的 done 事件。
  ///
  /// 合成在独立 isolate 里做，UI 不会卡；播完一段再合成下一段，
  /// 这样切换段落 / 调语速都能立刻响应。
  Future<void> _speakOffline(String text, int index) async {
    final engine = OfflineTtsEngine.instance;
    final seq = ++_speakSeq;
    final dir = await _offlinePath();
    if (!_speaking) return;
    final clean = text.replaceAll(RegExp(r'[\u0001-\u0008\u000b-\u001f]'), '');
    final ok = await engine.synthesize(
      clean,
      outPath: '$dir/p$index.wav',
      speed: _rate,
    );
    // 合成期间用户可能已经暂停 / 跳段 / 点了下一段：只播最新那次
    if (seq != _speakSeq || !_speaking || _index != index) return;
    if (!ok) {
      _lastError = engine.lastError ?? '内置语音合成失败';
      notifyListeners();
      await _onOfflineError();
      return;
    }
    try {
      await _channel.invokeMethod<bool>('ttsPlayFile', {
        'path': '$dir/p$index.wav',
        'utteranceId': 'p$index',
      });
    } catch (_) {}
  }

  /// 合成文件落地目录（App 缓存目录下 tts_speech/）。
  Future<String> _offlinePath() async {
    final cached = _offlineDir;
    if (cached != null) return cached;
    final dirs = await NativeBridge.appDirs();
    final dir = Directory('${dirs.cache}/tts_speech');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _offlineDir = dir.path;
    return dir.path;
  }

  /// 内置语音出错：停下来并提示，避免「点了朗读没反应」。
  Future<void> _onOfflineError() async {
    _speaking = false;
    notifyListeners();
    onError?.call(_lastError ?? '内置语音出错了');
  }

  /// 朗读出错时的回调（UI 用来弹提示）。
  void Function(String message)? onError;

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
          onError?.call(_lastError!);
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
    _usingOffline = false;
    OfflineTtsEngine.instance.dispose();
  }
}

/// 一段可朗读文本 + 它在原文中的起始偏移（用于朗读自动跟随）。
class SpeechParagraph {
  const SpeechParagraph(this.text, this.offset);

  final String text;

  /// 在传入原文中的字符起始位置。
  final int offset;
}

/// EPUB 插图占位标记：`\u0001IMG:文件名\u0001`（与 EpubParser 保持一致）。
///
/// 朗读前必须整段剔除，否则语音引擎会把标记里的文件名逐字念出来。
final RegExp _imageMarker = RegExp('\u0001IMG:[^\u0001]*\u0001');

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
    // 插图标记（\u0001IMG:pic1.png\u0001）不是正文：不剔掉的话内置语音会把
    // 「IMG pic1 png」逐字念出来（系统引擎同样会照读）。这里先整段移除，
    // 只剩标记的行自然变空行被跳过；offset 仍按原始行首计算，不影响自动跟读。
    final line = rawLine
        .replaceAll(_imageMarker, '')
        .replaceAll('［插图］', '')
        .replaceAll('　', ' ')
        .replaceAll('\r', '')
        .trim();
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
