// 在线书籍「离线缓存」：把整本（或一段章节）提前抓下来存本地。
//
// 用户反馈：「不支持离线缓存」——原先只有「读到哪缓存到哪」（翻页时顺手
// 存一章），没法提前把书下好，地铁 / 飞机上就断粮。这里提供批量预下载。
//
// 设计要点：
//   - 并发受控（默认 4）：书源站点对并发敏感，太多会被限流 / 封；
//   - 逐章落盘（复用 OnlineBookContent 的缓存文件名），**随时中断不白干**；
//   - 已缓存的章节直接跳过（可续传，重跑只补缺的）；
//   - 失败不中断整轮：记录失败章节，最后汇总（部分成功也是成功）。
import 'dart:async';

import 'book_source.dart';
import 'book_store.dart';
import 'models.dart';

/// 下载进度快照（供 UI 显示）。
class OfflineDownloadProgress {
  const OfflineDownloadProgress({
    required this.done,
    required this.total,
    required this.failed,
    required this.currentChapter,
    required this.finished,
    required this.cancelled,
  });

  /// 已完成（含跳过 + 成功）。
  final int done;

  /// 计划下载的总章节数。
  final int total;

  /// 失败章节数。
  final int failed;

  /// 当前正在抓的章节序号（从 0 开始）。
  final int currentChapter;

  /// 是否已全部结束。
  final bool finished;

  /// 是否被用户取消。
  final bool cancelled;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

/// 离线缓存下载器。
///
/// 一次只允许一个任务（同一实例内）；UI 持有一个实例即可。
class OfflineDownloader {
  OfflineDownloader({this.concurrency = 4});

  /// 并发抓取数（站点限流友好）。
  final int concurrency;

  bool _cancelled = false;
  bool _running = false;

  bool get running => _running;

  /// 请求取消（正在进行的章节会跑完当前请求）。
  void cancel() {
    if (_running) _cancelled = true;
  }

  /// 下载 [book] 的 [from, to] 章节区间（含两端）。
  ///
  /// - [onProgress]：每完成一章回调一次（UI 刷新进度条）；
  /// - 返回最终进度（含失败数与取消标记）。
  Future<OfflineDownloadProgress> download(
    Book book,
    BookStore store, {
    int from = 0,
    int? to,
    void Function(OfflineDownloadProgress)? onProgress,
  }) async {
    if (_running) {
      throw StateError('已有下载任务在进行');
    }
    final total = book.chapters.length;
    final start = from.clamp(0, total);
    final end = (to ?? total - 1).clamp(0, total - 1);
    final indices = [for (var i = start; i <= end; i++) i];

    _running = true;
    _cancelled = false;

    var done = 0;
    var failed = 0;
    var current = start;

    // 内容读取器负责真正的抓取 + 落盘（复用在线正文逻辑，含严格抽取）
    final content = createBookContent(book, store);

    void report() => onProgress?.call(
      OfflineDownloadProgress(
        done: done,
        total: indices.length,
        failed: failed,
        currentChapter: current,
        finished: done >= indices.length,
        cancelled: _cancelled,
      ),
    );

    report();

    try {
      // 简单的工作池：固定 concurrency 个 worker 抢同一个队列。
      final queue = List<int>.from(indices);
      Future<void> worker() async {
        while (true) {
          if (_cancelled) return;
          if (queue.isEmpty) return;
          final index = queue.removeAt(0);
          current = index;
          try {
            final text = await content.chapterText(index);
            if (text.trim().isEmpty) {
              failed++;
            } else {
              done++;
            }
          } catch (_) {
            failed++;
          }
          report();
        }
      }

      final workers = <Future<void>>[
        for (var i = 0; i < concurrency && i < indices.length; i++) worker(),
      ];
      await Future.wait(workers);
    } finally {
      await content.dispose();
      _running = false;
    }

    return OfflineDownloadProgress(
      done: done,
      total: indices.length,
      failed: failed,
      currentChapter: current,
      finished: true,
      cancelled: _cancelled,
    );
  }
}
