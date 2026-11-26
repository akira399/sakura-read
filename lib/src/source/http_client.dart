// 请求层：Dio + CookieManager + PersistCookieJar / CookieJar +
// 超时 / 重试 / 编码探测（UTF-8 与 GBK）/ 请求头 / 限流 / 手动重定向。
//
// 设计目标（对照 Legado 3.0 的公开行为，独立实现）：
// - 书源站点编码混杂（UTF-8 / GBK），按 显式 charset → 响应头 → 页面 meta → 兜底探测 解码；
// - 每源可配置并发率（concurrentRate：`N/M` 表示 M 秒最多 N 次请求）；
// - Cookie 通过 `dio_cookie_manager` + `cookie_jar`（`PersistCookieJar` / `CookieJar`）管理，
//   并同步桥接给 JS 引擎的 `cookie.getCookie(url)` / `cookie.setCookie(url, c)`。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:http/http.dart' as http;

import 'js_engine.dart';

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

/// 书源 HTTP 客户端（基于 `Dio` + `CookieManager` + `CookieJar`/`PersistCookieJar`）。
///
/// 兼容旧版构造参数 `SourceHttpClient(client: MockClient(...))`，保证既有离线测试全部通过。
class SourceHttpClient implements JsCookieBridge {
  SourceHttpClient({
    http.Client? client,
    Duration? timeout,
    Dio? dio,
    CookieJar? cookieJar,
    String? cookieStorageDir,
  }) : _legacyClient = client,
       _ownsDio = dio == null,
       defaultTimeout = timeout ?? const Duration(seconds: 15),
       cookieJar =
           cookieJar ??
           _createDefaultJar(
             storageDir: cookieStorageDir,
             isolated: client != null || dio != null,
           ) {
    _dio = dio ?? _buildDio(this.cookieJar, legacyClient: client);
    if (dio != null && !dio.interceptors.any((i) => i is CookieManager)) {
      dio.interceptors.add(
        CookieManager(
          _SecureEnforcingCookieJar(this.cookieJar),
          ignoreInvalidCookies: true,
        ),
      );
    }
  }

  /// 创建带磁盘持久化 Cookie 的客户端（`PersistCookieJar`）。
  factory SourceHttpClient.persistent({
    required String cookieDir,
    Duration? timeout,
  }) => SourceHttpClient(timeout: timeout, cookieStorageDir: cookieDir);

  /// 全局默认 Cookie 持久化目录（应用启动时可写入，未设置时默认内存 `CookieJar`）。
  static String? defaultCookieDir;

  /// 全局共享 CookieJar（仅在设置了 [defaultCookieDir] 且未传自定义 `client`/`dio` 时复用）。
  static CookieJar? _sharedPersistentJar;

  static CookieJar _createDefaultJar({
    String? storageDir,
    required bool isolated,
  }) {
    final dir = storageDir ?? (isolated ? null : defaultCookieDir);
    if (dir != null && dir.trim().isNotEmpty) {
      if (storageDir == null && _sharedPersistentJar != null) {
        return _sharedPersistentJar!;
      }
      final jar = PersistCookieJar(
        ignoreExpires: true,
        storage: FileStorage(dir),
      );
      if (storageDir == null) _sharedPersistentJar = jar;
      return jar;
    }
    return CookieJar();
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36';

  late Dio _dio;
  final http.Client? _legacyClient;
  final bool _ownsDio;
  final Duration defaultTimeout;
  final CookieJar cookieJar;

  /// 供 JS 同步调用 `cookie.getCookie(url)` 读取的镜像缓存（与 [cookieJar] 保持同步）。
  final Map<String, String> _syncCookieMirror = {};

  Dio _buildDio(CookieJar jar, {http.Client? legacyClient}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: defaultTimeout,
        receiveTimeout: defaultTimeout,
        sendTimeout: defaultTimeout,
        followRedirects: false,
        maxRedirects: 0,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    if (legacyClient != null) {
      dio.httpClientAdapter = _PackageHttpAdapter(legacyClient);
    }
    dio.interceptors.add(
      CookieManager(_SecureEnforcingCookieJar(jar), ignoreInvalidCookies: true),
    );
    return dio;
  }

  /// 丢掉缓冲在连接池里的坏连接。
  ///
  /// 用户反馈的「请求失败：Connection closed before full header was received」
  /// 就是 keep-alive 连接被对端提前关掉后继续复用的结果：重试时如果还拿着
  /// 同一个 client，会一直撞在同一条死连接上，所以必须换一个。
  void _resetConnectionPool() {
    if (!_ownsDio || _legacyClient != null) return;
    try {
      _dio.close(force: true);
    } catch (_) {
      // 关闭失败不影响后续重试
    }
    _dio = _buildDio(cookieJar);
  }

  // ---------- Cookie 管理与 JsCookieBridge 实现 ----------

  static String _cookieHostKey(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null && uri.host.isNotEmpty) return uri.host.toLowerCase();
    return url.trim().toLowerCase();
  }

