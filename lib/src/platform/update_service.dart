// 检查更新 + 下载新版本安装包（GitHub Release，国内镜像加速）。
//
// 为什么独立成服务：网络链路（多端点回退 / 镜像前缀 / 大小校验）需要
// 可测试，全部走注入的 http.Client，测试用 MockClient 覆盖。
//
// 链路设计：
//   - 检查：gh-proxy 透传 GitHub API → 直连 GitHub API → ungh.cc，
//     任一成功即出结果（返回 200 但数据不完整时继续下一个）；
//   - 下载：gh-proxy.com → ghproxy.net → ghfast.top → 直连，
//     「全程成功 + 大小校验通过」才算成功，否则换下一个镜像。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// 「检查更新」的结果状态。
enum UpdateCheckStatus {
  /// 有新版本可用。
  updateAvailable,

  /// 已是最新（含设备版本比线上更新的情况）。
  upToDate,

  /// 所有端点都失败（网络问题等）。
  failed,
}

/// 一次「检查更新」的完整结果。
class UpdateCheckResult {
  const UpdateCheckResult._(this.status, this.info, this.error);

  final UpdateCheckStatus status;

  /// 有新版时的详情；其余状态为 null。
  final UpdateInfo? info;

  /// 失败原因（用于调试与日志）。
  final String? error;

  static UpdateCheckResult available(UpdateInfo info) =>
      UpdateCheckResult._(UpdateCheckStatus.updateAvailable, info, null);

  static UpdateCheckResult upToDate() =>
      const UpdateCheckResult._(UpdateCheckStatus.upToDate, null, null);

  static UpdateCheckResult failed([String? error]) =>
      UpdateCheckResult._(UpdateCheckStatus.failed, null, error);
}

/// 线上 release 的解析结果。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.title,
    required this.notes,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.publishedAt,
    required this.pageUrl,
  });

  /// 语义版本（去掉前缀 v），如 `1.0.1`。
  final String version;

  /// release 标题（如「樱读 v1.0.1 ── ...」）。
  final String title;

  /// 更新说明（已做 markdown 轻量清洗，可直接展示）。
  final String notes;

  /// GitHub 原始下载地址（下载时依次套用镜像前缀）。
  final String downloadUrl;

  /// 安装包大小（字节；0 = 未知）。
  final int sizeBytes;

  /// 发布时间（ISO8601 字符串，可为空）。
  final String publishedAt;

  /// release 页面地址（浏览器打不开时的兜底去处）。
  final String pageUrl;
}

