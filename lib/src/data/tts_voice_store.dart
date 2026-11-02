import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../platform/native_bridge.dart';
import 'tts_voice_catalog.dart';

/// 语音包的下载 / 解压 / 删除。
///
/// 用户反馈「语音模型应该是选择下载的」——所以体积大的模型不进 APK，
/// 这里负责按需下载 tar.bz2、**流式**解压到 `<files>/tts/<id>/`。
///
/// 为什么解压要流式：aishell3 解压后接近 200 MB，一次性 `decodeBytes` 会把
/// 整个模型塞进 Dart 堆，低端机上直接 OOM。这里用 bzip2 的惰性流 + 手写 tar
/// 解析，一次只拿 64 KB。

String _join(String a, String b) {
  if (a.endsWith('/')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}

String _baseName(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  return parts.isEmpty ? path : parts.last;
}

class TtsVoiceStore extends ChangeNotifier {
  TtsVoiceStore({http.Client? client, Future<AppDirs> Function()? dirsProvider})
    : _client = client ?? http.Client(),
      _dirsProvider = dirsProvider ?? NativeBridge.appDirs;

  static TtsVoiceStore instance = TtsVoiceStore();

  final http.Client _client;
  final Future<AppDirs> Function() _dirsProvider;

  final Set<String> _installed = <String>{};
  final Map<String, double> _progress = <String, double>{};
  final Map<String, String> _errors = <String, String>{};
  String? _downloadingId;
  bool _scanned = false;

  /// 正在下载的语音包 id；没有就是 null（同一时刻只下一个，省流量）。
  String? get downloadingId => _downloadingId;

  double progressOf(String id) => _progress[id] ?? 0;

  String? errorOf(String id) => _errors[id];

  /// 是否已下载完成（内置包永远算已安装）。
  bool isInstalled(String id) {
    if (ttsVoicePackById(id)?.bundled == true) return true;
    return _installed.contains(id);
  }

  bool isDownloading(String id) => _downloadingId == id;

  Future<String> rootDir() async {
    final dirs = await _dirsProvider();
    return _join(dirs.files, 'tts');
  }

  /// 某个语音包解压后的目录。
  Future<String> packDir(String id) async => _join(await rootDir(), id);

  /// 扫一遍磁盘，看看哪些包已经解压好了。
  Future<void> refresh() async {
    try {
      final root = Directory(await rootDir());
      if (!root.existsSync()) {
        _installed.clear();
        _scanned = true;
        notifyListeners();
        return;
      }
      final found = <String>{};
      for (final entry in root.listSync().whereType<Directory>()) {
        final id = _baseName(entry.path);
        if (ttsVoicePackById(id) == null) continue;
        // 只要有 onnx 就算装好了（模型文件最大，最可能是半截的那一个）
        final has = entry.listSync().whereType<File>().any(
          (f) => f.path.endsWith('.onnx'),
        );
        if (has) found.add(id);
      }
      _installed
        ..clear()
        ..addAll(found);
      _scanned = true;
    } catch (_) {
      _scanned = true;
    }
    notifyListeners();
  }

  /// 下载并解压一个语音包。
  ///
  /// 返回 true 表示装好了。失败时 [errorOf] 里有人话说明。
  Future<bool> install(TtsVoicePack pack) async {
    if (pack.bundled) return true;
    if (isInstalled(pack.id)) return true;
    if (_downloadingId != null) {
      _errors[pack.id] =
          '正在下载「${ttsVoicePackById(_downloadingId!)?.name ?? ''}」，等它装完再来';
      notifyListeners();
      return false;
    }
    _downloadingId = pack.id;
    _errors.remove(pack.id);
    _progress[pack.id] = 0;
    notifyListeners();
    File? archive;
    try {
      archive = await _downloadToTemp(pack);
      if (archive == null) return false;
      final ok = await _extract(archive, pack);
      if (!ok) return false;
      _installed.add(pack.id);
      _progress[pack.id] = 1;
      return true;
    } catch (e) {
      _errors[pack.id] = '安装失败：$e';
      return false;
    } finally {
      _downloadingId = null;
      try {
        if (archive != null && archive.existsSync()) archive.deleteSync();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<File?> _downloadToTemp(TtsVoicePack pack) async {
    final root = Directory(await rootDir());
    root.createSync(recursive: true);
    final target = File(_join(root.path, '${pack.id}.download'));
    Object? lastError;
    for (final url in pack.mirrors) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }
        final total = response.contentLength ?? 0;
        final sink = target.openWrite();
        var received = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _progress[pack.id] = (received / total).clamp(0.0, 0.99);
            notifyListeners();
          }
        }
        await sink.flush();
        await sink.close();
        // 有 content-length 就按它校验；没有时只要下到东西就当成功
        if (received == 0 || (total > 0 && received < total)) {
          lastError = '下载到的文件不完整';
          continue;
        }
        return target;
      } catch (e) {
        lastError = e;
      }
    }
    _errors[pack.id] = '下载失败（$lastError），换个网络再试一次';
    return null;
  }

  /// 流式解压 tar.bz2 到 `<files>/tts/<id>/`。
  Future<bool> _extract(File archive, TtsVoicePack pack) async {
    final dest = Directory(await packDir(pack.id));
    final staging = Directory('${dest.path}.part');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);

    InputFileStream? input;
    try {
      input = InputFileStream(archive.path);
      final lazy = BZip2Decoder().decodeLazy(input);
      while (true) {
        final header = lazy.readBytes(512).toUint8List();
        if (header.length < 512) break;
        if (header.every((b) => b == 0)) break; // 结束块
        var name = _cString(header, 0, 100);
        final prefix = _cString(header, 345, 155);
        if (prefix.isNotEmpty) name = '$prefix/$name';
        final size = _octal(header, 124, 12);
        final type = header[156];
        final isFile = type == 0x30 || type == 0; // '0' 或老格式
        final rel = _stripRoot(name, pack.archiveName);
        if (isFile && rel.isNotEmpty) {
          final out = File(_join(staging.path, rel));
          out.parent.createSync(recursive: true);
          final sink = out.openWrite();
          var copied = 0;
          while (copied < size) {
            final want = (size - copied).clamp(1, 64 * 1024);
            final chunk = lazy.readBytes(want).toUint8List();
            if (chunk.isEmpty) break;
            sink.add(chunk);
            copied += chunk.length;
          }
          await sink.flush();
          await sink.close();
        }
        // 跳过文件内容后的 512 对齐填充
        final pad = (512 - (size % 512)) % 512;
        if (pad > 0) lazy.skip(pad);
      }
      // 校验必须文件都在，缺一个就当失败（避免留一个不能用的包）
      if (resolveTtsVoiceFiles(staging.path) == null) {
        _errors[pack.id] = '压缩包内容不对（没找到模型文件），可能下载被截断了';
        staging.deleteSync(recursive: true);
        return false;
      }
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      staging.renameSync(dest.path);
      return true;
    } catch (e) {
      _errors[pack.id] = '解压失败：$e';
      try {
        if (staging.existsSync()) staging.deleteSync(recursive: true);
      } catch (_) {}
      return false;
    } finally {
      try {
        input?.closeSync();
      } catch (_) {}
    }
  }

  /// 删除一个已下载的语音包。
  Future<void> remove(String id) async {
    // 目录里查不到的 id 也照样删（防御：老版本残留目录 / 测试包）
    if (ttsVoicePackById(id)?.bundled == true) return;
    final dir = Directory(await packDir(id));
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    _installed.remove(id);
    _progress.remove(id);
    _errors.remove(id);
    notifyListeners();
  }

  /// 是否已经扫过盘（设置页首次渲染用）。
  bool get scanned => _scanned;

  static String _cString(Uint8List data, int start, int length) {
    final end = (start + length).clamp(0, data.length);
    var stop = start;
    while (stop < end && data[stop] != 0) {
      stop++;
    }
    return String.fromCharCodes(data.sublist(start, stop)).trim();
  }

  static int _octal(Uint8List data, int start, int length) {
    var value = 0;
    for (var i = start; i < start + length && i < data.length; i++) {
      final c = data[i];
      if (c == 0 || c == 0x20) continue;
      if (c < 0x30 || c > 0x37) break;
      value = value * 8 + (c - 0x30);
    }
    return value;
  }

  /// 去掉压缩包里的顶层目录，防止把文件写到别处（也防止路径穿越）。
  static String _stripRoot(String name, String root) {
    var rel = name.replaceAll('\\', '/');
    if (root.isNotEmpty && rel.startsWith('$root/')) {
      rel = rel.substring(root.length + 1);
    }
    final parts = rel
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    return parts.join('/');
  }
}