  @override
  String getCookie(String url) => _syncCookieMirror[_cookieHostKey(url)] ?? '';

  @override
  void setCookie(String url, String cookie) {
    final hostKey = _cookieHostKey(url);
    if (hostKey.isEmpty) return;
    final trimmed = cookie.trim();
    if (trimmed.isEmpty) {
      _syncCookieMirror.remove(hostKey);
    } else {
      _syncCookieMirror[hostKey] = trimmed;
    }
    final uri = _parseCookieUri(url);
    if (uri != null) {
      unawaited(saveCookieHeader(uri.toString(), trimmed));
    }
  }

  @override
  void removeCookie(String url) {
    _syncCookieMirror.remove(_cookieHostKey(url));
    final uri = _parseCookieUri(url);
    if (uri != null) {
      unawaited(cookieJar.delete(uri, true));
    }
  }

  /// 异步从 [cookieJar] 读取指定 URL 的 Cookie 请求头。
  Future<String> loadCookieHeader(String url) async {
    final uri = _parseCookieUri(url);
    if (uri == null) return '';
    final list = await cookieJar.loadForRequest(uri);
    final header = CookieManager.getCookies(list);
    if (header.isNotEmpty) {
      _syncCookieMirror[_cookieHostKey(url)] = header;
    }
    return header;
  }

  /// 异步将 `k1=v1; k2=v2` 格式 Cookie 写入 [cookieJar] 并更新同步镜像。
  Future<void> saveCookieHeader(String url, String cookieHeader) async {
    final uri = _parseCookieUri(url);
    if (uri == null) return;
    final trimmed = cookieHeader.trim();
    if (trimmed.isEmpty) {
      await cookieJar.delete(uri, true);
      _syncCookieMirror.remove(_cookieHostKey(url));
      return;
    }
    final cookies = <Cookie>[];
    for (final part in trimmed.split(';')) {
      final p = part.trim();
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final name = p.substring(0, eq).trim();
      final value = p.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      try {
        cookies.add(Cookie(name, value)..path = '/');
      } catch (_) {
        // 忽略非法字符 Cookie
      }
    }
    if (cookies.isNotEmpty) {
      await cookieJar.saveFromResponse(uri, cookies);
      await _refreshCookieMirror(uri);
    }
  }

  /// 清空指定 URL 或全部 Cookie。
  Future<void> clearCookies([String? url]) async {
    if (url == null || url.trim().isEmpty) {
      _syncCookieMirror.clear();
      await cookieJar.deleteAll();
      return;
    }
    _syncCookieMirror.remove(_cookieHostKey(url));
    final uri = _parseCookieUri(url);
    if (uri != null) {
      await cookieJar.delete(uri, true);
    }
  }

  Future<void> _refreshCookieMirror(Uri uri) async {
    try {
      final list = await cookieJar.loadForRequest(uri);
      final header = CookieManager.getCookies(list);
      final key = uri.host.toLowerCase();
      if (header.isEmpty) {
        _syncCookieMirror.remove(key);
      } else {
        _syncCookieMirror[key] = header;
      }
    } catch (_) {
      // 忽略镜像刷新异常
    }
  }

