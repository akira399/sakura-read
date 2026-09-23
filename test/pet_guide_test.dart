// 新手引导控制器（PetGuideController）的单测：推进 / 跳过 / 劝导 5 次 / 第 6 次锁屏。
import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:sakura_read/src/data/pet_guide.dart';
import 'package:sakura_read/src/data/pet_mood.dart';

void main() {
  test('引导流程：覆盖核心入口且不过长', () {
    expect(petGuideSteps.length, lessThanOrEqualTo(6), reason: '流程不宜过长');
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

  test('结构约束：只允许指向「常驻导航栏」的锚点', () {
    // 回归背景（v1.3.5）：曾让用户点击书架右上角的放大镜 → 跳到搜索页后，
    // 后续步骤的锚点（书架页的「＋」）随页面一起消失，引导必然卡死。
    // 因此规定：要求用户点击的锚点只允许是底部常驻导航项。
    const allowed = {'nav_shelf', 'nav_recent', 'nav_settings'};
    for (final s in petGuideSteps) {
      final id = s.anchorId;
      if (id == null) continue;
      expect(
        allowed.contains(id),
        isTrue,
        reason:
            '步骤「${s.id}」指向了 $id：会跳页/弹层的控件不能作为点击目标，'
            '否则后续锚点会消失导致引导卡死',
      );
    }
  });

  test('结构约束：不要求点击「会打开页面或面板」的入口', () {
    // 这些 id 曾经被用作锚点，属于已知危险目标
    const dangerous = {
      'shelf_search', // 打开搜索页
      'shelf_add', // 打开导入面板
      'shelf_arrange', // 打开排列面板
    };
    for (final s in petGuideSteps) {
      expect(
        dangerous.contains(s.anchorId),
        isFalse,
        reason: '步骤「${s.id}」指向了会跳页/弹层的 $s.anchorId',
      );
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
}
