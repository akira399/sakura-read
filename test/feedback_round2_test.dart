// 社区反馈第二轮功能的回归测试。
//
// 覆盖用户反馈里这些可以纯逻辑验证的点：
//   ① 音量键翻页开关：默认关闭、可持久化；
//   ② 书架「大封面」样式：枚举与存储字符串互转；
//   ③ 段间距 / 行距下限（用户：间距还是有点大）；
//   ④ 移除书籍时可选择删除本地文件；
//   ⑤ 目录识别收紧：纯数字行不再被当成章节（用户：0 都被识别成目录章节）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/shelf_sort.dart';
import 'package:sakura_read/src/data/txt_parser.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';

/// 等 prefs 的 300ms 防抖落盘。
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 450));

/// 建一个临时目录并登记清理。
AppDirs _tempDirs(List<Directory> trash) {
  final dir = Directory.systemTemp.createTempSync('sakura_fb2_');
  trash.add(dir);
  return AppDirs(files: dir.path, cache: '${dir.path}/cache');
}

/// 生成一段最简单的多章小说文本。
String _novel({int chapters = 3}) => [
  for (var i = 1; i <= chapters; i++)
    '第$i章 测试章节$i\n这是第$i章的正文内容，用来验证解析与导入。',
].join('\n');

void main() {
  final trash = <Directory>[];
  tearDown(() {
    for (final d in trash) {
      try {
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
    trash.clear();
  });

  group('音量键翻页开关', () {
    test('默认开启（用户要求：装上就能用音量键翻页）', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      expect(prefs.volumeKeyPaging, isTrue);
    });

    test('设置后写入 settings.json，重新加载能读回', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      prefs.setVolumeKeyPaging(false);
      await _settle();

      final raw =
          jsonDecode(File('${dirs.files}/settings.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(raw['volumeKeyPaging'], isFalse);

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.volumeKeyPaging, isFalse);
    });

    test('老版本设置文件（无该键）不会崩，按默认值处理', () async {
      final dirs = _tempDirs(trash);
      File('${dirs.files}/settings.json')
          .writeAsStringSync(jsonEncode({'v': 2, 'fontSize': 20}));

      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      expect(prefs.volumeKeyPaging, isTrue);
      expect(prefs.fontSize, 20);
    });
  });

  group('书架「大封面」样式', () {
    test('cover 能存能读（用户想要 reeden 那种大封面书架）', () {
      expect(ShelfViewMode.cover.label, '大封面');
      expect(shelfViewModeFrom('cover'), ShelfViewMode.cover);
      expect(shelfViewModeFrom('grid'), ShelfViewMode.grid);
      // 未知值回退网格，不能抛异常
      expect(shelfViewModeFrom('nope'), ShelfViewMode.grid);
      expect(shelfViewModeFrom(null), ShelfViewMode.grid);
    });

    test('全部显示方式都有中文标签与唯一 name', () {
      final names = ShelfViewMode.values.map((v) => v.name).toSet();
      expect(names.length, ShelfViewMode.values.length);
      for (final v in ShelfViewMode.values) {
        expect(v.label.trim(), isNotEmpty);
      }
    });

    test('选择大封面后能持久化', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      prefs.setShelfView(ShelfViewMode.cover);
      await _settle();

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.shelfView, ShelfViewMode.cover);
    });
  });

  group('排版：段间距与行距下限', () {
    test('段间距默认 12，可调到 0（完全紧贴）', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      expect(prefs.paragraphSpacing, 12);
      prefs.setParagraphSpacing(0);
      expect(prefs.paragraphSpacing, 0);
      await _settle();

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.paragraphSpacing, 0);
    });

    test('段间距上限 40，超出被裁剪（防止盘面被撑爆）', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      prefs.setParagraphSpacing(999);
      expect(prefs.paragraphSpacing, 40);
      prefs.setParagraphSpacing(-5);
      expect(prefs.paragraphSpacing, 0);
    });

    test('行距可以低于 1.2（用户反馈间距还是有点大）', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      prefs.setLineHeight(1.1);
      expect(prefs.lineHeight, 1.1);
      // 下限 1.0：再小文字会重叠到不可读
      prefs.setLineHeight(0.1);
      expect(prefs.lineHeight, 1.0);
    });
  });

  group('移除书籍时可删除本地文件', () {
    test('deleteLocalFile=true 会删掉源文件与记录', () async {
      final dirs = _tempDirs(trash);
      final file = File('${dirs.files}/novel_fb2.txt');
      file.writeAsStringSync(_novel());

      final store = BookStore(dirsOverride: dirs);
      await store.load();
      final result = await store.importFile(file.path);
      expect(result.success, isTrue, reason: result.error);
      final book = result.book!;
      expect(file.existsSync(), isTrue);

      await store.removeById(book.id, deleteLocalFile: true);
      expect(store.byId(book.id), isNull);
      expect(file.existsSync(), isFalse);
    });

    test('默认 deleteLocalFile=false：只从书架移除，文件留着', () async {
      final dirs = _tempDirs(trash);
      final file = File('${dirs.files}/novel_keep.txt');
      file.writeAsStringSync(_novel());

      final store = BookStore(dirsOverride: dirs);
      await store.load();
      final book = (await store.importFile(file.path)).book!;
      await store.removeById(book.id);

      expect(store.byId(book.id), isNull);
      expect(file.existsSync(), isTrue, reason: '默认不删源文件，用户的原书不能丢');
    });

    test('在线书没有本地文件，删除时不应抛异常', () async {
      final dirs = _tempDirs(trash);
      final store = BookStore(dirsOverride: dirs);
      await store.load();
      final book = store.addOnline(
        Book(
          id: 'fb2online',
          title: '在线书',
          author: '作者',
          format: BookFormat.online,
          path: 'https://example.com/book/1',
          sourceUrl: 'https://example.com',
        ),
      );

      await store.removeById(book.id, deleteLocalFile: true);
      expect(store.byId(book.id), isNull);
    });
  });

  group('目录识别收紧（用户：0 都被识别成目录章节）', () {
    /// 解析一段文本，返回章节标题列表。
    List<String> titles(String text) =>
        TxtParser.parseText(text).chapters.map((c) => c.title).toList();

    test('纯数字 / 纯符号行不再当成章节', () {
      final text = [
        '第1章 开端',
        '正文内容在这里，很正常的一段话，说明这一章还没结束。',
        '0',
        '123',
        '...',
        '第2章 继续',
        '又是一段正文内容，同样是一段普通的话。',
      ].join('\n');
      final got = titles(text);
      expect(got, contains('第1章 开端'));
      expect(got, contains('第2章 继续'));
      expect(got, isNot(contains('0')));
      expect(got, isNot(contains('123')));
      expect(got, isNot(contains('...')));
    });

    test('带正文缩进的行即使像标题也不当章节', () {
      final text = [
        '第1章 开端',
        '正文第一段，这里是很普通的叙述文字。',
        '　　第2章 这句话是正文里的引用，并不是真的标题',
        '正文第二段，继续讲普通的故事内容。',
        '第3章 后来',
        '第三章正文，故事继续往下走。',
        '第4章 结局',
        '全书的最后一段正文内容。',
      ].join('\n');
      final result = TxtParser.parseText(text);
      final got = result.chapters.map((c) => c.title).toList();
      // 缩进的「第2章 …」属于正文，不能单独成章：只有 1/3/4 三章。
      expect(got, ['第1章 开端', '第3章 后来', '第4章 结局']);
      expect(
        result.text.substring(result.chapters[0].start, result.chapters[0].end),
        contains('这句话是正文里的引用'),
        reason: '这段文字仍然要留在正文里，不能被吞掉',
      );
    });

    test('【】标题仍然支持', () {
      final text = ['【序】', '序章正文，几句话铺垫一下。', '【第一章 归来】', '正文内容。']
          .join('\n');
      final got = titles(text);
      expect(got, contains('【序】'));
      expect(got, contains('【第一章 归来】'));
    });

    test('正常 200 章小说全部识别，不多不少', () {
      final text = [
        for (var i = 1; i <= 200; i++)
          '第$i章 测试章节$i\n这是第$i章的正文内容，小樱正在测试章节目录。',
      ].join('\n');
      final got = TxtParser.parseText(text).chapters;
      expect(got.length, 200);
      expect(got.first.title, contains('第1章'));
      expect(got.last.title, contains('第200章'));
    });
  });
}
