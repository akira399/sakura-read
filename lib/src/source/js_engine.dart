// Legado 3.0 兼容 JavaScript 执行引擎。
//
// - 生产环境优先使用 `quickjs_engine`（内置 QuickJS-NG 0.14.0）；
// - 在无原生 QuickJS 动态库的纯 Dart VM / 无头测试环境中自动降级到轻量容错执行器，
//   保证基础 Legado 表达式、加密/编码与内置 API 仍可无崩溃运行；
// - 注入 Legado 标准宿主对象与变量：
//   `result` / `baseUrl` / `src` / `key` / `page` /
//   `java.*` / `source.*` / `cookie.*` / `console.log`。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/dom.dart' as dom;
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:xml/xml.dart' as xml;

/// 同步 HTTP 请求结果（供 `java.ajax` / `java.get` / `java.post` 桥接）。
class JsHttpResult {
  const JsHttpResult({
    required this.body,
    this.statusCode = 200,
    this.headers = const {},
    this.url = '',
  });

  final String body;
  final int statusCode;
  final Map<String, String> headers;
  final String url;

  Map<String, dynamic> toJson() => {
    'body': body,
    'statusCode': statusCode,
    'headers': headers,
    'url': url,
  };
}

/// 异步 HTTP 请求委托（在 `evalAsync` 中执行真实网络请求并回填缓存）。
typedef JsAsyncHttpCallback = Future<JsHttpResult> Function(
  String method,
  String url, {
  String? body,
  Map<String, String>? headers,
});

/// 同步 HTTP 请求委托（用于离线单元测试或命中缓存的场景）。
typedef JsSyncHttpCallback = JsHttpResult? Function(
  String method,
  String url, {
  String? body,
  Map<String, String>? headers,
});

/// 书源变量仓库（支持 `source.getVariable()` / `source.setVariable(v)`）。
class SourceVariableStore {
  static final SourceVariableStore shared = SourceVariableStore();

  final Map<String, String> _vars = {};

  String getVariable(String sourceKey) => _vars[sourceKey] ?? '';

  void setVariable(String sourceKey, String value) {
    if (value.isEmpty) {
      _vars.remove(sourceKey);
    } else {
      _vars[sourceKey] = value;
    }
  }

  void clear() => _vars.clear();
}

/// Cookie 同步桥接接口（供 `cookie.getCookie(url)` / `cookie.setCookie(url, c)` 调用）。
abstract class JsCookieBridge {
  String getCookie(String url);
  void setCookie(String url, String cookie);
  void removeCookie(String url);
}

/// 默认内存 Cookie 桥接（当未显式传入 `SourceHttpClient` 时使用）。
class MemoryJsCookieBridge implements JsCookieBridge {
  static final MemoryJsCookieBridge shared = MemoryJsCookieBridge();

  final Map<String, String> _byHost = {};

  String _hostKey(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri != null && uri.host.isNotEmpty) return uri.host.toLowerCase();
    return url.trim().toLowerCase();
  }

  @override
  String getCookie(String url) => _byHost[_hostKey(url)] ?? '';

  @override
  void setCookie(String url, String cookie) {
    final k = _hostKey(url);
    if (k.isEmpty) return;
    if (cookie.trim().isEmpty) {
      _byHost.remove(k);
    } else {
      _byHost[k] = cookie.trim();
    }
  }

  @override
  void removeCookie(String url) => _byHost.remove(_hostKey(url));

  void clear() => _byHost.clear();
}

/// 单次 JS 执行上下文。
class JsEvalContext {
  JsEvalContext({
    this.result,
    this.baseUrl = '',
    this.src = '',
    this.key = '',
    this.page = 1,
    this.sourceKey = '',
    this.getStringCallback,
    this.getElementsCallback,
    this.httpSync,
    this.httpAsync,
    SourceVariableStore? variableStore,
    JsCookieBridge? cookieBridge,
    Map<String, String>? ruleVars,
    List<String>? logs,
  }) : variableStore = variableStore ?? SourceVariableStore.shared,
       cookieBridge = cookieBridge ?? MemoryJsCookieBridge.shared,
       ruleVars = ruleVars ?? <String, String>{},
       logs = logs ?? <String>[];

  final dynamic result;
  final String baseUrl;
  final String src;
  final String key;
  final int page;
  final String sourceKey;

  /// `java.getString(rule)` 委托（通常绑定到当前 `AnalyzeRule`）。
  final String Function(String rule)? getStringCallback;

  /// `java.getElements(rule)` 委托（返回元素列表）。
  final List<Object> Function(String rule)? getElementsCallback;

  /// 可选同步 HTTP 回调（优先于缓存与异步回放）。
  final JsSyncHttpCallback? httpSync;

  /// 可选异步 HTTP 回调（供 `evalAsync` 自动预取回放）。
  final JsAsyncHttpCallback? httpAsync;

  final SourceVariableStore variableStore;
  final JsCookieBridge cookieBridge;

  /// `java.put(k, v)` / `java.get(k)` 使用的规则内临时变量。
  final Map<String, String> ruleVars;

  /// 执行过程中通过 `console.log` / `java.log` 收集的日志。
  final List<String> logs;

  final Map<String, JsHttpResult> _httpCache = {};

  String get effectiveSourceKey => sourceKey.isNotEmpty ? sourceKey : baseUrl;

  JsEvalContext copyWithResult(dynamic nextResult) => JsEvalContext(
    result: nextResult,
    baseUrl: baseUrl,
    src: src,
    key: key,
    page: page,
    sourceKey: sourceKey,
    getStringCallback: getStringCallback,
    getElementsCallback: getElementsCallback,
    httpSync: httpSync,
    httpAsync: httpAsync,
    variableStore: variableStore,
    cookieBridge: cookieBridge,
    ruleVars: ruleVars,
    logs: logs,
  ).._httpCache.addAll(_httpCache);
}

/// JS 执行结果。
class LegadoJsResult {
  const LegadoJsResult({
    this.value,
    this.error,
    this.usedNativeQuickJs = false,
    this.logs = const [],
  });

  /// 返回值：可能为 `String`、`num`、`bool`、`List`、`Map` 或 `null`。
  final dynamic value;
  final String? error;
  final bool usedNativeQuickJs;
  final List<String> logs;

