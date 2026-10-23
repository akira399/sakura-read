import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'native_bridge.dart';

/// 内置离线朗读引擎（sherpa-onnx + VITS「超文」中文模型）。
///
/// 为什么要有它：用户反馈「朗读暂时不可用 · 系统未安装语音合成(TTS)引擎」——
/// 相当一部分机型（尤其国产 ROM / 精简版系统）根本没有可用的系统语音服务，
/// 只提示「去装一个」体验很差。这里直接内置一套离线语音：
///
///  - 合成：sherpa-onnx（Apache-2.0）+ VITS 中文模型「超文」（CC0，22.05kHz）；
///  - 播放：交给原生 MediaPlayer（见 MainActivity 的 ttsPlayFile），
///    复用现有 TTS 的 start / done / error 事件，朗读链路无需改动；
///  - 合成本身跑在**独立 isolate**：模型加载与推理不阻塞 UI，
///    一边播上一段、一边合成下一段，听起来是连续的。
///
/// 资源布局：`assets/tts/chaowen/` 打进 APK，首次使用时释放到
/// `<files>/tts/chaowen/`（sherpa 需要真实文件路径，不能直接读 asset）。
class OfflineTtsEngine {
  OfflineTtsEngine._();

  static final OfflineTtsEngine instance = OfflineTtsEngine._();

  /// 设置页 / 阅读页里代表「内置离线语音」的引擎标识。
  static const String engineId = 'builtin:sakura';

  /// 资源目录。
  static const String assetDir = 'assets/tts/chaowen';

  /// 需要释放到磁盘的文件（顺序无所谓）。
  static const List<String> assetFiles = <String>[
    'zh_CN-chaowen-medium.onnx',
    'lexicon.txt',
    'tokens.txt',
    'number.fst',
    'date.fst',
    'phone.fst',
  ];

  Isolate? _isolate;
  ReceivePort? _rx;
  SendPort? _tx;
  Completer<void>? _starting;
  Completer<bool>? _preparing;
  String? _dir;
  int _seq = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  /// 最近一次失败原因（设置页「测试朗读」用来给用户看）。
  String? lastError;

  bool get isRunning => _tx != null;

