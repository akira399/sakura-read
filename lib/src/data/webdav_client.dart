import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// WebDAV 操作失败时抛这个：message 已经翻成中文人话，页面直接显示。
class WebdavException implements Exception {
  const WebdavException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 云端目录里的一个条目（[WebdavClient.list] 的返回值）。
class WebdavEntry {
  const WebdavEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final int size;

  /// 服务器返回的修改时间（没给 / 解析不出来时为 null）。
  final DateTime? modified;
}

/// 极简 WebDAV 客户端：只做备份需要的 MKCOL / PUT / GET / PROPFIND。
///
/// 坚果云、Nextcloud、群晖、Alist 这些常见的 WebDAV 都能用；
/// 所有错误统一成 [WebdavException]，页面不用再区分 Socket / 状态码。
class WebdavClient {
  WebdavClient({
    required String baseUrl,
    required this.user,
    required this.pass,
    http.Client? client,
  }) : _baseUrl = _normalizeBase(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String _baseUrl;
  final String user;
  final String pass;
  final http.Client _client;

  /// 外部传进来的 client 由外部关，自己 new 的才自己关。
  final bool _ownsClient;

  static const Duration _timeout = Duration(seconds: 25);

  /// PROPFIND 只要目录本身的信息（测试连接用）。
  static const String _propfindDepth0 =
      '<?xml version="1.0" encoding="utf-8" ?>'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';

  /// PROPFIND Depth:1，列目录用。
  static const String _propfindDepth1 =
      '<?xml version="1.0" encoding="utf-8" ?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  Map<String, String> get _authHeaders => <String, String>{
    'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
  };

  /// 逐段 MKCOL 建目录；405 / 409 当作「已经存在」（各家的实现不太一样）。
  Future<void> ensureDir(String path) async {
    final segments = path.split('/').where((s) => s.trim().isNotEmpty).toList();
    for (var i = 0; i < segments.length; i++) {
      final sub = segments.take(i + 1).join('/');
      final resp = await _send('MKCOL', _uri('$sub/'));
      final code = resp.statusCode;
      if (code == 200 || code == 201 || code == 204) continue;
      if (code == 405 || code == 409) continue;
      throw WebdavException(_explain(code, '创建云端目录「$sub」'));
    }
  }

