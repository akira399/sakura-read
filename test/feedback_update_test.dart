import 'package:sakura_read/src/source/online_book_service.dart';
import 'package:sakura_read/src/source/http_client.dart';
import 'package:sakura_read/src/source/models.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sakura_read/src/data/epub_document.dart';
import 'package:sakura_read/src/data/epub_parser.dart';
import 'package:sakura_read/src/data/txt_parser.dart';
import 'package:sakura_read/src/data/legacy_shelf.dart';
import 'package:sakura_read/src/data/library_search.dart';
import 'package:sakura_read/src/data/local_llm.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/subscription_link.dart';

import 'epub_image_test.dart' show buildEpubWithImage;

Uint8List unusualEpub() {
  final archive = ZipDecoder().decodeBytes(buildEpubWithImage());
  final result = Archive();
  for (final file in archive.files) {
    var name = file.name.replaceAll('c1.xhtml', '100%篇.xhtml');
    var bytes = file.content as List<int>;
    if (!file.name.endsWith('.png')) {
      var text = utf8.decode(bytes).replaceAll('c1.xhtml', '100%篇.xhtml');
      text = text.replaceAll(
        '<img src="../images/pic1.png" alt="插图"/>',
        '<svg><image href="../images/pic1.png"/></svg>',
      );
      bytes = utf8.encode(text);
    }
    result.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(result));
}

void main() {
  test('详情封面相对地址得到解析，简介保留换行且不显示 HTML', () async {
    final service = OnlineBookService(
      client: SourceHttpClient(
        client: MockClient(
          (_) async => http.Response(
            '<html><img src="../cover.png"><div id="intro">第一段<br>第二段</div></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      ),
    );
    final source = BookSource.fromJson({
      'bookSourceUrl': 'https://example.test',
      'bookSourceName': 'sample',
      'ruleBookInfo': {'coverUrl': 'tag.img@src', 'intro': 'id.intro@html'},
    });
    final info = await service.fetchInfo(
      source,
      'https://example.test/book/one',
    );
    expect(info.coverUrl, 'https://example.test/cover.png');
    expect(info.intro, contains('第一段\n第二段'));
    service.dispose();
  });
  test('裸百分号、中文 EPUB 路径与 SVG image 正常导入', () {
    final book = EpubParser.parse(unusualEpub());
    expect(book.chapters.single.href, contains('100%篇'));
    expect(book.chapters.single.images, hasLength(1));
    expect(book.chapters.single.text, contains(EpubParser.imageMarkerPrefix));
  });
  test('原书排版保留样式和插图，移除主动脚本；注释可以取回', () {
    const source =
        '<html><head><style>p{font-weight:bold}</style></head><body onload="bad()"><p>正文<img src="p.png"><a href="#n1">[1]</a></p><aside id="n1">这是原书注释内容。</aside><script>bad()</script></body></html>';
    final rendered = prepareEpubHtml(
      source,
      fontSize: 18,
      background: '#fff',
      foreground: '#222',
    );
    expect(rendered, contains('font-weight:bold'));
    expect(rendered, contains('p.png'));
    expect(rendered, isNot(contains('<script')));
    expect(rendered, isNot(contains('onload=')));
    expect(epubNote(source, 'n1'), '这是原书注释内容。');
  });
  test('原书资源解包跳过越界路径', () {
    final archive = Archive()
      ..addFile(ArchiveFile('../outside', 1, [1]))
      ..addFile(ArchiveFile('inside', 1, [2]));
    final resources = unpackEpubDocument(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(resources.keys, ['inside']);
  });
  test('数字加顿号标题形成目录，零散数字正文不会过度切章', () {
    final result = TxtParser.parseText(
      '1、开局就迎来破灭是不是搞错了什么\n　　第一段正文。\n2、下一章\n　　第二段正文。',
    );
    expect(result.chapters, hasLength(2));
    expect(result.chapters.first.title, startsWith('1、'));
    expect(TxtParser.parseText('1、苹果\n正文\n9、香蕉\n正文').chapters, hasLength(1));
  });
  test('阅读订阅协议只接受 HTTP(S) 目标', () {
    expect(
      subscriptionUrl(
        'legado://import/bookSource?src=https%3A%2F%2Fexample.test%2Fsource.json',
      ),
      'https://example.test/source.json',
    );
    expect(
      () => subscriptionUrl('legado://import/bookSource?src=file:///private'),
      throwsFormatException,
    );
  });
  test('阅读 JSON 和 ZIP 书架备份均可解析', () {
    final bytes = utf8.encode(
      '[{"name":"样本","bookUrl":"https://example.test/book","origin":"https://example.test"}]',
    );
    expect(parseLegacyShelf(Uint8List.fromList(bytes)).single['name'], '样本');
    final archive = Archive()
      ..addFile(ArchiveFile('backup/bookshelf.json', bytes.length, bytes));
    expect(
      parseLegacyShelf(Uint8List.fromList(ZipEncoder().encode(archive))),
      hasLength(1),
    );
  });
  test('正文检索返回书名、章节与可跳转字符偏移', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_retrieval');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sample.txt');
    await file.writeAsString('第一章 起点\n她推开窗，看见樱花。\n第二章 重逢\n他也看见樱花。');
    final store = BookStore(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
    );
    await store.load();
    final result = await store.importFile(file.path);
    await store.flush();
    final hits = await LibrarySearch().search(store, '樱花');
    expect(result.success, isTrue);
    expect(hits, hasLength(2));
    expect(hits.map((h) => h.chapter), [0, 1]);
    expect(hits.first.offset, greaterThan(0));
  });
  test('桌宠默认开启，关闭选项跨重启保存', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_pet_optout');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final pet = PetStore(dirsOverride: dirs);
    await pet.load();
    expect(pet.enabled, isTrue);
    pet.setEnabled(false);
    await pet.flush();
    final reloaded = PetStore(dirsOverride: dirs);
    await reloaded.load();
    expect(reloaded.enabled, isFalse);
  });

  for (final ignoresRange in [false, true]) {
    test('模型续传${ignoresRange ? '遇到不支持 Range 时安全重下' : '从已保存偏移继续'}', () async {
      final dir = Directory.systemTemp.createTempSync('sakura_resume');
      addTearDown(() => dir.deleteSync(recursive: true));
      const spec = LocalModelSpec(
        id: 'tiny',
        name: 'tiny',
        params: 'test',
        license: 'test',
        bytes: 6,
        fileName: 'tiny.task',
        summary: '',
        mirrors: ['https://example.test/model'],
      );
      final path = '${dir.path}/models/tiny.task';
      await File('$path.part').parent.create();
      await File('$path.part').writeAsBytes([0, 1, 2]);
      await File('$path.part.meta').writeAsString(
        jsonEncode({'url': spec.mirrors.single, 'validator': '"v1"'}),
      );
      final manager = LocalModelManager(
        dirs: AppDirs(files: dir.path, cache: dir.path),
        supportedOverride: false,
        specOverride: spec,
        client: MockClient((request) async {
          expect(request.headers['range'], 'bytes=3-');
          expect(request.headers['if-range'], '"v1"');
          return ignoresRange
              ? http.Response.bytes([0, 1, 2, 3, 4, 5], 200)
              : http.Response.bytes(
                  [3, 4, 5],
                  206,
                  headers: {'content-range': 'bytes 3-5/6', 'etag': '"v1"'},
                );
        }),
      );
      await manager.download();
      expect(manager.isDownloaded, isTrue);
      expect(await File(path).readAsBytes(), [0, 1, 2, 3, 4, 5]);
      manager.dispose();
    });
  }
}
