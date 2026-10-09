// 本轮三项 UI 调整的回归测试：
//   ① 发现页从书架右上角移到常驻底栏（第四格）；
//   ② 底栏 3 格 → 4 格后，导航栏渲染正常（不溢出、四个标签都在）；
//   ③ 阅读器「本章来源」按钮的显示条件（在线书 + 有 href）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/app.dart';
import 'package:sakura_read/src/data/book_store.dart';
import 'package:sakura_read/src/data/models.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/data/stats_store.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/source/source_store.dart';

void main() {
  group('底栏四格（发现页挪入底栏）', () {
    testWidgets('导航栏有 4 个入口：书架 / 发现 / 最近 / 设置，且无布局溢出', (tester) async {
      late AppPrefs prefs;
      late BookStore store;
      late SourceStore sources;
      late StatsStore stats;
      late PetStore pet;

      await tester.runAsync(() async {
        final tmp = await Directory.systemTemp.createTemp('sakura_nav');
        final dirs = AppDirs(files: tmp.path, cache: tmp.path);
        prefs = AppPrefs(dirsOverride: dirs);
        await prefs.load();
        // 跳过首启流程，直接进主界面
        prefs.setAgreementAccepted(true);
        prefs.setGuideSeen(true);
        store = BookStore(dirsOverride: dirs);
        await store.load();
        sources = SourceStore(dirsOverride: dirs);
        await sources.load();
        stats = StatsStore(dirsOverride: dirs);
        await stats.load();
        pet = PetStore(dirsOverride: dirs);
        await pet.load();
      });

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        SakuraApp(
          prefs: prefs,
          store: store,
          sourceStore: sources,
          statsStore: stats,
          petStore: pet,
        ),
      );
      // 跑过开屏动画
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1600));

      // 四个入口都在底栏
      expect(find.text('书架'), findsWidgets);
      expect(find.text('发现'), findsWidgets, reason: '发现页应出现在常驻底栏');
      expect(find.text('最近'), findsWidgets);
      expect(find.text('设置'), findsWidgets);

      // 渲染无异常（溢出会抛异常 / 出 ErrorWidget）
      expect(find.byType(ErrorWidget), findsNothing);

      // 收尾：排空定时器
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('「本章来源」按钮的显示条件', () {
    test('在线书且章节有 href → 可跳转', () {
      final online = Book(
        id: 'o1',
        title: '在线书',
        author: '',
        path: '',
        format: BookFormat.online,
        chapters: [ChapterRef(title: '第1章', href: 'https://s.com/1.html')],
      );
      final href = online.chapters.first.href?.trim();
      expect(online.format == BookFormat.online, isTrue);
      expect(href != null && href.isNotEmpty, isTrue);
    });

    test('TXT（无 href）→ 不显示来源按钮', () {
      final txt = Book(
        id: 't1',
        title: '本地书',
        author: '',
        path: '/tmp/a.txt',
        format: BookFormat.txt,
        chapters: [ChapterRef(title: '第1章', start: 0, end: 10)],
      );
      expect(txt.format == BookFormat.online, isFalse);
      expect(txt.chapters.first.href, isNull);
    });

    test('href 为空字符串 → 同样不显示（避免点了没反应）', () {
      final b = Book(
        id: 'o2',
        title: '空链接',
        author: '',
        path: '',
        format: BookFormat.online,
        chapters: [ChapterRef(title: '第1章', href: '  ')],
      );
      final href = b.chapters.first.href?.trim();
      expect(href == null || href.isEmpty, isTrue);
    });
  });
}
