// 更新检查服务回归测试。
//
// 覆盖：
//   - 语义版本比较（v 前缀 / 预发布后缀 / 段数不一致）；
//   - release JSON 解析（GitHub API 与 ungh.cc 两种格式）；
//   - 检查链路：首选端点成功 / 首选失败回退次选 / 全部失败；
//   - 下载链路：镜像回退、大小校验（防坏包）、取消清理；
//   - release 说明清洗（markdown → 纯文本）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sakura_read/src/platform/update_service.dart';

/// GitHub API 格式的落盘样例（与线上真实字段一致）。
Map<String, Object?> _githubRelease({
  String tag = 'v1.0.2',
  String name = '樱读 v1.0.2',
  String body = '## 修复\n- 修了状态栏',
  int size = 100,
  String url =
      'https://github.com/akira399/sakura-read/releases/download/v1.0.2/SakuraRead-v1.0.2.apk',
}) {
  return {
    'tag_name': tag,
    'name': name,
    'body': body,
    'published_at': '2026-09-28T00:00:00Z',
    'html_url': 'https://github.com/akira399/sakura-read/releases/tag/$tag',
    'assets': [
      {
        'name': 'SakuraRead-v1.0.2.apk',
        'size': size,
        'browser_download_url': url,
      },
    ],
  };
}

/// ungh.cc 格式的落盘样例。
Map<String, Object?> _unghRelease({String tag = 'v1.0.2', int size = 100}) {
  return {
    'release': {
      'tag': tag,
      'name': '樱读 $tag',
      'markdown': '## 新增\n- 更新检查',
      'publishedAt': '2026-09-28T00:00:00Z',
      'htmlUrl': 'https://github.com/akira399/sakura-read/releases/tag/$tag',
      'assets': [
        {
          'size': size,
          'downloadUrl':
              'https://github.com/akira399/sakura-read/releases/download/$tag/SakuraRead-$tag.apk',
        },
      ],
    },
  };
}

