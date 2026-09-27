// 「用樱读打开文件」服务的回归测试。
//
// 背景（用户反馈）：在文件管理器打开 .txt / .epub / .json 时，系统
// 「打开方式」里没有樱读——应用此前未注册文件关联，也没有接收逻辑。
// 修复包含两部分（原生 + Dart），本测试钉住 Dart 侧的契约：
//   - 独立通道 sakuramanga/open（避免覆盖 TTS 在 native 通道上的事件处理器）；
//   - `fileOpened` 事件 → onOpenFile 回调；
//   - `getLaunchFile` 冷启动取路径（无则 null）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/platform/open_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('sakuramanga/open');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('冷启动：getLaunchFile 取到路径后透传', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getLaunchFile') return '/sdcard/Download/书.txt';
          return null;
        });

    final path = await OpenFileService.instance.consumeLaunchFile();
    expect(path, '/sdcard/Download/书.txt');
  });

  test('冷启动：无文件时返回 null（正常启动不受影响）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final path = await OpenFileService.instance.consumeLaunchFile();
    expect(path, isNull);
  });

  test('冷启动：通道异常时安全返回 null（不抛）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error');
        });

    final path = await OpenFileService.instance.consumeLaunchFile();
    expect(path, isNull);
  });

  test('热启动：fileOpened 事件触发 onOpenFile 回调', () async {
    final received = <String>[];
    OpenFileService.instance
      ..onOpenFile = received.add
      ..listen();

    // 模拟原生侧推送（热启动打开文件）
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'sakuramanga/open',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fileOpened', '/sdcard/Download/新书.epub'),
          ),
          (_) {},
        );

    expect(received, ['/sdcard/Download/新书.epub']);
  });

  test('热启动：非 fileOpened 事件被忽略', () async {
    final received = <String>[];
    OpenFileService.instance
      ..onOpenFile = received.add
      ..listen();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'sakuramanga/open',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('somethingElse', '/x.json'),
          ),
          (_) {},
        );

    expect(received, isEmpty);
  });

  test('热启动：空路径不触发回调', () async {
    final received = <String>[];
    OpenFileService.instance
      ..onOpenFile = received.add
      ..listen();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'sakuramanga/open',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fileOpened', ''),
          ),
          (_) {},
        );

    expect(received, isEmpty);
  });
}
