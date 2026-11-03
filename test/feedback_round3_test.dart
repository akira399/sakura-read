import 'package:sakura_read/src/source/source_store.dart';

// 酷安反馈（第 23 轮）里可纯逻辑验证的点的回归测试。
//
//   ① 书架自定义分组：Book.group 的 JSON 往返 + BookStore.setGroup 落盘；
//   ② 书源搜索并发数：默认 8、clamp 到 1~999、持久化、同步到 OnlineRepo；
//   ③ 桌宠全局开关：petHidden 默认 false、可持久化；
//   ④ TTS 语速上限放宽到 3.0（用户：倍速能加到 3 倍吗）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/online_repo.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/source/http_client.dart';

/// 等 prefs / pet store 的防抖落盘。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 700));

AppDirs _tempDirs(List<Directory> trash) {
  final dir = Directory.systemTemp.createTempSync('sakura_fb3_');
  trash.add(dir);
  return AppDirs(files: dir.path, cache: '${dir.path}/cache');
}

Book _book({String id = 'b1', String group = ''}) => Book(
  id: id,
  title: '测试书',
  author: '作者',
  format: BookFormat.txt,
  path: '${Directory.systemTemp.path}/novel.txt',
  chapters: [
    ChapterRef(title: '第1章 开始', start: 0, end: 10, charCount: 10),
    ChapterRef(title: '第2章 继续', start: 10, end: 20, charCount: 10),
  ],
  totalChars: 20,
  addedAt: 1700000000000,
  group: group,
);

/// 直接写一份 books.json，避免依赖导入流程。
void _seedBooks(AppDirs dirs, List<Book> books) {
  File('${dirs.files}/library.json').writeAsStringSync(
    jsonEncode({'version': 1, 'books': books.map((b) => b.toJson()).toList()}),
  );
}

void main() {
  final trash = <Directory>[];
  tearDown(() {
    for (final d in trash) {
      try {
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
    trash.clear();
    OnlineRepo.defaultConcurrency = 8;
  });

  group('书架分组', () {
    test('group 参与 JSON 往返，旧数据没有该字段时为空串', () {
      final b = _book(group: '玄幻');
      final back = Book.fromJson(b.toJson());
      expect(back.group, '玄幻');
      expect(_book().group, isEmpty);

      final legacy = b.toJson()..remove('group');
      expect(Book.fromJson(legacy).group, isEmpty);
    });

    test('setGroup 修改后写入library.json，重新加载仍在', () async {
      final dirs = _tempDirs(trash);
      _seedBooks(dirs, [_book()]);
      final store = BookStore(dirsOverride: dirs);
      await store.load();
      expect(store.byId('b1')!.group, isEmpty);

      store.setGroup('b1', ' 科幻 ');
      await _settle();

      final again = BookStore(dirsOverride: dirs);
      await again.load();
      expect(again.byId('b1')!.group, '科幻');
    });

    test('setGroup 传空串等于取消分组', () async {
      final dirs = _tempDirs(trash);
      _seedBooks(dirs, [_book(group: '玄幻')]);
      final store = BookStore(dirsOverride: dirs);
      await store.load();
      store.setGroup('b1', '');
      expect(store.byId('b1')!.group, isEmpty);
    });
  });

  group('书源搜索并发数', () {
    test('默认 8，也可调到 1 和 999', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      expect(prefs.searchConcurrency, 8);

      prefs.setSearchConcurrency(1);
      expect(prefs.searchConcurrency, 1);

      prefs.setSearchConcurrency(999);
      expect(prefs.searchConcurrency, 999);
    });

    test('超出 1~999 会被裁剪', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      prefs.setSearchConcurrency(0);
      expect(prefs.searchConcurrency, 1);
      prefs.setSearchConcurrency(5000);
      expect(prefs.searchConcurrency, 999);
    });

    test('设置后同步给 OnlineRepo 默认值并持久化', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      prefs.setSearchConcurrency(3);
      await _settle();
      expect(OnlineRepo.defaultConcurrency, 3);

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.searchConcurrency, 3);
      expect(OnlineRepo.defaultConcurrency, 3);
    });

    test('设置 999 后已打开的默认搜索仓库也采用 999', () async {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      final repo = OnlineRepo(store: SourceStore(initial: []));
      prefs.setSearchConcurrency(999);
      expect(prefs.searchConcurrency, 999);
      expect(OnlineRepo.defaultConcurrency, 999);
      expect(repo.concurrency, 999);
      repo.dispose();
    });

    test('并发 999 会实际派发给最多 999 个启用书源（只用 MockClient）', () async {
      var requests = 0;
      final sources = [
        for (var i = 0; i < 1000; i++)
          BookSource.fromJson({
            'bookSourceUrl': 'https://parallel-$i.example',
            'bookSourceName': '并发源 $i',
            'searchUrl': '/search?q={{key}}',
            'ruleSearch': <String, dynamic>{},
          }),
      ];
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      prefs.setSearchConcurrency(999);
      final repo = OnlineRepo(
        store: SourceStore(initial: sources),
        client: SourceHttpClient(
          client: MockClient((_) async {
            requests++;
            return http.Response('<html></html>', 200);
          }),
        ),
      );
      try {
        final results = await repo.searchAll('验收');
        expect(repo.concurrency, 999);
        expect(requests, 1000);
        expect(results, hasLength(1000));
      } finally {
        repo.dispose();
      }
    });

    test('老版本设置文件没有该键时用默认 8，不崩', () async {
      final dirs = _tempDirs(trash);
      File('${dirs.files}/settings.json').writeAsStringSync(
        '{"fontSize":18,"volumeKeyPaging":true,"xrayHighlight":true}',
      );
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      expect(prefs.searchConcurrency, 8);
    });
  });

  group('桌宠开关', () {
    test('默认不隐藏，setPetHidden 后可持久化', () async {
      final dirs = _tempDirs(trash);
      final pet = PetStore(dirsOverride: dirs);
      await pet.load();
      expect(pet.petHidden, isFalse);

      pet.setPetHidden(true);
      await _settle();

      final again = PetStore(dirsOverride: dirs);
      await again.load();
      expect(again.petHidden, isTrue);
    });
  });

  group('朗读语速上限', () {
    test('默认 1.0，可调到 3.0（用户要求 3 倍速）', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      expect(prefs.ttsRate, 1.0);
      prefs.setTtsRate(3.0);
      expect(prefs.ttsRate, 3.0);
    });

    test('超过 3.0 被裁剪到 3.0', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      prefs.setTtsRate(5.0);
      expect(prefs.ttsRate, 3.0);
    });
  });
}
