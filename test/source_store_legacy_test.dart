// 书源仓库升级逻辑：内置源更新 + 历史盗版源清理。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/source_store.dart';

/// 临时目录（模拟 App files 目录）。
Directory _tmpDir(String tag) {
  final dir = Directory.systemTemp.createTempSync('sakura_src_$tag');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // 忽略清理失败
    }
  });
  return dir;
}

AppDirs _dirsOf(Directory d) => AppDirs(files: d.path, cache: d.path);

void main() {
  test('首次启动：全量导入内置（公版）源', () async {
    final dir = _tmpDir('first');
    final store = SourceStore(dirsOverride: _dirsOf(dir));
    await store.load();
    expect(store.isEmpty, isTrue);

    // 直接走导入路径（等价于 ensureBuiltinSources 的核心行为）
    final text = await File(
      'assets/sources/builtin_sources.json',
    ).readAsString();
    final report = store.importFromText(text);
    await store.flush();

    expect(report.added, greaterThan(0));
    expect(
      store.sources.every((s) => s.bookSourceUrl.contains('wikisource')),
      isTrue,
    );
    // 落盘为文件（下次启动可读回）
    final saved = File('${dir.path}/book_sources.json');
    expect(saved.existsSync(), isTrue);
    final decoded = jsonDecode(await saved.readAsString()) as Map;
    expect((decoded['sources'] as List), isNotEmpty);
  });

  test('升级：旧的内置盗版源被清理，用户自建源不受影响', () async {
    final dir = _tmpDir('upgrade');
    // 预置一份「老版本」书源文件：两个盗版内置源 + 一个用户自己导入的源
    final old = File('${dir.path}/book_sources.json');
    await old.writeAsString(
      jsonEncode({
        'version': 1,
        'sources': [
          BookSource(
            bookSourceUrl: 'https://www.hkmtxt.cc',
            bookSourceName: '好看吗 (hkmtxt)',
          ).toJson(),
          BookSource(
            bookSourceUrl: 'https://www.bqgiu.cc',
            bookSourceName: '笔趣阁 (bqgiu)',
          ).toJson(),
          BookSource(
            bookSourceUrl: 'https://my-own-source.example',
            bookSourceName: '用户自建源',
          ).toJson(),
        ],
      }),
    );

    final store = SourceStore(dirsOverride: _dirsOf(dir));
    await store.load();
    expect(store.sources.length, 3);

    // 模拟 ensureBuiltinSources：读内置资产 → 清理 legacy → 导入
    final builtinJson = await File(
      'assets/sources/builtin_sources.json',
    ).readAsString();
    final legacy = <String>{};
    for (final item in jsonDecode(builtinJson) as List) {
      final v = (item as Map)['legacyBuiltinUrls'];
      if (v is List) legacy.addAll(v.map((e) => e.toString()));
    }
    expect(legacy, isNotEmpty, reason: '内置资产应带 legacy 清单');

    for (final url in legacy) {
      store.remove(url);
    }
    store.importFromText(builtinJson);
    await store.flush();

    final urls = store.sources.map((s) => s.bookSourceUrl).toList();
    expect(urls, isNot(contains('https://www.hkmtxt.cc')));
    expect(urls, isNot(contains('https://www.bqgiu.cc')));
    expect(urls, contains('https://my-own-source.example'));
    expect(urls, contains('https://zh.wikisource.org'));
  });

  test('重复升级是幂等的（不会重复添加内置源）', () async {
    final dir = _tmpDir('idem');
    final store = SourceStore(dirsOverride: _dirsOf(dir));
    await store.load();
    final text = await File(
      'assets/sources/builtin_sources.json',
    ).readAsString();

    final first = store.importFromText(text);
    final count = store.sources.length;
    final second = store.importFromText(text);

    expect(first.added, count);
    expect(second.added, 0);
    expect(store.sources.length, count);
  });

  test('同地址更新会保留用户的启用状态', () async {
    final dir = _tmpDir('keep');
    final store = SourceStore(dirsOverride: _dirsOf(dir));
    await store.load();
    final text = await File(
      'assets/sources/builtin_sources.json',
    ).readAsString();
    store.importFromText(text);

    // 用户手动停用了第一个源
    final url = store.sources.first.bookSourceUrl;
    store.setEnabled(url, false);
    expect(store.byUrl(url)!.enabled, isFalse);

    // 再次导入（模拟版本升级更新内置源）
    store.importFromText(text);
    expect(store.byUrl(url)!.enabled, isFalse, reason: '应保留用户的停用选择');
  });
}
