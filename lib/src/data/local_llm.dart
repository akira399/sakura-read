import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../platform/native_bridge.dart';
import 'ai_service.dart';

/// 一个可下载的本地小模型（Google LiteRT-LM 的 `.litertlm` 包）。
///
/// 为什么要内置模型而不是只支持在线接口：用户反馈里最常出现的两条是
/// 「不想再充钱买 API」和「不想让阅读数据上传」，本地跑就都解决了。
class LocalModelSpec {
  const LocalModelSpec({
    required this.id,
    required this.name,
    required this.params,
    required this.license,
    required this.bytes,
    required this.fileName,
    required this.summary,
    required this.mirrors,
  });

  /// 稳定的 id，写进设置文件（换模型时只改 [localModelCatalog]）。
  final String id;

  /// 展示名，如 `Qwen3-0.6B`。
  final String name;

  /// 参数量描述，如 `0.6B`。
  final String params;

  /// 许可证（做本地推理必须说清授权）。
  final String license;

  /// 模型文件字节数（用于下载进度与完整性校验）。
  final int bytes;

  /// 落地文件名（放在 `<files>/models/` 下）。
  final String fileName;

  /// 一句话介绍，展示在选择页。
  final String summary;

  /// 下载镜像，按顺序尝试（国内优先）。
  final List<String> mirrors;

  double get megabytes => bytes / (1024 * 1024);

  String get sizeLabel => megabytes >= 1024
      ? '${(megabytes / 1024).toStringAsFixed(1)} GB'
      : '${megabytes.toStringAsFixed(0)} MB';
}

/// 可选下载的新一代开源小模型目录（基于 Google LiteRT-LM 0.20）。
///
/// 为什么是一个「目录」而不是一档写死：手机内存差异大，这里按体积与性能
/// 提供从 0.6B 到 E2B 的多档模型；模型不进安装包（最小约 464 MB），
/// 设置页让用户按硬件和需求自行选择并断点下载。
///
/// 顺序 = 设置页展示顺序，第一条是最轻巧稳妥的默认 0.6B 档（Qwen3-0.6B）。
/// 每个模型给三个镜像：modelscope 国内直连最稳，后两个是备用，
/// [LocalModelManager] 下载失败会自动按顺位换下一个。
const List<LocalModelSpec> localModelCatalog = [
  LocalModelSpec(
    id: 'qwen3-0.6b-int8',
    name: 'Qwen3-0.6B',
    params: '0.6B',
    license: 'Apache-2.0',
    bytes: 613722264,
    fileName: 'qwen3-0.6b-int8.litertlm',
    summary: '默认轻量主力，约 585 MB（动态 INT8）；中文理解与指令遵循比老款 0.5B 明显提升，千元机也能流畅闲聊。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/Qwen3-0.6B/resolve/master/Qwen3-0.6B.litertlm',
      'https://hf-mirror.com/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    ],
  ),
  LocalModelSpec(
    id: 'qwen3.5-0.8b-mixed48',
    name: 'Qwen3.5-0.8B',
    params: '0.8B',
    license: 'Apache-2.0',
    bytes: 486539264,
    fileName: 'qwen3.5-0.8b-mixed48.litertlm',
    summary: '新一代 Qwen3.5 混合线性注意力架构（4/8-bit Hadamard 量化），体积仅 464 MB，速度更快且内存更省。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/Qwen3.5-0.8B/resolve/master/Qwen3.5-0.8B_mixed48_h1024.litertlm',
      'https://hf-mirror.com/litert-community/Qwen3.5-0.8B/resolve/main/Qwen3.5-0.8B_mixed48_h1024.litertlm',
      'https://huggingface.co/litert-community/Qwen3.5-0.8B/resolve/main/Qwen3.5-0.8B_mixed48_h1024.litertlm',
    ],
  ),
  LocalModelSpec(
    id: 'lfm2.5-1.2b-instruct-int4',
    name: 'LFM2.5-1.2B-Instruct',
    params: '1.2B',
    license: 'LFM-Open-1.0',
    bytes: 736015744,
    fileName: 'lfm2.5-1.2b-instruct-int4.litertlm',
    summary: 'Liquid AI 专为端侧设计的混合架构（约 702 MB），生成速度快、发热低，适合日常对话与摘录总结。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/LFM2.5-1.2B-Instruct/resolve/master/LFM2.5-1.2B-Instruct_int4.litertlm',
      'https://hf-mirror.com/litert-community/LFM2.5-1.2B-Instruct/resolve/main/LFM2.5-1.2B-Instruct_int4.litertlm',
      'https://huggingface.co/litert-community/LFM2.5-1.2B-Instruct/resolve/main/LFM2.5-1.2B-Instruct_int4.litertlm',
    ],
  ),
  LocalModelSpec(
    id: 'qwen3.5-2b-int8',
    name: 'Qwen3.5-2B',
    params: '2B',
    license: 'Apache-2.0',
    bytes: 2119843840,
    fileName: 'qwen3.5-2b-int8.litertlm',
    summary: '2.0 GB 进阶中文旗舰（INT8），GatedDeltaNet 长上下文显存占用平稳，适合长文总结与多轮深度问答。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/Qwen3.5-2B/resolve/master/Qwen3.5-2B_int8.litertlm',
      'https://hf-mirror.com/litert-community/Qwen3.5-2B/resolve/main/Qwen3.5-2B_int8.litertlm',
      'https://huggingface.co/litert-community/Qwen3.5-2B/resolve/main/Qwen3.5-2B_int8.litertlm',
    ],
  ),
  LocalModelSpec(
    id: 'gemma-4-e2b-it',
    name: 'Gemma 4 E2B',
    params: 'E2B',
    license: 'Apache-2.0',
    bytes: 2588147712,
    fileName: 'gemma-4-e2b-it.litertlm',
    summary: 'Google 2026 端侧强力小模型（约 2.4 GB，2/4/8-bit QAT 混合量化），综合推理与多语言表现优异，推荐大内存机型选用。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/gemma-4-E2B-it-litert-lm/resolve/master/gemma-4-E2B-it.litertlm',
      'https://hf-mirror.com/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    ],
  ),
];

