// 新手引导：小樱带新用户走一遍核心功能。
//
// 设计（与 UI 解耦、可单测）：
//  - 流程很短：自我介绍 → 在线搜书 → 导入本地书 → 设置入口 → 收尾；
//  - 开头可跳过（`skip()`）；
//  - 用户不按指引点击时「劝导」：语气逐次变差（[petGuideNags]）；
//  - 劝导满 [petGuideNags].length 次后，再有一次不听话 → 直接锁屏彩蛋。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Rect;

import 'pet_mood.dart';

/// 引导是否进行中（全局通知：桌宠本体在此间隐藏，由引导层自己摆位）。
final ValueNotifier<bool> kPetGuideActive = ValueNotifier<bool>(false);

/// 引导的一步。
class PetGuideStep {
  const PetGuideStep({
    required this.id,
    required this.text,
    this.anchorId,
    this.hint,
  });
  final String id;

  /// 小樱要指的目标（页面上注册的锚点 id）；null = 无目标，任意点击推进。
  final String? anchorId;

  /// 小樱说的话。
  final String text;

  /// 气泡下方的操作提示。
  final String? hint;

  bool get hasAnchor => anchorId != null;
}

/// 引导步骤。
///
/// 设计原则（踩坑后的硬约束）：
///  - **只让用户点「不会切换页面 / 不会弹层」的控件**。一旦某一步要求点的按钮
///    会跳页（如放大镜进搜索页）或弹面板，后续步骤的锚点就会随页面一起消失，
///    引导必然卡死。
///  - 因此「会跳页的入口」只做**口头介绍**（无锚点，点任意处继续），
///    真正要求点击的只有底部三个常驻导航项。
const List<PetGuideStep> petGuideSteps = [
  PetGuideStep(
    id: 'intro',
    text: '呀，终于见到你啦！\n我是小樱，这本书城的看板娘～\n以后你看书的时候，我都会待在屏幕边上陪着你哦。',
    hint: '点一下继续',
  ),
  PetGuideStep(
    id: 'shelf',
    anchorId: 'nav_shelf',
    text: '这里是你的书架，导入的书都会摆在这儿。右下角的「＋」可以导入本地小说，\n右上角的放大镜能在线搜书～',
    hint: '点一下「书架」',
  ),
  PetGuideStep(
    id: 'recent',
    anchorId: 'nav_recent',
    text: '「最近」里记着你读到哪儿了，想接着上次的地方读，从这里点最快。',
    hint: '点一下「最近」',
  ),
  PetGuideStep(
    id: 'settings',
    anchorId: 'nav_settings',
    text: '书源、朗读、还有我的各种开关，都藏在「设置」里，记得去看看。',
    hint: '点一下「设置」',
  ),
  PetGuideStep(
    id: 'done',
    text: '好啦，剩下的就交给你自己啦。\n想我的时候，戳我一下就行～',
    hint: '点一下完成',
  ),
];

/// 引导控制器。
class PetGuideController extends ChangeNotifier {
  PetGuideController({this.onFinished, this.onPatienceRunOut});

  /// 当前进程内生效的引导控制器（页面里的锚点通过它上报位置）。
  static PetGuideController? current;

  /// 引导正常结束 / 被跳过时回调（用于持久化「已看过引导」）。
  VoidCallback? onFinished;

  /// 耐心耗尽（第 6 次不听话）时回调 → 由 UI 层触发锁屏彩蛋。
  VoidCallback? onPatienceRunOut;

  /// 超时未操作也算一次「不听话」（比误点温和，间隔给足）。
  static const Duration idleNagDelay = Duration(seconds: 20);

  /// 当前步骤的锚点迟迟没出现在屏幕上时，等这么久就「软化」该步骤
  /// （点任意处即可继续），避免引导卡死在不可见的控件上。
  static const Duration anchorGrace = Duration(milliseconds: 1500);

  final Map<String, Rect> _anchors = {};

