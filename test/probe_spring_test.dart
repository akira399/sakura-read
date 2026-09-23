// 一次性探针：模拟 PageScrollPhysics 吸附弹簧的收敛尾巴，
// 量化“翻页末段（还差几 px）磨蹭多少毫秒”，验证“停顿”是否来自弹簧收敛过慢。
// 运行：flutter test test/probe_spring_test.dart
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spring tail probe', () {
    // 页面宽（逻辑 px）：1272/3.5 - 2*20 ≈ 323.4
    const w = 323.4;

    void trace(
      String label,
      SpringDescription spring,
      double startPage, [
      double v = 0,
    ]) {
      final sim = ScrollSpringSimulation(spring, startPage, 5.0, v);
      final sb = StringBuffer();
      sb.write('[$label] ');
      var last = startPage;
      var lastT = 0.0;
      for (var frame = 0; frame <= 120; frame++) {
        final t = frame / 60.0;
        if (sim.isDone(t)) {
          sb.write(
            'DONE@${(t * 1000).round()}ms(剩${((5.0 - sim.x(t)) * w).toStringAsFixed(2)}px) ',
          );
          break;
        }
        final x = sim.x(t);
        if (frame % 4 == 3 || frame < 12) {
          final remainPx = (5.0 - x) * w;
          final deltaPx = (x - last) * w;
          sb.write(
            '${(t * 1000).round()}:${remainPx.toStringAsFixed(1)}px(移${deltaPx.toStringAsFixed(1)}) ',
          );
          last = x;
          lastT = t;
        }
      }
      // ignore: avoid_print
      print(sb.toString());
      assert(lastT >= 0);
    }

    final classic = SpringDescription.withDampingRatio(
      mass: 0.5,
      stiffness: 100.0,
      ratio: 1.1,
    );
    final stiff200 = SpringDescription.withDampingRatio(
      mass: 0.5,
      stiffness: 200.0,
      ratio: 1.0,
    );
    final stiff500 = SpringDescription.withDampingRatio(
      mass: 0.5,
      stiffness: 500.0,
      ratio: 1.0,
    );

    // ignore: avoid_print
    print('=== A. 默认 spring（m=0.5, k=100, ratio=1.1） ===');
    trace('整页 4.0→5.0', classic, 4.0);
    trace('半程 4.5→5.0', classic, 4.5);
    trace('末段 4.9→5.0(剩32px)', classic, 4.9);
    trace('末段 4.977→5.0(剩7px)', classic, 4.977);
    // ignore: avoid_print
    print('=== B. 硬一点（k=200, ratio=1.0 临界） ===');
    trace('整页 4.0→5.0', stiff200, 4.0);
    trace('半程 4.5→5.0', stiff200, 4.5);
    trace('末段 4.9→5.0(剩32px)', stiff200, 4.9);
    // ignore: avoid_print
    print('=== C. 很硬（k=500, ratio=1.0） ===');
    trace('整页 4.0→5.0', stiff500, 4.0);
    trace('半程 4.5→5.0', stiff500, 4.5);
    trace('末段 4.9→5.0(剩32px)', stiff500, 4.9);
  });
}
