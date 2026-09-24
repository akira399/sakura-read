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

/// 引导步骤。
///
/// 支持**跨页面引导**（点放大镜 → 搜索页 → 点返回 → 回书架 → 点「＋」）：
///  - 锚点自带路由感知（[guideRouteObserver]）：本页被盖住时自动撤销上报，
///    避免高亮框飘在看不见的位置；
///  - 引导层挂在 MaterialApp 之上，因此**跳页后依然可见**，可以继续指向新页面
///    上的锚点（如搜索页的返回箭头）；
///  - 若跳转的是**弹出面板**（不占满屏幕，如导入面板），用
///    [PetGuideStep.hideWhileOpen] 在面板打开期间收起遮罩，免得挡住面板操作。
class PetGuideStep {
  const PetGuideStep({
    required this.id,
    required this.text,
    this.anchorId,
    this.hint,
    this.hideWhileOpen = false,
    this.freeRoam = false,
  });

  final String id;

  /// 小樱要指的目标（页面上注册的锚点 id）；null = 无目标，任意点击推进。
  final String? anchorId;

  /// 小樱说的话。
  final String text;

  /// 气泡下方的操作提示。
  final String? hint;

  /// 本步骤点击后会打开**弹出面板**（如「＋」弹出导入面板）：
  /// 点击后引导立即让开（目标被盖住即自动隐藏），面板关闭后自动进入下一步。
  final bool hideWhileOpen;

  /// 自由参观步骤：只高亮目标 + 小樱旁白，**不铺遮罩**、不计"不听话"。
  ///
  /// 用于「看看搜索页」这类探索性步骤——引导不该把页面堵死：
  /// 用户想先搜一下书、再点返回，是完全合理的（功能要符合直觉）。
  final bool freeRoam;

  bool get hasAnchor => anchorId != null;
}

const List<PetGuideStep> petGuideSteps = [
  PetGuideStep(
    id: 'intro',
    text: '呀，终于见到你啦！\n我是小樱，这本书城的看板娘～\n以后你看书的时候，我都会待在屏幕边上陪着你哦。',
    hint: '点一下继续',
  ),
  // ── 第 1 站：在线搜书（跳到搜索页 → 自由参观 → 点返回） ──
  PetGuideStep(
    id: 'search',
    anchorId: 'shelf_search',
    text: '想找书看，就点这个放大镜——里面是「在线搜书」，公版名著、热门网文都能搜到。',
    hint: '点一下这个放大镜',
  ),
  PetGuideStep(
    id: 'search_return',
    anchorId: 'search_back',
    text: '这里就是搜索页，输入书名就能搜～\n想试就试一下，看完点左上角箭头回书架。',
    hint: '点左上角箭头返回',
    freeRoam: true,
  ),
  // ── 第 2 站：导入本地书（打开导入面板，关闭后继续） ──
  PetGuideStep(
    id: 'import',
    anchorId: 'shelf_add',
    text: '手机里的 TXT / EPUB 小说，从这个「＋」导入，我会帮你整整齐齐摆上书架。',
    hint: '点一下这个「＋」',
    hideWhileOpen: true,
  ),
  // ── 第 3 站：底部两个常驻入口 ──
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
  bool _suppressed = false;
  String? _panelAnchor;
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

  /// 跳到指定 id 的步骤（保留给「需要指定落点」的场景）。
  void goToStep(String id) {
    if (!_active) return;
    final i = petGuideSteps.indexWhere((s) => s.id == id);
    if (i < 0 || i == _stepIndex) return;
    _stepIndex = i;
    _nagCount = 0;
    _nagLine = null;
    _softened = false;
    _armIdle();
    _armAnchorWatch();
    notifyListeners();
  }

  /// 用户点到了当前目标（由锚点的 Listener 在**点击当下**判定）。
  ///
  /// 注意：「是不是当前目标」必须在事件发生时读取 [step]，
  /// **绝不能在 build 时缓存**——锚点组件不在引导层内，引导推进时它不会重建，
  /// 缓存会过期，导致用户点对了却被漏判（曾造成"点了放大镜却卡在原地"）。
  void onTargetTapped(String anchorId) {
    if (!_active || step.anchorId != anchorId) return;
    _nagCount = 0;
    _nagLine = null;
    if (step.hideWhileOpen) {
      // 会弹出面板的入口（如「＋」打开导入面板）：
      // 先收起引导（免得遮罩挡住面板操作），等面板关闭后自动进入下一步。
      _panelAnchor = anchorId;
      _suppressed = true;
      _idleTimer?.cancel();
      notifyListeners();
      return;
    }
    advance();
  }

  /// 目标控件被销毁（所在页面关闭）。
  ///
  /// 典型场景：引导要你点搜索页的「返回箭头」，你却直接用了系统返回键——
  /// 页面同样回到了书架，这一步应当视为完成，而不是卡死在消失的目标上。
  void onAnchorGone(String anchorId) {
    if (!_active || _suppressed) return;
    if (step.anchorId == anchorId) advance();
  }

  /// 面板关闭、锚点重新露出 → 接续面板步骤的下一步。
  void onAnchorRevealed(String anchorId) {
    if (!_active) return;
    if (_panelAnchor == null || _panelAnchor != anchorId) return;
    _panelAnchor = null;
    _suppressed = false;
    advance();
  }

  /// 引导是否处于「临时收起」状态（面板打开期间）。
  bool get suppressed => _suppressed;

  /// 用户点了别处 / 迟迟不动 → 劝导。
  ///
  /// 返回 true 表示本次触发了锁屏（第 6 次不听话）。
  bool reportWrong() {
    if (!_active || _exhausted) return false;
    // 自由参观步骤：允许随便逛，不计"不听话"（功能要符合直觉）
    if (step.freeRoam) return false;
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