  static Uri? _parseCookieUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed;
    }
    return Uri.tryParse('https://$trimmed');
  }

  /// 导出给 [LegadoJsEngine.evalAsync] 的异步 HTTP 桥接。
  JsAsyncHttpCallback asJsAsyncHttpCallback({Duration? timeout}) {
    return (
      String method,
      String url, {
      String? body,
      Map<String, String>? headers,
    }) async {
      final resp = await request(
        method,
        url,
        headers: headers,
        body: body,
        timeout: timeout ?? defaultTimeout,
        retries: 1,
      );
      return JsHttpResult(
        body: resp.body,
        statusCode: resp.statusCode,
        headers: resp.headers,
        url: resp.finalUrl,
      );
    };
  }

  // ---------- HTTP 请求 API ----------

  /// GET。
  Future<SourceResponse> get(
    String url, {
    Map<String, String>? headers,
    String? charset,
    Duration? timeout,
    int retries = 2,
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
    int retries = 2,
  }) => request(
    'POST',
    url,
    headers: headers,
    body: body,
    charset: charset,
    timeout: timeout,
    retries: retries,
  );

  /// 通用请求（带重试、Cookie 与手动重定向）。
  ///
  /// 为什么手动处理 3xx：书站换域名时普遍返回 `301` + `Location`，而
  /// 浏览器语义在跟随 301/302 时会把 POST **改写成 GET**，
  /// 对「搜索接口只接受 POST」的站点这等于丢掉请求体。
  /// 这里对 301/302/307/308 保留原始方法 + 请求体重发，只有 303 才降级 GET。
  Future<SourceResponse> request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
    String? charset,
    Duration? timeout,
    int retries = 2,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isHttpUri(uri)) {
      throw SourceHttpException('无效的地址：$url');
    }
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final h = _normalizeInitialHeaders(headers);
        var currentUri = uri;
        var currentMethod = method.toUpperCase();
        var currentBody = body;
        var redirects = 0;
        final t = timeout ?? defaultTimeout;

        while (true) {
          final reqHeaders = Map<String, dynamic>.from(h);
          final response = await _dio
              .requestUri<List<int>>(
                currentUri,
                data: currentBody == null ? null : utf8.encode(currentBody),
                options: Options(
                  method: currentMethod,
                  headers: reqHeaders,
                  followRedirects: false,
                  maxRedirects: 0,
                  responseType: ResponseType.bytes,
                  validateStatus: (_) => true,
                  sendTimeout: t,
                  receiveTimeout: t,
                ),
              )
              .timeout(t);

          await _refreshCookieMirror(currentUri);

          final statusCode = response.statusCode ?? 0;
          final flatHeaders = _flattenHeaders(response.headers);
          final loc = flatHeaders['location'];
          final isRedirect =
              statusCode == 301 ||
              statusCode == 302 ||
              statusCode == 303 ||
              statusCode == 307 ||
              statusCode == 308;

          if (isRedirect && loc != null && loc.isNotEmpty) {
            if (redirects >= 4) {
              throw SourceHttpException('重定向次数过多');
            }
            redirects++;
            final next = currentUri.resolve(loc.trim());
            if (!_isHttpUri(next)) {
              throw SourceHttpException('无效的重定向地址：$next');
            }
            // 必须修改下一跳复用的 h；跨源跳转剥离敏感头且后续跳不恢复。
            final crossOrigin = currentUri.origin != next.origin;
            h.removeWhere((key, _) {
              final name = key.toLowerCase();
              return name == 'host' ||
                  (crossOrigin &&
                      const {
                        'authorization',
                        'proxy-authorization',
                        'cookie',
                        'referer',
                      }.contains(name));
            });
            if (statusCode == 303) {
              if (currentMethod != 'HEAD') currentMethod = 'GET';
              currentBody = null;
              h.removeWhere(
                (key, _) => const {
                  'content-type',
                  'content-length',
                  'transfer-encoding',
                }.contains(key.toLowerCase()),
              );
            }
            currentUri = next;
            continue;
          }

          final rawBytes = Uint8List.fromList(response.data ?? const <int>[]);
          final decoded = decodeBody(rawBytes, flatHeaders, charset);
          return SourceResponse(
            statusCode: statusCode,
            body: decoded,
            bytes: rawBytes,
            headers: flatHeaders,
            finalUrl: currentUri.toString(),
          );
        }
      } on SourceHttpException {
        rethrow;
      } on TimeoutException {
        if (attempt <= retries) {
          _resetConnectionPool();
          continue;
        }
        throw SourceHttpException(
          '请求超时（${(timeout ?? defaultTimeout).inSeconds}s）',
        );
      } on DioException catch (e) {
        if (attempt <= retries) {
          _resetConnectionPool();
          continue;
        }
        throw SourceHttpException(
          _friendlyDioMessage(e, timeout ?? defaultTimeout),
        );
      } on SocketException catch (e) {
        if (attempt <= retries) {
          _resetConnectionPool();
          continue;
        }
        throw SourceHttpException('网络错误：${e.message}');
      } on http.ClientException catch (e) {
        if (attempt <= retries) {
          _resetConnectionPool();
          continue;
        }
        throw SourceHttpException(_friendlyClientMessage(e.message));
      } on HandshakeException catch (e) {
        if (attempt <= retries) {
          _resetConnectionPool();
          continue;
        }
        throw SourceHttpException('安全连接失败：${e.message}');
      }
    }
  }

  static Map<String, String> _normalizeInitialHeaders(
    Map<String, String>? custom,
  ) {
    final out = <String, String>{'user-agent': _defaultUserAgent};
    if (custom != null) {
      for (final entry in custom.entries) {
        out[entry.key.toLowerCase()] = entry.value;
      }
    }
    return out;
  }

  static Map<String, String> _flattenHeaders(Headers headers) {
    final out = <String, String>{};
    headers.forEach((name, values) {
      if (values.isNotEmpty) {
        out[name.toLowerCase()] = values.join(', ');
      }
    });
    return out;
  }

  static bool _isHttpUri(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

  static String _friendlyDioMessage(DioException e, Duration timeout) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.error is TimeoutException) {
      return '请求超时（${timeout.inSeconds}s）';
    }
    final inner = e.error;
    if (inner is HandshakeException) {
      return '安全连接失败：${inner.message}';
    }
    if (inner is SocketException) {
      return '网络错误：${inner.message}';
    }
    if (inner is http.ClientException) {
      return _friendlyClientMessage(inner.message);
    }
    final msg = e.message ?? inner?.toString() ?? '未知网络错误';
    return _friendlyClientMessage(msg);
  }

  /// 把底层 socket 报错翻译成用户看得懂的提示。
  static String _friendlyClientMessage(String raw) {
    if (raw.contains('Connection closed') ||
        raw.contains('Connection reset') ||
        raw.contains('Connection terminated')) {
      return '连接被对方中断（网站不稳定或需要重试）';
    }
    if (raw.contains('timed out')) {
      return '连接超时，请检查网络后重试';
    }
    return '请求失败：$raw';
  }

  void close() {
    if (_ownsDio) {
      _dio.close();
    }
    _legacyClient?.close();
  }
}

