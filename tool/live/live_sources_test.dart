// 真机网络冒烟（人工执行，不进常规测试集）：
// 对内置源跑一次**真实联网**搜索，验证「令牌 + POST」链路在线上可用。
//
// 运行：flutter test tool/live/live_sources_test.dart
// 说明：
//   - 本文件位于 tool/ 下，`flutter test` 默认只扫 test/ 目录，不会连带跑它；
//   - 需要联网；网络异常时跳过（避免误报失败）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

Future<bool> _online() async {
  try {
    final s = await Socket.connect(
      'www.bqgiu.cc',
      443,
      timeout: const Duration(seconds: 6),
    );
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  // flutter_test 默认拦截网络；这里显式放行，做真实请求。
  setUpAll(() {
    HttpOverrides.global = null;
  });

  test('真实联网：三个源都能搜到书（令牌 + POST 全链路）', () async {
    final raw = await File(
      'assets/sources/builtin_sources.json',
    ).readAsString();
    final sources = BookSource.listFromJson(jsonDecode(raw));

    if (!await _online()) {
      markTestSkipped('无网络，跳过真实联网冒烟');
      return;
    }

    final cases = <String, String>{
      'https://www.hkmtxt.cc': '完美世界',
      'https://www.bqgiu.cc': '斗破',
      'https://zh.wikisource.org': '論語',
    };

    for (final entry in cases.entries) {
      final src = sources.firstWhere((s) => s.bookSourceUrl == entry.key);
      final repo = OnlineRepo(
        store: SourceStore(initial: [src]),
        perSourceTimeout: const Duration(seconds: 20),
      );
      final r = (await repo.searchAll(entry.value)).single;
      expect(r.ok, isTrue, reason: '${src.bookSourceName} 搜索失败：${r.error}');
      expect(
        r.books,
        isNotEmpty,
        reason: '${src.bookSourceName} 搜索「${entry.value}」0 本',
      );
      // 打印前 3 个结果，便于人工核对
      // ignore: avoid_print
      print(
        '✅ ${src.bookSourceName}「${entry.value}」→ ${r.books.length} 本 '
        '(${r.elapsedMs}ms)：'
        '${r.books.take(3).map((b) => b.name).join(" / ")}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
