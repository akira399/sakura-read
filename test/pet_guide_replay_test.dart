// 「重看新手引导」回归测试。
//
// 背景：引导按设计只在首次启动自动播放一次（guideSeen 落盘后不再出现）。
// 从旧版本升级、或早已看过引导的用户，想再看一遍时没有入口——用户反馈
// 「我这里已经没有新手引导了」促使我们补上了这个入口：
//   - 设置页 → 帮助 → 「重看新手引导」；
//   - 通过 kPetGuideReplay 信号请求宿主重播，不受 guideSeen 限制。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/ui/widgets/pet_guide_overlay.dart';

/// 复刻 app.dart 的层级：引导宿主挂在 Stack（引导层要求 Positioned 有 Stack 父级）。
Widget _host({
  required PetStore pet,
  required ValueNotifier<bool> ready,
  required bool seen,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          PetGuideHost(
            pet: pet,
            hostReady: ready,
            seen: seen,
            enabled: true,
            onSeen: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('重看引导：已看过的用户不会被打扰；重看信号能再次启动', (tester) async {
    final pet = PetStore();
    final ready = ValueNotifier<bool>(true);

    await tester.pumpWidget(_host(pet: pet, ready: ready, seen: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(kPetGuideActive.value, isFalse, reason: '已看过引导的用户不应被自动触发引导');

    // 设置页入口 → 重看信号
    petGuideRequestReplay();
    await tester.pump(const Duration(milliseconds: 300));
    expect(kPetGuideActive.value, isTrue, reason: '重看信号应能重新启动引导');
    expect(find.text('跳过引导'), findsOneWidget);

    // 跳过收尾：引导关闭
    await tester.tap(find.text('跳过引导'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(kPetGuideActive.value, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    ready.dispose();
  });

  testWidgets('重看引导：引导进行中重复请求不会叠加 / 报错', (tester) async {
    final pet = PetStore();
    final ready = ValueNotifier<bool>(true);

    await tester.pumpWidget(_host(pet: pet, ready: ready, seen: true));
    await tester.pump(const Duration(milliseconds: 300));

    petGuideRequestReplay();
    await tester.pump(const Duration(milliseconds: 200));
    expect(kPetGuideActive.value, isTrue);

    // 再来一次（重复请求）：仍只有一份引导在跑，不抛异常
    petGuideRequestReplay();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(kPetGuideActive.value, isTrue);
    expect(find.text('跳过引导'), findsOneWidget);

    await tester.tap(find.text('跳过引导'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    ready.dispose();
  });
}
