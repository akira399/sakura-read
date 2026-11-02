import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/ui/widgets/glass_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Stack(children: [child])),
  );

  testWidgets('打开磨砂时用 BackdropFilter 实时模糊', (tester) async {
    await tester.pumpWidget(
      wrap(
        GlassBar(
          frosted: true,
          tint: const Color(0xFF121212),
          radius: BorderRadius.circular(18),
          child: const SizedBox(height: 60, width: 400),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('关掉磨砂时退回实色底板，不含模糊层', (tester) async {
    await tester.pumpWidget(
      wrap(
        GlassBar(
          frosted: false,
          tint: const Color(0xFF121212),
          radius: BorderRadius.circular(18),
          child: const SizedBox(height: 60, width: 400),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GlassBar),
        matching: find.byType(DecoratedBox),
      ),
    );
    final color = (decorated.decoration as BoxDecoration).color!;
    expect(color.a, 1.0, reason: '关闭磨砂应该完全不透明');
  });

  testWidgets('磨砂打开时底板是半透明的，能透出下面的正文', (tester) async {
    await tester.pumpWidget(
      wrap(
        GlassBar(
          frosted: true,
          tint: const Color(0xFF121212),
          radius: BorderRadius.circular(18),
          child: const SizedBox(height: 60, width: 400),
        ),
      ),
    );
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GlassBar),
        matching: find.byType(DecoratedBox),
      ),
    );
    final color = (decorated.decoration as BoxDecoration).color!;
    expect(color.a, lessThan(1.0), reason: '磨砂层应该是半透明');
    expect(color.a, greaterThan(0.4), reason: '太透会看不清文字');
  });
}
