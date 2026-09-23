// PageSnapPhysics / PageSnapSimulation 的回归测试。
//
// 背景：Flutter 默认 PageScrollPhysics 用过阻尼弹簧吸附，
// 实测整页翻完需 ~1s、最后 30px 磨蹭 400~500ms（见 tool 里的弹簧探针记录）。
// 现在改为「阅读 3.0 风格」的固定速率吸附，本测试锁定三个关键性质：
// 1) 整页 ≈300ms 完成；2) 短距压缩到下限 110ms，不再磨蹭；
// 3) 已对齐位置不再生成动画（杜绝二次微调循环）。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/ui/reader/page_snap_physics.dart';

void main() {
  group('PageSnapSimulation', () {
    test('整页距离 ≈300ms 且终点精确', () {
      final sim = PageSnapSimulation(from: 0, to: 323.4, pageExtent: 323.4);
      expect(sim.duration, closeTo(0.300, 1e-9));
      expect(sim.isDone(0.2999), isFalse);
      expect(sim.isDone(0.3001), isTrue);
      expect((sim.x(0.31) - 323.4).abs() < 1e-9, isTrue);
    });

    test('短距（剩 26px 级）压缩到下限 110ms，不再有 400ms 磨蹭', () {
      final sim = PageSnapSimulation(from: 1000, to: 1026, pageExtent: 323.4);
      expect(sim.duration, closeTo(0.110, 1e-9));
      expect(sim.isDone(0.1099), isFalse);
      expect(sim.isDone(0.1101), isTrue);
      expect((sim.x(0.111) - 1026).abs() < 1e-9, isTrue);
    });

    test('曲线单调向前且不越过目标', () {
      final sim = PageSnapSimulation(from: 0, to: -323.4, pageExtent: 323.4);
      var prev = sim.x(0);
      for (var t = 0.0; t <= 0.4; t += 1 / 240) {
        final x = sim.x(t);
        expect(x <= prev + 1e-9, isTrue, reason: 't=$t 出现回退');
        expect(x >= -323.4 - 1e-9, isTrue, reason: 't=$t 越过目标');
        prev = x;
      }
    });
  });

  group('PageSnapPhysics', () {
    FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 6000,
      pixels: pixels,
      viewportDimension: 323.4,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 3.5,
    );

    test('未对齐（剩 7px）→ 生成仿真且 150ms 内完结', () {
      final sim = const PageSnapPhysics().createBallisticSimulation(
        metrics(4.977 * 323.4),
        0,
      );
      expect(sim, isNotNull);
      expect(sim!.isDone(0.15), isTrue, reason: '剩 7.4px 应在 150ms 内完结');
      expect((sim.x(0.15) - 5.0 * 323.4).abs() < 1e-9, isTrue);
    });

    test('已对齐（含浮点残差）→ null，杜绝二次微调循环', () {
      final sim = const PageSnapPhysics().createBallisticSimulation(
        metrics(5.0 * 323.4 - 1e-12),
        0,
      );
      expect(sim, isNull);
    });

    test('超过半页 + 正向速度 → 对齐到下一页整页位置', () {
      final sim = const PageSnapPhysics().createBallisticSimulation(
        metrics(4.6 * 323.4),
        900,
      );
      expect(sim, isNotNull);
      expect((sim!.x(1.0) - 5.0 * 323.4).abs() < 1e-9, isTrue);
    });

    test('弱速度 → 对齐到最近整页（4.2 → 4）', () {
      final sim = const PageSnapPhysics().createBallisticSimulation(
        metrics(4.2 * 323.4),
        0,
      );
      expect(sim, isNotNull);
      expect((sim!.x(1.0) - 4.0 * 323.4).abs() < 1e-9, isTrue);
    });
  });
}
