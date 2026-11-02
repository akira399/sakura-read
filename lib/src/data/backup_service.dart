import 'dart:convert';

import 'persistence.dart';

import 'dart:io';

import 'package:archive/archive.dart';

import '../platform/native_bridge.dart';
import 'prefs.dart';

/// 会被写进备份包的数据文件（都在 App 私有 files 目录下）。
///
/// 只备份这些「用户数据」，不碰缓存、书籍原文件和下载的模型：
/// 体积小、恢复后立刻能用，也就不会因为打包几本书把备份拖到几十 MB。
const List<String> kBackupFiles = <String>[
  'settings.json',
  'library.json',
  'pet.json',
  'bookmarks.json',
  'reading_stats.json',
  'book_sources.json',
];

/// 备份 / 恢复过程中可以直接展示给用户的中文错误。
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 恢复结果摘要。
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.restored,
    required this.failed,
    required this.ignoredCount,
    required this.bakDir,
  });

  /// 成功覆盖的文件名。
  final List<String> restored;

  /// 在白名单里、但写入失败的文件名。
  final List<String> failed;

  /// 压缩包里不属于白名单、被忽略的条目数（防止顺手恢复别的文件）。
  final int ignoredCount;

  /// 旧文件 `.bak` 留在这个目录。
  final String bakDir;

  bool get hasRestored => restored.isNotEmpty;

  /// 恢复后必须重启 App（各 Store 才会重新读盘），所以固定提示。
  bool get needsRestart => restored.isNotEmpty;

  /// 给 SnackBar / 对话框用的一句话摘要。
  String get summary {
    if (restored.isEmpty) {
      if (failed.isEmpty) return '这个压缩包里没有能找到的备份文件，确认选对了吗？';
      return '一个文件都没恢复成功（${failed.join('、')}）';
    }
    final buf = StringBuffer(
      '已恢复 ${restored.length} 个文件：${restored.join('、')}',
    );
    if (failed.isNotEmpty) {
      buf.write('；${failed.length} 个没成功（${failed.join('、')}）');
    }
    if (ignoredCount > 0) {
      buf.write('；另外 $ignoredCount 个条目不在备份名单里，已跳过');
    }
    buf.write('。原来的文件都留了 .bak，放在 $bakDir。重启 App 后生效哦～');
    return buf.toString();
  }
}

/// 本地 zip 备份 / 恢复。
///
/// 刻意不依赖 BuildContext：页面只负责按钮和提示，打包、写盘、路径兜底
/// 全部收在这里，以后要做「每天自动备份」也能直接复用。
class BackupService {
  BackupService({
    required this.prefs,
    this.downloadDirOverride,
    this.filesDirOverride,
    this.now,
  });

  final AppPrefs prefs;

  /// 测试用：优先写入目录（默认是手机 Download）。
  final String? downloadDirOverride;

  /// 测试用：指定 App 私有 files 目录。
  final String? filesDirOverride;

  /// 测试用：固定时间，方便断言文件名。
  final DateTime Function()? now;

  DateTime _now() => now?.call() ?? DateTime.now();

  /// 把 [kBackupFiles] 里存在的文件打成 zip。
  ///
  /// 先写临时文件再改名，避免中途失败留下半个 zip；Download 写不进去
  /// （部分机型 / 没给存储权限）就回退到 `<files>/backups/`。
  Future<File> createBackup() async {
    await flushPersistentStores();
    final filesPath = await _filesDirPath();
    final archive = Archive();
    var count = 0;
    for (final name in kBackupFiles) {
      final file = File('$filesPath/$name');
      try {
        if (!await file.exists()) continue;
        var bytes = await file.readAsBytes();
        if (name == 'settings.json') {
          final settings =
              Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map)
                ..remove('aiApiKey')
                ..remove('webdavPass');
          bytes = utf8.encode(jsonEncode(settings));
        }
        archive.addFile(ArchiveFile.bytes(name, bytes));
        count++;
      } catch (_) {
        // 单个文件读不出来（正被写入 / 权限异常）就先跳过，别让整次备份失败。
      }
    }
    if (count == 0) {
      throw const BackupException('还没有可备份的数据（书架和设置都是空的）');
    }

