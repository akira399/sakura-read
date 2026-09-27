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
}
