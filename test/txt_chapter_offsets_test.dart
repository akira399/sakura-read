import 'dart:convert';
import 'dart:io';


import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_source.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/txt_parser.dart';

void main() {
  test('CRLF 文本的章节切片不会逐章偏移', () async {
    final buffer = StringBuffer();
    for (var i = 1; i <= 130; i++) {
      buffer.write('第$i章 测试章节$i\r\n');
      buffer.write('这是第$i章的正文内容。小樱正在测试章节目录的定位功能。\r\n');
      buffer.write('\r\n');
    }
    final dir = Directory.systemTemp.createTempSync('sakura_txt_test_');
    final file = File('${dir.path}/crlf.txt');
    file.writeAsStringSync(buffer.toString(), encoding: utf8);

    final parsed = TxtParser.parseBytes(file.readAsBytesSync());
    expect(parsed.chapters.length, 130);

    final book = Book(
      id: 'crlf',
      title: 'crlf',
      format: BookFormat.txt,
      path: file.path,
      chapters: [
        for (final c in parsed.chapters)
          ChapterRef(title: c.title, start: c.start, end: c.end),
      ],
    );
    final content = TxtBookContent(book);
    try {
      final text = await content.chapterText(125);
      expect(text, startsWith('第126章 测试章节126'));
      expect(text, contains('这是第126章的正文内容'));
      final last = await content.chapterText(129);
      expect(last, startsWith('第130章 测试章节130'));
    } finally {
      await content.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
