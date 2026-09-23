import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/epub_parser.dart';
import 'package:sakura_read/src/data/natural_sort.dart';
import 'package:sakura_read/src/data/txt_parser.dart';

void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();

  group('TXT 解析', () {
    test('UTF-8：编码检测 + 章节切分', () {
      final r = TxtParser.parseBytes(fixture('novel_utf8.txt'));
      expect(r.encoding, 'utf-8');
      expect(r.chapters.length, 5);
      expect(r.chapters.first.title, startsWith('序章'));
      expect(r.chapters[1].title, contains('第一章'));
      expect(r.chapters.last.title, contains('第四章'));

      // 章节范围有效且内容匹配
      final ch = r.chapters[1];
      expect(ch.end > ch.start, true);
      final content = r.text.substring(ch.start, ch.end);
      expect(content.contains('借书证'), true);
    });

    test('GBK：编码检测 + 内容正确', () {
      final r = TxtParser.parseBytes(fixture('novel_gbk.txt'));
      expect(r.encoding, 'gbk');
      expect(r.chapters.length, 5);
      expect(r.text.contains('樱花'), true);
      expect(r.text.contains('星夜列车'), true);
      expect(r.text.contains('\uFFFD'), false);
    });

    test('无章节文本 → 单章「全文」', () {
      final r = TxtParser.parseText('这是一段没有任何章节标题的文字。${'很久很久以前。' * 60}');
      expect(r.chapters.length, 1);
      expect(r.chapters.first.title, '全文');
      expect(r.chapters.first.start, 0);
      expect(r.chapters.first.end, r.text.length);
    });

    test('章节标题误报防护：正文句子不被当作标题', () {
      const text =
          '第一章 开始\n'
          '　　他走过去，发现那一章的内容其实都在第三章里。\n'
          '第三章 重逢\n'
          '　　他们终于再见了。\n第四章 终局\n结束了。\n';
      final r = TxtParser.parseText(text);
      expect(r.chapters.length, 3);
      expect(r.chapters[0].title, '第一章 开始');
      expect(r.chapters[1].title, '第三章 重逢');
      expect(r.chapters[2].title, '第四章 终局');
    });
  });

  group('EPUB 解析', () {
    test('EPUB3：元数据 / nav 目录 / 封面 / 正文', () {
      final r = EpubParser.parse(fixture('novel_epub3.epub'));
      expect(r.meta.title, '星夜下的约定');
      expect(r.meta.author, '樱井小夜');
      expect(r.meta.intro.contains('轻小说'), true);
      expect(r.chapters.length, 5);
      expect(r.chapters.first.title, contains('序章'));
      expect(r.chapters[1].title, contains('第一章'));
      expect(r.chapters[1].text.contains('借书证'), true);
      expect(r.chapters.first.charCount > 100, true);

      // 封面是 PNG
      expect(r.coverBytes, isNotNull);
      expect(r.coverBytes!.length > 100, true);
      expect(r.coverBytes![0], 0x89);
    });

    test('EPUB2：ncx 目录 + meta cover + 文本提取', () {
      final r = EpubParser.parse(fixture('novel_epub2.epub'));
      expect(r.meta.title, '星夜下的约定');
      expect(r.meta.author, '樱井小夜');
      expect(r.chapters.length, 5);
      expect(r.chapters.last.title.contains('第四章'), true);
      expect(
        r.chapters.last.text.contains('樱花') || r.chapters.last.text.isNotEmpty,
        true,
      );
      expect(r.coverBytes, isNotNull);
    });

    test('HTML 片段提取：段落与标签处理', () {
      const html =
          '<html><head><style>p{color:red}</style></head>'
          '<body><h1>标题</h1><p>第一段。</p><p>第二段<br/>换行。</p>'
          '<script>var a=1;</script><p>  </p></body></html>';
      final text = EpubParser.extractText(html);
      expect(text.contains('标题'), true);
      expect(text.contains('第一段。'), true);
      expect(text.contains('第二段'), true);
      expect(text.contains('var a=1'), false);
      expect(text.contains('color:red'), false);
    });
  });

  test('自然排序（章节标题）', () {
    final list = ['第10章', '第2章', '第1章', '第20章'];
    list.sort(naturalCompare);
    expect(list, ['第1章', '第2章', '第10章', '第20章']);
  });
}
