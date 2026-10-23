import 'dart:io';

import 'package:flutter/services.dart';

/// App 私有目录。
class AppDirs {
  const AppDirs({required this.files, required this.cache});

  final String files;
  final String cache;
}

/// 电量状态。
class BatteryStatus {
  const BatteryStatus({required this.level, required this.charging});

  /// 0-100。
  final int level;
  final bool charging;
}

/// 与 Android 原生层通信的桥：存储权限 / 屏幕常亮 / 目录 / 电量。
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('sakuramanga/native');

  static bool get _supported => Platform.isAndroid;

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  /// 是否已获得读取外部存储的权限。
  static Future<bool> hasStoragePermission() async {
    if (!_supported) return true;
    final value = await _invoke<bool>('hasStoragePermission');
    return value ?? true;
  }

  /// 跳转系统页面请求「所有文件访问」权限。
  static Future<void> requestStoragePermission() async {
    await _invoke<void>('requestStoragePermission');
  }

  /// 阅读时保持屏幕常亮。
  static Future<void> setKeepScreenOn(bool value) async {
    await _invoke<void>('setKeepScreenOn', value);
  }

  /// 外部存储根目录（一般是 /storage/emulated/0）。
  static Future<String> storageRoot() async {
    final value = await _invoke<String>('getStorageRoot');
    return (value == null || value.isEmpty) ? '/storage/emulated/0' : value;
  }

  /// 读取当前电量与充电状态；失败时返回 null。
  static Future<BatteryStatus?> batteryStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('getBattery');
    if (map == null) return null;
    final level = (map['level'] as num?)?.toInt() ?? -1;
    if (level < 0) return null;
    return BatteryStatus(
      level: level,
      charging: map['charging'] as bool? ?? false,
    );
  }

  /// App 私有 files / cache 目录。
  static Future<AppDirs> appDirs() async {
    final map = await _invoke<Map<Object?, Object?>>('getDirs');
    final files = map?['files'] as String?;
    final cache = map?['cache'] as String?;
    if (files != null && cache != null) {
      return AppDirs(files: files, cache: cache);
    }
    final tmp = Directory.systemTemp.path;
    return AppDirs(files: tmp, cache: tmp);
  }

  /// 调起系统安装器安装 APK（原生侧走 FileProvider 授权读权限）。
  ///
  /// 返回 true = 已成功调起；false = 失败（文件缺失 / 平台不支持）。
  static Future<bool> installApk(String path) async {
    if (!_supported) return false;
    final ok = await _invoke<bool>('installApk', path);
    return ok ?? false;
  }

  /// 是否已允许「从本应用安装未知来源应用」（Android 8.0+ 需单独授权）。
  static Future<bool> canInstallApk() async {
    if (!_supported) return true;
    final ok = await _invoke<bool>('canInstallApk');
    return ok ?? true;
  }

  /// 跳转系统设置页，让用户授权「安装未知来源应用」。
  static Future<void> openInstallPermission() async {
    await _invoke<void>('openInstallPermission');
  }

  /// 跳转系统「语音合成（TTS）」设置页。
  ///
  /// 用户反馈：手机没有装语音引擎时，App 只弹一句「未安装 TTS 引擎」，
  /// 用户不知道该去哪里处理。这里把系统 TTS 设置页拉起来，
  /// 让他能直接安装 / 选择语音引擎与中文语音数据。
  ///
  /// 返回 true = 已拉起系统页面。
  static Future<bool> openTtsSettings() async {
    if (!_supported) return false;
    final ok = await _invoke<bool>('openTtsSettings');
    return ok ?? false;
  }

  // ---------- 音量键翻页 ----------

  /// 原生 → Dart 的事件通道（volumekey 由原生 onKeyDown 主动 invoke）。
  static const MethodChannel _keyChannel = MethodChannel('sakuramanga/keys');

  static bool _keyHandlerBound = false;

  /// 打开 / 关闭音量键翻页。
  ///
  /// 用户反馈「音量键翻页」：进入阅读页时打开，离开时关闭，
  /// 避免在书架 / 设置页误吞音量键。
  static Future<void> setVolumeKeyPaging(bool enabled) async {
    await _invoke<void>('setVolumeKeyPaging', enabled);
  }

  /// 注册音量键回调（幂等）。
  ///
  /// 原生在用户按音量键时通过 `volumeKeyPage` 方法回传 `next` / `prev`，
  /// 这里把它转成 Dart 侧的回调。只注册一次，避免重复绑定。
  static void bindVolumeKeyHandler(void Function(String action) onAction) {
    if (!_supported || _keyHandlerBound) return;
    _keyChannel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKeyPage') {
        final action = call.arguments?.toString() ?? '';
        if (action.isNotEmpty) onAction(action);
      }
      return null;
    });
    _keyHandlerBound = true;
  }
}