/// 原生侧推上来的一段流式输出。
class LocalLlmEvent {
  const LocalLlmEvent({
    required this.id,
    required this.type,
    required this.text,
  });

  final int id;

  /// `partial`（中间增量）/ `done`（结束）/ `error`（失败）。
  final String type;
  final String text;

  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}

/// MediaPipe LLM Inference 的 Dart 侧薄封装（通道 `sakuramanga/llm`）。
///
/// 原生实现见 `android/app/src/main/kotlin/.../LocalLlmEngine.kt`。
class LocalLlmEngine {
  LocalLlmEngine._();

  static const MethodChannel _channel = MethodChannel('sakuramanga/llm');

  static bool _hooked = false;
  static int _seq = 0;
  static final Map<int, StreamController<LocalLlmEvent>> _streams = {};

  /// 桌面 / 测试环境没有原生实现，直接判定不支持。
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static void _ensureHook() {
    if (_hooked) return;
    _hooked = true;
    // 原生用同一个 MethodChannel 反向发事件，这里接收并按 id 分发。
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'llm.event') return null;
      final map = call.arguments is Map ? call.arguments as Map : const {};
      final id = (map['id'] as num?)?.toInt() ?? -1;
      final controller = _streams[id];
      if (controller == null) return null;
      final type = '${map['type'] ?? ''}';
      final event = LocalLlmEvent(
        id: id,
        type: type,
        text: '${map['text'] ?? ''}',
      );
      controller.add(event);
      if (event.isDone || event.isError) {
        _streams.remove(id);
        unawaited(controller.close());
      }
      return null;
    });
  }

  /// 设备信息：`supported` / `loaded` / `totalMemMb` / `abi`。
  static Future<Map<String, Object?>?> info() async {
    if (!supported) return null;
    _ensureHook();
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('info');
      if (map == null) return null;
      return map.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return null;
    }
  }

  /// 加载模型（首次约 5~25 秒，成功后可反复生成）。
  static Future<void> load(String path, {int maxTokens = 2048}) async {
    _ensureHook();
    await _channel.invokeMethod<Map<Object?, Object?>>('load', {
      'path': path,
      'maxTokens': maxTokens,
    });
  }

  /// 卸载模型，释放 native 内存。
  static Future<void> unload() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('unload');
    } catch (_) {}
  }

  /// 估算 token 数（原生有分词器时用真实值，否则粗估）。
  static Future<int> tokenCount(String text) async {
    if (!supported) return (text.length / 1.6).ceil();
    try {
      final value = await _channel.invokeMethod<int>('tokenCount', {
        'text': text,
      });
      return value ?? (text.length / 1.6).ceil();
    } catch (_) {
      return (text.length / 1.6).ceil();
    }
  }

  /// 开始一段流式生成；结束后流自动关闭。
  ///
  /// 当传入 [system] / [history] 时，原生 LiteRT-LM 会自动按各模型内置的
  /// 对话模板（Qwen3 / Qwen3.5 / LFM2.5 / Gemma 4）拼接上下文。
  static Future<Stream<LocalLlmEvent>> generate(
    String prompt, {
    String? system,
    List<Map<String, String>>? history,
    bool enableThinking = false,
  }) async {
    _ensureHook();
    final controller = StreamController<LocalLlmEvent>();
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'generate',
        {
          'prompt': prompt,
          if (system != null && system.isNotEmpty) 'system': system,
          if (history != null && history.isNotEmpty) 'history': history,
          'enableThinking': enableThinking,
        },
      );
      final id = (result?['id'] as num?)?.toInt() ?? ++_seq;
      _streams[id] = controller;
    } catch (error) {
      // 通道异常：直接把错误交给调用方，别让 UI 卡在「正在想」。
      unawaited(controller.close());
      return Stream<LocalLlmEvent>.error(AiException(_friendly(error)));
    }
    return controller.stream;
  }

  /// 打断当前生成（原生会尽快停止吐字）。
  static Future<void> cancel() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  static String _friendly(Object error) {
    final text = '$error';
    if (error is MissingPluginException) return '这个版本还不支持本地模型';
    if (text.contains('not_loaded')) return '本地模型还没加载好，稍等一下再问';
    if (text.contains('busy')) return '上一条还在说呢，等它说完再问';
    if (text.contains('out of memory') || text.contains('OOM')) {
      return '内存不够了，关掉几个后台应用再试';
    }
    return '本地模型出错了：$text';
  }
}

