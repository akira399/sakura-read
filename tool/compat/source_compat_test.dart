// 书源兼容性基准测试（真实网络）。
//
// 用法：
//   $env:SAKURA_PACK = 'D:\sdk\src1298.json'
//   flutter test tool/compat/source_compat_test.dart -r expanded
//
// 每个书源跑「搜索 → 详情（目录）→ 第一章正文」三步，打印每一步的结果，
// 用来对照 yckceo 等公开书源仓库定位兼容性问题。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_book_service.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  test('source compat bench', () async {
    final path = Platform.environment['SAKURA_PACK'] ?? r'D:\sdk\src1298.json';
    final key = Platform.environment['SAKURA_KEY'] ?? '诡秘之主';
    final file = File(path);
    if (!file.existsSync()) {
      fail('找不到书源文件：$path');
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! List) fail('书源文件应为 JSON 数组');
    final sources = raw
        .whereType<Map>()
        .map((m) => BookSource.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final store = SourceStore(initial: sources);
    final repo = OnlineRepo(store: store);
    final service = OnlineBookService();

    stdout.writeln('pack=$path sources=${sources.length} key=$key');
    for (final s in sources) {
      final watch = Stopwatch()..start();
      String status;
      try {
        final r = await repo.searchOne(s, key);
        if (r.error != null) {
          status = 'SEARCH-ERR ${r.error}';
        } else if (r.books.isEmpty) {
          status = 'SEARCH-EMPTY';
        } else {
          final first = r.books.firstWhere(
            (b) => b.bookUrl != null && b.bookUrl!.isNotEmpty,
            orElse: () => r.books.first,
          );
          if (first.bookUrl == null || first.bookUrl!.isEmpty) {
            status = 'SEARCH-OK(${r.books.length}) 但无 bookUrl';
          } else {
            final info = await service.fetchInfo(s, first.bookUrl!);
            final chapters = info.chapters;
            if (chapters.isEmpty) {
              status = 'TOC-EMPTY  (book=${first.name})';
            } else {
              String textState;
              try {
                final text = await service.fetchChapterText(
                  s,
                  chapters.first.href ?? '',
                );
                final n = text.replaceAll(RegExp(r'\s'), '').length;
                textState = n == 0 ? 'TEXT-EMPTY' : 'text=$n字';
              } catch (e) {
                textState = 'TEXT-ERR $e';
              }
              status =
                  'OK books=${r.books.length} toc=${chapters.length} $textState';
            }
          }
        }
      } catch (e) {
        status = 'FAIL $e';
      }
      watch.stop();
      stdout.writeln(
        '${s.bookSourceName.padRight(20)} ${watch.elapsedMilliseconds}ms  $status',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