  bool get ok => error == null;

  String get asString {
    if (value == null) return '';
    if (value is String) return value as String;
    if (value is List || value is Map) return jsonEncode(value);
    return value.toString();
  }
}

class _PendingHttpRequest implements Exception {
  _PendingHttpRequest({
    required this.cacheKey,
    required this.method,
    required this.url,
    this.body,
    this.headers,
  });

  final String cacheKey;
  final String method;
  final String url;
  final String? body;
  final Map<String, String>? headers;
}

/// Legado 3.0 JS 执行引擎（优先 QuickJS-NG，缺失原生库时平滑降级）。
class LegadoJsEngine {
  LegadoJsEngine._();

  static final LegadoJsEngine shared = LegadoJsEngine._();

  static const String _bridgeChannel = 'sakuraLegadoBridge';
  static const String _needHttpPrefix = '__SAKURA_NEED_HTTP__:';

  JavascriptRuntime? _runtime;
  bool _nativeInitAttempted = false;
  bool _nativeAvailable = false;
  JsEvalContext? _activeCtx;

  /// 当前运行平台是否成功加载了原生 `quickjs_engine` 动态库。
  bool get isNativeQuickJsAvailable {
    _ensureRuntime();
    return _nativeAvailable;
  }

  /// 释放原生 QuickJS 运行时（应用退出或测试清理时调用）。
  void dispose() {
    final rt = _runtime;
    _runtime = null;
    _nativeInitAttempted = false;
    _nativeAvailable = false;
    if (rt != null) {
      try {
        JavascriptRuntime.channelFunctionsRegistered.remove(
          rt.getEngineInstanceId(),
        );
        rt.dispose();
      } catch (_) {
        // 忽略底层销毁异常
      }
    }
  }

  JavascriptRuntime? _ensureRuntime() {
    if (_nativeInitAttempted) return _runtime;
    _nativeInitAttempted = true;
    try {
      final rt = getJavascriptRuntime(xhr: false);
      rt.onMessage(_bridgeChannel, _handleBridgeMessage);
      final bootstrap = rt.evaluate(_kBootstrapJs);
      if (bootstrap.isError) {
        rt.dispose();
        _runtime = null;
        _nativeAvailable = false;
        return null;
      }
      _runtime = rt;
      _nativeAvailable = true;
      return rt;
    } catch (_) {
      // 纯 Dart VM / Windows 无头测试未编译 quickjs_c_bridge_plugin.dll 时平滑降级
      _runtime = null;
      _nativeAvailable = false;
      return null;
    }
  }

  /// 同步求值 JS 脚本（适用于 `AnalyzeRule.getString` 与 URL 模板渲染）。
  LegadoJsResult eval(String script, {JsEvalContext? context}) {
    final code = script.trim();
    final ctx = context ?? JsEvalContext();
    if (code.isEmpty) {
      return LegadoJsResult(
        value: ctx.result,
        usedNativeQuickJs: _nativeAvailable,
        logs: List.unmodifiable(ctx.logs),
      );
    }

    final rt = _ensureRuntime();
    if (rt != null) {
      return _evalWithQuickJs(rt, code, ctx);
    }
    return _evalWithFallback(code, ctx);
  }

  /// 异步求值 JS 脚本：自动支持 `java.ajax` / `java.get` / `java.post` 真实异步请求。
  ///
  /// 原理：若脚本调用的 URL 尚未在缓存中，宿主会捕获待请求描述符、执行异步 HTTP、
  /// 写入缓存后自动重放（最多 6 轮），完全避免在 FFI 回调内阻塞主线程。
  Future<LegadoJsResult> evalAsync(
    String script, {
    JsEvalContext? context,
    int maxHttpRounds = 6,
  }) async {
    final ctx = context ?? JsEvalContext();
    for (var round = 0; round <= maxHttpRounds; round++) {
      try {
        return eval(script, context: ctx);
      } on _PendingHttpRequest catch (pending) {
        if (ctx.httpAsync == null || round >= maxHttpRounds) {
          ctx._httpCache[pending.cacheKey] = const JsHttpResult(
            body: '',
            statusCode: 0,
          );
          continue;
        }
        try {
          final resp = await ctx.httpAsync!(
            pending.method,
            pending.url,
            body: pending.body,
            headers: pending.headers,
          );
          ctx._httpCache[pending.cacheKey] = resp;
        } catch (e) {
          ctx.logs.add('[http error] ${pending.method} ${pending.url}: $e');
          ctx._httpCache[pending.cacheKey] = JsHttpResult(
            body: '',
            statusCode: 0,
            url: pending.url,
          );
        }
      }
    }
    return eval(script, context: ctx);
  }

  // ---------- QuickJS 宿主桥接 ----------

  LegadoJsResult _evalWithQuickJs(
    JavascriptRuntime rt,
    String code,
    JsEvalContext ctx,
  ) {
    final prev = _activeCtx;
    _activeCtx = ctx;
    try {
      final payload = jsonEncode({
        'code': code,
        'result': _serializeForJs(ctx.result),
        'baseUrl': ctx.baseUrl,
        'src': ctx.src,
        'key': ctx.key,
        'page': ctx.page,
        'sourceKey': ctx.effectiveSourceKey,
      });
      final raw = rt.evaluate('__sakuraRun(${jsonEncode(payload)})');
      if (raw.isError) {
        final msg = raw.stringResult;
        final pending = _tryParsePendingHttp(msg);
        if (pending != null) throw pending;
        return LegadoJsResult(
          error: msg,
          usedNativeQuickJs: true,
          logs: List.unmodifiable(ctx.logs),
        );
      }
      final envelope = jsonDecode(raw.stringResult);
      if (envelope is Map) {
        if (envelope['error'] != null) {
          final errStr = envelope['error'].toString();
          final pending = _tryParsePendingHttp(errStr);
          if (pending != null) throw pending;
          return LegadoJsResult(
            error: errStr,
            usedNativeQuickJs: true,
            logs: List.unmodifiable(ctx.logs),
          );
        }
        return LegadoJsResult(
          value: envelope['value'],
          usedNativeQuickJs: true,
          logs: List.unmodifiable(ctx.logs),
        );
      }
      return LegadoJsResult(
        value: raw.rawResult,
        usedNativeQuickJs: true,
        logs: List.unmodifiable(ctx.logs),
      );
    } on _PendingHttpRequest {
      rethrow;
    } catch (e) {
      return LegadoJsResult(
        error: e.toString(),
        usedNativeQuickJs: true,
        logs: List.unmodifiable(ctx.logs),
      );
    } finally {
      _activeCtx = prev;
    }
  }

