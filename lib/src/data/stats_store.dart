// 书签与阅读统计：本地 JSON 持久化。
//
// - 书签：书 + 章节序号 + 章内偏移 + 摘录（跳回原文定位）；
// - 统计：总阅读时长、每日阅读时长、读完的书数（供记录页 / 统计页展示）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/native_bridge.dart';

/// 一条书签。
class Bookmark {
  Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    this.chapterTitle = '',
    this.excerpt = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String bookId;

  /// 章节序号（0 起）。
  final int chapterIndex;

  /// 章内字符偏移。
  final int charOffset;
  final String chapterTitle;

  /// 摘录（书签位置附近的正文片段）。
  final String excerpt;
  final int createdAt;

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String? ?? newId(),
    bookId: json['bookId'] as String? ?? '',
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
    charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    excerpt: json['excerpt'] as String? ?? '',
    createdAt: (json['createdAt'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'charOffset': charOffset,
    'chapterTitle': chapterTitle,
    'excerpt': excerpt,
    'createdAt': createdAt,
  };
}

/// 书签仓库（进程内共享实例 + JSON 持久化）。
class BookmarkStore extends ChangeNotifier {
  BookmarkStore({AppDirs? dirsOverride}) : _dirsOverride = dirsOverride;

  static BookmarkStore? shared;

  final AppDirs? _dirsOverride;
  final List<Bookmark> _items = [];
  File? _file;
  Timer? _saveTimer;

  List<Bookmark> get items => List.unmodifiable(_items);

  List<Bookmark> forBook(String bookId) =>
      [
        for (final b in _items)
          if (b.bookId == bookId) b,
      ]..sort((a, b) {
        if (a.chapterIndex != b.chapterIndex) {
          return a.chapterIndex.compareTo(b.chapterIndex);
        }
        return a.charOffset.compareTo(b.charOffset);
      });

  int get count => _items.length;

  Future<void> load() async {
    final dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${dirs.files}/bookmarks.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map && data['items'] is List) {
          for (final item in data['items'] as List) {
            if (item is Map) {
              try {
                _items.add(Bookmark.fromJson(Map<String, dynamic>.from(item)));
              } catch (_) {
                // 跳过坏数据
              }
            }
          }
        }
      }
    } catch (_) {
      // 读取失败时以空列表启动
    }
    notifyListeners();
  }

  /// 附近是否已有书签（章节相同且偏移差 ≤12 视为同一位置）。
  Bookmark? nearby(String bookId, int chapterIndex, int charOffset) {
    for (final b in _items) {
      if (b.bookId == bookId &&
          b.chapterIndex == chapterIndex &&
          (b.charOffset - charOffset).abs() <= 12) {
        return b;
      }
    }
    return null;
  }

  /// 添加书签；同一位置（章节 + 偏移 ±12 内）视为重复，返回已有书签。
  Bookmark add(Bookmark bookmark) {
    final existing = nearby(
      bookmark.bookId,
      bookmark.chapterIndex,
      bookmark.charOffset,
    );
    if (existing != null) return existing;
    _items.add(bookmark);
    _saveSoon();
    notifyListeners();
    return bookmark;
  }

  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((b) => b.id == id);
    if (_items.length != before) {
      _saveSoon();
      notifyListeners();
    }
  }

  /// 删除某本书的全部书签（书被移除时调用）。
  void removeForBook(String bookId) {
    final before = _items.length;
    _items.removeWhere((b) => b.bookId == bookId);
    if (_items.length != before) {
      _saveSoon();
      notifyListeners();
    }
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  /// 仅供测试：立即落盘（跳过防抖，消除时序脆弱）。
  @visibleForTesting
  Future<void> debugFlush() => _save();

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'items': _items.map((b) => b.toJson()).toList(),
        }),
      );
    } catch (_) {
      // 忽略保存失败
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

// ---------- 阅读统计 ----------

/// 阅读统计：总时长 / 每日时长 / 读完书数。
class StatsStore extends ChangeNotifier {
  StatsStore({AppDirs? dirsOverride}) : _dirsOverride = dirsOverride;

  static StatsStore? shared;

  /// 单次累计上限（秒）：防止"锁屏挂着"把时长刷爆。
  static const int maxChunkSeconds = 90;

  final AppDirs? _dirsOverride;
  int _totalSeconds = 0;
  int _finishedBooks = 0;
  final Map<String, int> _days = {};
  File? _file;
  Timer? _saveTimer;

  int get totalSeconds => _totalSeconds;
  int get finishedBooks => _finishedBooks;

  /// 每日阅读秒数（按日期字符串 'YYYY-MM-DD'）。
  Map<String, int> get days => Map.unmodifiable(_days);

  /// 累计有阅读记录的天数。
  int get readDays => _days.length;

  /// 连续阅读天数（截至今天 / 昨天）。
  int get streak {
    var s = 0;
    var day = _dateKey(DateTime.now());
    // 今天没读则从昨天起算（当天尚未开始不影响连续记录）
    if (!_days.containsKey(day)) {
      day = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    }
    while (_days.containsKey(day) && _days[day]! > 0) {
      s++;
      day = _dateKey(DateTime.parse(day).subtract(const Duration(days: 1)));
    }
    return s;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 最近 [n] 天的阅读秒数（含今天，从早到晚）。
  List<(String, int)> recentDays(int n) {
    final out = <(String, int)>[];
    final now = DateTime.now();
    for (var i = n - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = _dateKey(d);
      out.add((key, _days[key] ?? 0));
    }
    return out;
  }

  Future<void> load() async {
    final dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${dirs.files}/reading_stats.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map) {
          _totalSeconds = (data['totalSeconds'] as num?)?.toInt() ?? 0;
          _finishedBooks = (data['finishedBooks'] as num?)?.toInt() ?? 0;
          final days = data['days'];
          if (days is Map) {
            days.forEach((k, v) {
              if (v is num) _days[k.toString()] = v.toInt();
            });
          }
        }
      }
    } catch (_) {
      // 读取失败时从零开始
    }
    notifyListeners();
  }

  /// 记录一段阅读时长（秒；0 或负数忽略，超过上限截断）。
  void addReadingSeconds(int seconds) {
    if (seconds <= 0) return;
    final s = seconds > maxChunkSeconds ? maxChunkSeconds : seconds;
    _totalSeconds += s;
    final key = _dateKey(DateTime.now());
    _days[key] = (_days[key] ?? 0) + s;
    _saveSoon();
    notifyListeners();
  }

  /// 仅供测试：向指定日期（YYYY-MM-DD）注入阅读时长。
  @visibleForTesting
  void debugAddSecondsForDate(String dateKey, int seconds) {
    if (seconds <= 0) return;
    _totalSeconds += seconds;
    _days[dateKey] = (_days[dateKey] ?? 0) + seconds;
  }

  void addFinishedBook() {
    _finishedBooks++;
    _saveSoon();
    notifyListeners();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save());
    });
  }

  /// 仅供测试：立即落盘（跳过防抖，消除时序脆弱）。
  @visibleForTesting
  Future<void> debugFlush() => _save();

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'totalSeconds': _totalSeconds,
          'finishedBooks': _finishedBooks,
          'days': _days,
        }),
      );
    } catch (_) {
      // 忽略保存失败
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
