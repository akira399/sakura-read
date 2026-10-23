import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../platform/native_bridge.dart';
import 'ai_service.dart';

/// 一个可下载的本地小模型（MediaPipe LLM Inference 的 `.task` 包）。
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

  /// 展示名，如 `Qwen2.5-0.5B-Instruct`。
  final String name;

  /// 参数量描述，如 `0.5B`。
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

  String get sizeLabel =>
      megabytes >= 1024
      ? '${(megabytes / 1024).toStringAsFixed(1)} GB'
      : '${megabytes.toStringAsFixed(0)} MB';
}

/// 内置模型目录。
///
/// 只放一个「够小、够快、手机上跑得动」的档位：
/// Qwen2.5-0.5B-Instruct 的 q8 量化版（521 MB，Apache-2.0，支持中文）。
/// 引擎本身与模型无关，想换成 1.5B / 3B 只需在这里加一条。
const List<LocalModelSpec> localModelCatalog = [
  LocalModelSpec(
    id: 'qwen2.5-0.5b-instruct-q8',
    name: 'Qwen2.5-0.5B-Instruct',
    params: '0.5B',
    license: 'Apache-2.0',
    bytes: 546660344,
    fileName: 'qwen2.5-0.5b-instruct-q8.task',
    summary: '机身存储约 521 MB，内存占用约 1 GB；闲聊、总结阅读习惯够用，'
        '回答简单直接，不会编长篇大论。',
    mirrors: [
      'https://modelscope.cn/models/litert-community/Qwen2.5-0.5B-Instruct/resolve/master/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
      'https://hf-mirror.com/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
      'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    ],
  ),
];

/// 原生侧推上来的一段流式输出。
class LocalLlmEvent {
  const LocalLlmEvent({required this.id, required this.type, required this.text});

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

  /// 加载模型（首次约 10~30 秒，成功后可反复生成）。
  static Future<void> load(String path, {int maxTokens = 1280}) async {
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
  static Future<Stream<LocalLlmEvent>> generate(String prompt) async {
    _ensureHook();
    final controller = StreamController<LocalLlmEvent>();
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'generate',
        {'prompt': prompt},
      );
      final id = (result?['id'] as num?)?.toInt() ?? ++_seq;
      _streams[id] = controller;
    } catch (error) {
      // 通道异常：直接把错误交给调用方，别让 UI 卡在「正在想」。
      unawaited(controller.close());
      return Stream<LocalLlmEvent>.error(
        AiException(_friendly(error)),
      );
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
    bool? supportedOverride,
  }) : _dirsOverride = dirs,
       _client = client ?? http.Client(),
       _supportedOverride = supportedOverride {
    if (supported) unawaited(refresh());
  }

  /// 全局实例：设置页和对话页共用一个（下载过程中切页面不丢状态）。
  static LocalModelManager instance = LocalModelManager();

  /// 输入预算（token）：总上限 1280，给回答留出空间。
  static const int promptBudget = 800;

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

  /// 当前选中的模型（目前目录里只有一个）。
  LocalModelSpec get spec {
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
      final exists = await file.exists() && await file.length() > 0;
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
    return _downloading ??= _download().whenComplete(() {
      _downloading = null;
    });
  }

  Future<void> _download() async {
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
        final request = http.Request('GET', Uri.parse(url));
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
        }
        final sink = tmp.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 90),
          )) {
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
        lastError = e;
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
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
    _disposed = true;
    super.dispose();
  }
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

  static const String _persona = '你是「樱读」App 里的阅读助手「小樱」，'
      '温柔、简短，用简体中文，一般不超过 120 字。';

  static const String _rules = '规则：只根据下面给出的资料回答；资料里没有的就说不知道，'
      '不要编造书里的情节或数据；不要提这段说明。';

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
    if (await LocalLlmEngine.tokenCount(prompt) <= LocalModelManager.promptBudget) {
      return prompt;
    }
    // 还是太长：去掉阅读数据（人设很短，基本能过）。
    final lean = _wrap(
      _systemContent(null, includeReading: false),
      turns,
    );
    if (await LocalLlmEngine.tokenCount(lean) <= LocalModelManager.promptBudget) {
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
        ..write(turn.role == 'assistant'
            ? '<|im_start|>assistant\n'
            : '<|im_start|>user\n')
        ..write(turn.content)
        ..write(_imEnd)
        ..write('\n');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  /// 清洗模型输出：切掉结束标记与残留的特殊 token。
  static String clean(String raw) {
    var text = raw;
    for (final marker in [_imEnd, '<|im_start|>', '<|endoftext|>']) {
      final index = text.indexOf(marker);
      if (index >= 0) text = text.substring(0, index);
    }
    text = text.replaceAll('\r\n', '\n').trim();
    return text;
  }
}

/// 全局本地模型管理器（设置页 / 对话页共用）。
LocalModelManager get localModels => LocalModelManager.instance;
