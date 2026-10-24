// 性能相关开关的回归测试（用户：「我也感觉有点卡，检查一下帧数，不要锁帧了」）。
//
// 覆盖：
//   ① 高刷新率开关：默认开启（默认按屏幕最高刷新率出帧，而不是钉在 60Hz）；
//   ② 帧率浮层开关：默认关闭，开启后持久化；
//   ③ 老版本设置文件没有这两个键时按默认值处理，不崩。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/native_bridge.dart';

/// 等 prefs 的 300ms 防抖落盘。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 450));

AppDirs _tempDirs(List<Directory> trash) {
  final dir = Directory.systemTemp.createTempSync('sakura_perf_');
  trash.add(dir);
  return AppDirs(files: dir.path, cache: '${dir.path}/cache');
}

void main() {
  final trash = <Directory>[];
  tearDown(() {
    for (final d in trash) {
      try {
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
    trash.clear();
  });

  group('高刷新率开关', () {
    test('默认开启', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      expect(prefs.highRefreshRate, isTrue);
    });

    test('关掉后写入 settings.json，重新加载能读回', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      prefs.setHighRefreshRate(false);
      await _settle();

      final raw =
          jsonDecode(File('${dirs.files}/settings.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(raw['highRefreshRate'], isFalse);

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.highRefreshRate, isFalse);
    });

    test('老版本设置文件（无该键）按默认值 true 处理', () async {
      final dirs = _tempDirs(trash);
      File(
        '${dirs.files}/settings.json',
      ).writeAsStringSync(jsonEncode({'v': 2, 'fontSize': 20}));

      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      expect(prefs.highRefreshRate, isTrue);
      expect(prefs.showPerformanceOverlay, isFalse);
    });
  });

  group('帧率浮层开关', () {
    test('默认关闭', () {
      final prefs = AppPrefs(dirsOverride: _tempDirs(trash));
      expect(prefs.showPerformanceOverlay, isFalse);
    });

    test('开启后持久化', () async {
      final dirs = _tempDirs(trash);
      final prefs = AppPrefs(dirsOverride: dirs);
      await prefs.load();
      prefs.setShowPerformanceOverlay(true);
      await _settle();

      final again = AppPrefs(dirsOverride: dirs);
      await again.load();
      expect(again.showPerformanceOverlay, isTrue);
    });
  });
}
