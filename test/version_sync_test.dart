// 版本号一致性守护测试。
//
// 背景：版本号存在于两个位置，发版时必须一起改：
//   - `pubspec.yaml` 的 `version:`（语义版本 + build 号，Android 安装包用）
//   - `lib/src/app_info.dart` 的 `AppInfo.version`（设置页「关于」展示）
// 漏改任何一处都会导致「关于」页显示旧版本号 → 用户反馈版本对不上。
//
// 这里在测试阶段就把关：两处语义版本必须一致。
// （build 号可以只增不减地前进，check 只看 `+` 前面的部分。）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/app_info.dart';

void main() {
  test('pubspec 与 AppInfo 的版本号必须一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 里找不到 version: 行');

    final pubspecVersion = match!.group(1)!.split('+').first;
    expect(
      AppInfo.version,
      pubspecVersion,
      reason:
          '版本不同步：pubspec=$pubspecVersion，app_info=${AppInfo.version}\n'
          '发版时请同时修改两处（见 CONTRIBUTING.md「版本与发版」）。',
    );
  });

  test('build 号存在且为数字（保证可覆盖安装）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*\S+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      match,
      isNotNull,
      reason:
          'pubspec.yaml 的 version 必须带 build 号（形如 1.0.0+49），否则 Android 无法比较新旧',
    );
    expect(int.parse(match!.group(1)!), greaterThan(0));
  });
}
