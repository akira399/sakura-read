// 「从『阅读』备份导入书架」纯逻辑测试：备份解析容错 + 候选匹配打分。
//
// 不联网：这里只测 parseBackup / matchScore / readBackupFile（本地临时文件），
// 搜索书源和抓目录走网络，放到手测里验证。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/legado_import.dart';

LegadoBook _target({String name = '诡秘之主', String author = '爱潜水的乌贼'}) =>
    LegadoBook(name: name, author: author);

void main() {
  group('parseBackup 解析容错', () {
    test('正常备份：字段都取到，顺序不变', () {
      final text = jsonEncode({
        'books': [
          {
            'name': '诡秘之主',
            'author': '爱潜水的乌贼',
            'bookUrl': 'https://a.com/book/1',
            'origin': 'https://a.com',
            'originName': '源A',
            'durChapterIndex': 12,
            'durChapterTitle': '第13章',
            'intro': '很长很长的简介',
            'coverUrl': 'https://a.com/1.jpg',
          },
          {'name': '   ', 'author': '空白书名'}, // 名字空白：跳过
          {'author': '没有书名'}, // 没名字：跳过
          {'name': '第二本'},
        ],
      });

      final books = LegadoImporter.parseBackup(text);
      expect(books, hasLength(2));

      final first = books.first;
      expect(first.name, '诡秘之主');
      expect(first.author, '爱潜水的乌贼');
      expect(first.bookUrl, 'https://a.com/book/1');
      expect(first.origin, 'https://a.com');
      expect(first.originName, '源A');
      expect(first.durChapterIndex, 12);
      expect(first.durChapterTitle, '第13章');
      expect(first.intro, '很长很长的简介');
      expect(first.coverUrl, 'https://a.com/1.jpg');
      expect(books.last.name, '第二本');
    });

    test('带 UTF-8 BOM 也能解析', () {
      final text =
          '\uFEFF${jsonEncode({
            'books': [
              {'name': '带 BOM 的书'},
            ],
          })}';
      final books = LegadoImporter.parseBackup(text);
      expect(books.single.name, '带 BOM 的书');
    });

    test('字段缺失 / 类型不对时给安全默认值', () {
      final text = jsonEncode({
        'books': [
          {'name': '缺字段的书'},
          {'name': 123, 'author': 45, 'durChapterIndex': '7', 'intro': null},
          {'name': '小数进度', 'durChapterIndex': 3.9},
        ],
      });

      final books = LegadoImporter.parseBackup(text);
      expect(books, hasLength(3));

      final missing = books[0];
      expect(missing.author, '');
      expect(missing.durChapterIndex, 0);
      expect(missing.intro, '');

      final wrongType = books[1];
      expect(wrongType.name, '123');
      expect(wrongType.author, '45');
      expect(wrongType.durChapterIndex, 7);
      expect(wrongType.intro, '');

      expect(books[2].durChapterIndex, 3);
    });

    test('books 为空 / 顶层不是对象 / 不是 json：都返回空列表', () {
      expect(LegadoImporter.parseBackup('{"books": []}'), isEmpty);
      expect(LegadoImporter.parseBackup('{"bookProgress": []}'), isEmpty);
      expect(LegadoImporter.parseBackup('[]'), isEmpty);
      expect(LegadoImporter.parseBackup('"hello"'), isEmpty);
      expect(LegadoImporter.parseBackup('not json at all'), isEmpty);
      expect(LegadoImporter.parseBackup(''), isEmpty);
      expect(LegadoImporter.parseBackup('  \n\t '), isEmpty);
      expect(LegadoImporter.parseBackup('\uFEFF'), isEmpty);
    });

    test('books 里混入非对象项时跳过，不影响别的书', () {
      final text = jsonEncode({
        'books': [
          1,
          'x',
          null,
          {'name': '能活下来'},
        ],
      });
      final books = LegadoImporter.parseBackup(text);
      expect(books.single.name, '能活下来');
    });
  });

  group('matchScore 候选匹配', () {
    test('书名归一化后完全一致最高，精确 > 包含', () {
      final target = _target();
      final exact = LegadoImporter.matchScore(target, name: '诡秘之主', author: '');
      final partial = LegadoImporter.matchScore(
        target,
        name: '诡秘之主（完本）',
        author: '',
      );
      expect(exact, 100);
      expect(partial, 60);
      expect(exact, greaterThan(partial));
      // 空格 / 大小写不影响判断。
      expect(
        LegadoImporter.matchScore(
          _target(name: 'The Great', author: ''),
          name: 'the great',
          author: '',
        ),
        100,
      );
      expect(LegadoImporter.matchScore(target, name: '诡秘 之主', author: ''), 100);
    });

    test('作者一致再 +30，够得着合格线', () {
      final target = _target();
      expect(
        LegadoImporter.matchScore(target, name: '诡秘之主', author: '爱潜水的乌贼'),
        130,
      );
      expect(
        LegadoImporter.matchScore(target, name: '诡秘之主：番外', author: '爱潜水的乌贼'),
        90,
      );
      // 书名对上、作者对不上：不加分。
      expect(
        LegadoImporter.matchScore(target, name: '诡秘之主', author: '别人'),
        100,
      );
    });

    test('不相关的书分数很低，过不了 60 的合格线', () {
      final target = _target();
      expect(
        LegadoImporter.matchScore(target, name: '斗破苍穹', author: '天蚕土豆'),
        0,
      );
      // 只有作者撞上、书名无关：加成也到不了合格线。
      expect(
        LegadoImporter.matchScore(target, name: '别的书', author: '爱潜水的乌贼'),
        lessThan(LegadoImporter.matchThreshold),
      );
      // 空书名 / 空作者不参与比较（两个都没作者不算「相等」）。
      expect(LegadoImporter.matchScore(target, name: '', author: ''), 0);
      expect(
        LegadoImporter.matchScore(
          _target(author: ''),
          name: '诡秘之主',
          author: '爱潜水的乌贼',
        ),
        100,
      );
    });

    test('合格线是 60', () {
      expect(LegadoImporter.matchThreshold, 60);
      expect(LegadoImporter.maxBackupBytes, 20 * 1024 * 1024);
    });
  });

  group('readBackupFile 文件容错', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('legado_import_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('文件不存在：返回中文提示而不是抛异常', () async {
      final read = await LegadoImporter.readBackupFile(
        '${tempDir.path}/nope.json',
      );
      expect(read.ok, isFalse);
      expect(read.books, isEmpty);
      expect(read.error, contains('没找到'));
    });

    test('空路径 / 非 UTF-8 / 不是备份 json：都给出可读原因', () async {
      expect((await LegadoImporter.readBackupFile('   ')).ok, isFalse);

      final binary = File('${tempDir.path}/binary.json');
      await binary.writeAsBytes([0xFF, 0xFE, 0x00, 0x01]);
      final binaryRead = await LegadoImporter.readBackupFile(binary.path);
      expect(binaryRead.ok, isFalse);
      expect(binaryRead.error, contains('UTF-8'));

      final notBackup = File('${tempDir.path}/other.json');
      await notBackup.writeAsString('{"hello": "world"}');
      final wrongRead = await LegadoImporter.readBackupFile(notBackup.path);
      expect(wrongRead.ok, isFalse);
      expect(wrongRead.error, contains('备份'));
    });

    test('正常备份（带 BOM + 多余引号）：能读出书目', () async {
      final file = File('${tempDir.path}/legado_backup.json');
      await file.writeAsString(
        '\uFEFF${jsonEncode({
          'books': [
            {'name': '诡秘之主', 'author': '爱潜水的乌贼', 'durChapterIndex': 3},
          ],
        })}',
      );

      // 用户从文件管理器复制路径时常带引号，这里模拟一下。
      final read = await LegadoImporter.readBackupFile('"${file.path}"');
      expect(read.ok, isTrue, reason: read.error ?? '');
      expect(read.books.single.name, '诡秘之主');
      expect(read.books.single.durChapterIndex, 3);
    });
  });
}
