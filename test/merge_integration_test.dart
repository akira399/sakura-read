import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/backup_service.dart';
import 'package:sakura_read/src/data/persistence.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/platform/credential_store.dart';

class _Secrets extends CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String secret) async {
    value = secret;
  }
}

class _Writer with ReliablePersistence {}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sakura_merge');
  });
  tearDown(() async {
    persistenceFlushers = [];
    restoredFilePaths.clear();
    restoredDataAwaitingRestart.value = false;
    persistenceFailures.value = {};
    await dir.delete(recursive: true);
  });
  test('上游 WebDAV 凭据与 API Key 同时迁移，设置与备份都无明文凭据', () async {
    final file = File('${dir.path}/settings.json');
    await file.writeAsString(
      jsonEncode({
        'aiApiKey': 'test-api',
        'webdavPass': 'test-dav',
        'frostedGlass': true,
        'ttsRolePlay': true,
      }),
    );
    final secrets = _Secrets();
    final prefs = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: secrets,
    );
    await prefs.load();
    final stored = jsonDecode(secrets.value!);
    expect(stored['aiApiKey'], 'test-api');
    expect(stored['webdavPass'], 'test-dav');
    final settings = jsonDecode(await file.readAsString());
    expect(settings.containsKey('aiApiKey'), isFalse);
    expect(settings.containsKey('webdavPass'), isFalse);
    expect(settings['frostedGlass'], isTrue);
    expect(settings['ttsRolePlay'], isTrue);
    final backup = BackupService(
      prefs: prefs,
      filesDirOverride: dir.path,
      downloadDirOverride: dir.path,
    );
    final archive = ZipDecoder().decodeBytes(
      await (await backup.createBackup()).readAsBytes(),
    );
    await prefs.flush();
    final exported = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'settings.json').content
          as List<int>,
    );
    expect(exported, isNot(contains('test-api')));
    expect(exported, isNot(contains('test-dav')));
    final reload = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: secrets,
    );
    await reload.load();
    expect(reload.webdavPass, 'test-dav');
    expect(reload.aiApiKey, 'test-api');
  });
  test('恢复后阻止旧内存快照覆盖已恢复文件，坏 JSON 不覆盖原文件', () async {
    final prefs = AppPrefs(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
      credentials: _Secrets(),
    );
    await prefs.load();
    final file = File('${dir.path}/library.json');
    final writer = _Writer();
    await writer.writeJson(file, '{"books":[]}');
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'library.json',
          utf8.encode('{"books":[{"title":"restored"}]}'),
        ),
      )
      ..addFile(ArchiveFile.bytes('pet.json', utf8.encode('{invalid')));
    final zip = File('${dir.path}/restore.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final service = BackupService(
      prefs: prefs,
      filesDirOverride: dir.path,
      downloadDirOverride: dir.path,
    );
    final result = await service.restore(zip);
    expect(result.restored, ['library.json']);
    expect(result.failed, ['pet.json']);
    await writer.writeJson(file, '{"books":[]}');
    expect(await file.readAsString(), contains('restored'));
    expect(restoredDataAwaitingRestart.value, isTrue);
  });
}
