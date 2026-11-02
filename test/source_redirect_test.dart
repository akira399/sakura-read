import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/source/http_client.dart';

void main() {
  test('跨来源重定向清理认证、Cookie、Host 和 Referer，返回原站也不恢复', () async {
    final requests = <http.Request>[];
    final client = SourceHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        return switch (requests.length) {
          1 => http.Response(
            '',
            302,
            headers: {'location': 'https://b.test/next'},
          ),
          2 => http.Response(
            '',
            302,
            headers: {'location': 'https://a.test/back'},
          ),
          _ => http.Response('ok', 200),
        };
      }),
    );
    addTearDown(client.close);
    await client.get(
      'https://a.test/start',
      headers: {
        'aUtHoRiZaTiOn': 'Bearer private',
        'COOKIE': 'session=private',
        'HOST': 'a.test',
        'ReFeReR': 'https://a.test/private',
        'Proxy-Authorization': 'Basic private',
        'Accept': 'text/html',
      },
    );
    for (final request in requests.skip(1)) {
      for (final header in [
        'authorization',
        'cookie',
        'host',
        'referer',
        'proxy-authorization',
      ]) {
        expect(request.headers[header], isNull, reason: header);
      }
      expect(request.headers['accept'], 'text/html');
    }
  });

  test('同源 307 保留 POST 正文和认证，303 清理正文头并改为 GET', () async {
    final requests = <http.Request>[];
    final client = SourceHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        return switch (requests.length) {
          1 => http.Response('', 307, headers: {'location': '/post'}),
          2 => http.Response('', 303, headers: {'location': '/result'}),
          _ => http.Response('ok', 200),
        };
      }),
    );
    addTearDown(client.close);
    await client.post(
      'https://a.test/start',
      body: 'q=book',
      headers: {
        'Authorization': 'Bearer private',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );
    expect(requests[1].method, 'POST');
    expect(requests[1].body, 'q=book');
    expect(requests[1].headers['authorization'], 'Bearer private');
    expect(requests[2].method, 'GET');
    expect(requests[2].body, isEmpty);
    expect(requests[2].headers['content-type'], isNull);
    expect(requests[2].headers['authorization'], 'Bearer private');
  });

  test('HTTPS 降级时不发送认证信息及 Secure Cookie', () async {
    final requests = <http.Request>[];
    final client = SourceHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {
              'location': 'http://a.test/plain',
              'set-cookie': 'session=secret; Path=/; Secure',
            },
          );
        }
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);
    await client.get(
      'https://a.test/start',
      headers: {'Authorization': 'secret'},
    );
    expect(requests[1].headers['cookie'], isNull);
    expect(requests[1].headers['authorization'], isNull);
    await client.get('https://a.test/secure');
    expect(requests.last.headers['cookie'], 'session=secret');
  });

  test('拒绝非 HTTP 地址以及非法重定向协议', () async {
    var calls = 0;
    final client = SourceHttpClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 302, headers: {'location': 'file:///private'});
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.get('file:///private'),
      throwsA(isA<SourceHttpException>()),
    );
    expect(calls, 0);
    await expectLater(
      client.get('https://a.test/'),
      throwsA(isA<SourceHttpException>()),
    );
    expect(calls, 1);
  });

  test('重定向循环给出明确异常', () async {
    var calls = 0;
    final client = SourceHttpClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 302, headers: {'location': '/loop'});
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.get('https://a.test/loop'),
      throwsA(
        isA<SourceHttpException>().having(
          (e) => e.message,
          'message',
          contains('重定向'),
        ),
      ),
    );
    expect(calls, 5);
  });
}