/// 检查更新 / 下载安装包服务。
///
/// 由 [instance] 单例在 App 内共享；测试用 `UpdateService(client: mock)`
/// 构造独立实例（注入 MockClient）。
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 全局共享实例（App 内使用）。
  static final UpdateService instance = UpdateService();

  /// 单端点超时。
  static const Duration _checkTimeout = Duration(seconds: 10);

  /// 检查端点（按顺序回退；由 [AppInfo.repo] 派生，仓库地址只维护一处）。
  static List<String> get checkEndpoints {
    final path = Uri.parse(AppInfo.repo).path; // /akira399/sakura-read
    return [
      'https://gh-proxy.com/https://api.github.com/repos$path/releases/latest',
      'https://api.github.com/repos$path/releases/latest',
      'https://ungh.cc/repos$path/releases/latest',
    ];
  }

  /// 下载镜像前缀（按顺序回退）；空串 = 直连 GitHub。
  ///
  /// 实测（写入项目时）：前三个均能对 release 下载链返回 200；
  /// 直连兜底通常无效但保留（部分网络环境下可通）。
  static const List<String> downloadMirrors = [
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
    'https://ghfast.top/',
    '',
  ];

  /// 检查是否有新版本。
  ///
  /// [currentVersion] 默认取 [AppInfo.version]（测试可传任意版本）。
  Future<UpdateCheckResult> check({
    String currentVersion = AppInfo.version,
  }) async {
    String? lastError;
    for (final endpoint in checkEndpoints) {
      try {
        final resp = await _client
            .get(
              Uri.parse(endpoint),
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'SakuraRead',
              },
            )
            .timeout(_checkTimeout);
        if (resp.statusCode != 200) {
          lastError = '$endpoint -> HTTP ${resp.statusCode}';
          continue;
        }
        final info = parseReleaseJson(jsonDecode(utf8.decode(resp.bodyBytes)));
        if (info == null || info.downloadUrl.isEmpty) {
          lastError = '$endpoint -> 数据不完整';
          continue;
        }
        return isNewerVersion(info.version, currentVersion)
            ? UpdateCheckResult.available(info)
            : UpdateCheckResult.upToDate();
      } catch (e) {
        lastError = '$endpoint -> $e';
      }
    }
    return UpdateCheckResult.failed(lastError);
  }

  /// 下载 APK 到 [targetPath]。
  ///
  /// - 按 [downloadMirrors] 顺序尝试：任一镜像「全程成功 + 大小校验
  ///   通过」即返回 true；
  /// - [onProgress]：`(已下载字节, 总字节)`（总字节未知时为 0）；
  /// - [isCancelled]：返回 true 时中止下载（清理半成品），返回 false。
  Future<bool> download(
    UpdateInfo info,
    String targetPath, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    for (final mirror in downloadMirrors) {
      if (isCancelled?.call() == true) return false;
      try {
        final ok = await _downloadOnce(
          url: '$mirror${info.downloadUrl}',
          targetPath: targetPath,
          expectedBytes: info.sizeBytes,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (ok) return true;
        if (isCancelled?.call() == true) return false;
      } catch (_) {
        // 本镜像失败：继续下一个
      }
    }
    return false;
  }

  /// 单镜像下载：先写 `.part` 临时文件，完成后做大小校验并改名。
  Future<bool> _downloadOnce({
    required String url,
    required String targetPath,
    required int expectedBytes,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    final resp = await _client.send(req).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final tmp = File('$targetPath.part');
    final sink = tmp.openWrite();
    var received = 0;
    final total = resp.contentLength ?? expectedBytes;
    try {
      await for (final chunk in resp.stream.timeout(
        const Duration(seconds: 60),
      )) {
        if (isCancelled?.call() == true) {
          await sink.close();
          await _quietDelete(tmp);
          return false;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      await _quietDelete(tmp);
      rethrow;
    }
    // 大小校验：镜像返回错误页 / 传输截断时拒绝（防止装到坏包）
    if (expectedBytes > 0 && received != expectedBytes) {
      await _quietDelete(tmp);
      throw const FileSystemException('安装包大小校验失败');
    }
    await _quietDelete(file);
    await tmp.rename(targetPath);
    return true;
  }

  Future<void> _quietDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 语义版本比较：`candidate` 是否比 `current` 新。
///
/// - 容忍 `v` 前缀与 `1.2.3-beta.1` 这类预发布后缀（只比较数字段）；
/// - 逐段比较，缺失段按 0 处理（`1.0` vs `1.0.1` 视作更旧）；
/// - 完全相同时返回 false（避免每次启动重复提示同一版本）。
bool isNewerVersion(String candidate, String current) {
  final a = _versionParts(candidate);
  final b = _versionParts(current);
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

List<int> _versionParts(String raw) {
  final cleaned = raw.trim().replaceFirst(RegExp('^[vV]'), '');
  final core = cleaned.split('-').first.split('+').first;
  return core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
}

/// 解析 release JSON（同时兼容 GitHub API 与 ungh.cc 两种格式）：
///
/// - GitHub API：`tag_name` / `name` / `body` / `assets[].browser_download_url`
///   / `published_at` / `html_url`；
/// - ungh.cc：`{"release": {tag / name / markdown / assets[].downloadUrl
///   / publishedAt / htmlUrl}}`。
UpdateInfo? parseReleaseJson(Object? json) {
  if (json is! Map) return null;
  final release = json['release'] is Map ? json['release'] as Map : json;

  final tag = _firstString(release, ['tag_name', 'tag']);
  if (tag.isEmpty) return null;

  Map? asset;
  final assets = release['assets'];
  if (assets is List) {
    for (final item in assets) {
      if (item is Map) {
        asset = item;
        break;
      }
    }
  }

  final downloadUrl = asset == null
      ? ''
      : _firstString(asset, ['browser_download_url', 'downloadUrl']);
  final size = asset == null ? 0 : _firstInt(asset, ['size']);
  final name = _firstString(release, ['name']);
  final body = _firstString(release, ['body', 'markdown']);
  final publishedAt = _firstString(release, ['published_at', 'publishedAt']);
  final htmlUrl = _firstString(release, ['html_url', 'htmlUrl']);

  return UpdateInfo(
    version: tag.replaceFirst(RegExp('^[vV]'), ''),
    title: name.isEmpty ? '樱读 $tag' : name,
    notes: cleanReleaseNotes(body),
    downloadUrl: downloadUrl,
    sizeBytes: size,
    publishedAt: publishedAt,
    pageUrl: htmlUrl.isEmpty ? '${AppInfo.repo}/releases' : htmlUrl,
  );
}

String _firstString(Map map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return '';
}

int _firstInt(Map map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
  }
  return 0;
}

/// 轻量清洗 release 说明（markdown → 纯文本）：保留结构与换行，去掉装饰。
///
/// 只做「阅读友好」处理，不追求完整 markdown 渲染（详情可跳 release 页）。
String cleanReleaseNotes(String markdown) {
  var s = markdown.replaceAll('\r\n', '\n');
  // 图片 ![alt](url) 与链接 [text](url)
  s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  // HTML 标签与行内代码标记
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll('`', '');
  // 行首标题 # / 引用 > / 列表符（- * + 与数字序号）
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '· ');
  s = s.replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '· ');
  // 加粗 / 斜体 / 水平线
  s = s.replaceAll('**', '').replaceAll('__', '');
  s = s.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
  // 连续空行压缩（最多保留一个空行）
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
