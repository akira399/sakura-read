import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/reading_excerpt.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/ui/ai_chat_page.dart';

void main() {
  test('安静、减少动画和暂停设置保存，主动动作不刷奖励', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_companion');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dirs = AppDirs(files: dir.path, cache: dir.path);
    final pet = PetStore(dirsOverride: dirs);
    await pet.load();
    pet.setQuiet(true);
    pet.setMotionEnabled(false);
    pet.pauseForMinutes(15);
    for (final action in ['dance', 'tea', 'curious', 'stretch', 'encourage']) {
      pet.perform(action);
      expect(pet.activity, action);
    }
    final sequence = pet.activitySequence;
    pet.perform('unknown');
    expect(pet.activitySequence, sequence);
    expect(pet.interactions, 0);
    await pet.flush();
    final restored = PetStore(dirsOverride: dirs);
    await restored.load();
    expect(restored.quiet, isTrue);
    expect(restored.motionEnabled, isFalse);
    expect(restored.paused, isTrue);
    restored.resumeCompanion();
    await restored.flush();
    expect(restored.paused, isFalse);
  });
  test('在线章节分析仅使用缓存，截取范围明确且不隐式联网', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_excerpt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = BookStore(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
    );
    await store.load();
    final book = Book(
      id: 'one',
      title: '样本',
      format: BookFormat.online,
      path: 'https://example.test',
      chapters: [ChapterRef(title: '第一章')],
    );
    await expectLater(ReadingExcerpt.load(store, book), throwsStateError);
    final file = File('${store.chapterCacheDir(book.id).path}/ch_v2_0000.txt');
    await file.parent.create(recursive: true);
    await file.writeAsString('樱花开放。人物在窗前看书。');
    final excerpt = await ReadingExcerpt.load(store, book, limit: 6);
    expect(excerpt.truncated, isTrue);
    expect(excerpt.text, hasLength(6));
    expect(excerpt.prompt('总结'), contains('不能代表整章'));
    expect(excerpt.source, '《样本》· 第一章');
  });
  test('模型笔记与同位置普通书签共存，重复保存同一笔记不重复', () async {
    final dir = Directory.systemTemp.createTempSync('sakura_notes');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marks = BookmarkStore(
      dirsOverride: AppDirs(files: dir.path, cache: dir.path),
    );
    await marks.load();
    marks.add(
      Bookmark(
        id: 'normal',
        bookId: 'one',
        chapterIndex: 0,
        charOffset: 0,
        excerpt: '原文',
      ),
    );
    final note = Bookmark(
      id: 'note',
      bookId: 'one',
      chapterIndex: 0,
      charOffset: 0,
      excerpt: '模型辅助笔记',
    );
    marks.addNote(note);
    marks.addNote(note);
    await marks.flush();
    expect(marks.count, 2);
    expect(marks.items.first.excerpt, '原文');
  });
  testWidgets('未配置模型也显示阅读工作台的本地任务入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(store: BookStore(), prefs: AppPrefs()),
      ),
    );
    expect(find.text('小樱 · 阅读工作台'), findsOneWidget);
    expect(find.text('找一句原文'), findsOneWidget);
    expect(find.text('读懂当前章节'), findsOneWidget);
    expect(find.text('自由对话'), findsOneWidget);
  });
}
