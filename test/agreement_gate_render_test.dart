// 首启「使用条款与声明」页 + 引导联动的渲染回归测试。
//
// 回归背景：
//   ① 首启页是新页面，文字如果没包在 Material 里，会继承 MaterialApp 最外层的
//      调试用 DefaultTextStyle（红字 + 黄色双下划线，即"双黄线"）。
//   ② 引导必须等「同意条款」之后才开始：`PetGuideHost.enabled` 从 false 变 true
//      时要自动启动，否则用户同意后引导永远不出现。
// 这里钉死这两条约束。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';
import 'package:sakura_read/src/ui/agreement_gate.dart';
import 'package:sakura_read/src/ui/widgets/pet_guide_overlay.dart';

/// 跑真实文件 IO 的 AppPrefs（测试环境是模拟时钟）。
Future<AppPrefs> _makePrefs(WidgetTester tester) async {
  late AppPrefs prefs;
  await tester.runAsync(() async {
    final tmp = await Directory.systemTemp.createTemp('sakura_agreement_test');
    prefs = AppPrefs(
      dirsOverride: AppDirs(files: tmp.path, cache: tmp.path),
    );
    await prefs.load();
  });
  return prefs;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('首启页：文字必须处于 Material 内（防双黄线）', (tester) async {
    final prefs = await _makePrefs(tester);

    await tester.pumpWidget(
      _host(AgreementGate(prefs: prefs, child: const SizedBox.expand())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 关键内容都在
    expect(find.text('欢迎来到樱读'), findsOneWidget);
    expect(find.text('我已阅读并同意上述声明与条款'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);

    // 标题/条款文字必须有 Material 祖先 —— 否则渲染出黄双下划线
    expect(
      find.ancestor(of: find.text('欢迎来到樱读'), matching: find.byType(Material)),
      findsWidgets,
      reason: '首启页标题必须位于 Material 内，否则会出现黄色双下划线',
    );
    expect(
      find.ancestor(
        of: find.textContaining('樱读是阅读工具'),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: '条款文字必须位于 Material 内，否则会出现黄色双下划线',
    );
    expect(tester.takeException(), isNull);

    // 收起动画定时器收尾
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('首启页：未勾选点「同意并继续」不放行，勾选后放行', (tester) async {
    final prefs = await _makePrefs(tester);

    await tester.pumpWidget(
      _host(AgreementGate(prefs: prefs, child: const SizedBox.expand())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 未勾选直接点同意：应弹 SnackBar 而不是放行
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请先勾选「我已阅读并同意」'), findsOneWidget);
    expect(prefs.agreementAccepted, isFalse);

    // 勾选后点击 → 放行（prefs 写为 true，页面对应的视图被移除）
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('同意并继续'));
    await tester.pump();
    expect(prefs.agreementAccepted, isTrue);
    // 同意后视图应消失
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('同意并继续'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('引导联动：enabled=false 不启动；同意（false→true）后自动开始', (tester) async {
    final pet = PetStore();
    final ready = ValueNotifier<bool>(true);
    var seenCalled = 0;
    void onSeen() => seenCalled++;
    addTearDown(() => expect(seenCalled, 0, reason: '本用例不应走完引导'));

    // enabled=false：宿主在就绪也不应开始
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PetGuideHost(
                pet: pet,
                hostReady: ready,
                seen: false,
                enabled: false,
                onSeen: onSeen,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(kPetGuideActive.value, isFalse, reason: '未同意条款前不应开始引导');

    // enabled 翻转为 true（模拟用户点了「同意并继续」）：应自动开始
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PetGuideHost(
                pet: pet,
                hostReady: ready,
                seen: false,
                enabled: true,
                onSeen: onSeen,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(kPetGuideActive.value, isTrue, reason: '同意条款后引导应自动开始');
    expect(find.text('跳过引导'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 收尾：销毁（停掉引导定时器）
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    ready.dispose();
  });
}