  String _handleBridgeMessage(dynamic payload) {
    final ctx = _activeCtx;
    if (ctx == null || payload is! Map) {
      return jsonEncode({'ok': false, 'error': 'no active js context'});
    }
    final op = payload['op']?.toString() ?? '';
    final args = payload['args'] is List
        ? payload['args'] as List
        : const <dynamic>[];
    try {
      final value = _dispatchHostOp(ctx, op, args);
      return jsonEncode({'ok': true, 'value': value});
    } on _PendingHttpRequest catch (pending) {
      return jsonEncode({
        'ok': false,
        'pendingHttp': {
          'cacheKey': pending.cacheKey,
          'method': pending.method,
          'url': pending.url,
          'body': pending.body,
          'headers': pending.headers,
        },
      });
    } catch (e) {
      return jsonEncode({'ok': false, 'error': e.toString()});
    }
  }

  dynamic _dispatchHostOp(JsEvalContext ctx, String op, List<dynamic> args) {
    String argStr(int i) =>
        i < args.length && args[i] != null ? args[i].toString() : '';

    switch (op) {
      case 'log':
        final line = args.map((e) => e?.toString() ?? 'undefined').join(' ');
        ctx.logs.add(line);
        return null;
      case 'base64Encode':
        return base64EncodeStr(argStr(0));
      case 'base64Decode':
        return base64DecodeStr(argStr(0));
      case 'md5Encode':
        return md5Encode(argStr(0));
      case 'md5Encode16':
        return md5Encode16(argStr(0));
      case 'hexDecodeToString':
        return hexDecodeToString(argStr(0));
      case 'encodeURI':
        return encodeUriWithCharset(argStr(0), argStr(1));
      case 'getString':
        return ctx.getStringCallback?.call(argStr(0)) ?? '';
      case 'getElements':
        final rawEls = ctx.getElementsCallback?.call(argStr(0)) ?? const [];
        return rawEls.map(_serializeElement).toList();
      case 'put':
        final k = argStr(0);
        final v = argStr(1);
        ctx.ruleVars[k] = v;
        return v;
      case 'getVar':
        return ctx.ruleVars[argStr(0)] ?? '';
      case 'sourceGetVariable':
        return ctx.variableStore.getVariable(ctx.effectiveSourceKey);
      case 'sourceSetVariable':
        ctx.variableStore.setVariable(ctx.effectiveSourceKey, argStr(0));
        return argStr(0);
      case 'cookieGet':
        final target = argStr(0).isEmpty ? ctx.baseUrl : argStr(0);
        return ctx.cookieBridge.getCookie(target);
      case 'cookieSet':
        final target = argStr(0).isEmpty ? ctx.baseUrl : argStr(0);
        ctx.cookieBridge.setCookie(target, argStr(1));
        return null;
      case 'cookieRemove':
        final target = argStr(0).isEmpty ? ctx.baseUrl : argStr(0);
        ctx.cookieBridge.removeCookie(target);
        return null;
      case 'ajax':
        final res = _resolveHttp(ctx, 'GET', argStr(0));
        return res.body;
      case 'httpGet':
        final url = argStr(0);
        final headers = _parseHeadersArg(args.length > 1 ? args[1] : null);
        // Legado 兼容：单参数且不是 URL 时，`java.get("key")` 读临时变量
        if (args.length == 1 &&
            !url.startsWith('http://') &&
            !url.startsWith('https://') &&
            !url.startsWith('/')) {
          return ctx.ruleVars[url] ?? '';
        }
        return _resolveHttp(ctx, 'GET', url, headers: headers).toJson();
      case 'httpPost':
        final url = argStr(0);
        final body = argStr(1);
        final headers = _parseHeadersArg(args.length > 2 ? args[2] : null);
        return _resolveHttp(
          ctx,
          'POST',
          url,
          body: body,
          headers: headers,
        ).toJson();
      default:
        throw UnsupportedError('Unknown host op: $op');
    }
  }

  JsHttpResult _resolveHttp(
    JsEvalContext ctx,
    String method,
    String rawUrl, {
    String? body,
    Map<String, String>? headers,
  }) {
    final url = _resolveRelativeUrl(rawUrl, ctx.baseUrl);
    final cacheKey = jsonEncode({
      'm': method.toUpperCase(),
      'u': url,
      'b': body ?? '',
      'h': headers ?? const <String, String>{},
    });
    final cached = ctx._httpCache[cacheKey];
    if (cached != null) return cached;

    if (ctx.httpSync != null) {
      final syncRes = ctx.httpSync!(method, url, body: body, headers: headers);
      if (syncRes != null) {
        ctx._httpCache[cacheKey] = syncRes;
        return syncRes;
      }
    }

    if (ctx.httpAsync != null) {
      throw _PendingHttpRequest(
        cacheKey: cacheKey,
        method: method,
        url: url,
        body: body,
        headers: headers,
      );
    }

    return JsHttpResult(body: '', statusCode: 0, url: url);
  }

  static _PendingHttpRequest? _tryParsePendingHttp(String message) {
    final idx = message.indexOf(_needHttpPrefix);
    if (idx < 0) return null;
    final jsonPart = message.substring(idx + _needHttpPrefix.length).trim();
    try {
      final decoded = jsonDecode(jsonPart);
      if (decoded is Map) {
        return _PendingHttpRequest(
          cacheKey: decoded['cacheKey']?.toString() ?? '',
          method: decoded['method']?.toString() ?? 'GET',
          url: decoded['url']?.toString() ?? '',
          body: decoded['body']?.toString(),
          headers: _parseHeadersArg(decoded['headers']),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, String>? _parseHeadersArg(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    return null;
  }

  static dynamic _serializeForJs(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is dom.Element) return value.outerHtml;
    if (value is xml.XmlElement) return value.toXmlString();
    if (value is List) return value.map(_serializeForJs).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _serializeForJs(v)));
    }
    return value.toString();
  }

