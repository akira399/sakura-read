import 'dart:async';

import 'package:flutter/services.dart';

/// 文件打开专用通道（见 MainActivity.kt 的 openChannelName）。
///
/// 为什么独立通道：`sakuramanga/native` 已被 TTS 用作「原生→Dart」事件
/// 通道（ttsState），Flutter 的 `setMethodCallHandler` 在同一通道上会
/// **后设置覆盖先设置**——两处都用同一通道会互相打断。
const MethodChannel _channel = MethodChannel('sakuramanga/open');

/// 「用樱读打开文件」服务。
///
/// 背景（用户反馈）：在文件管理器中打开 .txt / .epub / .json 时，系统
/// 「打开方式」里找不到樱读——应用此前没有注册任何文件关联。
/// 现在通过两条链路接收：
///   - **冷启动**：系统带 VIEW intent 启动 App → 原生先保存路径，
///     Dart 就绪后调用 [consumeLaunchFile] 取走；
///   - **热启动**（App 已在后台）：原生通过 `fileOpened` 事件推送。
///
/// 收到路径后的处理（见 [onOpenFile] 回调，由 UI 层分派）：
///   - txt / epub → 导入书架并打开阅读器；
///   - json → 按书源导入。
class OpenFileService {
  OpenFileService._();

  static final OpenFileService instance = OpenFileService._();

  bool _listening = false;

  /// 文件打开回调（文件绝对路径）。
  void Function(String path)? onOpenFile;

  /// 监听原生侧的「打开文件」事件（热启动）。
  void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'fileOpened') return;
      final path = call.arguments as String?;
      if (path != null && path.isNotEmpty) onOpenFile?.call(path);
    });
  }

  /// 取走「冷启动时系统传入的文件路径」（取后清除）；没有则返回 null。
  ///
  /// 应在 App 完全就绪后调用一次（见 HomePage 初始化）。
  Future<String?> consumeLaunchFile() async {
    try {
      final path = await _channel.invokeMethod<String>('getLaunchFile');
      if (path == null || path.isEmpty) return null;
      return path;
    } catch (_) {
      return null;
    }
  }
}
