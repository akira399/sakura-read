// 请求层：超时 / 重试 / 编码探测（UTF-8 与 GBK）/ 请求头 / Cookie / 简单限流。
//
// 设计目标（对照 Legado 的公开行为，独立实现）：
// - 书源站点编码混杂（UTF-8 / GBK），需要按 响应头 → 页面 meta → 兜底探测 的顺序解码；
// - 每源可配置并发率（concurrentRate：`N/M` 表示 M 秒最多 N 次请求）；
// - Cookie 暂存于内存（enabledCookieJar 的基础形态，后续里程碑再持久化）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;

/// 一次请求的响应。
class SourceResponse {
  SourceResponse({
    required this.statusCode,
    required this.body,
    required this.bytes,
    required this.headers,
    required this.finalUrl,
  });

  final int statusCode;

  /// 按检测到的编码解码后的正文。
  final String body;

  /// 原始字节（保存封面等二进制场景备用）。
  final Uint8List bytes;

  final Map<String, String> headers;

  /// 重定向后的最终地址。
  final String finalUrl;

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// 请求失败（网络层）。
class SourceHttpException implements Exception {
  SourceHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 轻量请求客户端。
class SourceHttpClient {
  SourceHttpClient({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      defaultTimeout = timeout ?? const Duration(seconds: 15);

  final http.Client _client;
  final Duration defaultTimeout;
  final _CookieJar _cookies = _CookieJar();

  /// GET。
  Future<SourceResponse> get(
    String url, {
    Map<String, String>? headers,
    String? charset,
    Duration? timeout,
    int retries = 1,
  }) => request(
    'GET',
    url,
    headers: headers,
    charset: charset,
    timeout: timeout,
    retries: retries,
  );

  /// POST（body 为原始字符串，通常已在模板层渲染好）。
  Future<SourceResponse> post(
    String url, {
    Map<String, String>? headers,
    String? body,
    String? charset,
    Duration? timeout,
    int retries = 1,
  }) => request(
    'POST',
    url,
    headers: headers,
    body: body,
    charset: charset,
    timeout: timeout,
    retries: retries,
  );

  /// 通用请求（带重试与 Cookie）。
  Future<SourceResponse> request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
    String? charset,
    Duration? timeout,
    int retries = 1,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw SourceHttpException('无效的地址：$url');
    }
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final h = <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36',
          ...?headers,
        };
        final cookie = _cookies.headerFor(uri);
        if (cookie != null) {
          h['Cookie'] = cookie;
        }
        http.Response resp;
        final t = timeout ?? defaultTimeout;
        if (method == 'POST') {
          resp = await _client
              .post(
                uri,
                headers: h,
                body: body == null ? null : utf8.encode(body),
              )
              .timeout(t);
        } else if (method == 'GET') {
          resp = await _client.get(uri, headers: h).timeout(t);
        } else {
          final req = http.Request(method, uri);
          req.headers.addAll(h);
          if (body != null) req.bodyBytes = utf8.encode(body);
          resp = await http.Response.fromStream(
            await _client.send(req).timeout(t),
          );
        }
        _cookies.absorb(uri, resp.headers);
        final decoded = decodeBody(resp.bodyBytes, resp.headers, charset);
        return SourceResponse(
          statusCode: resp.statusCode,
          body: decoded,
          bytes: resp.bodyBytes,
          headers: resp.headers,
          finalUrl: resp.request?.url.toString() ?? url,
        );
      } on TimeoutException {
        if (attempt <= retries) continue;
        throw SourceHttpException(
          '请求超时（${(timeout ?? defaultTimeout).inSeconds}s）',
        );
      } on SocketException catch (e) {
        if (attempt <= retries) continue;
        throw SourceHttpException('网络错误：${e.message}');
      } on http.ClientException catch (e) {
        if (attempt <= retries) continue;
        throw SourceHttpException('请求失败：${e.message}');
      }
    }
  }

  void close() => _client.close();
}

/// 解析 `concurrentRate`：`N/M`（M 秒 N 次）或 `N`（每秒 N 次）。
class RateGate {
  RateGate(String? concurrentRate) {
    final s = concurrentRate?.trim() ?? '';
    if (s.isEmpty) return;
    final parts = s.split('/');
    final n = int.tryParse(parts[0].trim());
    if (n == null || n <= 0) return;
    final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 1) : 1;
    window = Duration(seconds: math.max(1, m));
    limit = n;
  }

  Duration? window;
  int limit = 0;
  final List<DateTime> _recent = [];

  bool get active => window != null && limit > 0;

  /// 在允许的速率内等待。
  Future<void> waitSlot() async {
    final w = window;
    if (w == null || limit <= 0) return;
    while (true) {
      final now = DateTime.now();
      _recent.removeWhere((t) => now.difference(t) > w);
      if (_recent.length < limit) {
        _recent.add(now);
        return;
      }
      final oldest = _recent.first;
      final wait = w - now.difference(oldest);
      await Future<void>.delayed(wait.isNegative ? Duration.zero : wait);
    }
  }
}

// ---------- 编码解码 ----------

/// 解码响应正文：
/// 显式 charset → Content-Type → meta 探测 → UTF-8 严格 → GBK → UTF-8 宽松。
String decodeBody(
  Uint8List bytes,
  Map<String, String>? headers, [
  String? charsetHint,
]) {
  var cs = charsetHint?.toLowerCase().trim();
  cs ??= _charsetFromContentType(headers?['content-type']);
  cs ??= _sniffCharset(bytes);
  return _decodeWith(bytes, cs);
}

String? _charsetFromContentType(String? contentType) {
  if (contentType == null) return null;
  final m = RegExp(
    r'charset\s*=\s*["\x27]?([\w-]+)',
    caseSensitive: false,
  ).firstMatch(contentType);
  return m?.group(1)?.toLowerCase();
}

String? _sniffCharset(Uint8List bytes) {
  final n = math.min(bytes.length, 2048);
  final head = latin1.decode(bytes.sublist(0, n), allowInvalid: true);
  final m = RegExp(
    r'charset\s*=\s*["\x27]?\s*([\w-]+)',
    caseSensitive: false,
  ).firstMatch(head);
  return m?.group(1)?.toLowerCase();
}

String _decodeWith(Uint8List bytes, String? cs) {
  if (cs != null) {
    if (cs.contains('gb')) {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        // 落到兜底
      }
    }
    if (cs.contains('utf')) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        // 落到兜底
      }
    }
  }
  // 兜底链：严格 UTF-8 → GBK → 宽松 UTF-8
  try {
    return utf8.decode(bytes);
  } catch (_) {}
  try {
    final t = gbk.decode(bytes);
    if (!t.contains('\uFFFD')) return t;
  } catch (_) {}
  return utf8.decode(bytes, allowMalformed: true);
}

// ---------- 极简 Cookie 暂存 ----------

class _CookieJar {
  final Map<String, Map<String, String>> _byHost = {};

  void absorb(Uri uri, Map<String, String> headers) {
    final setCookie = headers['set-cookie'] ?? headers['Set-Cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final host = uri.host;
    final jar = _byHost.putIfAbsent(host, () => {});
    // 粗粒度解析：按 ", " 拆分多枚 Cookie（忽略 Expires 内的逗号误差）
    for (final raw in setCookie.split(RegExp(r',(?=[^;=]+=)'))) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }
  }

  String? headerFor(Uri uri) {
    final jar = _byHost[uri.host];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
