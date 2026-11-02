import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'webdav_client.dart';

/// 坚果云登录失败时抛这个，[message] 直接展示给用户（中文、可操作）。
class JianguoyunException implements Exception {
  JianguoyunException(this.message, {this.needsAppPassword = false});

  final String message;

  /// true 表示「坚果云只认应用密码」，UI 应该引导用户去生成并粘贴。
  final bool needsAppPassword;

  @override
  String toString() => message;
}

/// 登录成功后拿到的 WebDAV 凭据。
class JianguoyunCredential {
  const JianguoyunCredential({
    required this.account,
    required this.secret,
    required this.webdavUrl,
    required this.usedAccountPassword,
  });

  /// 坚果云账号（邮箱 / 手机号）。
  final String account;

  /// WebDAV 用的密码：可能等于账号密码，也可能是应用密码。
  final String secret;

  /// WebDAV 根地址。
  final String webdavUrl;

  /// true 表示账号密码本身就可用；false 表示用的是应用密码。
  final bool usedAccountPassword;
}

/// 坚果云「本地登录」。
///
/// 背景：坚果云 WebDAV 官方要求用「第三方应用密码」，很多用户不知道去哪儿拿。
/// 这里给一个更省事的入口：在 App 里直接输坚果云账号 + 密码，
///
/// 1. 先用账号密码试一次 WebDAV（部分账号可以，就是登录密码）；
/// 2. 不行就明确告诉用户「坚果云只认应用密码」，并把生成页面的地址给出来，
///    用户粘贴回来立刻再验一次（[appPasswordProvider]）。
///
/// 为什么不模拟网页登录：坚果云登录页带 CSRF token + 可能弹验证码，硬抓接口
/// 既容易失效，也让用户觉得「这 App 在偷我的账号密码」。宁清楚别假装。
class JianguoyunLogin {
  JianguoyunLogin._();

  static const String webdavUrl = 'https://dav.jianguoyun.com/dav';

  /// 生成 / 查看第三方应用密码的页面。
  static const String appPasswordUrl =
      'https://www.jianguoyun.com/d/account/safety';

  static const Duration timeout = Duration(seconds: 20);

  /// 登录：先试账号密码，再走应用密码兜底。
  ///
  /// [client] 只在测试里注入；[appPasswordProvider] 由 UI 提供（弹输入框 +
  /// 打开官方页面）。返回可用凭据，失败抛 [JianguoyunException]。
  static Future<JianguoyunCredential> login({
    required String account,
    required String password,
    http.Client? client,
    Future<String?> Function()? appPasswordProvider,
  }) async {
    final user = account.trim();
    final pass = password.trim();
    if (user.isEmpty) throw JianguoyunException('坚果云账号不能为空');
    if (pass.isEmpty) throw JianguoyunException('坚果云密码不能为空');

    WebdavClient make(String secret) => WebdavClient(
      baseUrl: webdavUrl,
      user: user,
      pass: secret,
      client: client,
    );

    // ---- 1) 账号密码直接试 ----
    final direct = make(pass);
    var unauthorised = false;
    try {
      final ok = await direct.testConnection().timeout(timeout);
      if (ok) {
        return JianguoyunCredential(
          account: user,
          secret: pass,
          webdavUrl: webdavUrl,
          usedAccountPassword: true,
        );
      }
      unauthorised = true;
    } on WebdavException catch (e) {
      // 401/403 → 凭据不对，走应用密码；其它（网络 / 地址）直接报错
      if (e.message.contains('401') || e.message.contains('403')) {
        unauthorised = true;
      } else {
        throw JianguoyunException('连不上坚果云：${e.message}');
      }
    } catch (e) {
      throw JianguoyunException('连不上坚果云：$e');
    } finally {
      direct.close();
    }
    if (!unauthorised) {
      throw JianguoyunException('坚果云返回异常，先看看手机网络是否正常', needsAppPassword: true);
    }

    // ---- 2) 用应用密码再试 ----
    if (appPasswordProvider != null) {
      final typed = (await appPasswordProvider())?.trim() ?? '';
      if (typed.isEmpty) {
        throw JianguoyunException(
          '坚果云 WebDAV 需要用「应用密码」，去安全选项生成一个吧',
          needsAppPassword: true,
        );
      }
      final dav = make(typed);
      try {
        final ok = await dav.testConnection().timeout(timeout);
        if (ok) {
          return JianguoyunCredential(
            account: user,
            secret: typed,
            webdavUrl: webdavUrl,
            usedAccountPassword: false,
          );
        }
        throw JianguoyunException(
          '应用密码没通过：核对一下有没有多余空格，或者换一个应用密码',
          needsAppPassword: true,
        );
      } on JianguoyunException {
        rethrow;
      } catch (e) {
        throw JianguoyunException('验证应用密码失败：$e', needsAppPassword: true);
      } finally {
        dav.close();
      }
    }

    throw JianguoyunException(
      '坚果云 WebDAV 不认登录密码，要在「安全选项 → 添加应用」里生成应用密码',
      needsAppPassword: true,
    );
  }

  /// 打开坚果云应用密码页面（交给系统浏览器，登录态 / 验证码都由官方页面处理）。
  static Future<bool> openAppPasswordPage() async {
    const channel = MethodChannel('sakuramanga/native');
    try {
      final ok = await channel.invokeMethod<bool>('openUrl', appPasswordUrl);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 把「账号:密码」拼成 Basic 头（测试用，避免重复实现）。
  static String basicHeader(String account, String secret) =>
      'Basic ${base64Encode(utf8.encode('$account:$secret'))}';
}
