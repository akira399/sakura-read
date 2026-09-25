import 'dart:io';

import 'package:flutter/services.dart';

/// 用系统浏览器打开链接（走项目自有的 `sakuramanga/native` 通道，
/// 不引入第三方依赖）。
///
/// 返回 true = 已成功唤起；false = 当前平台不支持或没有可用浏览器。
Future<bool> launchUrlString(String url) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await const MethodChannel(
      'sakuramanga/native',
    ).invokeMethod<bool>('openUrl', url);
    return ok ?? false;
  } catch (_) {
    return false;
  }
}