  /// 释放资源文件（幂等；已经释放过且大小对得上就跳过）。
  Future<String> _ensureAssets() async {
    final cached = _dir;
    if (cached != null) return cached;
    final dirs = await NativeBridge.appDirs();
    final dir = Directory('${dirs.files}/tts/chaowen');
    dir.createSync(recursive: true);
    for (final name in assetFiles) {
      final file = File('${dir.path}/$name');
      final data = await rootBundle.load('$assetDir/$name');
      // 已存在且大小一致 → 不重复写（省掉首次之后的 20MB 拷贝）
      if (file.existsSync() && file.lengthSync() == data.lengthInBytes) {
        continue;
      }
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _dir = dir.path;
    return dir.path;
  }

  /// 准备引擎：释放资源 + 起 isolate 加载模型。
  ///
  /// 返回 false 表示这台设备上用不了内置语音（资源损坏 / 内存不足等），
  /// 调用方应回退到系统引擎或提示用户。
  Future<bool> prepare() async {
    if (_tx != null) return true;
    final inFlight = _preparing;
    if (inFlight != null) return inFlight.future;
    final completer = Completer<bool>();
    _preparing = completer;
    try {
      final dir = await _ensureAssets();
      await _startIsolate(dir);
      completer.complete(true);
    } catch (e) {
      lastError = '内置语音启动失败：$e';
      debugPrint('[offline-tts] prepare failed: $e');
      completer.complete(false);
    } finally {
      _preparing = null;
    }
    return completer.future;
  }

  Future<void> _startIsolate(String dir) async {
    final existing = _starting;
    if (existing != null) {
      await existing.future;
      return;
    }
    final completer = Completer<void>();
    _starting = completer;
    final rx = ReceivePort();
    _rx = rx;
    rx.listen((message) {
      // isolate 崩了：onError 发 [error, stackTrace]，onExit 发 null
      if (message is List) {
        final err = message.isNotEmpty ? message.first : '未知错误';
        lastError = '内置语音崩溃：$err';
        debugPrint('[offline-tts] isolate error: $err');
        _tx = null;
        _isolate = null;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (message == null) {
        lastError ??= '内置语音意外退出';
        _tx = null;
        _isolate = null;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'ready') {
        _tx = message['sendPort'] as SendPort;
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (type == 'fatal') {
        lastError = '内置语音加载失败：${message['message']}';
        debugPrint('[offline-tts] fatal: ${message['message']}');
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (type == 'result') {
        final id = message['id'] as int;
        final pending = _pending.remove(id);
        pending?.complete(Map<String, dynamic>.from(message));
      }
    });
    _isolate = await Isolate.spawn(
      _ttsIsolateMain,
      <Object>[
        rx.sendPort,
        <String, String>{
          'model': '$dir/zh_CN-chaowen-medium.onnx',
          'lexicon': '$dir/lexicon.txt',
          'tokens': '$dir/tokens.txt',
          'ruleFsts': '$dir/number.fst,$dir/date.fst,$dir/phone.fst',
        },
      ],
      debugName: 'sakura-offline-tts',
      // isolate 里崩了也要让上层知道，否则只会卡到超时、用户看到「没反应」
      onError: rx.sendPort,
      onExit: rx.sendPort,
      errorsAreFatal: true,
    );
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
    if (_tx == null) {
      throw StateError(lastError ?? '内置语音没有就绪');
    }
    _starting = null;
  }

  /// 合成一段文字到 [outPath]（WAV），返回是否成功。
  ///
  /// [speed] 与系统朗读的「语速」含义一致（1.0 = 正常）。
  Future<bool> synthesize(
    String text, {
    required String outPath,
    double speed = 1.0,
  }) async {
    if (text.trim().isEmpty) return false;
    if (!await prepare()) return false;
    final tx = _tx;
    if (tx == null) return false;
    final id = ++_seq;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    tx.send(<String, Object>{
      'id': id,
      'text': text,
      'speed': speed,
      'path': outPath,
    });
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _pending.remove(id);
          return <String, dynamic>{'ok': false, 'error': '合成超时'};
        },
      );
      final ok = result['ok'] == true;
      if (!ok) {
        lastError = '合成失败：${result['error'] ?? '未知原因'}';
        debugPrint('[offline-tts] synth failed: $lastError');
      }
      return ok;
    } catch (e) {
      _pending.remove(id);
      lastError = '合成失败：$e';
      return false;
    }
  }

  /// 释放 isolate（App 退出 / 换引擎时调用）。
  void dispose() {
    _pending.clear();
    _tx = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rx?.close();
    _rx = null;
    _starting = null;
    _preparing = null;
  }
}

// ---------------------------------------------------------------------------
// isolate 侧：加载 sherpa-onnx，按请求合成 WAV
// ---------------------------------------------------------------------------

Future<void> _ttsIsolateMain(List<Object> args) async {
  final out = args[0] as SendPort;
  final paths = Map<String, String>.from(args[1] as Map);

  sherpa.OfflineTts? tts;
  try {
    sherpa.initBindings();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: paths['model'] ?? '',
          lexicon: paths['lexicon'] ?? '',
          tokens: paths['tokens'] ?? '',
        ),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      ),
      ruleFsts: paths['ruleFsts'] ?? '',
      maxNumSenetences: 1,
    );
    tts = sherpa.OfflineTts(config);
  } catch (e) {
    out.send(<String, Object>{'type': 'fatal', 'message': '$e'});
    return;
  }

  final rx = ReceivePort();
  out.send(<String, Object>{'type': 'ready', 'sendPort': rx.sendPort});

  await for (final message in rx) {
    if (message is! Map) continue;
    final id = message['id'] as int;
    final text = message['text'] as String? ?? '';
    final speed = (message['speed'] as num?)?.toDouble() ?? 1.0;
    final path = message['path'] as String? ?? '';
    try {
      final audio = tts.generate(text: text, sid: 0, speed: speed);
      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        out.send(<String, Object>{
          'type': 'result',
          'id': id,
          'ok': false,
          'error': '没有生成音频（文字里有不支持的符号？）',
        });
        continue;
      }
      _writeWav(path, audio.samples, audio.sampleRate);
      out.send(<String, Object>{
        'type': 'result',
        'id': id,
        'ok': true,
        'path': path,
      });
    } catch (e) {
      out.send(<String, Object>{
        'type': 'result',
        'id': id,
        'ok': false,
        'error': '$e',
      });
    }
  }
  tts.free();
}

/// 写 16bit PCM 单声道 WAV（播放器直接认这个格式）。
void _writeWav(String path, Float32List samples, int sampleRate) {
  final byteCount = samples.length * 2;
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + byteCount, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, byteCount, Endian.little);

  final pcm = ByteData(byteCount);
  for (var i = 0; i < samples.length; i++) {
    var v = (samples[i] * 32767.0).round();
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    pcm.setInt16(i * 2, v, Endian.little);
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  final sink = file.openSync(mode: FileMode.write);
  try {
    sink.writeFromSync(header.buffer.asUint8List());
    sink.writeFromSync(pcm.buffer.asUint8List());
  } finally {
    sink.closeSync();
  }
}
