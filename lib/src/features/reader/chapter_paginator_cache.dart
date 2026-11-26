import 'dart:collection';

import '../../data/paginator.dart';

/// 章节分页与正文的 LRU 预缓存。
///
/// 用于阅读器中缓存当前章与相邻章节（±1、±2）的分页结果与处理后文本，
/// 在控制内存上限的同时，保证翻越章界时毫秒级衔接。
class ChapterPaginatorCache {
  ChapterPaginatorCache({this.maxPageEntries = 12, this.maxTextEntries = 16})
    : assert(maxPageEntries > 0),
      assert(maxTextEntries > 0);

  /// 最多保留的分页条目数（键为布局签名）。
  final int maxPageEntries;

  /// 最多保留的原始 / 处理后章节文本条目数。
  final int maxTextEntries;

  final LinkedHashMap<String, List<PageSlice>> _pages = LinkedHashMap();
  final LinkedHashMap<int, String> _rawTexts = LinkedHashMap();
  final LinkedHashMap<String, String> _processedTexts = LinkedHashMap();
  final Set<String> _inFlight = <String>{};

  int _hits = 0;
  int _misses = 0;

  int get pageEntryCount => _pages.length;
  int get rawTextEntryCount => _rawTexts.length;
  int get processedTextEntryCount => _processedTexts.length;
  int get hitCount => _hits;
  int get missCount => _misses;

  /// 读取分页结果并刷新其 LRU 活跃度。
  List<PageSlice>? getPages(String layoutSig) {
    final value = _pages.remove(layoutSig);
    if (value == null) {
      _misses++;
      return null;
    }
    _pages[layoutSig] = value;
    _hits++;
    return value;
  }

  /// 查看是否已有分页缓存（不改变统计，用于预加载去重）。
  bool hasPages(String layoutSig) => _pages.containsKey(layoutSig);

  /// 写入分页结果并在超限时淘汰最久未用条目。
  void putPages(String layoutSig, List<PageSlice> slices) {
    _pages.remove(layoutSig);
    _pages[layoutSig] = slices;
    while (_pages.length > maxPageEntries) {
      _pages.remove(_pages.keys.first);
    }
  }

  /// 读取原始章节文本并刷新 LRU 顺序。
  String? getRawText(int chapterIndex) {
    final value = _rawTexts.remove(chapterIndex);
    if (value == null) return null;
    _rawTexts[chapterIndex] = value;
    return value;
  }

  /// 写入原始章节文本。
  void putRawText(int chapterIndex, String raw) {
    _rawTexts.remove(chapterIndex);
    _rawTexts[chapterIndex] = raw;
    while (_rawTexts.length > maxTextEntries) {
      _rawTexts.remove(_rawTexts.keys.first);
    }
  }

  /// 读取清洗/缩进后的章节文本并刷新 LRU 顺序。
  String? getProcessedText(String key) {
    final value = _processedTexts.remove(key);
    if (value == null) return null;
    _processedTexts[key] = value;
    return value;
  }

  /// 写入清洗/缩进后的章节文本。
  void putProcessedText(String key, String text) {
    _processedTexts.remove(key);
    _processedTexts[key] = text;
    while (_processedTexts.length > maxTextEntries) {
      _processedTexts.remove(_processedTexts.keys.first);
    }
  }

  /// 标记某布局签名开始后台预分页；已在缓存或正在进行中时返回 false。
  bool tryStartPreload(String layoutSig) {
    if (_pages.containsKey(layoutSig) || _inFlight.contains(layoutSig)) {
      return false;
    }
    _inFlight.add(layoutSig);
    return true;
  }

  /// 结束后台预分页标记。
  void finishPreload(String layoutSig) {
    _inFlight.remove(layoutSig);
  }

  /// 清空处理后文本与分页缓存（排版设置或净化规则变化时使用）。
  void invalidateLayout() {
    _pages.clear();
    _processedTexts.clear();
    _inFlight.clear();
  }

  /// 清空全部缓存（换书 / 换源时使用）。
  void clearAll() {
    _pages.clear();
    _rawTexts.clear();
    _processedTexts.clear();
    _inFlight.clear();
    _hits = 0;
    _misses = 0;
  }
}