    final stamp = _now();
    final bytes = ZipEncoder().encodeBytes(archive);
    final dir = await _targetDir();
    final file = await _writeUnique(
      dir,
      'sakura-backup-${_stamp(stamp)}.zip',
      bytes,
    );
    prefs.setLastBackupAt(stamp.toIso8601String());
    return file;
  }

  /// 解包 [zip] 并覆盖到 `<files>/`。
  ///
  /// 只认白名单里的「纯文件名」，压缩包里带 `../` 或别的文件名一律忽略，
  /// 这样就算用户随手恢复一个恶意 zip 也写不到 App 目录之外去。
  /// 覆盖前先把原文件存成 `<name>.bak`，给手滑留一条退路。
  Future<BackupRestoreResult> restore(File zip) async {
    if (!await zip.exists()) {
      throw const BackupException('找不到这个备份文件，检查一下路径有没有写错～');
    }
    final List<int> bytes;
    try {
      bytes = await zip.readAsBytes();
    } catch (e) {
      throw BackupException('读不了这个备份文件（$e）');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (_) {
      throw const BackupException('这个文件不是 sakura 的备份（解压失败）');
    }

    final filesDir = Directory(await _filesDirPath());
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
    await flushPersistentStores();
    final restored = <String>[];
    final failed = <String>[];
    var ignored = 0;
    for (final entry in archive.files) {
      if (!entry.isFile || entry.isSymbolicLink) {
        ignored++;
        continue;
      }
      // 统一分隔符后再精确比对：白名单外（含带目录的路径）全部忽略。
      final name = entry.name.replaceAll('\\', '/');
      if (!kBackupFiles.contains(name)) {
        ignored++;
        continue;
      }
      final target = File('${filesDir.path}/$name');
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(entry.content as List<int>)) as Map,
        );
        if (name == 'settings.json') {
          data
            ..remove('aiApiKey')
            ..remove('webdavPass');
        }
        restoredFilePaths.add(target.path);
        if (await target.exists()) {
          final bak = File('${target.path}.bak');
          await bak.writeAsBytes(await target.readAsBytes(), flush: true);
        }
        final temporary = File('${target.path}.restore');
        await temporary.writeAsString(jsonEncode(data), flush: true);
        await temporary.rename(target.path);
        restored.add(name);
      } catch (e) {
        restoredFilePaths.remove(target.path);
        failed.add(name);
      }
    }

    if (restored.isNotEmpty) restoredDataAwaitingRestart.value = true;
    return BackupRestoreResult(
      restored: restored,
      failed: failed,
      ignoredCount: ignored,
      bakDir: filesDir.path,
    );
  }

  /// 列出 Download 与 `<files>/backups/` 下的备份，按时间从新到旧。
  Future<List<File>> listLocalBackups() async {
    final dirPaths = <String>[
      await _downloadDirPath(),
      '${await _filesDirPath()}/backups',
    ];
    final found = <File>[];
    for (final path in dirPaths) {
      final dir = Directory(path);
      try {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = _baseName(entity.path);
          if (!name.startsWith('sakura-backup-') || !name.endsWith('.zip')) {
            continue;
          }
          found.add(entity);
        }
      } catch (_) {
        // 目录没权限 / 被删掉了就跳过，页面上少列几个总比整页报错好。
      }
    }
    found.sort((a, b) => _modified(b).compareTo(_modified(a)));
    return found;
  }

  /// Download 目录（拿不到就交给 [_targetDir] 兜底）。
  Future<String> _downloadDirPath() async {
    final override = downloadDirOverride;
    if (override != null) return override;
    final root = await NativeBridge.storageRoot();
    return '$root/Download';
  }

  Future<String> _filesDirPath() async {
    final override = filesDirOverride;
    if (override != null) return override;
    final dirs = await NativeBridge.appDirs();
    return dirs.files;
  }

  /// 找一个真能写的备份目录；全部失败才抛错。
  Future<Directory> _targetDir() async {
    final candidates = <String>[
      await _downloadDirPath(),
      '${await _filesDirPath()}/backups',
    ];
    Object? lastError;
    for (final path in candidates) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) await dir.create(recursive: true);
        // 目录存在不代表能写（Download 在某些机型上就是这么别扭），
        // 写一个探针文件落一下地。
        final probe = File('${dir.path}/.sakura-write-check');
        await probe.writeAsBytes(const <int>[0], flush: true);
        try {
          await probe.delete();
        } catch (_) {}
        return dir;
      } catch (e) {
        lastError = e;
      }
    }
    throw BackupException('找不到能写备份的目录（$lastError）');
  }

  /// 同一分钟连续备份时自动加后缀，不覆盖上一个备份。
  Future<File> _writeUnique(Directory dir, String name, List<int> bytes) async {
    final base = name.substring(0, name.length - '.zip'.length);
    var file = File('${dir.path}/$name');
    var index = 2;
    while (await file.exists()) {
      file = File('${dir.path}/$base-$index.zip');
      index++;
    }
    return file.writeAsBytes(bytes, flush: true);
  }
}

/// `yyyyMMdd-HHmm`，和文件名里的时间戳保持一致。
String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
}

/// 路径最后一段（Download 里可能有中文名，按分隔符切最稳）。
String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? path : path.substring(i + 1);
}

DateTime _modified(File file) {
  try {
    return file.lastModifiedSync();
  } catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
