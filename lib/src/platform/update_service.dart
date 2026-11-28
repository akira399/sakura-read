// 检查更新 + 多线路智能优选与极速下载（GitHub Release + 多镜像自动測速与断点续传）。
//
// 链路设计：
//   - 检查：并发竞速多个 GitHub Release API 镜像 + 官方 API + ungh.cc，
//     谁最快返回有效 Release JSON 就用谁（也保留顺序回退选项便于测试）；
//   - 下载：
//       1) 开下载前先并发测速 Range 0-0 优选最快健康镜像（过滤 HTML 假响应）；
//       2) 下载期间支持 HTTP 206 Range 断点续传，同一 .part 临时文件跨线路复用；
//       3) 遇断流（12s 无数据）、持续低速（< 48 KB/s 持续 8s）或用户点「换条线路」，
//          保留已下进度自动切到下一条镜像继续下载，全程无需从头再来；
//       4) 完成后做精确字节校验，防坏包/错误页。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// 一条 GitHub Release 下载线路。
class UpdateMirror {
  const UpdateMirror({
    required this.id,
    required this.label,
    required this.prefix,
  });

  final String id;
  final String label;

  /// URL 前缀；空串表示直连 GitHub。
  final String prefix;

  String resolve(String rawUrl) => '$prefix$rawUrl';
}

/// 下载调度阶段。
enum UpdateDownloadPhase {
  /// 正在并发测速各镜像节点。
  probing,

  /// 正在通过选定节点传输安装包。
  downloading,

  /// 当前线路较慢或失败，正在带着已下进度切换到下一条线路。
  switching,
}

/// 实时下载状态（供更新弹窗显示线路名称、实时速度与切换提示）。
class UpdateDownloadStatus {
  const UpdateDownloadStatus({
    required this.phase,
    required this.mirrorLabel,
    this.bytesPerSecond = 0,
    this.attempt = 1,
    this.totalMirrors = 1,
    this.message = '',
  });

  final UpdateDownloadPhase phase;
  final String mirrorLabel;
  final int bytesPerSecond;
  final int attempt;
  final int totalMirrors;
  final String message;
}

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

  /// 语义版本（去掉前缀 v），如 `2.1.0`。
  final String version;

  /// release 标题（如「樱读 v2.1.0」）。
  final String title;

  /// 更新说明（已做 markdown 轻量清洗，可直接展示）。
  final String notes;

  /// GitHub 原始下载地址（下载时按测速结果套用最优镜像）。
  final String downloadUrl;

  /// 安装包大小（字节；0 = 未知）。
  final int sizeBytes;

  /// 发布时间（ISO8601 字符串，可为空）。
  final String publishedAt;

  /// release 页面地址（浏览器兜底去处）。
  final String pageUrl;
}

class _SwitchRouteException implements Exception {
  const _SwitchRouteException(this.reason);
  final String reason;
}

/// 检查更新 / 多线路智能下载服务。
class UpdateService {
  UpdateService({
    http.Client? client,
    this.enableRouteProbe = true,
    this.raceCheckEndpoints = true,
    this.probeTimeout = const Duration(seconds: 4),
    this.stallTimeout = const Duration(seconds: 12),
    this.minSpeedBytesPerSec = 48 * 1024,
    this.slowGraceWindow = const Duration(seconds: 8),
    List<UpdateMirror>? mirrors,
    List<String>? endpoints,
  }) : _client = client ?? http.Client(),
       _mirrors = mirrors ?? defaultMirrors,
       _customEndpoints = endpoints;

  final http.Client _client;
  final bool enableRouteProbe;
  final bool raceCheckEndpoints;
  final Duration probeTimeout;
  final Duration stallTimeout;
  final int minSpeedBytesPerSec;
  final Duration slowGraceWindow;
  final List<UpdateMirror> _mirrors;
  final List<String>? _customEndpoints;

  /// 本次会话记住的最快可用线路 id（小幅优先，避免重复踩慢节点）。
  String? _lastFastestMirrorId;

  /// 全局共享实例（App 内使用）。
  static final UpdateService instance = UpdateService();

  /// 单端点检查超时。
  static const Duration _checkTimeout = Duration(seconds: 10);

  /// 检查端点（由 [AppInfo.repo] 派生）。
  static List<String> get checkEndpoints {
    final path = Uri.parse(AppInfo.repo).path;
    return [
      'https://gh-proxy.com/https://api.github.com/repos$path/releases/latest',
      'https://hk.gh-proxy.org/https://api.github.com/repos$path/releases/latest',
      'https://gh-proxy.org/https://api.github.com/repos$path/releases/latest',
      'https://api.github.com/repos$path/releases/latest',
      'https://ungh.cc/repos$path/releases/latest',
    ];
  }

