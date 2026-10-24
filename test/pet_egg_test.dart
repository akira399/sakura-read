// 回归：锁屏彩蛋是「没有出口」的设定。
//
// 历史：「彩蛋」曾因为把用户锁死在软件外（酷安反馈「不让我用软件了」）而
// 加过两个出口（长按 5 秒认错 / 60 秒自动放行）。产品决定保留彩蛋本身、
// 移除出口——彩蛋就该是「小樱真的生气了」，退出方式只有重启 App。
// 本用例钉死：画面上没有任何退出提示，点击 / 长按 / 拖拽 / 等待都不会放行。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/pet_mood.dart';
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

  testWidgets('激活时铺满黑屏，显示阴沉台词与血字', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text(petEggLine), findsOneWidget);
    expect(find.text(petEggFooter), findsOneWidget);
  });

  testWidgets('画面上不出现任何退出提示', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.textContaining('长按'), findsNothing);
    expect(find.textContaining('重启'), findsNothing);
    expect(find.textContaining('退出'), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('点击 / 长按 / 拖拽都不会放行', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.tap(find.byType(Scaffold), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(kPetEggActive.value, isTrue);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Scaffold)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 6));
    await gesture.up();
    await tester.pump();
    expect(kPetEggActive.value, isTrue, reason: '长按不能成为出口');

    await tester.dragFrom(
      tester.getCenter(find.byType(Scaffold)),
      const Offset(0, -200),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(kPetEggActive.value, isTrue);
  });

  testWidgets('放着不管也不会自动放行', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    expect(kPetEggActive.value, isTrue, reason: '设定上没有兜底计时器');
  });
}
