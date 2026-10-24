import 'package:flutter/services.dart';

/// 屏幕刷新率：让 App 按屏幕支持的最高刷新率出帧。
///
/// Android 的系统默认显示模式常常是 60Hz——即使屏幕是 120Hz，应用不主动
/// 声明的话只能按 60Hz 拿 vsync，观感上就像"锁帧"。这里调原生通道，让系统
/// 切到最高刷新率模式（退出 App 后系统会自己恢复，不常驻）。
class DisplayService {
  DisplayService._();

  static const MethodChannel _channel = MethodChannel('sakuramanga/display');

  /// 切换高刷新率；失败（桌面/测试环境没有通道）时静默忽略。
  static Future<void> setHighRefresh(bool high) async {
    try {
      await _channel.invokeMethod<void>('setHighRefresh', high);
    } catch (_) {
      // 非 Android 环境或通道不可用：忽略即可
    }
  }
}