/// 本地模型的下载 / 加载状态机。
///
/// UI 直接监听这个对象（ChangeNotifier）即可拿到进度与错误。
enum LocalModelPhase {
  /// 还没检查完。
  idle,

  /// 正在下载。
  downloading,

  /// 文件已就绪，但还没加载进内存。
  downloaded,

  /// 正在加载（耗时几秒到几十秒）。
  loading,

  /// 已加载，可以对话。
  ready,

  /// 出错了，见 [LocalModelManager.error]。
  error,
}

class LocalModelManager extends ChangeNotifier {
  LocalModelManager({
    AppDirs? dirs,
    http.Client? client,
    this._supportedOverride,
    this._specOverride,
  }) : _dirsOverride = dirs,
       _client = client ?? http.Client() {
    if (supported) unawaited(refresh());
  }

  /// 全局实例：设置页和对话页共用一个（下载过程中切页面不丢状态）。
  static LocalModelManager instance = LocalModelManager();

  /// 输入预算（token）：总上限 2048，给回答留出空间。
  static const int promptBudget = 1400;

  final LocalModelSpec? _specOverride;
  final AppDirs? _dirsOverride;
  final http.Client _client;
  final bool? _supportedOverride;

  AppDirs? _dirs;
  LocalModelPhase _phase = LocalModelPhase.idle;
  int _received = 0;
  int _total = 0;
  String? _error;
  bool _loaded = false;
  bool _disposed = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _downloading;
  Future<void>? _loading;

  /// 当前选中的模型；目录里查不到时回落到第一档，UI 永远有东西可显示。
  LocalModelSpec get spec {
    if (_specOverride != null) return _specOverride;
    final id = _selectedId;
    for (final item in localModelCatalog) {
      if (item.id == id) return item;
    }
    return localModelCatalog.first;
  }

  String _selectedId = '';

  /// 选中的模型 id（空 = 默认）。
  set selectedId(String id) {
    _selectedId = id;
    _notify();
  }

  bool get supported => _supportedOverride ?? LocalLlmEngine.supported;

  LocalModelPhase get phase => _phase;
  bool get isDownloading => _phase == LocalModelPhase.downloading;
  bool get isDownloaded =>
      _loaded ||
      _phase == LocalModelPhase.downloaded ||
      _phase == LocalModelPhase.ready;
  bool get isReady => _loaded && _phase == LocalModelPhase.ready;
  String? get error => _error;

  /// 0~1，未开始下载时为 0。
  double get progress {
    if (_total <= 0) return 0;
    final value = _received / _total;
    return value.isNaN || value.isInfinite ? 0 : value.clamp(0.0, 1.0);
  }

