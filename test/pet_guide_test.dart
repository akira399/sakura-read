// 新手引导控制器（PetGuideController）的单测：推进 / 跳过 / 劝导 5 次 / 第 6 次锁屏。
import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_mood.dart';

void main() {
  test('引导流程：覆盖核心入口且不过长', () {
    expect(petGuideSteps.length, lessThanOrEqualTo(8), reason: '流程不宜过长');
    expect(petGuideSteps.length, greaterThanOrEqualTo(3));
    final ids = petGuideSteps.map((s) => s.id).toList();
    expect(ids.first, 'intro');
    expect(ids.last, 'done');
    // 有锚点的步骤必须带指引提示
    for (final s in petGuideSteps) {
      if (s.hasAnchor) expect(s.hint, isNotNull);
      expect(s.text.trim(), isNotEmpty);
    }
  });

  test('流程覆盖关键功能：搜书 → 返回 → 导入 → 最近 → 设置', () {
    // 这是「不砍功能」的保障：跨页引导必须完整表达
    // 「点放大镜 → 进搜索页 → 点返回 → 回书架 → 点＋」这条链路。
    final ids = petGuideSteps.map((s) => s.id).toList();
    expect(ids, contains('search'));
    expect(ids, contains('search_return')); // 必须引导用户点返回
    expect(ids, contains('import'));
    expect(ids, contains('recent'));
    expect(ids, contains('settings'));

    // 「返回」步骤必须排在「进入搜索页」之后
    expect(ids.indexOf('search_return'), greaterThan(ids.indexOf('search')));
    // 「导入」应排在返回之后（此时已回到书架）
    expect(ids.indexOf('import'), greaterThan(ids.indexOf('search_return')));
  });

  test('锚点 id 与页面注册保持一致', () {
    // 这些 id 在页面里通过 PetGuideTarget(id: ...) 注册；
    // 若改了名字却忘了同步，引导会找不到目标（曾导致流程卡死）。
    final used = petGuideSteps
        .map((s) => s.anchorId)
        .whereType<String>()
        .toSet();
    const known = {
      'shelf_search', // 书架右上角放大镜
      'shelf_add', // 书架右下角「＋」
      'search_back', // 搜索页左上角返回
      'nav_shelf',
      'nav_recent',
      'nav_settings',
    };
    for (final id in used) {
      expect(known.contains(id), isTrue, reason: '未知锚点 $id（页面里没有注册）');
    }
  });

  test('start → 逐步推进 → 最后一步结束并回调 onFinished', () {
    var finished = 0;
    final c = PetGuideController(onFinished: () => finished++);
    addTearDown(c.dispose);

    c.start();
    expect(c.active, isTrue);
    expect(kPetGuideActive.value, isTrue);
    expect(c.stepIndex, 0);

    // 无锚点的开场步骤：可以推进
    c.advance();
    expect(c.stepIndex, 1);

    // 一直推进到结束
    for (var i = 0; i < petGuideSteps.length; i++) {
      if (!c.active) break;
      if (c.step.hasAnchor) {
        c.registerAnchor(c.step.anchorId!, const Rect.fromLTWH(0, 0, 10, 10));
      }
      c.advance();
    }
    expect(c.active, isFalse);
    expect(finished, 1, reason: '正常结束应回调一次');
    expect(kPetGuideActive.value, isFalse);
  });

  test('开头可跳过：skip 立即结束且回调', () {
    var finished = 0;
    final c = PetGuideController(onFinished: () => finished++);
    addTearDown(c.dispose);
    c.start();
    c.skip();
    expect(c.active, isFalse);
    expect(finished, 1);
  });

  test('不听话时劝导 5 次，语气逐次变化，第 6 次触发锁屏', () {
    var burned = 0;
    final c = PetGuideController(onPatienceRunOut: () => burned++);
    addTearDown(c.dispose);
    c.start();
    // 进入一个带锚点的步骤
    c.advance();
    expect(c.step.hasAnchor, isTrue);

    for (var i = 1; i <= petGuideNags.length; i++) {
      final locked = c.reportWrong();
      expect(locked, isFalse, reason: '第 $i 次不该锁屏');
      expect(c.nagCount, i);
      expect(c.nagLine, petGuideNags[i - 1], reason: '语气应按顺序递进');
    }
    // 第 6 次：耐心耗尽 → 锁屏
    expect(c.reportWrong(), isTrue);
    expect(c.exhausted, isTrue);
    expect(c.active, isFalse, reason: '锁屏前应退出引导');
    expect(burned, 1);
  });

  test('点对位置会重置劝导计数（不算不听话）', () {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();
    c.reportWrong();
    expect(c.nagCount, 1);
    // 用「当前步骤真正的锚点 id」上报，避免硬编码（锚点会随流程调整）
    c.registerAnchor(c.step.anchorId!, const Rect.fromLTWH(0, 0, 10, 10));
    c.advance();
    expect(c.nagCount, 0);
    expect(c.nagLine, isNull);
  });

  test('锚点缺失时软化为「点任意处继续」，避免引导卡死', () async {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();
    expect(c.step.hasAnchor, isTrue);
    expect(c.anchorRect, isNull);
    await Future<void>.delayed(
      PetGuideController.anchorGrace + const Duration(milliseconds: 120),
    );
    expect(c.softened, isTrue, reason: '锚点迟迟不出现应软化');
    expect(c.anchorRect, isNull);
  });

  test('锚点上报后可取到矩形', () {
    final c = PetGuideController();
    addTearDown(c.dispose);
    c.start();
    c.advance();
    const r = Rect.fromLTWH(12, 34, 56, 78);
    final id = c.step.anchorId!;
    c.registerAnchor(id, r);
    expect(c.anchorRect, r);
    c.unregisterAnchor(id);
    expect(c.anchorRect, isNull);
  });

  group('直觉交互（回归：曾把用户操作误判为"不听话"）', () {
    test('点中目标应立即推进（判定在点击当下做，不看缓存）', () {
      final c = PetGuideController();
      addTearDown(c.dispose);
      c.start();
      c.advance(); // 第一个带锚点的步骤（放大镜）
      final id = c.step.anchorId!;
      expect(id, 'shelf_search');

      // 模拟"点击当下"回调（锚点 Listener 调用）
      c.onTargetTapped(id);
      expect(
        c.step.id,
        'search_return',
        reason: '点了目标（放大镜）应立即进入下一步——曾因缓存过期被漏判',
      );
      expect(c.nagCount, 0, reason: '点对目标不应记"不听话"');
    });

    test('点目标后切页 + 用系统返回键关页 → 视为完成，不算不听话', () {
      final c = PetGuideController();
      addTearDown(c.dispose);
      c.start();
      c.advance();
      c.onTargetTapped('shelf_search'); // 进入搜索页
      expect(c.step.id, 'search_return');

      // 用户没点"返回箭头"，直接用系统返回键 → 锚点销毁
      c.onAnchorGone('search_back');
      expect(c.step.id, 'import', reason: '目标随页面关闭 → 这一步应视为完成（返回键也是返回）');
      expect(c.nagCount, 0);
    });

    test('自由参观（freeRoam）步骤：点非目标处不计"不听话"', () {
      final c = PetGuideController();
      addTearDown(c.dispose);
      c.start();
      c.goToStep('search_return');
      expect(c.step.freeRoam, isTrue, reason: '搜索页应是自由参观步骤');

      c.registerAnchor('search_back', const Rect.fromLTWH(1, 2, 3, 4));
      // 模拟"点到页面别处"（自由参观下不该有遮罩，但即便记到也应直接推进）
      c.reportWrong();
      expect(c.nagCount, 0, reason: '自由参观不该累计劝导次数');
    });

    test('面板入口（＋）：点击后收起引导，面板关闭后自动继续', () {
      final c = PetGuideController();
      addTearDown(c.dispose);
      c.start();
      c.goToStep('import');
      expect(c.step.hideWhileOpen, isTrue);
      final id = c.step.anchorId!;
      c.registerAnchor(id, const Rect.fromLTWH(300, 600, 60, 60));

      final before = c.stepIndex;
      c.onTargetTapped(id); // 面板打开（锚点被盖住）
      expect(c.suppressed, isTrue, reason: '面板打开时引导应立即让路');
      expect(c.stepIndex, before, reason: '面板未关闭前不推进');

      c.onAnchorRevealed(id); // 面板关闭
      expect(c.suppressed, isFalse);
      expect(c.stepIndex, before + 1, reason: '面板看完自动进入下一步');
    });
  });
}