  bool _active = false;
  int _stepIndex = 0;
  int _nagCount = 0;
  String? _nagLine;
  bool _exhausted = false;
  bool _softened = false;
  Timer? _idleTimer;
  Timer? _anchorTimer;

  bool get active => _active;
  int get stepIndex => _stepIndex;
  int get nagCount => _nagCount;
  String? get nagLine => _nagLine;

  /// 当前步骤是否已软化（锚点不可见 → 不强制点指定位置）。
  bool get softened => _softened;

  /// 是否已经因不听话而触发锁屏（用于测试与去重）。
  bool get exhausted => _exhausted;

  PetGuideStep get step =>
      petGuideSteps[_stepIndex.clamp(0, petGuideSteps.length - 1)];

  bool get isLast => _stepIndex >= petGuideSteps.length - 1;

  /// 当前步骤指向的锚点矩形（未注册 / 无锚点时为 null）。
  Rect? get anchorRect {
    if (_softened) return null;
    final id = step.anchorId;
    if (id == null) return null;
    return _anchors[id];
  }

  Rect? rectOf(String id) => _anchors[id];

  // ---------- 锚点注册（页面在 layout 后上报） ----------

  void registerAnchor(String id, Rect rect) {
    if (_anchors[id] == rect) return;
    _anchors[id] = rect;
    if (_active) notifyListeners();
  }

  void unregisterAnchor(String id) {
    if (_anchors.remove(id) != null && _active) notifyListeners();
  }

  // ---------- 流程 ----------

  void start() {
    if (_active) return;
    _active = true;
    _stepIndex = 0;
    _nagCount = 0;
    _nagLine = null;
    _exhausted = false;
    current = this;
    kPetGuideActive.value = true;
    _armIdle();
    _armAnchorWatch();
    notifyListeners();
  }

  /// 跳过引导（开头即可用）。
  void skip() => _finish();

  /// 用户点了正确的位置 → 进入下一步。
  void advance() {
    if (!_active) return;
    _nagCount = 0;
    _nagLine = null;
    if (isLast) {
      _finish();
      return;
    }
    _stepIndex++;
    _softened = false;
    _armIdle();
    _armAnchorWatch();
    notifyListeners();
  }

  /// 用户点了别处 / 迟迟不动 → 劝导。
  ///
  /// 返回 true 表示本次触发了锁屏（第 6 次不听话）。
  bool reportWrong() {
    if (!_active || _exhausted) return false;
    _nagCount++;
    if (_nagCount > petGuideNags.length) {
      _exhausted = true;
      _idleTimer?.cancel();
      _active = false;
      kPetGuideActive.value = false;
      notifyListeners();
      onPatienceRunOut?.call();
      return true;
    }
    _nagLine = petGuideNags[_nagCount - 1];
    _armIdle();
    notifyListeners();
    return false;
  }

  void _finish() {
    _idleTimer?.cancel();
    _anchorTimer?.cancel();
    final wasActive = _active;
    _active = false;
    _nagCount = 0;
    _nagLine = null;
    _softened = false;
    if (identical(current, this)) current = null;
    kPetGuideActive.value = false;
    if (wasActive) {
      onFinished?.call();
      notifyListeners();
    }
  }

  /// 当前步骤的锚点若迟迟没上报（控件不在屏幕上 / 未渲染），
  /// 就软化该步骤：遮罩铺满全屏，点任意处即可继续（避免卡死）。
  void _armAnchorWatch() {
    _anchorTimer?.cancel();
    if (!step.hasAnchor) return;
    _anchorTimer = Timer(anchorGrace, () {
      if (!_active || _softened) return;
      if (anchorsMissing) {
        _softened = true;
        notifyListeners();
      }
    });
  }

  /// 当前步骤的锚点是否仍未上报。
  bool get anchorsMissing {
    final id = step.anchorId;
    return id != null && !_anchors.containsKey(id);
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleNagDelay, () {
      if (_active) reportWrong();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _anchorTimer?.cancel();
    if (identical(current, this)) current = null;
    super.dispose();
  }
}