  /// PUT 上传（[remotePath] 相对 baseUrl，例如 `sakura-read/x.zip`）。
  Future<void> upload(String remotePath, List<int> bytes) async {
    final resp = await _send(
      'PUT',
      _uri(remotePath),
      headers: const <String, String>{
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );
    final code = resp.statusCode;
    if (code == 200 || code == 201 || code == 204) return;
    throw WebdavException(_explain(code, '上传'));
  }

  /// GET 下载。
  Future<List<int>> download(String remotePath) async {
    final resp = await _send('GET', _uri(remotePath));
    if (resp.statusCode == 200 || resp.statusCode == 206) {
      return resp.bodyBytes;
    }
    throw WebdavException(_explain(resp.statusCode, '下载'));
  }

  /// 列目录（Depth:1，不含目录自己）。
  Future<List<WebdavEntry>> list(String path) async {
    final resp = await _send(
      'PROPFIND',
      _uri(path),
      headers: const <String, String>{
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(_propfindDepth1),
    );
    if (resp.statusCode != 207 && resp.statusCode != 200) {
      throw WebdavException(_explain(resp.statusCode, '读取云端目录'));
    }
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    return _parseEntries(body, path);
  }

  /// 测试地址 / 账号能不能用：PROPFIND Depth:0，207/200 算成功。
  ///
  /// 401/403 直接抛中文错误（「地址不对或密码错误」），其它非成功状态码
  /// 返回 false，让页面提示「连上了但不让访问」。
  Future<bool> testConnection() async {
    final resp = await _send(
      'PROPFIND',
      _uri(''),
      headers: const <String, String>{
        'Depth': '0',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(_propfindDepth0),
    );
    final code = resp.statusCode;
    if (code == 207 || code == 200) return true;
    if (code == 401 || code == 403) {
      throw WebdavException(_explain(code, '测试连接'));
    }
    return false;
  }

  /// 关掉内部创建的 http client（页面每次操作 new 一个，用完就关）。
  void close() {
    if (_ownsClient) _client.close();
  }

  /// 发请求：统一加 Basic Auth、统一转中文超时 / 网络错误。
  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final request = http.Request(method, url)..headers.addAll(_authHeaders);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const WebdavException('连接超时了，检查一下网络和服务器地址');
    } on SocketException {
      throw const WebdavException('连不上服务器，检查一下地址和网络');
    } on HandshakeException {
      throw const WebdavException('HTTPS 证书没通过，检查服务器证书是否有效');
    } on http.ClientException catch (e) {
      throw WebdavException('网络出问题了：${e.message}');
    }
  }

  /// 把相对路径拼到 baseUrl 后面。
  ///
  /// 用 Uri.pathSegments 拼而不是字符串相加：中文目录名会自动百分号编码，
  /// 也不会出现 `//` 或漏斜杠。
  Uri _uri(String path) {
    if (_baseUrl.isEmpty) {
      throw const WebdavException('先填一下 WebDAV 地址吧');
    }
    final Uri base;
    try {
      base = Uri.parse(_baseUrl);
    } catch (_) {
      throw WebdavException('WebDAV 地址看起来不太对：$_baseUrl');
    }
    if (!base.hasScheme || base.host.isEmpty) {
      throw WebdavException('WebDAV 地址要带 http:// 或 https:// 哦：$_baseUrl');
    }
    final trimmed = path.trim();
    final wantsDir = trimmed.endsWith('/');
    final extra = trimmed
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
    final segments = <String>[
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...extra,
      // 目录要保留结尾斜杠，否则部分服务器会 301 / 404。
      if (wantsDir && extra.isNotEmpty) '',
    ];
    return base.replace(pathSegments: segments, query: null, fragment: null);
  }

  List<WebdavEntry> _parseEntries(String xmlBody, String requestedPath) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } catch (_) {
      throw const WebdavException('云端返回的目录信息看不懂（不是标准 XML）');
    }
    final selfName = _lastSegment(requestedPath);
    final entries = <WebdavEntry>[];
    for (final node in doc.descendants) {
      if (node is! XmlElement || node.name.local != 'response') continue;
      final hrefEl = _firstDescendant(node, 'href');
      if (hrefEl == null) continue;
      final rawHref = hrefEl.innerText.trim();
      final name = _hrefName(rawHref);
      // Depth:1 会把目录自己也列出来，跳过。
      if (name.isEmpty || name == selfName) continue;

      final typeEl = _firstDescendant(node, 'resourcetype');
      final isDir =
          (typeEl != null && _hasDescendant(typeEl, 'collection')) ||
          rawHref.endsWith('/');
      final sizeEl = _firstDescendant(node, 'getcontentlength');
      final size = int.tryParse(sizeEl?.innerText.trim() ?? '') ?? 0;
      final modEl = _firstDescendant(node, 'getlastmodified');
      final rawMod = modEl?.innerText.trim() ?? '';
      DateTime? modified;
      if (rawMod.isNotEmpty) {
        try {
          modified = HttpDate.parse(rawMod);
        } catch (_) {}
      }
      entries.add(
        WebdavEntry(
          name: name,
          isDirectory: isDir,
          size: size,
          modified: modified,
        ),
      );
    }
    return entries;
  }

  /// 状态码 → 中文人话。
  String _explain(int code, String action) {
    switch (code) {
      case 401:
        return '地址不对或密码错误（401）';
      case 403:
        return '服务器不让访问这个目录（403），检查一下账号权限';
      case 404:
        return '云端找不到这个文件或目录（404）';
      case 405:
        return '服务器不支持这个操作（405）';
      case 409:
        return '云端目录不存在（409），先建好目录再试';
      case 423:
        return '云端文件被锁住了（423），稍等一会儿再试';
      case 507:
        return '云端空间不够了（507）';
      default:
        if (code >= 500) return '服务器出错了（HTTP $code），稍后再试';
        return '$action失败（HTTP $code）';
    }
  }
}

/// 去掉末尾斜杠、缺协议时补 https://，让用户可以直接粘贴 `dav.jianguoyun.com/dav`。
String _normalizeBase(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return '';
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// 遍历后代找第一个本地名匹配的元素（忽略命名空间前缀 d:/D:/无前缀）。
XmlElement? _firstDescendant(XmlElement parent, String local) {
  for (final node in parent.descendants) {
    if (node is XmlElement && node.name.local == local) return node;
  }
  return null;
}

bool _hasDescendant(XmlElement parent, String local) {
  for (final node in parent.descendants) {
    if (node is XmlElement && node.name.local == local) return true;
  }
  return false;
}

/// href（可能是完整 URL 也可能是绝对路径）→ 最后一段名字。
String _hrefName(String href) {
  if (href.isEmpty) return '';
  String path;
  try {
    path = Uri.parse(href).path;
  } catch (_) {
    path = href;
    try {
      path = Uri.decodeComponent(path);
    } catch (_) {}
  }
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.last;
}

String _lastSegment(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.last;
}