  static Map<String, dynamic> _serializeElement(Object el) {
    if (el is dom.Element) {
      return {
        'html': el.outerHtml,
        'text': el.text.trim(),
        'attrs': el.attributes.map((k, v) => MapEntry(k.toString(), v)),
      };
    }
    if (el is xml.XmlElement) {
      return {
        'html': el.toXmlString(),
        'text': el.innerText.trim(),
        'attrs': {for (final a in el.attributes) a.name.local: a.value},
      };
    }
    if (el is Map) {
      return {'html': jsonEncode(el), 'text': jsonEncode(el), 'data': el};
    }
    final s = el.toString();
    return {'html': s, 'text': s};
  }

  static String _resolveRelativeUrl(String url, String baseUrl) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (baseUrl.isEmpty) return u;
    try {
      return Uri.parse(baseUrl).resolve(u).toString();
    } catch (_) {
      return u;
    }
  }

  // ---------- 规则中的 JS 语法识别与拆分 ----------

  /// 判断规则是否包含 JS（`@js:` / `<js>...</js>` / 非纯变量的 `{{...}}`）。
  static bool containsJs(String rule) {
    final t = rule.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    if (lower.startsWith('@js:') ||
        lower.contains('\n@js:') ||
        lower.contains('\r@js:') ||
        lower.contains('<js>')) {
      return true;
    }
    return false;
  }

  /// 将包含 `@js:` 或 `<js>...</js>` 的规则拆分为有序段（普通规则段与 JS 脚本段）。
  static List<RuleJsSegment> splitRuleSegments(String rule) {
    final segments = <RuleJsSegment>[];
    var remaining = rule;

    // 1. 先处理 `<js>...</js>` 块（可能多个，前后可能有普通规则）
    final jsTagRe = RegExp(r'<js>([\s\S]*?)</js>', caseSensitive: false);
    var cursor = 0;
    for (final m in jsTagRe.allMatches(remaining)) {
      final before = remaining.substring(cursor, m.start).trim();
      if (before.isNotEmpty) {
        segments.addAll(_splitAtJsSuffix(before));
      }
      final jsCode = m.group(1)?.trim() ?? '';
      if (jsCode.isNotEmpty) {
        segments.add(RuleJsSegment(jsCode, isJs: true));
      }
      cursor = m.end;
    }

    final tail = remaining.substring(cursor).trim();
    if (tail.isNotEmpty) {
      segments.addAll(_splitAtJsSuffix(tail));
    }
    return segments;
  }

  static List<RuleJsSegment> _splitAtJsSuffix(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final lower = t.toLowerCase();
    if (lower.startsWith('@js:')) {
      final code = t.substring(4).trim();
      return code.isEmpty ? const [] : [RuleJsSegment(code, isJs: true)];
    }
    final atJsMatch = RegExp(
      r'(?:\r?\n)\s*@js:',
      caseSensitive: false,
    ).firstMatch(t);
    if (atJsMatch != null) {
      final head = t.substring(0, atJsMatch.start).trim();
      final code = t.substring(atJsMatch.end).trim();
      return [
        if (head.isNotEmpty) RuleJsSegment(head, isJs: false),
        if (code.isNotEmpty) RuleJsSegment(code, isJs: true),
      ];
    }
    return [RuleJsSegment(t, isJs: false)];
  }

  // ---------- 编码 / 哈希公共工具（QuickJS 与降级引擎共享） ----------

  static String base64EncodeStr(String input) =>
      base64Encode(utf8.encode(input));

  static String base64DecodeStr(String input) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return '';
    final normalized = base64.normalize(cleaned);
    final bytes = base64Decode(normalized);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 标准 32 位小写十六进制 MD5（RFC 1321 纯 Dart 实现）。
  static String md5Encode(String input) => _md5Hex(utf8.encode(input));

  /// Legado 兼容 16 位 MD5（取 32 位 MD5 的 `[8..24)` 中间 16 位）。
  static String md5Encode16(String input) => md5Encode(input).substring(8, 24);

  /// 十六进制字符串解码为 UTF-8 文本（兼容空格与 `0x` 前缀）。
  static String hexDecodeToString(String hex) {
    final cleaned = hex
        .trim()
        .replaceAll(RegExp(r'0x', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s:-]+'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) return '';
    final bytes = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      final byte = int.tryParse(cleaned.substring(i, i + 2), radix: 16);
      if (byte == null) return '';
      bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String encodeUriWithCharset(String input, String charset) {
    final cs = charset.trim().toLowerCase();
    if (cs.contains('gb')) {
      final bytes = gbk.encode(input);
      final buf = StringBuffer();
      for (final b in bytes) {
        final isUnreserved =
            (b >= 0x41 && b <= 0x5A) ||
            (b >= 0x61 && b <= 0x7A) ||
            (b >= 0x30 && b <= 0x39) ||
            b == 0x2D ||
            b == 0x5F ||
            b == 0x2E ||
            b == 0x7E;
        if (isUnreserved) {
          buf.writeCharCode(b);
        } else {
          buf.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
      return buf.toString();
    }
    return Uri.encodeComponent(input);
  }

  // ---------- 无原生 QuickJS DLL 时的优雅降级执行器（用于纯 Dart VM 测试） ----------

  LegadoJsResult _evalWithFallback(String code, JsEvalContext ctx) {
    final env = <String, dynamic>{
      'result': ctx.result,
      'baseUrl': ctx.baseUrl,
      'src': ctx.src,
      'key': ctx.key,
      'page': ctx.page,
    };
    try {
      dynamic lastValue;
      final statements = _splitStatements(code);
      for (final rawStmt in statements) {
        var stmt = rawStmt.trim();
        if (stmt.isEmpty || stmt.startsWith('//')) continue;
        if (stmt.startsWith('return ')) {
          lastValue = _evalFallbackExpr(stmt.substring(7).trim(), env, ctx);
          return LegadoJsResult(
            value: lastValue,
            usedNativeQuickJs: false,
            logs: List.unmodifiable(ctx.logs),
          );
        }
        final assignMatch = RegExp(
          r'^(?:(?:var|let|const)\s+)?([A-Za-z_$][\w$]*)\s*=\s*([\s\S]+)$',
        ).firstMatch(stmt);
        if (assignMatch != null && !stmt.contains('==')) {
          final varName = assignMatch.group(1)!;
          final rhs = assignMatch.group(2)!.trim();
          final val = _evalFallbackExpr(rhs, env, ctx);
          env[varName] = val;
          lastValue = val;
          continue;
        }
        lastValue = _evalFallbackExpr(stmt, env, ctx);
      }
      final finalValue = lastValue ?? env['result'];
      return LegadoJsResult(
        value: finalValue,
        usedNativeQuickJs: false,
        logs: List.unmodifiable(ctx.logs),
      );
    } on _PendingHttpRequest {
      rethrow;
    } catch (e) {
      return LegadoJsResult(
        error: 'Fallback JS error: $e',
        usedNativeQuickJs: false,
        logs: List.unmodifiable(ctx.logs),
      );
    }
  }

  List<String> _splitStatements(String code) {
    final out = <String>[];
    final buf = StringBuffer();
    var quote = '';
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var escaped = false;

    for (var i = 0; i < code.length; i++) {
      final ch = code[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
        continue;
      }
      if (quote.isNotEmpty) {
        buf.write(ch);
        if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == '"' || ch == "'" || ch == '`') {
        quote = ch;
        buf.write(ch);
        continue;
      }
      if (ch == '(') paren++;
      if (ch == ')') paren--;
      if (ch == '[') bracket++;
      if (ch == ']') bracket--;
      if (ch == '{') brace++;
      if (ch == '}') brace--;

      if ((ch == ';' || ch == '\n') &&
          paren == 0 &&
          bracket == 0 &&
          brace == 0) {
        final s = buf.toString().trim();
        if (s.isNotEmpty) out.add(s);
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) out.add(tail);
    return out;
  }

  dynamic _evalFallbackExpr(
    String raw,
    Map<String, dynamic> env,
    JsEvalContext ctx,
  ) {
    final expr = _stripOuterParens(raw.trim());
    if (expr.isEmpty) return null;

    // 1. 字符串 / 数字 / 布尔 / null 字面量
    if (_isQuotedLiteral(expr)) {
      return _unquoteLiteral(expr);
    }
    if (expr == 'null' || expr == 'undefined') return null;
    if (expr == 'true') return true;
    if (expr == 'false') return false;
    final numVal = num.tryParse(expr);
    if (numVal != null) return numVal;

    // JSON 对象或数组字面量
    if ((expr.startsWith('{') && expr.endsWith('}')) ||
        (expr.startsWith('[') && expr.endsWith(']'))) {
      try {
        return jsonDecode(expr);
      } catch (_) {}
    }

    // 2. 二元 `+`（字符串拼接 / 数值加法）
    final addParts = _splitTopLevel(expr, '+');
    if (addParts.length > 1) {
      final vals = addParts.map((p) => _evalFallbackExpr(p, env, ctx)).toList();
      if (vals.every((v) => v is num)) {
        return vals.cast<num>().reduce((a, b) => a + b);
      }
      return vals.map((v) => v?.toString() ?? '').join();
    }

    // 数值 `*` / `-`
    final mulParts = _splitTopLevel(expr, '*');
    if (mulParts.length > 1) {
      final vals = mulParts.map((p) => _evalFallbackExpr(p, env, ctx)).toList();
      if (vals.every((v) => v is num)) {
        return vals.cast<num>().reduce((a, b) => a * b);
      }
    }

    // 3. 链式方法调用：target.method(args) 或属性访问 target.prop
    final chain = _splitLastMemberAccess(expr);
    if (chain != null) {
      final (targetExpr, memberExpr) = chain;
      final callMatch = RegExp(r'^([A-Za-z_$][\w$]*)\(([\s\S]*)\)$')
          .firstMatch(memberExpr);
      if (callMatch != null) {
        final method = callMatch.group(1)!;
        final rawArgs = _splitTopLevel(callMatch.group(2)!, ',');
        final evalArgs = rawArgs
            .where((a) => a.trim().isNotEmpty)
            .map((a) => _evalFallbackExpr(a, env, ctx))
            .toList();

        // 宿主对象调用：java.* / source.* / cookie.* / console.* / JSON.*
        if (targetExpr == 'java') {
          return _fallbackJavaCall(ctx, method, evalArgs);
        }
        if (targetExpr == 'source') {
          return _fallbackSourceCall(ctx, method, evalArgs);
        }
        if (targetExpr == 'cookie') {
          return _fallbackCookieCall(ctx, method, evalArgs);
        }
        if (targetExpr == 'console') {
          if (method == 'log' || method == 'warn' || method == 'error') {
            ctx.logs.add(evalArgs.map((e) => e?.toString() ?? '').join(' '));
          }
          return null;
        }
        if (targetExpr == 'JSON') {
          if (method == 'parse' && evalArgs.isNotEmpty) {
            return jsonDecode(evalArgs.first.toString());
          }
          if (method == 'stringify' && evalArgs.isNotEmpty) {
            return jsonEncode(evalArgs.first);
          }
        }

        final target = _evalFallbackExpr(targetExpr, env, ctx);
        return _invokeMemberMethod(target, method, evalArgs);
      } else {
        final target = _evalFallbackExpr(targetExpr, env, ctx);
        return _readProperty(target, memberExpr);
      }
    }

    // 4. 全局函数：encodeURIComponent / decodeURIComponent / String / Number
    final fnMatch = RegExp(r'^([A-Za-z_$][\w$]*)\(([\s\S]*)\)$')
        .firstMatch(expr);
    if (fnMatch != null) {
      final name = fnMatch.group(1)!;
      final args = _splitTopLevel(fnMatch.group(2)!, ',')
          .where((a) => a.trim().isNotEmpty)
          .map((a) => _evalFallbackExpr(a, env, ctx))
          .toList();
      if (name == 'encodeURIComponent' && args.isNotEmpty) {
        return Uri.encodeComponent(args.first.toString());
      }
      if (name == 'decodeURIComponent' && args.isNotEmpty) {
        return Uri.decodeComponent(args.first.toString());
      }
      if (name == 'String' && args.isNotEmpty) {
        return args.first?.toString() ?? '';
      }
      if (name == 'Number' && args.isNotEmpty) {
        return num.tryParse(args.first.toString()) ?? 0;
      }
    }

    // 5. 数组/对象下标访问：a[0] / a['k']
    final idxMatch = RegExp(r'^([\s\S]+)\[([^\[\]]+)\]$').firstMatch(expr);
    if (idxMatch != null) {
      final target = _evalFallbackExpr(idxMatch.group(1)!.trim(), env, ctx);
      final keyVal = _evalFallbackExpr(idxMatch.group(2)!.trim(), env, ctx);
      if (target is List && keyVal is num) {
        final i = keyVal.toInt();
        return (i >= 0 && i < target.length) ? target[i] : null;
      }
      if (target is Map && keyVal != null) {
        return target[keyVal.toString()];
      }
    }

    // 6. 变量读取
    if (env.containsKey(expr)) {
      return env[expr];
    }

    throw StateError('Unsupported expression in fallback JS runtime: $expr');
  }

  dynamic _fallbackJavaCall(
    JsEvalContext ctx,
    String method,
    List<dynamic> args,
  ) {
    switch (method) {
      case 'ajax':
        return _dispatchHostOp(ctx, 'ajax', args);
      case 'get':
        final raw = _dispatchHostOp(ctx, 'httpGet', args);
        if (raw is Map) {
          return _FallbackHttpResponse(raw.cast<String, dynamic>());
        }
        return raw;
      case 'post':
        final raw = _dispatchHostOp(ctx, 'httpPost', args);
        if (raw is Map) {
          return _FallbackHttpResponse(raw.cast<String, dynamic>());
        }
        return raw;
      case 'base64Encode':
        return _dispatchHostOp(ctx, 'base64Encode', args);
      case 'base64Decode':
        return _dispatchHostOp(ctx, 'base64Decode', args);
      case 'md5Encode':
        return _dispatchHostOp(ctx, 'md5Encode', args);
      case 'md5Encode16':
        return _dispatchHostOp(ctx, 'md5Encode16', args);
      case 'hexDecodeToString':
        return _dispatchHostOp(ctx, 'hexDecodeToString', args);
      case 'getString':
        return _dispatchHostOp(ctx, 'getString', args);
      case 'getElements':
        return _dispatchHostOp(ctx, 'getElements', args);
      case 'put':
        return _dispatchHostOp(ctx, 'put', args);
      case 'encodeURI':
        return _dispatchHostOp(ctx, 'encodeURI', args);
      case 'log':
        return _dispatchHostOp(ctx, 'log', args);
      default:
        throw UnsupportedError('Unknown java.$method');
    }
  }

  dynamic _fallbackSourceCall(
    JsEvalContext ctx,
    String method,
    List<dynamic> args,
  ) {
    switch (method) {
      case 'getVariable':
        return _dispatchHostOp(ctx, 'sourceGetVariable', args);
      case 'setVariable':
        return _dispatchHostOp(ctx, 'sourceSetVariable', args);
      case 'getKey':
        return ctx.effectiveSourceKey;
      default:
        throw UnsupportedError('Unknown source.$method');
    }
  }

  dynamic _fallbackCookieCall(
    JsEvalContext ctx,
    String method,
    List<dynamic> args,
  ) {
    switch (method) {
      case 'getCookie':
        return _dispatchHostOp(ctx, 'cookieGet', args);
      case 'setCookie':
        return _dispatchHostOp(ctx, 'cookieSet', args);
      case 'removeCookie':
        return _dispatchHostOp(ctx, 'cookieRemove', args);
      default:
        throw UnsupportedError('Unknown cookie.$method');
    }
  }

  dynamic _invokeMemberMethod(
    dynamic target,
    String method,
    List<dynamic> args,
  ) {
    if (target is _FallbackHttpResponse) {
      switch (method) {
        case 'body':
        case 'text':
        case 'toString':
          return target.body;
        case 'statusCode':
        case 'code':
          return target.statusCode;
        case 'headers':
          return target.headers;
      }
    }
    if (target is List) {
      switch (method) {
        case 'join':
          final sep = args.isEmpty ? ',' : args.first.toString();
          return target.map((e) => e?.toString() ?? '').join(sep);
        case 'size':
          return target.length;
      }
    }
    if (target is Map) {
      if (method == 'text') return target['text'] ?? '';
      if (method == 'html') return target['html'] ?? '';
    }
    final s = target?.toString() ?? '';
    switch (method) {
      case 'trim':
        return s.trim();
      case 'toUpperCase':
        return s.toUpperCase();
      case 'toLowerCase':
        return s.toLowerCase();
      case 'replace':
      case 'replaceAll':
        if (args.length < 2) return s;
        final pat = args[0].toString();
        final rep = args[1].toString();
        if (pat.startsWith('/') && pat.lastIndexOf('/') > 0) {
          final lastSlash = pat.lastIndexOf('/');
          final body = pat.substring(1, lastSlash);
          final flags = pat.substring(lastSlash + 1);
          final re = RegExp(
            body,
            caseSensitive: !flags.contains('i'),
            multiLine: flags.contains('m'),
          );
          return flags.contains('g') || method == 'replaceAll'
              ? s.replaceAll(re, rep)
              : s.replaceFirst(re, rep);
        }
        return method == 'replaceAll'
            ? s.replaceAll(pat, rep)
            : s.replaceFirst(pat, rep);
      case 'split':
        final sep = args.isEmpty ? '' : args.first.toString();
        return s.split(sep);
      case 'substring':
      case 'slice':
        if (args.isEmpty) return s;
        var start = (args[0] as num).toInt();
        var end = args.length > 1 ? (args[1] as num).toInt() : s.length;
        if (start < 0) start = (s.length + start).clamp(0, s.length);
        if (end < 0) end = (s.length + end).clamp(0, s.length);
        start = start.clamp(0, s.length);
        end = end.clamp(start, s.length);
        return s.substring(start, end);
      case 'toString':
        return s;
      default:
        throw UnsupportedError('Unsupported method .$method in fallback');
    }
  }

  dynamic _readProperty(dynamic target, String prop) {
    if (target is _FallbackHttpResponse) {
      if (prop == 'body') return target.body;
      if (prop == 'statusCode') return target.statusCode;
      if (prop == 'headers') return target.headers;
    }
    if (target is List && prop == 'length') return target.length;
    if (target is String && prop == 'length') return target.length;
    if (target is Map) return target[prop];
    return null;
  }

  static String _stripOuterParens(String s) {
    var out = s;
    while (out.startsWith('(') && out.endsWith(')')) {
      var depth = 0;
      var wrapsAll = true;
      var quote = '';
      for (var i = 0; i < out.length; i++) {
        final ch = out[i];
        if (quote.isNotEmpty) {
          if (ch == quote && (i == 0 || out[i - 1] != '\\')) quote = '';
          continue;
        }
        if (ch == '"' || ch == "'" || ch == '`') {
          quote = ch;
          continue;
        }
        if (ch == '(') depth++;
        if (ch == ')') {
          depth--;
          if (depth == 0 && i < out.length - 1) {
            wrapsAll = false;
            break;
          }
        }
      }
      if (!wrapsAll) break;
      out = out.substring(1, out.length - 1).trim();
    }
    return out;
  }

  static bool _isQuotedLiteral(String s) {
    if (s.length < 2) return false;
    final first = s[0];
    final last = s[s.length - 1];
    if ((first != '"' && first != "'" && first != '`') || first != last) {
      return false;
    }
    for (var i = 1; i < s.length - 1; i++) {
      if (s[i] == '\\') {
        i++;
        continue;
      }
      if (s[i] == first) return false;
    }
    return true;
  }

  static String _unquoteLiteral(String s) {
    final inner = s.substring(1, s.length - 1);
    return inner
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', r'\');
  }

  static List<String> _splitTopLevel(String input, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var quote = '';
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
        continue;
      }
      if (quote.isNotEmpty) {
        buf.write(ch);
        if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == '"' || ch == "'" || ch == '`') {
        quote = ch;
        buf.write(ch);
        continue;
      }
      if (ch == '(') paren++;
      if (ch == ')') paren--;
      if (ch == '[') bracket++;
      if (ch == ']') bracket--;
      if (ch == '{') brace++;
      if (ch == '}') brace--;

      if (ch == sep && paren == 0 && bracket == 0 && brace == 0) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString().trim());
    return out;
  }

  static (String, String)? _splitLastMemberAccess(String expr) {
    var quote = '';
    var paren = 0;
    var bracket = 0;
    var brace = 0;
    var lastDot = -1;
    var escaped = false;

    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quote.isNotEmpty) {
        if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == '"' || ch == "'" || ch == '`') {
        quote = ch;
        continue;
      }
      if (ch == '(') paren++;
      if (ch == ')') paren--;
      if (ch == '[') bracket++;
      if (ch == ']') bracket--;
      if (ch == '{') brace++;
      if (ch == '}') brace--;

      if (ch == '.' && paren == 0 && bracket == 0 && brace == 0) {
        lastDot = i;
      }
    }
    if (lastDot <= 0 || lastDot >= expr.length - 1) return null;
    return (
      expr.substring(0, lastDot).trim(),
      expr.substring(lastDot + 1).trim(),
    );
  }

  // ---------- QuickJS 引导脚本（注入 Legado 3.0 兼容对象） ----------

  static const String _kBootstrapJs = r'''
(function() {
  function __hostCall(op, args) {
    var raw = sendMessage('sakuraLegadoBridge', JSON.stringify({ op: op, args: args || [] }));
    var parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (parsed && parsed.pendingHttp) {
      throw new Error('__SAKURA_NEED_HTTP__:' + JSON.stringify(parsed.pendingHttp));
    }
    if (parsed && parsed.ok === false) {
      throw new Error(parsed.error || 'host call failed');
    }
    return parsed ? parsed.value : undefined;
  }

  function __wrapHttpResp(raw) {
    if (typeof raw === 'string') return raw;
    var data = raw || { body: '', statusCode: 0, headers: {}, url: '' };
    return {
      body: function() { return data.body || ''; },
      text: function() { return data.body || ''; },
      statusCode: function() { return data.statusCode || 0; },
      code: function() { return data.statusCode || 0; },
      headers: function() { return data.headers || {}; },
      url: function() { return data.url || ''; },
      toString: function() { return data.body || ''; },
      valueOf: function() { return data.body || ''; }
    };
  }

  function __wrapElements(list) {
    var arr = (list || []).map(function(item) {
      return {
        html: function() { return item.html || ''; },
        outerHtml: function() { return item.html || ''; },
        text: function() { return item.text || ''; },
        attr: function(name) { return (item.attrs && item.attrs[name]) || ''; },
        toString: function() { return item.html || item.text || ''; }
      };
    });
    arr.size = function() { return arr.length; };
    return arr;
  }

  globalThis.__sakuraRun = function(payloadJson) {
    var p = JSON.parse(payloadJson);
    var result = p.result;
    var baseUrl = p.baseUrl || '';
    var src = p.src || '';
    var key = p.key || '';
    var page = p.page || 1;

    var java = {
      ajax: function(url) { return __hostCall('ajax', [String(url || '')]); },
      get: function(url, headers) {
        if (arguments.length === 1) {
          return __wrapHttpResp(__hostCall('httpGet', [String(url || '')]));
        }
        return __wrapHttpResp(__hostCall('httpGet', [String(url || ''), headers || {}]));
      },
      post: function(url, body, headers) {
        return __wrapHttpResp(__hostCall('httpPost', [String(url || ''), body == null ? '' : String(body), headers || {}]));
      },
      put: function(k, v) { return __hostCall('put', [String(k || ''), v == null ? '' : String(v)]); },
      base64Encode: function(s) { return __hostCall('base64Encode', [s == null ? '' : String(s)]); },
      base64Decode: function(s) { return __hostCall('base64Decode', [s == null ? '' : String(s)]); },
      md5Encode: function(s) { return __hostCall('md5Encode', [s == null ? '' : String(s)]); },
      md5Encode16: function(s) { return __hostCall('md5Encode16', [s == null ? '' : String(s)]); },
      hexDecodeToString: function(s) { return __hostCall('hexDecodeToString', [s == null ? '' : String(s)]); },
      encodeURI: function(s, enc) { return __hostCall('encodeURI', [s == null ? '' : String(s), enc == null ? 'utf-8' : String(enc)]); },
      getString: function(rule) { return __hostCall('getString', [rule == null ? '' : String(rule)]); },
      getElements: function(rule) { return __wrapElements(__hostCall('getElements', [rule == null ? '' : String(rule)])); },
      log: function() {
        var parts = [];
        for (var i = 0; i < arguments.length; i++) parts.push(arguments[i]);
        __hostCall('log', parts);
      }
    };

    var source = {
      getVariable: function() { return __hostCall('sourceGetVariable', []); },
      setVariable: function(v) { return __hostCall('sourceSetVariable', [v == null ? '' : String(v)]); },
      getKey: function() { return p.sourceKey || baseUrl; }
    };

    var cookie = {
      getCookie: function(url) { return __hostCall('cookieGet', [url == null ? '' : String(url)]); },
      setCookie: function(url, c) { return __hostCall('cookieSet', [url == null ? '' : String(url), c == null ? '' : String(c)]); },
      removeCookie: function(url) { return __hostCall('cookieRemove', [url == null ? '' : String(url)]); }
    };

    var console = {
      log: function() { java.log.apply(java, arguments); },
      warn: function() { java.log.apply(java, arguments); },
      error: function() { java.log.apply(java, arguments); }
    };

    try {
      var out;
      try {
        out = eval(p.code);
      } catch (e) {
        if (e && e.name === 'SyntaxError' && String(e.message || '').indexOf('return') >= 0) {
          var fn = new Function('result', 'baseUrl', 'src', 'key', 'page', 'java', 'source', 'cookie', 'console', p.code);
          out = fn(result, baseUrl, src, key, page, java, source, cookie, console);
        } else {
          throw e;
        }
      }
      if (out === undefined) out = result;
      return JSON.stringify({ value: out });
    } catch (err) {
      return JSON.stringify({ error: String(err && err.message ? err.message : err) });
    }
  };
})();
''';
}

