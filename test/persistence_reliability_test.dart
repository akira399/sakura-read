import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/persistence.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/credential_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';

class _Writer with ReliablePersistence {}

class _Credentials extends CredentialStore {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('unavailable');
    return value;
  }

  @override
  Future<void> write(String key) async {
    if (failWrite) throw StateError('unavailable');
    value = key;
  }
}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sakura_persistence_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
    persistenceFailures.value = {};
  });

  test('并发快照按顺序持久化，重载得到最后一次状态', () async {
    final writer = _Writer();
    final file = File('${dir.path}/state.json');
    await Future.wait([
      for (var i = 0; i < 12; i++)
        writer.writeJson(file, jsonEncode({'value': i})),
    ]);
    expect((await writer.readJson(file))['value'], 11);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('写入失败保留原文件并报告错误，解除故障后可以重试', () async {
    final file = File('${dir.path}/state.json');
    final writer = _Writer();
    await writer.writeJson(file, '{"value":1}');
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    await expectLater(
      writer.writeJson(file, '{"value":2}'),
      throwsA(isA<FileSystemException>()),
    );
    expect(jsonDecode(await file.readAsString())['value'], 1);
    expect(writer.lastPersistenceError, isNotNull);
    await obstruction.delete();
    await writer.writeJson(file, '{"value":3}');
    expect((await writer.readJson(file))['value'], 3);
    expect(writer.lastPersistenceError, isNull);
  });

  test('损坏原文件读取失败后禁止默认值覆盖', () async {
    final file = File('${dir.path}/state.json');
    await file.writeAsString('{broken');
    final writer = _Writer();
    await expectLater(writer.readJson(file), throwsFormatException);
    await expectLater(writer.writeJson(file, '{}'), throwsStateError);
    expect(await file.readAsString(), '{broken');
  });

  test('书架 flush 取消防抖并保存最后一次阅读进度', () async {
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final store = BookStore(dirsOverride: dirs);
    await store.load();
    store.addOnline(
      Book(
        id: 'one',
        title: '测试',
        format: BookFormat.online,
        path: 'https://example.test',
      ),
    );
    store.updateProgress('one', chapter: 3, offset: 42);
    await store.flush();
    final reloaded = BookStore(dirsOverride: dirs);
    await reloaded.load();
    expect(reloaded.byId('one')!.charOffset, 42);
    expect(reloaded.byId('one')!.chapterIndex, 3);
  });

  test('旧明文先迁移安全存储，再从 JSON 移除；空值可以删除凭据', () async {
    final file = File('${dir.path}/settings.json');
    await file.writeAsString(
      jsonEncode({'aiApiKey': 'legacy-test-key', 'fontSize': 22}),
    );
    final credentials = _Credentials();
    final prefs = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: credentials,
    );
    await prefs.load();
    expect(jsonDecode(credentials.value!)['aiApiKey'], 'legacy-test-key');
    expect(
      jsonDecode(await file.readAsString()).containsKey('aiApiKey'),
      isFalse,
    );
    expect(prefs.fontSize, 22);
    prefs.setAiConfig(
      baseUrl: 'https://example.test',
      apiKey: '',
      model: 'test',
      includeReading: false,
    );
    await prefs.flush();
    expect(jsonDecode(credentials.value!)['aiApiKey'], '');
    final reloaded = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: credentials,
    );
    await reloaded.load();
    expect(reloaded.aiApiKey, '');
  });

  test('安全存储写入失败保留旧明文，恢复后可重试迁移', () async {
    final file = File('${dir.path}/settings.json');
    await file.writeAsString('{"aiApiKey":"legacy-test-key"}');
    final credentials = _Credentials()..failWrite = true;
    final prefs = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: credentials,
    );
    await prefs.load();
    await expectLater(prefs.flush(), throwsStateError);
    expect(
      jsonDecode(await file.readAsString())['aiApiKey'],
      'legacy-test-key',
    );
    credentials.failWrite = false;
    await prefs.flush();
    expect(jsonDecode(credentials.value!)['aiApiKey'], 'legacy-test-key');
    expect(
      jsonDecode(await file.readAsString()).containsKey('aiApiKey'),
      isFalse,
    );
  });

  test('安全存储读取失败时禁止空凭据覆盖已有数据', () async {
    final credentials = _Credentials()
      ..value = 'existing-test-key'
      ..failRead = true;
    final prefs = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: credentials,
    );
    await prefs.load();
    await expectLater(prefs.flush(), throwsStateError);
    expect(credentials.value, 'existing-test-key');
  });
}
