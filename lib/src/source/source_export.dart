// 书源导出：小数据复制到剪贴板，大数据保存为文件。
//
// 背景（用户反馈「导出按钮点了没反应」）：Android 剪贴板内容经 Binder
// 传输，单次事务上限约 1 MB。当书源很多（实测 1000+ 个、JSON 6 MB+）时，
// `Clipboard.setData` 会直接抛异常；旧实现未捕获异常、也没有任何反馈，
// 用户看到的就是"点了没反应"。
//
// 策略：
//   - 小数据（≤ [kClipboardExportLimitBytes]）：复制到剪贴板（便于跨应用粘贴）；
//   - 大数据：保存为 JSON 文件（Download 目录优先，失败退回 App 私有目录）；
//   - 剪贴板调用失败时同样退回文件——导出不能是无反馈的死路。
import 'dart:convert';
import 'dart:io';

import '../platform/native_bridge.dart';

/// 尝试复制到剪贴板的数据上限（UTF-8 字节）。
///
/// 保守取值：Android Binder 单次事务上限约 1 MB，留足余量。
const int kClipboardExportLimitBytes = 200 * 1024;

/// 导出结果。
class SourceExportResult {
  const SourceExportResult.clipboard() : path = null, byteLength = 0;

  const SourceExportResult.file(this.path, this.byteLength);

  /// 保存的文件路径；null = 已复制到剪贴板。
  final String? path;

  /// 导出内容的 UTF-8 字节数（用于提示文案）。
  final int byteLength;

  bool get savedToFile => path != null;
}

/// 导出书源 JSON。
///
/// - [copyToClipboard]：剪贴板实现（注入以便测试与失败降级）；
/// - [downloadDirOverride] / [filesDirOverride]：仅测试注入目录。
Future<SourceExportResult> exportSourcesJson(
  String json, {
  required Future<void> Function(String text) copyToClipboard,
  String? downloadDirOverride,
  String? filesDirOverride,
}) async {
  final byteLength = utf8.encode(json).length;
  if (byteLength <= kClipboardExportLimitBytes) {
    try {
      await copyToClipboard(json);
      return const SourceExportResult.clipboard();
    } catch (_) {
      // 剪贴板被系统拒绝（服务不可用 / 内容偏大）→ 改走文件
    }
  }
  final path = await _writeExportFile(
    json,
    downloadDirOverride: downloadDirOverride,
    filesDirOverride: filesDirOverride,
  );
  return SourceExportResult.file(path, byteLength);
}

Future<String> _writeExportFile(
  String json, {
  String? downloadDirOverride,
  String? filesDirOverride,
}) async {
  final name = '樱读书源-${_stamp(DateTime.now())}.json';

  final candidates = <String>[];
  if (downloadDirOverride != null) {
    candidates.add(downloadDirOverride);
  } else {
    candidates.add('${await NativeBridge.storageRoot()}/Download');
  }
  if (filesDirOverride != null) {
    candidates.add(filesDirOverride);
  } else {
    candidates.add((await NativeBridge.appDirs()).files);
  }

  Object? lastError;
  for (final dirPath in candidates) {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      await file.writeAsString(json);
      return file.path;
    } catch (e) {
      lastError = e;
    }
  }
  throw FileSystemException('没有可写的目录（$lastError）', candidates.join('、'));
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