  int get receivedBytes => _received;
  int get totalBytes => _total > 0 ? _total : spec.bytes;

  Future<AppDirs> _appDirs() async =>
      _dirs ??= _dirsOverride ?? await NativeBridge.appDirs();

  /// 模型落地的绝对路径。
  Future<String> modelPath() async {
    final dirs = await _appDirs();
    return '${dirs.files}${Platform.pathSeparator}models'
        '${Platform.pathSeparator}${spec.fileName}';
  }

  /// 页面打开时调用：确认文件是否存在、原生引擎是否已经加载过。
  Future<void> refresh() async {
    if (!supported) {
      _phase = LocalModelPhase.idle;
      _notify();
      return;
    }
    try {
      final path = await modelPath();
      final file = File(path);
      final exists = await file.exists() && await file.length() == spec.bytes;
      final info = await LocalLlmEngine.info();
      final loaded = info?['loaded'] == true;
      final loadedPath = info?['path'] as String?;
      _loaded = loaded && loadedPath == path;
      if (_loaded) {
        _phase = LocalModelPhase.ready;
        _error = null;
      } else if (exists) {
        final length = await file.length();
        _received = length;
        _total = spec.bytes;
        _phase = LocalModelPhase.downloaded;
        _error = null;
      } else {
        _phase = LocalModelPhase.idle;
        _received = 0;
        _total = 0;
        _error = null;
      }
    } catch (_) {
      _phase = LocalModelPhase.idle;
      _error = null;
    }
    _notify();
  }

  /// 下载模型（按镜像顺序重试，先写 `.part` 再改名）。
  Future<void> download() {
    return _downloading ??= _download()
        .catchError((Object error) {
          _phase = LocalModelPhase.error;
          _error = '模型下载失败：${_shortError(error)}';
          _notify(force: true);
        })
        .whenComplete(() {
          _downloading = null;
        });
  }

  bool _cancelDownload = false;
  Completer<void>? _downloadAbort;
  void pauseDownload() {
    _cancelDownload = true;
    if (_downloadAbort?.isCompleted == false) _downloadAbort!.complete();
  }

