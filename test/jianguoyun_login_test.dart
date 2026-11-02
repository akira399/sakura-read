import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/data/jianguoyun_login.dart';

/// 构造一个只认「账号 + 指定密码」的假坚果云 WebDAV。
MockClient _davMock({
  required String user,
  required Set<String> acceptedSecrets,
  int failStatus = 401,
  int okStatus = 207,
  List<String>? log,
}) {
  return MockClient((request) async {
    final auth = request.headers['Authorization'] ?? '';
    final raw = auth.startsWith('Basic ') ? auth.substring(6) : '';
    String decoded = '';
    try {
      decoded = utf8.decode(base64Decode(raw));
    } catch (_) {}
    log?.add(decoded);
    final parts = decoded.split(':');
    final pass = parts.length > 1 ? parts.sublist(1).join(':') : '';
    if (parts.first == user && acceptedSecrets.contains(pass)) {
      return http.Response('<?xml version="1.0"?><d:multistatus/>', okStatus);
    }
    return http.Response('unauthorized', failStatus);
  });
}

void main() {
  group('JianguoyunLogin.login', () {
    test('账号密码能直连时直接成功，不需要应用密码', () async {
      final log = <String>[];
      final cred = await JianguoyunLogin.login(
        account: ' someone@example.com ',
        password: ' login-pass ',
        client: _davMock(
          user: 'someone@example.com',
          acceptedSecrets: {'login-pass'},
          log: log,
        ),
      );

      expect(cred.account, 'someone@example.com');
      expect(cred.secret, 'login-pass');
      expect(cred.usedAccountPassword, isTrue);
      expect(cred.webdavUrl, JianguoyunLogin.webdavUrl);
      expect(log, hasLength(1));
    });

    test('只有应用密码能用时，第二次请求换成应用密码并成功', () async {
      final log = <String>[];
      var asked = 0;
      final cred = await JianguoyunLogin.login(
        account: 'someone@example.com',
        password: 'login-pass',
        client: _davMock(
          user: 'someone@example.com',
          acceptedSecrets: {'app-secret'},
          log: log,
        ),
        appPasswordProvider: () async {
          asked++;
          return '  app-secret  ';
        },
      );

      expect(asked, 1);
      expect(cred.usedAccountPassword, isFalse);
      expect(cred.secret, 'app-secret');
      expect(log, hasLength(2));
      expect(log.first, 'someone@example.com:login-pass');
      expect(log.last, 'someone@example.com:app-secret');
    });

    test('用户放弃输入应用密码时给出 needsAppPassword', () async {
      await expectLater(
        JianguoyunLogin.login(
          account: 'someone@example.com',
          password: 'login-pass',
          client: _davMock(
            user: 'someone@example.com',
            acceptedSecrets: {'app-secret'},
          ),
          appPasswordProvider: () async => '',
        ),
        throwsA(
          isA<JianguoyunException>().having(
            (e) => e.needsAppPassword,
            'needsAppPassword',
            isTrue,
          ),
        ),
      );
    });

    test('没有兜底输入框时提示去生成应用密码', () async {
      await expectLater(
        JianguoyunLogin.login(
          account: 'someone@example.com',
          password: 'login-pass',
          client: _davMock(
            user: 'someone@example.com',
            acceptedSecrets: <String>{},
          ),
        ),
        throwsA(
          isA<JianguoyunException>().having(
            (e) => e.message,
            'message',
            contains('应用密码'),
          ),
        ),
      );
    });

    test('应用密码也不对时仍然报 needsAppPassword，不会静默成功', () async {
      await expectLater(
        JianguoyunLogin.login(
          account: 'someone@example.com',
          password: 'login-pass',
          client: _davMock(
            user: 'someone@example.com',
            acceptedSecrets: {'other'},
          ),
          appPasswordProvider: () async => 'app-secret',
        ),
        throwsA(isA<JianguoyunException>()),
      );
    });

    test('账号 / 密码为空时立刻报错，不发请求', () async {
      var called = 0;
      final client = MockClient((_) async {
        called++;
        return http.Response('', 207);
      });
      await expectLater(
        JianguoyunLogin.login(account: '  ', password: 'x', client: client),
        throwsA(isA<JianguoyunException>()),
      );
      await expectLater(
        JianguoyunLogin.login(account: 'x', password: ' ', client: client),
        throwsA(isA<JianguoyunException>()),
      );
      expect(called, 0);
    });

    test('网络异常时给出「连不上坚果云」而不是假装成功', () async {
      final client = MockClient((_) async {
        throw const SocketExceptionStub();
      });
      await expectLater(
        JianguoyunLogin.login(
          account: 'someone@example.com',
          password: 'login-pass',
          client: client,
        ),
        throwsA(
          isA<JianguoyunException>().having(
            (e) => e.message,
            'message',
            contains('连不上坚果云'),
          ),
        ),
      );
    });

    test('服务器 5xx 不当成「没权限」，直接报错', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      await expectLater(
        JianguoyunLogin.login(
          account: 'someone@example.com',
          password: 'login-pass',
          client: client,
        ),
        throwsA(isA<JianguoyunException>()),
      );
    });
  });

  test('basicHeader 拼的是标准 Basic 认证头', () {
    final header = JianguoyunLogin.basicHeader('u@example.com', 'p:w');
    expect(header.startsWith('Basic '), isTrue);
    expect(utf8.decode(base64Decode(header.substring(6))), 'u@example.com:p:w');
  });
}

/// 测试里模拟 socket 异常（不引入 dart:io 的 SocketException 依赖）。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketException: 网络不可达';
}
