import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/ui/reader/cover_turn.dart';

// 纯色占位页，便于逐像素断言。
const _green = Color(0xFF00CC00);
const _red = Color(0xFFCC0000);
const _blue = Color(0xFF0000CC);

Future<(ByteData, int)> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (bytes, image.width);
  });
  expect(result, isNotNull, reason: '未能栅格化测试画面');
  final (bytes, width) = result!;
  expect(bytes, isNotNull, reason: '未能读取像素数据');
  return (bytes!, width);
}

List<int> _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  ];
}

bool _isBlue(List<int> p) => p[2] > 150 && p[0] < 80 && p[1] < 80;

bool _isGreen(List<int> p) => p[1] > 120 && p[0] < 80;

bool _isRed(List<int> p) => p[0] > 150 && p[2] < 80;

/// 构造一个 800x600 的测试画面：
/// - 整屏铺底绿色；
/// - 一个 400x200 的"条目"放在屏幕 [200, 600) 处，
///   内容为左半红、右半蓝（模拟一页的左右两部分）。
Widget _frame(CoverTurnItem item) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: _green)),
        Positioned(left: 200, top: 0, width: 400, height: 200, child: item),
      ],
    ),
  );
}

Widget _twoToneChild() {
  return Row(
    children: [
      SizedBox(width: 200, height: 200, child: ColoredBox(color: _red)),
      SizedBox(width: 200, height: 200, child: ColoredBox(color: _blue)),
    ],
  );
}

void main() {
  // 覆盖翻页的核心回归：0 < delta < 1 的"钉住页"必须
  // 1) 只显示已被揭示的右侧部分（本测试中为蓝色半页）；
  // 2) 平移出视口的部分被显式裁剪（红色半页不得溢出到左侧）。
  // 之前依赖 Stack 隐式裁剪时，非定位子级的平移不会被裁剪——
  // 该测试会在那种回归下立刻失败（左侧变红）。
  testWidgets('覆盖翻页：钉住页只揭示右侧、左侧不溢出', (tester) async {
    const key = ValueKey('cover-frame');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: _frame(
          CoverTurnItem(
            delta: 0.5,
            width: 400,
            shadowWidth: 0,
            child: _twoToneChild(),
          ),
        ),
      ),
    );
    await tester.pump();

    final (bytes, width) = await _capture(tester, key);

    final left = _pixel(bytes, width, 60, 100);
    expect(
      _isGreen(left),
      isTrue,
      reason: '条目平移出左侧的部分必须被裁剪（应露出底层绿色），实际 RGB=$left',
    );

    final mid = _pixel(bytes, width, 210, 100);
    expect(_isBlue(mid), isTrue, reason: '揭示区应显示钉住页的右半（蓝色），实际 RGB=$mid');

    final right = _pixel(bytes, width, 390, 100);
    expect(_isBlue(right), isTrue, reason: '揭示区右端应为蓝色，实际 RGB=$right');
  });

  // 前缘投影：贴住移动页边缘，左深右浅（对应原版 shadowDrawableR）。
  testWidgets('覆盖翻页：前缘渐变投影带（左深右浅）', (tester) async {
    const key = ValueKey('cover-shadow');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: _frame(
          const CoverTurnItem(
            delta: 0.5,
            width: 400,
            shadowWidth: 30,
            child: ColoredBox(color: _blue),
          ),
        ),
      ),
    );
    await tester.pump();

    final (bytes, width) = await _capture(tester, key);

    int brightnessAt(int x) {
      final p = _pixel(bytes, width, x, 100);
      return p[0] + p[1] + p[2];
    }

    final atEdge = brightnessAt(204); // 投影带内、贴近边界
    final atFade = brightnessAt(226); // 投影带尾部（渐隐）
    final outside = brightnessAt(390); // 带外纯色
    expect(
      atEdge < outside - 25,
      isTrue,
      reason: '边缘应有明显投影（edge=$atEdge, outside=$outside）',
    );
    expect(
      atEdge < atFade,
      isTrue,
      reason: '投影应左深右浅（edge=$atEdge, fade=$atFade）',
    );
  });

  // delta 在 (0,1) 之外（静止页 / 离屏页）应原样绘制，不做裁剪。
  testWidgets('覆盖翻页：静止页原样绘制（delta=0 / 1）', (tester) async {
    const key = ValueKey('cover-static');
    for (final delta in const [0.0, 1.0]) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _frame(
            CoverTurnItem(
              delta: delta,
              width: 400,
              shadowWidth: 12,
              child: _twoToneChild(),
            ),
          ),
        ),
      );
      await tester.pump();

      final (bytes, width) = await _capture(tester, key);
      final a = _pixel(bytes, width, 300, 100);
      expect(_isRed(a), isTrue, reason: 'delta=$delta 时左半页应原样显示（红色），实际 RGB=$a');
      final b = _pixel(bytes, width, 500, 100);
      expect(
        _isBlue(b),
        isTrue,
        reason: 'delta=$delta 时右半页应原样显示（蓝色），实际 RGB=$b',
      );
    }
  });
}