void main() {
  /// JSON 响应（UTF-8 编码——与真实 GitHub 服务器一致）。
  ///
  /// 注意：`http.Response(body, code)` 在无 charset 请求头时按 latin1
  /// 编码 body；含中文的 JSON 用它会直接抛编码错误。这里统一用
  /// `Response.bytes` 明确 UTF-8。
  http.Response ok(Object json) => http.Response.bytes(
    utf8.encode(jsonEncode(json)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  group('语义版本比较', () {
    test('更高的补丁版本算新', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('更高的次版本 / 主版本算新', () {
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.9.9', '2.0.0'), isFalse);
    });

    test('相同时不算新（避免重复提示同一版本）', () {
      expect(isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(isNewerVersion('v1.0.1', '1.0.1'), isFalse);
    });

    test('容忍 v 前缀与预发布后缀', () {
      expect(isNewerVersion('v1.0.2', '1.0.1'), isTrue);
      expect(isNewerVersion('1.0.2-beta.1', '1.0.1'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.1-beta.1'), isFalse);
    });

    test('段数不一致时缺失段按 0 处理', () {
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.1', '1.0'), isTrue);
      expect(isNewerVersion('1', '1.0.1'), isFalse);
    });
  });

  group('release JSON 解析', () {
    test('GitHub API 格式', () {
      final info = parseReleaseJson(_githubRelease());
      expect(info, isNotNull);
      expect(info!.version, '1.0.2');
      expect(info.sizeBytes, 100);
      expect(info.downloadUrl, contains('SakuraRead-v1.0.2.apk'));
      expect(info.pageUrl, contains('/releases/tag/v1.0.2'));
    });

    test('ungh.cc 格式（字段名不同）', () {
      final info = parseReleaseJson(_unghRelease());
      expect(info, isNotNull);
      expect(info!.version, '1.0.2');
      expect(info.sizeBytes, 100);
      expect(info.downloadUrl, contains('SakuraRead-v1.0.2.apk'));
    });

    test('无 tag / 非 Map 返回 null', () {
      expect(parseReleaseJson(null), isNull);
      expect(parseReleaseJson('not json'), isNull);
      expect(parseReleaseJson({'no_tag': true}), isNull);
    });

    test('无附件时 downloadUrl 为空（上层据此判不完整）', () {
      final json = _githubRelease();
      json['assets'] = <Object>[];
      final info = parseReleaseJson(json);
      expect(info, isNotNull);
      expect(info!.downloadUrl, isEmpty);
    });
  });

  group('检查更新链路', () {
    test('首选端点成功：返回有新版', () async {
      final svc = UpdateService(
        client: MockClient((req) async {
          // 仅 gh-proxy 端点应答
          expect(req.url.toString(), contains('gh-proxy.com'));
          return ok(_githubRelease());
        }),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.info!.version, '1.0.2');
    });

    test('首选失败 → 自动回退到下一个端点', () async {
      var hits = 0;
      final svc = UpdateService(
        client: MockClient((req) async {
          hits++;
          if (hits == 1) return http.Response('oops', 502);
          return ok(_unghRelease());
        }),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(hits, 2);
    });

    test('全部端点失败：返回 failed（不抛异常）', () async {
      var hits = 0;
      final svc = UpdateService(
        client: MockClient((req) async {
          hits++;
          throw const SocketException('no network');
        }),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.failed);
      expect(hits, 3, reason: '三个端点都应尝试过');
    });

    test('线上版本不比当前新：返回 upToDate', () async {
      final svc = UpdateService(
        client: MockClient((req) async => ok(_githubRelease(tag: 'v1.0.1'))),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.upToDate);
    });

    test('200 但数据不完整（无附件）→ 继续尝试下一端点', () async {
      var hits = 0;
      final svc = UpdateService(
        client: MockClient((req) async {
          hits++;
          if (hits == 1) {
            final broken = _githubRelease();
            broken['assets'] = <Object>[];
            return ok(broken);
          }
          return ok(_unghRelease());
        }),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(hits, 2);
    });
  });

  group('下载链路（镜像回退 + 大小校验）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sakura_update_test');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    UpdateInfo infoOf({int size = 4}) => UpdateInfo(
      version: '1.0.2',
      title: 't',
      notes: '',
      downloadUrl: 'https://github.com/a/b/releases/download/v1.0.2/x.apk',
      sizeBytes: size,
      publishedAt: '',
      pageUrl: '',
    );

    test('首个镜像成功：文件内容与预期一致', () async {
      final payload = [1, 2, 3, 4];
      var hits = 0;
      final svc = UpdateService(
        client: MockClient.streaming((req, bodyStream) async {
          hits++;
          return http.StreamedResponse(
            http.ByteStream.fromBytes(payload),
            200,
            contentLength: payload.length,
          );
        }),
      );
      final target = '${tmp.path}/app.apk';
      final progress = <int>[];
      final ok = await svc.download(
        infoOf(),
        target,
        onProgress: (r, t) => progress.add(r),
      );
      expect(ok, isTrue);
      expect(hits, 1);
      expect(await File(target).readAsBytes(), payload);
      expect(progress, isNotEmpty);
      // 半成品文件不应残留
      expect(File('$target.part').existsSync(), isFalse);
    });

    test('镜像返回错误页（大小不符）→ 换下一个镜像', () async {
      var hits = 0;
      final svc = UpdateService(
        client: MockClient.streaming((req, bodyStream) async {
          hits++;
          // 第一个镜像返回坏数据（2 字节 vs 预期 4 字节）；第二个正确
          final payload = hits == 1 ? [9, 9] : [1, 2, 3, 4];
          return http.StreamedResponse(
            http.ByteStream.fromBytes(payload),
            200,
            contentLength: payload.length,
          );
        }),
      );
      final target = '${tmp.path}/app.apk';
      final ok = await svc.download(infoOf(), target);
      expect(ok, isTrue);
      expect(hits, 2);
      expect(await File(target).readAsBytes(), [1, 2, 3, 4]);
    });

    test('HTTP 非 200 → 换下一个镜像；全失败返回 false 且不留文件', () async {
      var hits = 0;
      final svc = UpdateService(
        client: MockClient.streaming((req, bodyStream) async {
          hits++;
          return http.StreamedResponse(http.ByteStream.fromBytes([]), 404);
        }),
      );
      final target = '${tmp.path}/app.apk';
      final ok = await svc.download(infoOf(), target);
      expect(ok, isFalse);
      expect(hits, 4, reason: '四个镜像线路都应尝试过');
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
    });

    test('下载中途取消：返回 false 并清理半成品', () async {
      final svc = UpdateService(
        client: MockClient.streaming((req, bodyStream) async {
          // 多 chunk 流：模拟真实网络分段传输，取消在 chunk 之间生效
          final chunks = Stream<List<int>>.fromIterable([
            List.filled(32, 7),
            List.filled(32, 7),
          ]);
          return http.StreamedResponse(
            http.ByteStream(chunks),
            200,
            contentLength: 64,
          );
        }),
      );
      final target = '${tmp.path}/app.apk';
      // 首次进度回调后即取消
      var called = false;
      final ok = await svc.download(
        infoOf(size: 64),
        target,
        onProgress: (r, t) => called = true,
        isCancelled: () => called,
      );
      expect(ok, isFalse);
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
    });
  });

  group('release 说明清洗', () {
    test('去掉标题 / 图片 / 链接装饰，保留正文', () {
      final out = cleanReleaseNotes(
        '## 🌸 樱读 v1.0.1\n'
        '![banner](https://x/y.png)\n'
        '- **修复**了[某问题](https://github.com/a/b)\n'
        '- 新增更新检查\n',
      );
      expect(out, isNot(contains('##')));
      expect(out, isNot(contains('![banner]')));
      expect(out, isNot(contains('](')));
      expect(out, contains('修复'));
      expect(out, contains('新增更新检查'));
    });

    test('保持空行结构，压缩连续空行', () {
      final out = cleanReleaseNotes('a\n\n\n\nb');
      expect(out, 'a\n\nb');
    });
  });
}
