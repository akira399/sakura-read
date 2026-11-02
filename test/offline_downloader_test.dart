import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_source.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/offline_downloader.dart';

class _Content extends BookContent {
  _Content(this.read, {this.failDispose = false});

  final Future<String> Function(int) read;
  final bool failDispose;
  bool disposed = false;

  @override
  Future<String> chapterText(int index) => read(index);

  @override
  Future<void> dispose() async {
    disposed = true;
    if (failDispose) throw StateError('dispose failed');
  }
}

Book _book(int count) => Book(
  id: 'test',
  title: '测试书',
  format: BookFormat.online,
  path: 'https://example.com/book',
  chapters: List.generate(count, (i) => ChapterRef(title: '$i')),
);

void main() {
  test('空目录和反向区间直接完成，不创建读取器', () async {
    final downloader = OfflineDownloader(
      contentFactory: (_, _) => throw StateError('不应创建'),
    );
    final store = BookStore();
    addTearDown(store.dispose);
    final empty = await downloader.download(_book(0), store);
    final reversed = await downloader.download(_book(3), store, from: 2, to: 0);
    for (final result in [empty, reversed]) {
      expect(result.total, 0);
      expect(result.finished, isTrue);
      expect(result.fraction, 1);
    }
    expect(downloader.running, isFalse);
  });

  test('拒绝无效并发数', () {
    for (final concurrency in [0, -1]) {
      expect(
        () => OfflineDownloader(concurrency: concurrency),
        throwsRangeError,
      );
    }
  });

  test('混合成功、空正文与异常会继续下载，进度到达完成', () async {
    final visited = <int>[];
    final content = _Content((index) async {
      visited.add(index);
      if (index == 1) return '  ';
      if (index == 2) throw StateError('网络错误');
      return '正文';
    });
    final downloader = OfflineDownloader(contentFactory: (_, _) => content);
    final store = BookStore();
    addTearDown(store.dispose);
    final progress = <OfflineDownloadProgress>[];
    final result = await downloader.download(
      _book(4),
      store,
      onProgress: progress.add,
    );
    expect(visited, unorderedEquals([0, 1, 2, 3]));
    expect(result.done, 2);
    expect(result.failed, 2);
    expect(result.fraction, 1);
    expect(progress.last, same(result));
    expect(progress.last.finished, isTrue);
    expect(content.disposed, isTrue);
    expect(downloader.running, isFalse);
  });

  test('并发受限，取消后等待在途章节且不领取新章节', () async {
    final pending = <Completer<String>>[];
    final content = _Content((_) {
      final completer = Completer<String>();
      pending.add(completer);
      return completer.future;
    });
    final downloader = OfflineDownloader(
      concurrency: 2,
      contentFactory: (_, _) => content,
    );
    final store = BookStore();
    addTearDown(store.dispose);
    final task = downloader.download(_book(5), store);
    expect(pending, hasLength(2));
    await expectLater(downloader.download(_book(1), store), throwsStateError);
    downloader.cancel();
    for (final completer in pending) {
      completer.complete('正文');
    }
    final result = await task;
    expect(pending, hasLength(2));
    expect(result.done, 2);
    expect(result.cancelled, isTrue);
    expect(result.finished, isTrue);
    expect(result.fraction, 0.4);
    expect(content.disposed, isTrue);
    expect(downloader.running, isFalse);
  });

  test('初始化、回调和释放异常后仍可再次启动任务', () async {
    final store = BookStore();
    addTearDown(store.dispose);
    for (final failure in ['factory', 'callback', 'dispose']) {
      var shouldFail = true;
      final downloader = OfflineDownloader(
        contentFactory: (_, _) {
          if (shouldFail && failure == 'factory') throw StateError('初始化失败');
          return _Content(
            (_) async => '正文',
            failDispose: shouldFail && failure == 'dispose',
          );
        },
      );
      await expectLater(
        downloader.download(
          _book(1),
          store,
          onProgress: (_) {
            if (shouldFail && failure == 'callback') throw StateError('回调失败');
          },
        ),
        throwsStateError,
      );
      expect(downloader.running, isFalse);
      shouldFail = false;
      expect((await downloader.download(_book(1), store)).done, 1);
    }
  });
}