  Future<void> _download() async {
    _cancelDownload = false;
    _downloadAbort = Completer<void>();
    _error = null;
    _phase = LocalModelPhase.downloading;
    _received = 0;
    _total = spec.bytes;
    _notify(force: true);

    final path = await modelPath();
    final target = File(path);
    await target.parent.create(recursive: true);
    final tmp = File('$path.part');

    Object? lastError;
    for (final url in spec.mirrors) {
      try {
        var offset = await tmp.exists() ? await tmp.length() : 0;
        if (offset > spec.bytes) {
          await tmp.delete();
          offset = 0;
        }
        if (offset == spec.bytes) {
          await tmp.rename(path);
          _phase = LocalModelPhase.downloaded;
          _received = offset;
          _notify(force: true);
          return;
        }
        final metadata = File('$path.part.meta');
        Map<String, dynamic> previous = {};
        try {
          previous =
              jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
        final validator = previous['validator'] as String? ?? '';
        if (offset > 0 && (previous['url'] != url || validator.isEmpty)) {
          offset = 0;
        }
        final request = http.AbortableRequest(
          'GET',
          Uri.parse(url),
          abortTrigger: _downloadAbort!.future,
        );
        if (offset > 0) {
          request.headers['Range'] = 'bytes=$offset-';
          request.headers['If-Range'] = validator;
        }
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(url),
          );
        }
        if (response.statusCode == 206) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
              .firstMatch(response.headers['content-range'] ?? '');
          if (range == null ||
              int.parse(range[1]!) != offset ||
              int.parse(range[3]!) != spec.bytes) {
            throw const HttpException('续传范围不匹配，已保留下载进度');
          }
        } else {
          offset = 0;
        }
        await metadata.writeAsString(
          jsonEncode({
            'url': url,
            'validator':
                response.headers['etag'] ??
                response.headers['last-modified'] ??
                '',
          }),
          flush: true,
        );
        final sink = tmp.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var received = offset;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 90),
          )) {
            if (_cancelDownload || _disposed) {
              await sink.flush();
              _phase = LocalModelPhase.idle;
              _notify(force: true);
              return;
            }
            if (received + chunk.length > spec.bytes) {
              throw const HttpException('模型响应大小异常');
            }
            sink.add(chunk);
            received += chunk.length;
            _received = received;
            if (received > _total) _total = received;
            _notify();
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        final length = await tmp.length();
        if (spec.bytes > 0 && length != spec.bytes) {
          throw FileSystemException('文件不完整（$length / ${spec.bytes}）');
        }
        if (await target.exists()) await target.delete();
        await tmp.rename(path);
        _received = length;
        _total = length;
        _phase = LocalModelPhase.downloaded;
        _notify(force: true);
        return;
      } catch (e) {
        if (_cancelDownload) {
          _phase = LocalModelPhase.idle;
          _notify(force: true);
          return;
        }
        lastError = e;
        // Keep partial bytes across retries and app restarts.
      }
    }
    _phase = LocalModelPhase.error;
    _error = '模型下载失败：${_shortError(lastError)}';
    _notify(force: true);
  }

  /// 把模型加载进内存（已在内存则直接返回成功）。
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    final file = File(await modelPath());
    if (!await file.exists()) {
      await refresh();
      return _loaded;
    }
    await (_loading ??= _load().whenComplete(() => _loading = null));
    return _loaded;
  }

  Future<void> _load() async {
    _phase = LocalModelPhase.loading;
    _error = null;
    _notify(force: true);
    try {
      final path = await modelPath();
      await LocalLlmEngine.load(path);
      _loaded = true;
      _phase = LocalModelPhase.ready;
    } catch (e) {
      _loaded = false;
      _phase = LocalModelPhase.error;
      _error = _shortError(e);
    }
    _notify(force: true);
  }

  /// 卸载内存中的模型（文件保留）。
  Future<void> unload() async {
    await LocalLlmEngine.unload();
    if (_loaded) {
      _loaded = false;
      _phase = LocalModelPhase.downloaded;
      _notify(force: true);
    }
  }

  /// 删除模型文件（用户想省空间时）。
  Future<void> deleteModel() async {
    await LocalLlmEngine.unload();
    _loaded = false;
    try {
      final file = File(await modelPath());
      if (await file.exists()) await file.delete();
      final metadata = File('${file.path}.part.meta');
      if (await metadata.exists()) await metadata.delete();
      final part = File('${file.path}.part');
      if (await part.exists()) await part.delete();
    } catch (_) {}
    _received = 0;
    _total = 0;
    _error = null;
    _phase = LocalModelPhase.idle;
    _notify(force: true);
  }

  String _shortError(Object? error) {
    if (error == null) return '未知错误';
    final text = '$error';
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return '网络不通，换个网络再试（已尝试全部镜像）';
    }
    if (text.contains('TimeoutException')) return '下载超时了，稍后再试';
    if (text.length > 120) return '${text.substring(0, 120)}…';
    return text;
  }

  /// 进度回调很密（521 MB / 8 KB 一块），节流到 150 ms 一次，别把 UI 拖死。
  void _notify({bool force = false}) {
    if (_disposed) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastNotify) < const Duration(milliseconds: 150)) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  @override
  void dispose() {
    pauseDownload();
    _disposed = true;
    super.dispose();
  }
}

/// 结构化本地模型对话请求，交给 LiteRT-LM 原生对话模板渲染。
class LocalLlmRequest {
  const LocalLlmRequest({
    required this.system,
    required this.history,
    required this.userText,
  });

  final String system;
  final List<Map<String, String>> history;
  final String userText;
}

/// 本地模型的提示词拼装与输出清洗。
///
/// 小模型的「记忆力」和指令跟随都有限，所以这里刻意把提示词做得很短：
/// 只有一个简短人设 + 一小段阅读数据 + 最近两轮对话。
class LocalLlmChat {
  LocalLlmChat._();

  /// 输出上限（token）：约 200 个汉字，够一条聊天回复。
  static const int replyBudget = 340;

  static const String _imEnd = '<|im_end|>';

  static const String _persona =
      '你是「樱读」App 里的阅读助手「小樱」，'
      '温柔、简短，用简体中文，一般不超过 120 字。';

  static const String _rules =
      '规则：只根据下面给出的资料回答；资料里没有的就说不知道，'
      '不要编造书里的情节或数据；不要提这段说明。';

