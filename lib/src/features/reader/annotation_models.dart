import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/database/sakura_database.dart';

/// 四色划线荧光色板（低饱和编辑纸感，日夜模式皆柔和可读）。
enum AnnotationColor {
  sakura('樱绯', Color(0xFFE86A92)),
  apricot('暖杏', Color(0xFFE58E49)),
  bamboo('若竹', Color(0xFF46A884)),
  sky('晴空', Color(0xFF4A9BE8));

  const AnnotationColor(this.label, this.swatch);

  final String label;
  final Color swatch;

  static AnnotationColor fromIndex(int index) {
    if (index < 0 || index >= values.length) return AnnotationColor.sakura;
    return values[index];
  }

  /// 正文划线背景色（按日夜背景自动调节透明度）。
  Color highlightFill({required bool dark}) =>
      swatch.withValues(alpha: dark ? 0.28 : 0.24);
}

/// 一条阅读器划线 / 批注记录，与 SQLite `annotations` 表结构 1:1 对齐。
@immutable
class ReaderAnnotation {
  const ReaderAnnotation({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.startOffset,
    required this.endOffset,
    required this.quote,
    this.note = '',
    this.colorIndex = 0,
    this.kind = 'highlight',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final int startOffset;
  final int endOffset;
  final String quote;
  final String note;
  final int colorIndex;
  final String kind;
  final int createdAt;
  final int updatedAt;

  AnnotationColor get color => AnnotationColor.fromIndex(colorIndex);
  bool get hasNote => note.trim().isNotEmpty;

  static final Random _rnd = Random();

  static String newId() =>
      'ann_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '_${_rnd.nextInt(1 << 24).toRadixString(36)}';

  ReaderAnnotation copyWith({
    String? quote,
    String? note,
    int? colorIndex,
    String? kind,
    int? updatedAt,
  }) => ReaderAnnotation(
    id: id,
    bookId: bookId,
    chapterIndex: chapterIndex,
    startOffset: startOffset,
    endOffset: endOffset,
    quote: quote ?? this.quote,
    note: note ?? this.note,
    colorIndex: colorIndex ?? this.colorIndex,
    kind: kind ?? this.kind,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, Object?> toDbRow() => {
    'id': id,
    'book_id': bookId,
    'chapter_index': chapterIndex,
    'start_offset': startOffset,
    'end_offset': endOffset,
    'quote': quote,
    'note': note,
    'color_index': colorIndex,
    'kind': kind,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory ReaderAnnotation.fromDbRow(Map<String, Object?> row) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ReaderAnnotation(
      id: row['id'] as String? ?? newId(),
      bookId: row['book_id'] as String? ?? '',
      chapterIndex: (row['chapter_index'] as num?)?.toInt() ?? 0,
      startOffset: (row['start_offset'] as num?)?.toInt() ?? 0,
      endOffset: (row['end_offset'] as num?)?.toInt() ?? 0,
      quote: row['quote'] as String? ?? '',
      note: row['note'] as String? ?? '',
      colorIndex: (row['color_index'] as num?)?.toInt() ?? 0,
      kind: row['kind'] as String? ?? 'highlight',
      createdAt: (row['created_at'] as num?)?.toInt() ?? now,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? now,
    );
  }
}

/// 书籍划线 / 批注仓储（直连 [SakuraDatabase] `annotations` DAO，无数据库时退回内存态）。
class ReaderAnnotationStore extends ChangeNotifier {
  ReaderAnnotationStore({this.database});

  final SakuraDatabase? database;
  final List<ReaderAnnotation> _items = <ReaderAnnotation>[];

  List<ReaderAnnotation> get all => List.unmodifiable(_items);

  /// 某章的全部划线/批注（排除普通 bookmark）。
  List<ReaderAnnotation> forChapter(int chapterIndex) => _items
      .where((a) => a.chapterIndex == chapterIndex && a.kind != 'bookmark')
      .toList();

  /// 全书所有划线/批注（按章节和位置升序）。
  List<ReaderAnnotation> get highlightsAndNotes =>
      _items.where((a) => a.kind != 'bookmark').toList();

  Future<void> loadForBook(String bookId) async {
    final db = database;
    if (db == null) return;
    final rows = await db.loadAnnotationsForBook(bookId);
    _items
      ..clear()
      ..addAll(rows.map(ReaderAnnotation.fromDbRow));
    notifyListeners();
  }

  Future<ReaderAnnotation> save(ReaderAnnotation annotation) async {
    final db = database;
    if (db != null) {
      await db.upsertAnnotation(annotation.toDbRow());
    }
    final idx = _items.indexWhere((a) => a.id == annotation.id);
    if (idx >= 0) {
      _items[idx] = annotation;
    } else {
      _items.add(annotation);
    }
    _items.sort((a, b) {
      if (a.chapterIndex != b.chapterIndex) {
        return a.chapterIndex.compareTo(b.chapterIndex);
      }
      if (a.startOffset != b.startOffset) {
        return a.startOffset.compareTo(b.startOffset);
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    notifyListeners();
    return annotation;
  }

  Future<void> remove(String id) async {
    final db = database;
    if (db != null) {
      await db.deleteAnnotation(id);
    }
    _items.removeWhere((a) => a.id == id);
    notifyListeners();
  }
}