  /// 默认下载加速线路（均为实测支持 Range 206 的镜像 + GitHub 直连兜底）。
  static const List<UpdateMirror> defaultMirrors = [
    UpdateMirror(
      id: 'gh-proxy',
      label: '加速线路 · gh-proxy',
      prefix: 'https://gh-proxy.com/',
    ),
    UpdateMirror(
      id: 'ghfast',
      label: '极速线路 · ghfast',
      prefix: 'https://ghfast.top/',
    ),
    UpdateMirror(
      id: 'hk-gh-proxy',
      label: '香港节点 · hk.gh-proxy',
      prefix: 'https://hk.gh-proxy.org/',
    ),
    UpdateMirror(
      id: 'gh-proxy-org',
      label: '备用节点 · gh-proxy.org',
      prefix: 'https://gh-proxy.org/',
    ),
    UpdateMirror(
      id: 'v6-gh-proxy',
      label: '双栈节点 · v6.gh-proxy',
      prefix: 'https://v6.gh-proxy.org/',
    ),
    UpdateMirror(id: 'direct', label: 'GitHub 直连', prefix: ''),
  ];

  /// 镜像前缀清单（兼容旧调用方）。
  static List<String> get downloadMirrors =>
      defaultMirrors.map((m) => m.prefix).toList(growable: false);

  /// 检查是否有新版本。
  Future<UpdateCheckResult> check({
    String currentVersion = AppInfo.version,
  }) async {
    final endpoints = _customEndpoints ?? checkEndpoints;
    if (endpoints.isEmpty) return UpdateCheckResult.failed('无可用检查端点');

    if (!raceCheckEndpoints || endpoints.length == 1) {
      return _checkSequential(endpoints, currentVersion);
    }
    return _checkRacing(endpoints, currentVersion);
  }

  Future<UpdateCheckResult> _checkSequential(
    List<String> endpoints,
    String currentVersion,
  ) async {
    String? lastError;
    for (final endpoint in endpoints) {
      final attempt = await _fetchEndpoint(endpoint, currentVersion);
      if (attempt.result != null) return attempt.result!;
      lastError = attempt.error;
    }
    return UpdateCheckResult.failed(lastError);
  }

  Future<UpdateCheckResult> _checkRacing(
    List<String> endpoints,
    String currentVersion,
  ) async {
    final completer = Completer<UpdateCheckResult>();
    var remaining = endpoints.length;
    String? lastError;

    for (final endpoint in endpoints) {
      _fetchEndpoint(endpoint, currentVersion).then((attempt) {
        if (completer.isCompleted) return;
        if (attempt.result != null) {
          completer.complete(attempt.result!);
          return;
        }
        lastError = attempt.error ?? lastError;
        remaining--;
        if (remaining <= 0 && !completer.isCompleted) {
          completer.complete(UpdateCheckResult.failed(lastError));
        }
      });
    }
    return completer.future;
  }

