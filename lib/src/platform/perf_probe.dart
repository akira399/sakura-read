import 'dart:developer' as dev;
import 'dart:ui' as ui show FramePhase;

import 'package:flutter/scheduler.dart';

/// 轻量帧率探针：只在 `--dart-define=PERF_PROBE=true` 编译时打开。
///
/// 用 [SchedulerBinding.addTimingsCallback] 收集真实帧耗时，每 5 秒往
/// logcat（`flutter` tag）打一行汇总，方便 `adb logcat | grep PERF` 直接读：
///
///   PERF frames=300 fps=59.8 build=1.2ms raster=2.1ms jank=0 (0.0%)
///
/// `jank` 定义为 build+raster 超过 16.7ms 的帧数——手机上就是掉帧的那几帧。
class PerfProbe {
  PerfProbe._();

  static const bool enabled = bool.fromEnvironment('PERF_PROBE');

  static final List<FrameTiming> _window = <FrameTiming>[];
  static Duration _windowStart = Duration.zero;

  /// 在 runApp 之前调用；未启用时什么都不做。
  static void start() {
    if (!enabled) return;
    _windowStart = Duration.zero;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    dev.log('PERF probe started', name: 'PERF');
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    final first = timings.first.timestampInMicroseconds(
      ui.FramePhase.vsyncStart,
    );
    if (_windowStart == Duration.zero) {
      _windowStart = Duration(microseconds: first);
    }
    _window.addAll(timings);
    final elapsed = Duration(
      microseconds:
          timings.last.timestampInMicroseconds(ui.FramePhase.vsyncStart) -
          _windowStart.inMicroseconds,
    );
    if (elapsed < const Duration(seconds: 5)) return;

    var build = 0;
    var raster = 0;
    var jank = 0;
    for (final t in _window) {
      final b = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      build += b;
      raster += r;
      if ((b + r) > 16667) jank++;
    }
    final frames = _window.length;
    final fps = frames * 1000000 / elapsed.inMicroseconds;
    final msg =
        'PERF frames=$frames fps=${fps.toStringAsFixed(1)} '
        'build=${(build / frames / 1000).toStringAsFixed(1)}ms '
        'raster=${(raster / frames / 1000).toStringAsFixed(1)}ms '
        'jank=$jank (${(jank * 100 / frames).toStringAsFixed(1)}%)';
    dev.log(msg, name: 'PERF');
    // ignore: avoid_print
    print(msg);
    _window.clear();
    _windowStart = Duration(
      microseconds: timings.last.timestampInMicroseconds(
        ui.FramePhase.vsyncStart,
      ),
    );
  }
}
