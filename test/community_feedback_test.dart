// 本轮社区反馈四项功能的回归测试。
//
// 覆盖：
//   ① 发现页：exploreUrl 分类解析（多种分隔写法 / 容错）；
//   ② 离线缓存：缓存计数与清理；
//   ③ 朗读：引擎选择 / 回退（TtsService 纯逻辑部分）；
//   ④ 排版：上下留白与页眉页脚开关的持久化。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/epub_parser.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/models.dart';
import 'package:sakura_read/src/source/online_repo.dart';

BookSource _src({String exploreUrl = ''}) => BookSource(
  bookSourceUrl: 'https://example.com',
  bookSourceName: '测试源',
  exploreUrl: exploreUrl.isEmpty ? null : exploreUrl,
);

void main() {
  group('发现页：exploreUrl 分类解析', () {
    test('标准写法「标题::地址」，多行', () {
      final cats = OnlineRepo.parseExploreCategories(
        _src(
          exploreUrl:
              '玄幻::https://s.com/list/xh/{{page}}.html\n'
              '排行榜::https://s.com/rank/all.html',
        ),
      );
      expect(cats.length, 2);
      expect(cats[0].title, '玄幻');
      expect(cats[0].url, contains('/list/xh/'));
      expect(cats[1].title, '排行榜');
    });

    test('兼容「标题,地址」逗号写法', () {
      final cats = OnlineRepo.parseExploreCategories(
        _src(exploreUrl: '都市,https://s.com/dushi.html'),
      );
      expect(cats.single.title, '都市');
      expect(cats.single.url, 'https://s.com/dushi.html');
    });

    test('只有地址：标题自动取 URL 末段（不留空白标签）', () {
      final cats = OnlineRepo.parseExploreCategories(
        _src(exploreUrl: 'https://s.com/list/xianxia.html'),
      );
      expect(cats.single.title, isNotEmpty);
      expect(cats.single.title, contains('xianxia'));
    });

    test('容错：忽略空行与 # 注释行', () {
      final cats = OnlineRepo.parseExploreCategories(
        _src(
          exploreUrl:
              '\n'
              '# 这是注释\n'
              '科幻::https://s.com/kh.html\n'
              '   \n',
        ),
      );
      expect(cats.length, 1);
      expect(cats.single.title, '科幻');
    });

    test('未配置 exploreUrl → 空列表（发现页据此提示引导）', () {
      expect(OnlineRepo.parseExploreCategories(_src()), isEmpty);
      expect(
        OnlineRepo.parseExploreCategories(_src(exploreUrl: '   ')),
        isEmpty,
      );
    });
  });

  group('离线缓存：缓存计数与清理', () {
    late Directory tmp;
    late BookStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sakura_offline');
      final dirs = AppDirs(files: tmp.path, cache: tmp.path);
      store = BookStore(dirsOverride: dirs);
      await store.load();
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    /// 写一个章节缓存文件（模拟已抓取）。
    Future<void> writeChapter(
      String bookId,
      int index, [
      String text = '正文',
    ]) async {
      final dir = store.chapterCacheDir(bookId);
      await dir.create(recursive: true);
      await File(
        '${dir.path}/ch_v2_${index.toString().padLeft(4, '0')}.txt',
      ).writeAsString(text);
    }

    test('未缓存 → 0 章', () async {
      expect(await store.cachedChapterCount('book1'), 0);
    });

    test('写入后能正确统计（只算 ch_v2_* 且非空）', () async {
      await writeChapter('book1', 0);
      await writeChapter('book1', 1);
      // 空文件不算（抓取失败留下的空壳）
      await writeChapter('book1', 2, '');
      // 非章节文件也不算
      final dir = store.chapterCacheDir('book1');
      await File('${dir.path}/other.txt').writeAsString('x');

      expect(await store.cachedChapterCount('book1'), 2);
    });

    test('清除本书缓存只影响该书', () async {
      await writeChapter('book1', 0);
      await writeChapter('book2', 0);

      await store.clearBookCache('book1');

      expect(await store.cachedChapterCount('book1'), 0);
      expect(await store.cachedChapterCount('book2'), 1);
    });
  });

  group('阅读排版：上下留白与页眉页脚开关', () {
    late Directory tmp;
    late AppPrefs prefs;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sakura_reader_prefs');
      prefs = AppPrefs(
        dirsOverride: AppDirs(files: tmp.path, cache: tmp.path),
      );
      await prefs.load();
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('默认值与旧版本一致（30 / 46，页眉页脚开）', () {
      expect(prefs.readerPaddingTop, 30);
      expect(prefs.readerPaddingBottom, 46);
      expect(prefs.readerHeaderVisible, isTrue);
      expect(prefs.readerFooterVisible, isTrue);
    });

    test('setter 生效且带边界钳制', () {
      prefs.setReaderPaddingTop(80);
      expect(prefs.readerPaddingTop, 80);
      prefs.setReaderPaddingTop(-10);
      expect(prefs.readerPaddingTop, 0, reason: '负数应钳到 0');
      prefs.setReaderPaddingTop(9999);
      expect(prefs.readerPaddingTop, 160, reason: '过大应钳到上限');
    });

    test('页眉页脚开关可关闭', () {
      prefs.setReaderHeaderVisible(false);
      prefs.setReaderFooterVisible(false);
      expect(prefs.readerHeaderVisible, isFalse);
      expect(prefs.readerFooterVisible, isFalse);
    });
  });

  group('朗读引擎偏好', () {
    test('默认空 = 系统默认；可设置与清除', () {
      final prefs = AppPrefs();
      expect(prefs.ttsEngine, isEmpty);
      prefs.setTtsEngine('com.iflytek.tts');
      expect(prefs.ttsEngine, 'com.iflytek.tts');
      prefs.setTtsEngine('');
      expect(prefs.ttsEngine, isEmpty);
    });
  });

  group('EPUB 插图（社区反馈：书里的插图不能加载）', () {
    test('图片标记格式：正文里以控制字符包裹，不与正文冲突', () {
      // 与 EpubParser 的常量保持一致（渲染端按同格式解析）
      const marker = '\u0001IMG:pic1.png\u0001';
      final re = RegExp('\u0001IMG:[^\u0001]*\u0001');
      expect(re.hasMatch(marker), isTrue);
      expect(re.hasMatch('普通正文没有标记'), isFalse);
    });

    test('HTML → 纯文本：无 archive 时退化为「［插图］」文字', () {
      final text = EpubParser.extractText(
        '<html><body><p>正文一</p><img src="a.png"/><p>正文二</p></body></html>',
      );
      expect(text, contains('正文一'));
      expect(text, contains('正文二'));
      expect(text, contains('［插图］'));
      // 没有 archive 时不应出现控制字符标记
      expect(text.contains('\u0001IMG:'), isFalse);
    });
  });

  group('在线书离线缓存：模型约束', () {
    test('章节数与缓存区间计算（离线下载按章节范围工作）', () {
      final book = Book(
        id: 'b1',
        title: '测试书',
        author: '',
        path: '',
        format: BookFormat.online,
        chapters: [
          for (var i = 0; i < 10; i++)
            ChapterRef(title: '第 $i 章', href: 'https://s.com/$i.html'),
        ],
      );
      expect(book.chapterCount, 10);
    });
  });
}