  Future<({UpdateCheckResult? result, String? error})> _fetchEndpoint(
    String endpoint,
    String currentVersion,
  ) async {
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
        return (result: null, error: '$endpoint -> HTTP ${resp.statusCode}');
      }
      final info = parseReleaseJson(jsonDecode(utf8.decode(resp.bodyBytes)));
      if (info == null || info.downloadUrl.isEmpty) {
        return (result: null, error: '$endpoint -> 数据不完整');
      }
      final result = isNewerVersion(info.version, currentVersion)
          ? UpdateCheckResult.available(info)
          : UpdateCheckResult.upToDate();
      return (result: result, error: null);
    } catch (e) {
      return (result: null, error: '$endpoint -> $e');
    }
  }

  /// 下载 APK 到 [targetPath]：测速优选 + 断点续传 + 慢速/断流自动切源。
  Future<bool> download(
    UpdateInfo info,
    String targetPath, {
    void Function(int received, int total)? onProgress,
    void Function(UpdateDownloadStatus status)? onStatus,
    bool Function()? isCancelled,
    bool Function()? shouldSwitchRoute,
  }) async {
    if (_mirrors.isEmpty) return false;

    List<UpdateMirror> ordered = _mirrors;
    if (enableRouteProbe && _mirrors.length > 1) {
      onStatus?.call(
        UpdateDownloadStatus(
          phase: UpdateDownloadPhase.probing,
          mirrorLabel: '多线路并发测速',
          totalMirrors: _mirrors.length,
          message: '正在并发测速并优选最快下载线路…',
        ),
      );
      ordered = await _rankMirrors(info.downloadUrl);
    }

    if (isCancelled?.call() == true) {
      await _quietDelete(File('$targetPath.part'));
      return false;
    }

    final tmp = File('$targetPath.part');
    for (var i = 0; i < ordered.length; i++) {
      if (isCancelled?.call() == true) {
        await _quietDelete(tmp);
        return false;
      }
      final mirror = ordered[i];
      final hasNext = i + 1 < ordered.length;
      onStatus?.call(
        UpdateDownloadStatus(
          phase: UpdateDownloadPhase.downloading,
          mirrorLabel: mirror.label,
          attempt: i + 1,
          totalMirrors: ordered.length,
          message: '正在连接 ${mirror.label}…',
        ),
      );

      try {
        final ok = await _downloadOnce(
          mirror: mirror,
          url: mirror.resolve(info.downloadUrl),
          targetPath: targetPath,
          expectedBytes: info.sizeBytes,
          attempt: i + 1,
          totalMirrors: ordered.length,
          hasNextMirror: hasNext,
          onProgress: onProgress,
          onStatus: onStatus,
          isCancelled: isCancelled,
          shouldSwitchRoute: shouldSwitchRoute,
        );
        if (ok) {
          _lastFastestMirrorId = mirror.id;
          return true;
        }
        if (isCancelled?.call() == true) {
          await _quietDelete(tmp);
          return false;
        }
      } on _SwitchRouteException catch (e) {
        if (hasNext) {
          onStatus?.call(
            UpdateDownloadStatus(
              phase: UpdateDownloadPhase.switching,
              mirrorLabel: ordered[i + 1].label,
              attempt: i + 2,
              totalMirrors: ordered.length,
              message: '${e.reason}，切换至 ${ordered[i + 1].label}…',
            ),
          );
        }
      } catch (_) {
        if (hasNext) {
          onStatus?.call(
            UpdateDownloadStatus(
              phase: UpdateDownloadPhase.switching,
              mirrorLabel: ordered[i + 1].label,
              attempt: i + 2,
              totalMirrors: ordered.length,
              message: '${mirror.label} 连接中断，正在断点续传切换下一条线路…',
            ),
          );
        }
      }
    }

    await _quietDelete(tmp);
    return false;
  }

  Future<List<UpdateMirror>> _rankMirrors(String downloadUrl) async {
    final results = await Future.wait(
      _mirrors.map((mirror) async {
        final sw = Stopwatch()..start();
        try {
          final uri = Uri.parse(mirror.resolve(downloadUrl));
          final req = http.Request('GET', uri)
            ..headers.addAll(const {
              'Range': 'bytes=0-0',
              'User-Agent': 'SakuraRead',
            });
          final resp = await _client.send(req).timeout(probeTimeout);
          final ct = (resp.headers['content-type'] ?? '').toLowerCase();
          // 尽快释放测速探测流，不额外拉取数据
          unawaited(resp.stream.drain<void>().catchError((_) {}));
          sw.stop();
          final okStatus = resp.statusCode == 206 || resp.statusCode == 200;
          final looksLikeWebPage =
              ct.contains('text/html') || ct.contains('application/json');
          if (okStatus && !looksLikeWebPage) {
            final bias = mirror.id == _lastFastestMirrorId ? -80 : 0;
            return (
              mirror: mirror,
              ok: true,
              score: sw.elapsedMilliseconds + bias,
            );
          }
        } catch (_) {}
        return (mirror: mirror, ok: false, score: 1 << 30);
      }),
    );

    final healthy = results.where((r) => r.ok).toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    final fallback = results.where((r) => !r.ok);
    return [
      for (final r in healthy) r.mirror,
      for (final r in fallback) r.mirror,
    ];
  }

  /// 单线路下载：支持 HTTP 206 断点续传、断流与低速检测。
  ///
  /// 切换线路或网络抖动时保留 `.part` 临时文件以便下一条线路继续传；
  /// 仅当校验损坏、用户取消或全部线路均失败时删掉 `.part`。
  Future<bool> _downloadOnce({
    required UpdateMirror mirror,
    required String url,
    required String targetPath,
    required int expectedBytes,
    required int attempt,
    required int totalMirrors,
    required bool hasNextMirror,
    void Function(int received, int total)? onProgress,
    void Function(UpdateDownloadStatus status)? onStatus,
    bool Function()? isCancelled,
    bool Function()? shouldSwitchRoute,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final tmp = File('$targetPath.part');

    var resumeFrom = 0;
    if (await tmp.exists()) {
      final len = await tmp.length();
      if (expectedBytes > 0 && len > expectedBytes) {
        await _quietDelete(tmp);
      } else if (expectedBytes > 0 && len == expectedBytes) {
        await _quietDelete(file);
        await tmp.rename(targetPath);
        return true;
      } else if (len > 0) {
        resumeFrom = len;
      }
    }

    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'SakuraRead';
    if (resumeFrom > 0) {
      req.headers['Range'] = 'bytes=$resumeFrom-';
    }

    final resp = await _client.send(req).timeout(const Duration(seconds: 15));
    final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
    final isHtmlOrJson =
        contentType.contains('text/html') ||
        contentType.contains('application/json');
    if ((resp.statusCode != 200 && resp.statusCode != 206) || isHtmlOrJson) {
      await resp.stream.drain<void>().catchError((_) {});
      throw HttpException(
        'HTTP ${resp.statusCode}${isHtmlOrJson ? ' ($contentType)' : ''}',
        uri: Uri.parse(url),
      );
    }

    final contentRange = (resp.headers['content-range'] ?? '').toLowerCase();
    final canAppend =
        resumeFrom > 0 &&
        resp.statusCode == 206 &&
        (contentRange.isEmpty || contentRange.startsWith('bytes $resumeFrom-'));

    var received = canAppend ? resumeFrom : 0;
    final total = expectedBytes > 0
        ? expectedBytes
        : ((resp.contentLength ?? 0) + (canAppend ? resumeFrom : 0));

    final sink = tmp.openWrite(
      mode: canAppend ? FileMode.append : FileMode.write,
    );
    final iter = StreamIterator<List<int>>(resp.stream);

    var speedWindowBytes = 0;
    var lastSpeedAt = DateTime.now();
    var lastStatusAt = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime? lowSpeedSince;
    var currentBps = 0;
    var cancelled = false;

    try {
      while (await iter.moveNext().timeout(stallTimeout)) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
        if (hasNextMirror && shouldSwitchRoute?.call() == true) {
          throw const _SwitchRouteException('已手动换线');
        }

        final chunk = iter.current;
        if (chunk.isNotEmpty) {
          sink.add(chunk);
          received += chunk.length;
          speedWindowBytes += chunk.length;
          onProgress?.call(received, total);
        }

        final now = DateTime.now();
        final elapsedMs = now.difference(lastSpeedAt).inMilliseconds;
        if (elapsedMs >= 500) {
          currentBps = (speedWindowBytes * 1000 / elapsedMs).round();
          speedWindowBytes = 0;
          lastSpeedAt = now;

          final remainingBytes = total > 0 ? total - received : (1 << 20);
          if (hasNextMirror &&
              minSpeedBytesPerSec > 0 &&
              remainingBytes > 256 * 1024) {
            if (currentBps < minSpeedBytesPerSec) {
              lowSpeedSince ??= now;
              if (now.difference(lowSpeedSince) >= slowGraceWindow) {
                throw const _SwitchRouteException('当前线路速度较慢');
              }
            } else {
              lowSpeedSince = null;
            }
          }
        }

        if (now.difference(lastStatusAt).inMilliseconds >= 350) {
          lastStatusAt = now;
          onStatus?.call(
            UpdateDownloadStatus(
              phase: UpdateDownloadPhase.downloading,
              mirrorLabel: mirror.label,
              bytesPerSecond: currentBps,
              attempt: attempt,
              totalMirrors: totalMirrors,
              message: canAppend && resumeFrom > 0
                  ? '已断点续传 ${mirror.label}'
                  : mirror.label,
            ),
          );
        }
      }
    } finally {
      await iter.cancel().catchError((_) {});
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
    }

    if (cancelled || isCancelled?.call() == true) {
      await _quietDelete(tmp);
      return false;
    }

    // 大小校验：镜像返回截断或异常包时删掉损坏的 .part 并换下一条线
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

/// 解析 release JSON（同时兼容 GitHub API 与 ungh.cc 两种格式）。
UpdateInfo? parseReleaseJson(Object? json) {
  if (json is! Map) return null;
  final release = json['release'] is Map ? json['release'] as Map : json;

  final tag = _firstString(release, ['tag_name', 'tag']);
  if (tag.isEmpty) return null;

  final asset = _pickApkAsset(release['assets']);

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

/// 从 release 的 `assets[]` 里挑出适配当前手机架构（arm64 优先）的 APK。
Map? _pickApkAsset(Object? assets) {
  if (assets is! List) return null;
  Map? best;
  var bestScore = -1;
  for (final item in assets) {
    if (item is! Map) continue;
    final name = _firstString(item, [
      'name',
      'browser_download_url',
      'downloadUrl',
    ]).toLowerCase();
    if (!name.contains('.apk')) continue;
    final int score;
    if (name.contains('arm64') || name.contains('aarch64')) {
      score = 3;
    } else if (name.contains('universal') || name.contains('all-abi')) {
      score = 2;
    } else if (name.contains('x86') || name.contains('x64')) {
      score = 0;
    } else {
      score = 1;
    }
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  return best;
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
String cleanReleaseNotes(String markdown) {
  var s = markdown.replaceAll('\r\n', '\n');
  s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = s.replaceAll('`', '');
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true), '· ');
  s = s.replaceAll(RegExp(r'^\s{0,3}\d+\.\s+', multiLine: true), '· ');
  s = s.replaceAll('**', '').replaceAll('__', '');
  s = s.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