  /// 组装结构化请求（供原生 LiteRT-LM Conversation API 使用）；超预算时按梯度裁切。
  static Future<LocalLlmRequest> buildRequest({
    required List<AiTurn> history,
    required String userText,
    ReadingSnapshot? snapshot,
    bool includeReading = true,
  }) async {
    final system = _systemContent(snapshot, includeReading: includeReading);
    var turns = [...history];
    while (turns.length > 4) {
      turns.removeRange(0, 2);
    }
    String rawPreview(String sys, List<AiTurn> h, String u) =>
        '$sys\n${h.map((t) => t.content).join('\n')}\n$u';

    if (await LocalLlmEngine.tokenCount(rawPreview(system, turns, userText)) <=
        LocalModelManager.promptBudget) {
      return LocalLlmRequest(
        system: system,
        history: [
          for (final t in turns) {'role': t.role, 'content': t.content},
        ],
        userText: userText,
      );
    }

    final leanSystem = _systemContent(null, includeReading: false);
    if (await LocalLlmEngine.tokenCount(
          rawPreview(leanSystem, turns, userText),
        ) <=
        LocalModelManager.promptBudget) {
      return LocalLlmRequest(
        system: leanSystem,
        history: [
          for (final t in turns) {'role': t.role, 'content': t.content},
        ],
        userText: userText,
      );
    }

    final clipped = userText.length <= 600
        ? userText
        : userText.substring(userText.length - 600);
    return LocalLlmRequest(
      system: leanSystem,
      history: const [],
      userText: clipped,
    );
  }

  /// 组一份 ChatML 提示词；超预算时先丢最早的对话，再丢阅读数据。
  static Future<String> buildPrompt({
    required List<AiTurn> history,
    required String userText,
    ReadingSnapshot? snapshot,
    bool includeReading = true,
  }) async {
    final system = _systemContent(snapshot, includeReading: includeReading);
    var turns = <AiTurn>[...history, AiTurn.user(userText)];
    // 小模型扛不住长上下文：只保留最近两轮（4 条）。
    while (turns.length > 4) {
      turns.removeRange(0, 2);
    }
    var prompt = _wrap(system, turns);
    if (await LocalLlmEngine.tokenCount(prompt) <=
        LocalModelManager.promptBudget) {
      return prompt;
    }
    // 还是太长：去掉阅读数据（人设很短，基本能过）。
    final lean = _wrap(_systemContent(null, includeReading: false), turns);
    if (await LocalLlmEngine.tokenCount(lean) <=
        LocalModelManager.promptBudget) {
      return lean;
    }
    // 最后手段：只留用户这一句，并截断到 300 字。
    final clipped = userText.length <= 300
        ? userText
        : userText.substring(userText.length - 300);
    turns = [AiTurn.user(clipped)];
    return _wrap(_systemContent(null, includeReading: false), turns);
  }

  static String _systemContent(
    ReadingSnapshot? snapshot, {
    required bool includeReading,
  }) {
    final buffer = StringBuffer(_persona)
      ..write('\n')
      ..write(_rules);
    if (includeReading && snapshot != null) {
      buffer
        ..write('\n【用户的阅读资料】\n')
        ..write(snapshot.toPrompt());
    } else if (!includeReading) {
      buffer.write('\n用户的阅读数据没有共享，你看不到他的书架和进度。');
    }
    return buffer.toString();
  }

  static String _wrap(String system, List<AiTurn> turns) {
    final buffer = StringBuffer()
      ..write('<|im_start|>system\n')
      ..write(system)
      ..write(_imEnd)
      ..write('\n');
    for (final turn in turns) {
      buffer
        ..write(
          turn.role == 'assistant'
              ? '<|im_start|>assistant\n'
              : '<|im_start|>user\n',
        )
        ..write(turn.content)
        ..write(_imEnd)
        ..write('\n');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  /// 清洗模型输出：移除思维链片段、结束标记与残留特殊 token。
  static String clean(String raw) {
    var text = raw;
    text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final openThink = text.indexOf('<think>');
    if (openThink >= 0) {
      text = text.substring(0, openThink);
    }
    for (final marker in [
      _imEnd,
      '<|im_start|>',
      '<|endoftext|>',
      '<end_of_turn>',
      '<|eot_id|>',
    ]) {
      final index = text.indexOf(marker);
      if (index >= 0) text = text.substring(0, index);
    }
    text = text.replaceAll('\r\n', '\n').trim();
    return text;
  }
}

/// 全局本地模型管理器（设置页 / 对话页共用）。
LocalModelManager get localModels => LocalModelManager.instance;