/// 包装 [CookieJar]，严格禁止向非 HTTPS 请求发送 `Secure` Cookie
/// （修复上游 `cookie_jar` 在 `loadForRequest` 中对 `Secure` 标记判断过宽的问题）。
class _SecureEnforcingCookieJar implements CookieJar {
  _SecureEnforcingCookieJar(this._inner);

  final CookieJar _inner;

  @override
  bool get ignoreExpires => _inner.ignoreExpires;

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    final cookies = await _inner.loadForRequest(uri);
    if (uri.scheme.toLowerCase() == 'https') return cookies;
    return cookies.where((c) => !c.secure).toList();
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) =>
      _inner.saveFromResponse(uri, cookies);

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) =>
      _inner.delete(uri, withDomainSharedCookie);

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

/// 将外部传入的 `package:http` `http.Client`（如离线 `MockClient`）适配到 `Dio`。
class _PackageHttpAdapter implements HttpClientAdapter {
  _PackageHttpAdapter(this._client);

  final http.Client _client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final req = http.Request(options.method, options.uri);
    req.followRedirects = false;
    req.maxRedirects = 0;

    options.headers.forEach((key, value) {
      if (value == null) return;
      final s = value.toString();
      if (key.toLowerCase() == 'cookie' && s.isEmpty) return;
      // 跳过 Dio 为 GET 自动补的空 content-type
      if (key.toLowerCase() == 'content-type' &&
          options.data == null &&
          !_hasExplicitContentType(options)) {
        return;
      }
      req.headers[key] = s;
    });

    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        req.bodyBytes = chunks;
      }
    } else if (options.data is List<int>) {
      req.bodyBytes = options.data as List<int>;
    } else if (options.data is String) {
      req.bodyBytes = utf8.encode(options.data as String);
    }

    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    final headersMap = <String, List<String>>{};
    resp.headers.forEach((k, v) {
      headersMap[k.toLowerCase()] = [v];
    });
    return ResponseBody.fromBytes(
      resp.bodyBytes,
      resp.statusCode,
      headers: headersMap,
      isRedirect: false,
    );
  }

  bool _hasExplicitContentType(RequestOptions options) => options
      .headers
      .entries
      .any((e) => e.key.toLowerCase() == 'content-type' && e.value != null);

  @override
  void close({bool force = false}) {
    _client.close();
  }
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
