import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/ui/splash_gate.dart';

/// 开屏动画的节奏回归测试。
///
/// 线上出过一个问题：冷启动第一帧很慢，引擎把这段停顿一次性算进下一帧的
/// 时间戳，AnimationController 一帧就把 1.5s 动画播完，用户看到的就是
/// 「开屏动画没了」。这里钉住两个行为：
///  1. 正常帧率下，1.5s 之内开屏一直在，之后消失；
///  2. 哪怕出现一次超大的帧时间跳变，开屏也不会被瞬间略过。
void main() {
  Widget wrap() => const MaterialApp(
    home: SplashGate(forcePlay: true, child: Scaffold(body: Text('正文'))),
  );

  bool splashVisible(WidgetTester tester) => tester.any(find.text('樱 读'));

  testWidgets('开屏动画按真实帧推进，1.5 秒后消失', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(splashVisible(tester), isTrue, reason: '开屏一开始就应该在');

    // 模拟 60fps：每帧 16ms，累计到 0.8s
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(splashVisible(tester), isTrue, reason: '0.8s 时开屏还不该结束');

    // 再走 0.8s，累计 1.6s，应该结束
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(splashVisible(tester), isFalse, reason: '1.5s 之后开屏应该收起');
    expect(find.text('正文'), findsOneWidget);
  });

  testWidgets('单帧时间跳变不会把开屏整段略过', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(splashVisible(tester), isTrue);

    // 冷启动卡顿：一帧就跳了 3 秒（旧实现会直接跳到 100%）
    await tester.pump(const Duration(seconds: 3));
    expect(splashVisible(tester), isTrue, reason: '跳变只能推进一小步，不能一帧播完');

    // 之后正常走完剩余时间
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(splashVisible(tester), isFalse);
  });
}
