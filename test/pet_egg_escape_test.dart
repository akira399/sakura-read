// 回归：锁屏彩蛋必须能自己出来。
//
// 线上反馈（酷安）：「一直让我点加号我点不到然后不让我用软件了」，截图是
// 黑屏血字 + 「小樱禁止你使用该软件」。旧实现里这一层是全屏吞手势、没有任何
// 出口，只能杀进程重进；本用例钉死两个出口：长按 5 秒认错、60 秒兜底放行。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/ui/widgets/pet_egg.dart';
import 'package:sakura_read/src/ui/widgets/pet_overlay.dart' show kPetEggActive;

Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: Stack(children: [PetEggOverlay(active: kPetEggActive)]),
    ),
  );
}

void main() {
  setUp(() => kPetEggActive.value = true);
  tearDown(() => kPetEggActive.value = false);

  testWidgets('长按 5 秒可以退出锁屏彩蛋', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('长按 5 秒认错'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Scaffold)),
    );
    // 先让长按手势被识别（默认 500ms），再走完 5 秒计时
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(kPetEggActive.value, isFalse, reason: '长按到底必须放行，不能把人锁死');
    await gesture.up();
    await tester.pump();
    expect(find.text('长按 5 秒认错'), findsNothing);
  });

  testWidgets('什么都不点也会在 60 秒后自动放行', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(kPetEggActive.value, isTrue);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    expect(kPetEggActive.value, isFalse, reason: '兜底计时器必须存在');
  });

  testWidgets('短按不会误退出（彩蛋该有点脾气）', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.tap(find.byType(Scaffold));
    await tester.pump(const Duration(milliseconds: 300));

    expect(kPetEggActive.value, isTrue);
  });
}
