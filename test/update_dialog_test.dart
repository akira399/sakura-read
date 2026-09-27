// 「发现新版本」更新弹窗的渲染回归测试。
//
// 为什么单测渲染：本项目多次出现「布局错误在 release 下表现为整屏灰
// ErrorWidget」的教训（ParentDataWidget 断言等），引导层与彩蛋层均踩坑。
// 更新弹窗是新的覆盖层组件，这里把「无异常 + 内容正确 + 无 ErrorWidget」
// 钉死；顺带验证「以后再说（自动）/关闭（手动）」的差异化行为。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakura_read/src/app_info.dart';
import 'package:sakura_read/src/data/prefs.dart';
import 'package:sakura_read/src/platform/update_service.dart';
import 'package:sakura_read/src/ui/update_dialog.dart';

/// 构造一条测试用更新信息。
UpdateInfo _info() => const UpdateInfo(
  version: '9.9.9',
  title: '樱读 v9.9.9',
  notes: '· 修复了状态栏\n· 新增更新检查',
  downloadUrl: 'https://github.com/a/b/releases/download/v9.9.9/x.apk',
  sizeBytes: 1024 * 1024,
  publishedAt: '',
  pageUrl: 'https://github.com/a/b/releases/tag/v9.9.9',
);

Future<void> _open(
  WidgetTester tester, {
  required bool isAuto,
  required AppPrefs prefs,
}) async {
  // 弹窗里有图片与进度组件；给一个宽裕的屏幕避免溢出误报
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                info: _info(),
                isAuto: isAuto,
                prefs: prefs,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 排空「以后再说」触发的 prefs 防抖保存定时器（300ms）。
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('自动弹窗：显示版本对比与更新说明，无 ErrorWidget', (tester) async {
    final prefs = AppPrefs();
    await _open(tester, isAuto: true, prefs: prefs);

    expect(find.text('发现新版本'), findsOneWidget);
    expect(
      find.text('v9.9.9 · 当前 v${AppInfo.version}'),
      findsOneWidget,
      reason: '应展示新版本与当前版本对比',
    );
    expect(find.textContaining('新增更新检查'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);

    // 布局异常在测试里会直接抛异常；这里再显式查一次 ErrorWidget
    expect(find.byType(ErrorWidget), findsNothing);
    await _drainTimers(tester);
  });

  testWidgets('自动弹窗点「以后再说」：记住该版本', (tester) async {
    final prefs = AppPrefs();
    await _open(tester, isAuto: true, prefs: prefs);

    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    expect(prefs.skipUpdateVersion, '9.9.9', reason: '自动弹窗略过后应记住版本');
    await _drainTimers(tester);
  });

  testWidgets('手动弹窗：按钮文案为「关闭」，且不记跳过版本', (tester) async {
    final prefs = AppPrefs();
    await _open(tester, isAuto: false, prefs: prefs);

    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('以后再说'), findsNothing);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(prefs.skipUpdateVersion, isEmpty, reason: '手动检查不写跳过标记');
    await _drainTimers(tester);
  });

  testWidgets('版本对比文案随 AppInfo 联动（发版漏改会立刻暴露）', (tester) async {
    final prefs = AppPrefs();
    await _open(tester, isAuto: false, prefs: prefs);
    // 该断言看似同义反复：真正的守护在 version_sync_test（pubspec ↔ AppInfo）。
    // 这里确保弹窗展示的就是 AppInfo.version，而不是硬编码字符串。
    final text = tester.widget<Text>(
      find.text('v9.9.9 · 当前 v${AppInfo.version}'),
    );
    expect(text.data, contains(AppInfo.version));
    await _drainTimers(tester);
  });
}
