// 书源导出的回归测试。
//
// 回归背景（用户反馈「导出按钮点了没反应」）：书源很多时（实测 1234 个、
// JSON 6.6MB），旧实现把全部 JSON 塞进剪贴板——超出 Android Binder ~1MB
// 上限 → `Clipboard.setData` 抛异常、无捕获 → 点击后毫无反馈。
//
// 修复后的行为：
//   - 小数据（≤ 200KB）：复制到剪贴板；
//   - 大数据 / 剪贴板失败：保存为文件（Download 优先，退回 App 目录）；
//   - 任何路径都不抛未捕获异常（失败给出可展示的错误）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/source_export.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sakura_export_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('小数据：复制到剪贴板，不落文件', () async {
    var copied = '';
    final result = await exportSourcesJson(
      '{"bookSourceUrl":"https://a.com"}',
      copyToClipboard: (text) async => copied = text,
      downloadDirOverride: '${tmp.path}/dl',
      filesDirOverride: '${tmp.path}/files',
    );

    expect(result.savedToFile, isFalse);
    expect(copied, contains('a.com'));
    expect(Directory('${tmp.path}/dl').existsSync(), isFalse, reason: '不应落文件');
  });

  test('大数据（>200KB）：跳过剪贴板，保存到文件', () async {
    // 构造 ~300KB 文本（书源很多时的真实场景）
    final big = 'x' * (300 * 1024);
    var clipboardCalled = false;
    final result = await exportSourcesJson(
      big,
      copyToClipboard: (text) async => clipboardCalled = true,
      downloadDirOverride: '${tmp.path}/dl',
      filesDirOverride: '${tmp.path}/files',
    );

    expect(clipboardCalled, isFalse, reason: '大数据不应尝试剪贴板');
    expect(result.savedToFile, isTrue);
    final f = File(result.path!);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), big.length);
    expect(result.byteLength, greaterThan(200 * 1024));
  });

  test('剪贴板失败（模拟超限异常）：自动降级为文件', () async {
    final result = await exportSourcesJson(
      '{"small":"but clipboard broken"}',
      copyToClipboard: (text) async => throw Exception('TransactionTooLarge'),
      downloadDirOverride: '${tmp.path}/dl',
      filesDirOverride: '${tmp.path}/files',
    );

    expect(result.savedToFile, isTrue, reason: '剪贴板失败必须降级到文件');
    expect(File(result.path!).existsSync(), isTrue);
  });

  test('Download 目录不可写时：退回 App 私有目录', () async {
    final bad = '${tmp.path}/dl_as_file';
    // 把目标目录占成普通文件，制造「目录不可写」
    File(bad).writeAsStringSync('occupied');

    final result = await exportSourcesJson(
      'x' * (250 * 1024),
      copyToClipboard: (text) async {},
      downloadDirOverride: bad,
      filesDirOverride: '${tmp.path}/files',
    );

    expect(result.savedToFile, isTrue);
    expect(result.path, contains('files'));
    expect(File(result.path!).existsSync(), isTrue);
  });

  test('两个目录都不可写：抛出可展示的异常（不静默）', () async {
    final bad1 = '${tmp.path}/bad1';
    final bad2 = '${tmp.path}/bad2';
    File(bad1).writeAsStringSync('x');
    File(bad2).writeAsStringSync('x');

    await expectLater(
      exportSourcesJson(
        'x' * (250 * 1024),
        copyToClipboard: (text) async {},
        downloadDirOverride: bad1,
        filesDirOverride: bad2,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
