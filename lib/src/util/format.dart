/// "刚刚 / n 分钟前 / n 天前 / 日期"。
String timeAgo(int millis) {
  if (millis <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - millis;
  if (diff < 60 * 1000) return '刚刚';
  if (diff < 3600 * 1000) return '${diff ~/ 60000} 分钟前';
  if (diff < 86400 * 1000) return '${diff ~/ 3600000} 小时前';
  if (diff < 7 * 86400 * 1000) return '${diff ~/ 86400000} 天前';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}/$month/$day';
}

/// 秒数 → "x 小时 y 分钟" / "y 分钟" / "z 秒"。
String formatDuration(int seconds) {
  if (seconds <= 0) return '0 分钟';
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

/// 字节数 → 可读文本。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
