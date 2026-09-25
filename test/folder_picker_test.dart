// 文件选择器的「书源文件」模式回归测试。
//
// 回归背景（用户反馈）：书源管理 → 从文件导入 → 选择器里**看不到 .json**
// ——书源导入此前复用了「小说文件」模式，而该模式写死只认 .txt / .epub。
// 修复：新增 `PickerMode.sourceFiles`（.json / .txt），书源导入改用它。
//
// 本测试同时钉住三个模式的过滤规则，防止以后再把扩展名写死进单一模式。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/file_scan.dart';
import 'package:sakura_read/src/ui/folder_picker_page.dart';

void main() {
  test('扩展名过滤规则：小说 / 书源 / 文件夹三模式互不串味', () {
    // 小说模式：只有 txt/epub
    expect(pickerExtensionsFor(PickerMode.files), {'txt', 'epub'});
    // 书源模式：json（书源标准格式）与 txt（允许用户存成 txt）
    expect(pickerExtensionsFor(PickerMode.sourceFiles), {'json', 'txt'});
    // 文件夹模式：不展示任何文件
    expect(pickerExtensionsFor(PickerMode.folder), isEmpty);

    // 常量本身
    expect(kNovelExtensions, {'txt', 'epub'});
    expect(kSourceFileExtensions, {'json', 'txt'});
  });

  testWidgets('书源文件模式：目录中 .json 可见、.epub 被过滤', (tester) async {
    // 真实文件 IO 需要 runAsync（测试环境是模拟时钟）
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('sakura_picker_test');
      File('${tmp.path}/my_sources.json').writeAsStringSync('[]');
      File('${tmp.path}/novel.epub').writeAsBytesSync([0, 1, 2]);
      File('${tmp.path}/note.txt').writeAsStringSync('x');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FolderPickerPage(
          mode: PickerMode.sourceFiles,
          rootOverride: tmp.path,
        ),
      ),
    );
    // 真实目录读取：交替推进「真实异步 + 帧」
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.text('选择书源文件'), findsOneWidget);
    expect(find.text('my_sources.json'), findsOneWidget, reason: '.json 必须可见');
    expect(find.text('note.txt'), findsOneWidget, reason: '.txt 允许导入');
    expect(find.text('novel.epub'), findsNothing, reason: '.epub 不属于书源文件');

    // 收尾
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => tmp.delete(recursive: true));
  });

  testWidgets('小说文件模式：.json 不可见（防止串味）', (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('sakura_picker_test2');
      File('${tmp.path}/my_sources.json').writeAsStringSync('[]');
      File('${tmp.path}/novel.txt').writeAsStringSync('x');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FolderPickerPage(mode: PickerMode.files, rootOverride: tmp.path),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.text('选择小说文件'), findsOneWidget);
    expect(find.text('novel.txt'), findsOneWidget);
    expect(find.text('my_sources.json'), findsNothing, reason: '小说模式不展示 json');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => tmp.delete(recursive: true));
  });
}
