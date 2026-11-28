// 更新检查服务回归测试：多线路竞速检查、并发测速优选、HTTP 206 断点续传与低速/异常切源。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sakura_read/src/platform/update_service.dart';

Map<String, Object?> _githubRelease({
  String tag = 'v1.0.2',
  String name = '樱读 v1.0.2',
  String body = '## 修复\n- 修了状态栏',
  int size = 100,
  String url = 'https://github.com/akira399/sakura-read/releases/download/v1.0.2/SakuraRead-v1.0.2.apk',
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

    test('多架构附件里挑 arm64，不会下到模拟器专用的 x86_64 包', () {
      final json = _githubRelease();
      json['assets'] = <Object?>[
        {
          'name': 'SakuraRead-v1.2.0-x86_64.apk',
          'size': 50,
          'browser_download_url': 'https://example.com/x86_64.apk',
        },
        {
          'name': 'SakuraRead-v1.2.0-arm64.apk',
          'size': 48,
          'browser_download_url': 'https://example.com/arm64.apk',
        },
      ];
      final info = parseReleaseJson(json)!;
      expect(info.downloadUrl, contains('arm64.apk'));
      expect(info.downloadUrl, isNot(contains('x86_64')));
      expect(info.sizeBytes, 48);
    });

    test('只有 x86_64 时仍能取到包（不因架构打分丢掉唯一附件）', () {
      final json = _githubRelease();
      json['assets'] = <Object?>[
        {
          'name': 'SakuraRead-v1.2.0-x86_64.apk',
          'size': 50,
          'browser_download_url': 'https://example.com/x86_64.apk',
        },
      ];
      expect(parseReleaseJson(json)!.downloadUrl, contains('x86_64.apk'));
    });
  });

  group('检查更新链路', () {
    test('顺序模式：首选失败自动回退', () async {
      var hits = 0;
      final svc = UpdateService(
        raceCheckEndpoints: false,
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

    test('竞速模式：最快健康端点立刻出结果', () async {
      final slow = Completer<http.Response>();
      final svc = UpdateService(
        raceCheckEndpoints: true,
        endpoints: [
          'https://slow.example/latest',
          'https://fast.example/latest',
        ],
        client: MockClient((req) async {
          if (req.url.host == 'slow.example') {
            return slow.future;
          }
          return ok(_githubRelease(tag: 'v2.2.0'));
        }),
      );
      final r = await svc.check(currentVersion: '2.1.0');
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.info!.version, '2.2.0');
      slow.complete(http.Response('timeout', 504));
    });

    test('全部端点失败：返回 failed（不抛异常）', () async {
      var hits = 0;
      final svc = UpdateService(
        raceCheckEndpoints: false,
        client: MockClient((req) async {
          hits++;
          throw const SocketException('no network');
        }),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.failed);
      expect(hits, UpdateService.checkEndpoints.length);
    });

    test('线上版本不比当前新：返回 upToDate', () async {
      final svc = UpdateService(
        raceCheckEndpoints: false,
        client: MockClient((req) async => ok(_githubRelease(tag: 'v1.0.1'))),
      );
      final r = await svc.check(currentVersion: '1.0.1');
      expect(r.status, UpdateCheckStatus.upToDate);
    });

    test('200 但数据不完整（无附件）→ 继续尝试下一端点', () async {
      var hits = 0;
      final svc = UpdateService(
        raceCheckEndpoints: false,
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

  group('下载链路（并发测速优选 + 断点续传 + 多线切换）', () {
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
        enableRouteProbe: false,
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
      expect(File('$target.part').existsSync(), isFalse);
    });

    test('并发测速优选更快节点且跳过 HTML 错误页镜像', () async {
      final payload = [10, 20, 30, 40];
      String? downloadHost;
      final svc = UpdateService(
        enableRouteProbe: true,
        mirrors: const [
          UpdateMirror(
            id: 'html',
            label: 'Bad HTML',
            prefix: 'https://html.example/',
          ),
          UpdateMirror(
            id: 'slow',
            label: 'Slow',
            prefix: 'https://slow.example/',
          ),
          UpdateMirror(
            id: 'fast',
            label: 'Fast',
            prefix: 'https://fast.example/',
          ),
        ],
        client: MockClient.streaming((req, bodyStream) async {
          final isProbe = req.headers['Range'] == 'bytes=0-0';
          if (isProbe) {
            if (req.url.host == 'html.example') {
              return http.StreamedResponse(
                http.ByteStream.fromBytes(utf8.encode('<html>error</html>')),
                200,
                headers: {'content-type': 'text/html; charset=utf-8'},
              );
            }
            if (req.url.host == 'slow.example') {
              await Future<void>.delayed(const Duration(milliseconds: 120));
            }
            return http.StreamedResponse(
              http.ByteStream.fromBytes([payload.first]),
              206,
              headers: {
                'content-type': 'application/vnd.android.package-archive',
                'content-range': 'bytes 0-0/4',
              },
            );
          }
          downloadHost = req.url.host;
          return http.StreamedResponse(
            http.ByteStream.fromBytes(payload),
            200,
            contentLength: payload.length,
            headers: {
              'content-type': 'application/vnd.android.package-archive',
            },
          );
        }),
      );

      final target = '${tmp.path}/probed.apk';
      final ok = await svc.download(infoOf(), target);
      expect(ok, isTrue);
      expect(downloadHost, 'fast.example');
      expect(await File(target).readAsBytes(), payload);
    });

    test('切线保留 .part 进度并以 HTTP 206 Range 断点续传接力完成', () async {
      final fullPayload = [1, 2, 3, 4, 5, 6];
      var switchNow = false;
      String? seenRange;
      final svc = UpdateService(
        enableRouteProbe: false,
        mirrors: const [
          UpdateMirror(
            id: 'm1',
            label: 'Mirror1',
            prefix: 'https://m1.example/',
          ),
          UpdateMirror(
            id: 'm2',
            label: 'Mirror2',
            prefix: 'https://m2.example/',
          ),
        ],
        client: MockClient.streaming((req, bodyStream) async {
          if (req.url.host == 'm1.example') {
            final controller = StreamController<List<int>>();
            // 先传前 2 字节，触发用户切换/断流
            controller.add([1, 2]);
            Future<void>.delayed(const Duration(milliseconds: 20), () {
              switchNow = true;
              controller.add([3]);
            });
            return http.StreamedResponse(
              http.ByteStream(controller.stream),
              200,
              contentLength: fullPayload.length,
            );
          }
          seenRange = req.headers['Range'];
          final offset = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(seenRange ?? '')!.group(1)!,
          );
          final tail = fullPayload.sublist(offset);
          return http.StreamedResponse(
            http.ByteStream.fromBytes(tail),
            206,
            contentLength: tail.length,
            headers: {
              'content-range':
                  'bytes $offset-${fullPayload.length - 1}/${fullPayload.length}',
            },
          );
        }),
      );

      final target = '${tmp.path}/resume.apk';
      final ok = await svc.download(
        infoOf(size: fullPayload.length),
        target,
        shouldSwitchRoute: () {
          if (!switchNow) return false;
          switchNow = false;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(seenRange, 'bytes=2-');
      expect(await File(target).readAsBytes(), fullPayload);
    });

    test('镜像返回错误页（大小不符）→ 换下一个镜像', () async {
      var hits = 0;
      final svc = UpdateService(
        enableRouteProbe: false,
        client: MockClient.streaming((req, bodyStream) async {
          hits++;
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
        enableRouteProbe: false,
        client: MockClient.streaming((req, bodyStream) async {
          hits++;
          return http.StreamedResponse(http.ByteStream.fromBytes([]), 404);
        }),
      );
      final target = '${tmp.path}/app.apk';
      final ok = await svc.download(infoOf(), target);
      expect(ok, isFalse);
      expect(hits, UpdateService.defaultMirrors.length);
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
    });

    test('下载中途取消：返回 false 并清理半成品', () async {
      final svc = UpdateService(
        enableRouteProbe: false,
        client: MockClient.streaming((req, bodyStream) async {
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