/// 拆解后的规则段（普通规则或 JS 脚本）。
class RuleJsSegment {
  const RuleJsSegment(this.content, {required this.isJs});

  final String content;
  final bool isJs;
}

class _FallbackHttpResponse {
  _FallbackHttpResponse(this._data);

  final Map<String, dynamic> _data;

  String get body => _data['body']?.toString() ?? '';
  int get statusCode => (_data['statusCode'] as num?)?.toInt() ?? 0;
  Map<String, String> get headers => (_data['headers'] is Map)
      ? (_data['headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        )
      : const {};

  @override
  String toString() => body;
}

// ---------- RFC 1321 纯 Dart MD5 ----------

const List<int> _md5S = [
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
];

const List<int> _md5K = [
  0xd76aa478,
  0xe8c7b756,
  0x242070db,
  0xc1bdceee,
  0xf57c0faf,
  0x4787c62a,
  0xa8304613,
  0xfd469501,
  0x698098d8,
  0x8b44f7af,
  0xffff5bb1,
  0x895cd7be,
  0x6b901122,
  0xfd987193,
  0xa679438e,
  0x49b40821,
  0xf61e2562,
  0xc040b340,
  0x265e5a51,
  0xe9b6c7aa,
  0xd62f105d,
  0x02441453,
  0xd8a1e681,
  0xe7d3fbc8,
  0x21e1cde6,
  0xc33707d6,
  0xf4d50d87,
  0x455a14ed,
  0xa9e3e905,
  0xfcefa3f8,
  0x676f02d9,
  0x8d2a4c8a,
  0xfffa3942,
  0x8771f681,
  0x6d9d6122,
  0xfde5380c,
  0xa4beea44,
  0x4bdecfa9,
  0xf6bb4b60,
  0xbebfbc70,
  0x289b7ec6,
  0xeaa127fa,
  0xd4ef3085,
  0x04881d05,
  0xd9d4d039,
  0xe6db99e5,
  0x1fa27cf8,
  0xc4ac5665,
  0xf4292244,
  0x432aff97,
  0xab9423a7,
  0xfc93a039,
  0x655b59c3,
  0x8f0ccc92,
  0xffeff47d,
  0x85845dd1,
  0x6fa87e4f,
  0xfe2ce6e0,
  0xa3014314,
  0x4e0811a1,
  0xf7537e82,
  0xbd3af235,
  0x2ad7d2bb,
  0xeb86d391,
];

String _md5Hex(List<int> input) {
  final bitLen = input.length * 8;
  final padLen = ((56 - (input.length + 1) % 64) + 64) % 64;
  final totalLen = input.length + 1 + padLen + 8;
  final bytes = Uint8List(totalLen);
  bytes.setRange(0, input.length, input);
  bytes[input.length] = 0x80;
  final bd = ByteData.view(bytes.buffer);
  bd.setUint32(totalLen - 8, bitLen & 0xFFFFFFFF, Endian.little);
  bd.setUint32(
    totalLen - 4,
    (bitLen ~/ 0x100000000) & 0xFFFFFFFF,
    Endian.little,
  );

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  final m = Uint32List(16);
  for (var offset = 0; offset < totalLen; offset += 64) {
    for (var j = 0; j < 16; j++) {
      m[j] = bd.getUint32(offset + j * 4, Endian.little);
    }
    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;

    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d));
        g = (7 * i) % 16;
      }
      f = (f + a + _md5K[i] + m[g]) & 0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      final shift = _md5S[i];
      final rot = ((f << shift) | (f >>> (32 - shift))) & 0xFFFFFFFF;
      b = (b + rot) & 0xFFFFFFFF;
    }

    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final out = Uint8List(16);
  final outBd = ByteData.view(out.buffer);
  outBd.setUint32(0, a0, Endian.little);
  outBd.setUint32(4, b0, Endian.little);
  outBd.setUint32(8, c0, Endian.little);
  outBd.setUint32(12, d0, Endian.little);

  final sb = StringBuffer();
  for (final byte in out) {
    sb.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
