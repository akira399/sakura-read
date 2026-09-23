// 回归测试：开屏文字必须处于 Material 内。
//
// 背景：MaterialApp 会把整棵树的根 DefaultTextStyle 设为一段“兜底样式”，
// 该样式自带黄色双下划线（decorationColor 0xFFFFFF00 + double 样式），
// 用于提示开发者“文字没有包在 Material 里”。开屏文字若落在 Material 之外，
// 标题与副标题下方会出现突兀的“双黄线”（真实发生过的 bug）。
// 本测试确保 SplashGate 的文字始终有 Material 祖先。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/ui/splash_gate.dart';

void main() {
  testWidgets('开屏标题与副标题必须处于 Material 内（防双黄线下划线）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashGate(child: SizedBox.shrink())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('樱 读'), findsOneWidget);
    expect(find.text('在樱花树下，慢慢读完一本书'), findsOneWidget);

    expect(
      find.ancestor(of: find.text('樱 读'), matching: find.byType(Material)),
      findsWidgets,
      reason: '开屏标题必须位于 Material 内，否则会出现黄色双下划线',
    );
    expect(
      find.ancestor(
        of: find.text('在樱花树下，慢慢读完一本书'),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: '开屏副标题必须位于 Material 内，否则会出现黄色双下划线',
    );

    // 结束动画，避免帧回调遗留。
    await tester.pump(const Duration(milliseconds: 1600));
  });
}
