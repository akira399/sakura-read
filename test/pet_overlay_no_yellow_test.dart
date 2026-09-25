// 桌宠台词气泡的「双黄线」回归测试。
//
// 背景：桌宠挂在 MaterialApp.builder 层（Navigator 的兄弟位，不在任何页面
// Material 之内）。MaterialApp 会把整棵树根部的 DefaultTextStyle 设为调试用
// 兜底样式（红字 + 黄色双下划线），任何裸 Text 都会继承它——引导层已经踩过
// 这个坑（见 pet_guide_overlay.dart 的 Material 包裹），桌宠气泡处在同一层级。
// 这里钉住：气泡文字的最终渲染样式不能带下划线 / 黄色装饰线。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_store.dart';
import 'package:sakura_read/src/ui/widgets/pet_overlay.dart';

void main() {
  testWidgets('桌宠台词气泡不应继承调试样式（防黄双下划线）', (tester) async {
    final pet = PetStore();

    await tester.pumpWidget(
      MaterialApp(
        // 复刻 app.dart 的真实层级：桌宠在 builder 层、Navigator 的兄弟位
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            PetOverlay(pet: pet),
          ],
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 点一下桌宠 → 冒出台词气泡。
    // 注意：桌宠同时绑定了 onTap 与 onDoubleTap，单击回调要等双击判定
    // 窗口（约 300ms）过去后才会触发。
    await tester.tap(find.byKey(const ValueKey('pet_positioned')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));

    // 气泡是该子树里唯一的 RichText
    final bubble = find.descendant(
      of: find.byKey(const ValueKey('pet_positioned')),
      matching: find.byType(RichText),
    );
    expect(bubble, findsOneWidget, reason: '点击后应出现台词气泡');

    final style = tester.widget<RichText>(bubble).text.style!;
    expect(
      style.decoration,
      isNot(TextDecoration.underline),
      reason: '气泡文字出现了下划线（继承调试样式的黄双下划线）',
    );
    expect(
      style.decorationColor,
      isNot(const Color(0xFFFFFF00)),
      reason: '气泡文字出现调试样式的黄色装饰线',
    );

    // 收尾：销毁渲染树 + 耗尽桌宠的巡检定时器
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 61));
  });
}
