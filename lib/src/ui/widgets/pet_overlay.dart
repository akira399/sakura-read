import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/pet_mood.dart';
import '../../data/pet_store.dart';

/// 全局悬浮桌宠：可拖动、点击互动（换表情 + 台词 + 亲密度 +1）。
///
/// 通过 MaterialApp 的 builder 覆盖层承载，任何页面（除阅读器内）都能看到。
class PetOverlay extends StatefulWidget {
  const PetOverlay({super.key, required this.pet, this.hostReady});

  final PetStore pet;

  /// 宿主就绪开关（开屏 / 权限页时不显示）。
  final ValueListenable<bool>? hostReady;

  @override
  State<PetOverlay> createState() => _PetOverlayState();
}

/// 透明立绘差分（Q 版；背景已去除，只含人物）。
const _petFaces = [
  'assets/images/pet_chibi.png',
  'assets/images/pet_wave.png',
  'assets/images/pet_read.png',
  'assets/images/pet_cheer.png',
  'assets/images/pet_sleep.png',
  'assets/images/pet_shy.png',
  'assets/images/pet_angry.png',
  'assets/images/pet_rage.png',
];

/// hostReady 缺省值（避免每次 build 新建 ValueNotifier）。
final ValueNotifier<bool> _alwaysReady = ValueNotifier<bool>(true);

/// 彩蛋是否激活（全黑锁定界面）。由 PetOverlay 在触发时置真。
final ValueNotifier<bool> kPetEggActive = ValueNotifier<bool>(false);

/// 摸头台词（双击触发）。
const _petPatLines = ['诶嘿……被摸头啦', '呜……好舒服', '呀！别、别突然摸头啦', '再摸一下也不是不可以……'];

class _PetOverlayState extends State<PetOverlay> with TickerProviderStateMixin {
  static const double _size = 74;

  late final AnimationController _bobber;
  late final AnimationController _celebrate; // 升级 / 投喂庆祝弹跳
  late final AnimationController _hearts; // 摸头飘心
  Timer? _lineTimer;
  Timer? _dozeTimer;
  Timer? _faceTimer;
  Timer? _greetTimer;
  String? _line;
  int _faceIndex = 0;

  /// 最近一次互动时间（用于判断打瞌睡）。
  DateTime _lastInteractionAt = DateTime.now();

  /// 是否处于瞌睡状态（深夜或长时间未互动）。
  bool _dozing = false;

  /// 拖拽倾斜角度（±0.2 rad，松手回正）。
  double _tilt = 0;

  /// 已见过的投喂时间戳（用于触发投喂反应）。
  int _seenFeedAt = 0;

  /// 是否已做过时段问候。
  bool _greeted = false;

  /// 摸头飘心是否显示中。
  bool _showHearts = false;

  /// 互动心情状态机（生气 / 彩蛋 / 随机台词）。
  final PetMood _mood = PetMood();

  /// 蹦跳动画（点击时在屏幕内随机位移）。
  Timer? _hopTimer;

  /// 生气表情持续时间。
  Timer? _angryTimer;

  /// 乱跑（捣乱）相关。
  Timer? _roamCheckTimer;
  bool _roaming = false;
  int _roamLoopsLeft = 0;

  /// 奔跑动画相位（0~1 循环，用于身体起伏 + 前倾）。
  double _runPhase = 0;
  Timer? _runAnimTimer;

  double _dx = 0;
  double _dy = 0;
  bool _positioned = false;

  /// 屏幕可用范围（供蹦跳计算；在 build 时刷新）。
  double _maxX = 0;
  double _maxY = 0;

  @override
  void initState() {
    super.initState();
    _bobber = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _celebrate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _hearts = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _hearts.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showHearts = false);
      }
    });
    _seenFeedAt = widget.pet.lastFeedAt;
    widget.pet.addListener(_onPetChanged);
    _checkPendingGains();
    _startDozeTimer();
    _startRoamWatch();
    // 进入后稍等片刻，做一次时段问候
    _greetTimer = Timer(const Duration(milliseconds: 900), _greetByTime);
  }

  @override
  void dispose() {
    widget.pet.removeListener(_onPetChanged);
    _lineTimer?.cancel();
    _dozeTimer?.cancel();
    _faceTimer?.cancel();
    _greetTimer?.cancel();
    _hopTimer?.cancel();
    _angryTimer?.cancel();
    _roamCheckTimer?.cancel();
    _runAnimTimer?.cancel();
    _bobber.dispose();
    _celebrate.dispose();
    _hearts.dispose();
    super.dispose();
  }

  /// 首次出现时的时段问候（只做一次）。
  void _greetByTime() {
    if (!mounted || _greeted) return;
    _greeted = true;
    if (_dozing) return; // 睡着时不打扰
    _showLine(petGreetingForHour(DateTime.now().hour));
  }

  /// 升级 / 投喂：庆祝弹跳 + 开心差分。
  Future<void> _playCelebrate() async {
    if (!mounted) return;
    setState(() => _faceIndex = _petFaces.indexOf(_cheerFace));
    try {
      _celebrate.value = 0;
      await _celebrate.animateTo(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
      );
      await _celebrate.animateBack(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {
      // 动画途中被销毁：忽略
    }
    // 稍后恢复常态差分
    _faceTimer?.cancel();
    _faceTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_dozing && _faceIndex == _petFaces.indexOf(_cheerFace)) {
        setState(() => _faceIndex = 0);
      }
    });
  }

  /// 摸头：飘心动画。
  void _playHearts() {
    if (!mounted) return;
    setState(() => _showHearts = true);
    _hearts.forward(from: 0);
  }

  /// 点击 / 拖拽落地的小跳：轻量弹跳反馈。
  Future<void> _playNudge() async {
    try {
      await _celebrate.animateTo(
        .32,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
      );
      await _celebrate.animateBack(
        0,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
      );
    } catch (_) {
      // 动画途中被销毁：忽略
    }
  }

  /// 每分钟检查一次是否该打瞌睡（深夜时段或 5 分钟没互动）。
  void _startDozeTimer() {
    _checkDoze(); // 启动时立即检查（深夜打开 App 会直接以睡容出现）
    _dozeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkDoze(),
    );
  }

  void _checkDoze() {
    if (!mounted) return;
    final shouldDoze = shouldPetDoze(
      now: DateTime.now(),
      lastInteraction: _lastInteractionAt,
    );
    if (shouldDoze != _dozing) {
      setState(() {
        _dozing = shouldDoze;
        if (shouldDoze) _faceIndex = _petFaces.indexOf(_sleepFace);
      });
    }
  }

  /// 睡容差分索引。
  static const _sleepFace = 'assets/images/pet_sleep.png';

  /// 开心差分索引（庆祝时使用）。
  static const _cheerFace = 'assets/images/pet_cheer.png';

  /// 生气差分索引。
  static const _angryFace = 'assets/images/pet_angry.png';

  /// 阴沉差分索引（彩蛋用）。
  static const _rageFace = 'assets/images/pet_rage.png';

  /// 差分索引工具。
  int _faceOf(String asset) => _petFaces.indexOf(asset);

  // ==================== 乱跑（奔跑捣乱） ====================

  /// 启动乱跑巡检：主界面低频、阅读界面高频（故意捣乱）。
  void _startRoamWatch() {
    _roamCheckTimer?.cancel();
    final interval = widget.pet.readerActive
        ? petRoamCheckIntervalReader
        : petRoamCheckInterval;
    _roamCheckTimer = Timer.periodic(interval, (_) => _maybeRoam());
  }

  /// 按当前场景概率决定是否开始乱跑。
  void _maybeRoam() {
    if (!mounted || _roaming || _dozing) return;
    if (kPetEggActive.value) return;
    if (_maxX <= 0 || _maxY <= 0) return;
    final chance = widget.pet.readerActive
        ? petRoamChanceReader
        : petRoamChanceHome;
    if (math.Random().nextDouble() >= chance) return;
    _startRoam();
  }

  /// 开始一次乱跑（连续跑几圈）。
  void _startRoam() {
    if (_roaming) return;
    final rnd = math.Random();
    final span = petRoamDurationMaxSec - petRoamDurationMinSec + 1;
    final seconds = petRoamDurationMinSec + rnd.nextInt(span);
    _roamLoopsLeft = math.max(2, seconds);
    _roaming = true;
    // 奔跑台词（阅读时更调皮）
    final pool = widget.pet.readerActive ? petRoamReaderLines : petRoamLines;
    _showLine(_pickLine(pool));
    _startRunAnim();
    _runLoop();
  }

  /// 奔跑动画：身体上下起伏（模拟小步跑）。
  void _startRunAnim() {
    _runAnimTimer?.cancel();
    _runAnimTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() => _runPhase = (_runPhase + 1) % 2);
    });
  }

  /// 连续跑到目标位置（每次一小段，形成"到处乱跑"）。
  Future<void> _runLoop() async {
    while (mounted && _roamLoopsLeft > 0 && !kPetEggActive.value) {
      if (_maxX <= 0 || _maxY <= 0) break;
      _roamLoopsLeft--;
      final rnd = math.Random();
      // 随机目标点（整个屏幕范围）
      final tx = rnd.nextDouble() * _maxX;
      final ty = rnd.nextDouble() * _maxY;
      await _runTo(tx, ty);
    }
    if (!mounted) return;
    setState(() {
      _roaming = false;
      _runPhase = 0;
      _tilt = 0;
    });
    _runAnimTimer?.cancel();
    // 落定后保存位置
    widget.pet.setPosition(
      _maxX <= 0 ? 0 : _dx / _maxX,
      _maxY <= 0 ? 0 : _dy / _maxY,
    );
  }

  /// 跑向目标点：比蹦跳快且带轻微弧线（跑步感）。
  Future<void> _runTo(double tx, double ty) async {
    const steps = 14;
    final sx = _dx;
    final sy = _dy;
    // 朝移动方向轻微前倾
    final lean = ((tx - sx) >= 0 ? 1 : -1) * 0.09;
    for (var i = 1; i <= steps; i++) {
      if (!mounted || kPetEggActive.value) return;
      final t = i / steps;
      setState(() {
        _dx = sx + (tx - sx) * t;
        _dy = (sy + (ty - sy) * t) - math.sin(math.pi * t) * 10;
        _tilt = lean;
      });
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    if (!mounted) return;
    setState(() {
      _dx = tx;
      _dy = ty;
      _tilt = 0;
    });
  }

  /// 用户主动互动时打断乱跑。
  void _stopRoamIfAny() {
    if (!_roaming) return;
    _roamLoopsLeft = 0;
  }

  /// 点击时的「屏幕内随机蹦跳」：短距离弹跳，可爱且频繁。
  void _hopAround() {
    if (!mounted || _maxX <= 0 || _maxY <= 0) return;
    final rnd = math.Random();
    // 蹦跳距离：以当前位置为中心，40~180px，方向随机
    final dist = 40 + rnd.nextDouble() * 140;
    final angle = rnd.nextDouble() * 2 * math.pi;
    final tx = (_dx + math.cos(angle) * dist).clamp(0.0, _maxX);
    final ty = (_dy + math.sin(angle) * dist).clamp(0.0, _maxY);
    _animateHop(tx, ty);
  }

  /// 弧线位移（上抛感），约 180ms 完成。
  Future<void> _animateHop(double tx, double ty) async {
    const steps = 8;
    final sx = _dx;
    final sy = _dy;
    for (var i = 1; i <= steps; i++) {
      if (!mounted) return;
      final t = i / steps;
      setState(() {
        _dx = sx + (tx - sx) * t;
        // 抛物线：sin 弧线制造"跳起来"的感觉
        _dy = (sy + (ty - sy) * t) - math.sin(math.pi * t) * 18;
      });
      await Future<void>.delayed(const Duration(milliseconds: 22));
    }
    if (!mounted) return;
    setState(() => _dy = ty);
    widget.pet.setPosition(
      _maxX <= 0 ? 0 : _dx / _maxX,
      _maxY <= 0 ? 0 : _dy / _maxY,
    );
  }

  /// 进入生气状态：换生气差分 + 台词；可能触发彩蛋。
  void _enterAngry(PetReaction r) {
    if (r.egg) {
      _triggerEgg();
      return;
    }
    setState(() => _faceIndex = _faceOf(_angryFace));
    _showLine(r.line ?? '哼！');
    _angryTimer?.cancel();
    _angryTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted || _dozing) return;
      // 生气结束回到常态（若期间没被其他状态接管）
      if (_faceIndex == _faceOf(_angryFace)) {
        setState(() => _faceIndex = 0);
      }
    });
  }

  /// 触发彩蛋：全黑锁定界面。
  void _triggerEgg() {
    setState(() => _faceIndex = _faceOf(_rageFace));
    _showLine(petEggLine);
    kPetEggActive.value = true;
    HapticFeedback.heavyImpact();
  }

  /// 拖动结束：随机台词 + 可能的生气。
  void _onDragEnd() {
    if (_dozing) return; // 睡觉被拖走不额外播台词（唤醒已有专属反馈）
    final r = _mood.onDrag();
    if (r.angry) {
      _enterAngry(r);
    } else if (r.line != null) {
      _showLine(r.line!);
    }
  }

  /// 从彩蛋恢复。
  ///
  /// 注意：正式流程下**只有重启 App** 能恢复（彩蛋层是全屏锁定且无出口），
  /// 这里保留入口供测试 / 将来做「后悔药」功能使用。
  // ignore: unused_element
  void _exitEgg() {
    kPetEggActive.value = false;
    _mood.reset();
    if (mounted) setState(() => _faceIndex = 0);
  }

  /// 记录一次互动；若正处于瞌睡状态则先"叫醒"（叫醒必定生气）。
  /// 返回 true = 刚被叫醒（调用方不再走常规流程）。
  bool _markInteraction() {
    _lastInteractionAt = DateTime.now();
    if (!_dozing) return false;
    setState(() {
      _dozing = false;
      _faceIndex = 0;
    });
    // 睡觉被叫醒：必定生气（可能是彩蛋）
    _enterAngry(_mood.onWake());
    return true;
  }

  void _onPetChanged() {
    if (!mounted) return;
    setState(() {});
    _checkPendingGains();
    // 阅读状态变化 → 调整乱跑频率
    _startRoamWatch();
    // 投喂反应：设置页/面板投喂后，桌宠做庆祝弹跳
    final feedAt = widget.pet.lastFeedAt;
    if (feedAt != _seenFeedAt) {
      _seenFeedAt = feedAt;
      _playCelebrate();
      _showLine('好吃！谢谢投喂～（+亲密度）');
    }
  }

  /// 有新点心到手时，桌宠主动冒泡提醒一次。
  void _checkPendingGains() {
    if (widget.pet.unseenGains <= 0) return;
    final n = widget.pet.takeUnseenGains();
    _showLine('书本里有惊喜！+$n 份点心 🍡');
  }

  void _showLine(String text) {
    _lineTimer?.cancel();
    setState(() => _line = text);
    _lineTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _line = null);
    });
  }

  void _onTap() {
    if (_markInteraction()) return;
    _stopRoamIfAny(); // 点击打断乱跑
    // 频繁点击 → 生气（不涨好感度）
    if (_mood.registerTap(DateTime.now())) {
      _enterAngry(_mood.onSpam());
      return;
    }
    final result = widget.pet.interact();
    setState(() {
      _faceIndex = (_faceIndex + 1) % _petFaces.length;
    });
    switch (result.reason) {
      case 'daily_cap':
        _showLine('今天互动好多次啦，明天再陪我玩～');
        break;
      default:
        // 点击：蹦跳 + 随机台词
        _hopAround();
        if (result.leveledUp) {
          _playCelebrate();
          _showLine('亲密度升级！现在是「${widget.pet.levelName}」啦 🎉');
        } else {
          _playNudge();
          _showLine(_pickLine(petHopLines));
        }
    }
  }

  /// 从台词池随机取一句。
  String _pickLine(List<String> pool) =>
      pool[DateTime.now().microsecond % pool.length];

  /// 双击摸头：切换到 shy 差分 + 摸头台词 + 亲密度 +2。
  void _onDoubleTap() {
    if (_markInteraction()) return;
    final result = widget.pet.pat();
    if (result.reason == 'pat_cap') {
      _showLine('呜……今天被摸太多次了啦');
      return;
    }
    setState(() => _faceIndex = _petFaces.indexOf('assets/images/pet_shy.png'));
    _playHearts();
    if (result.leveledUp) {
      _playCelebrate();
      _showLine('亲密度升级！现在是「${widget.pet.levelName}」啦 🎉');
    } else {
      _showLine(
        '${_petPatLines[DateTime.now().microsecond % _petPatLines.length]}'
        '（+$kPetPatPoints）',
      );
    }
  }

  void _onLongPress() {
    _markInteraction();
    showPetPanelGlobal(widget.pet);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 安全边距：弹跳缩放 / 轮廓阴影会超出 _size 一点，留缓冲保证不出屏
        const margin = 8.0;
        // 可移动范围（含安全边距）
        final maxX = constraints.maxWidth - _size - margin;
        final maxY = constraints.maxHeight - _size - 96 - margin; // 底部导航留空
        if (!_positioned) {
          _dx = ((widget.pet.petX * maxX).clamp(0.0, maxX));
          _dy = ((widget.pet.petY * maxY).clamp(0.0, maxY));
          _positioned = true;
        }
        _dx = _dx.clamp(0.0, maxX);
        _dy = _dy.clamp(0.0, maxY);
        // 供蹦跳计算使用（每次布局刷新）
        _maxX = maxX;
        _maxY = maxY;
        // 贴边状态：仅用于决定台词气泡朝哪边长（缩放锚定在下方，不贴边）
        final snapLeft = _dx < maxX / 2;
        final nearLeft = _dx <= margin + 1;
        final nearRight = maxX - _dx <= margin + 1;

        return ValueListenableBuilder<bool>(
          valueListenable: widget.hostReady ?? _alwaysReady,
          builder: (context, ready, _) {
            if (!ready) return const SizedBox.shrink();
            // 阅读器内：默认隐藏；用户开启「阅读时显示桌宠」才显示
            if (widget.pet.readerActive && !widget.pet.showPetInReader) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Stack(
                children: [
                  Positioned(
                    key: const ValueKey('pet_positioned'),
                    left: snapLeft ? _dx : null,
                    right: snapLeft ? null : constraints.maxWidth - _dx - _size,
                    top: _dy,
                    child: GestureDetector(
                      onTap: _onTap,
                      onDoubleTap: _onDoubleTap,
                      onLongPress: _onLongPress,
                      onPanStart: (_) {
                        // 用户开始拖动 → 打断乱跑
                        _stopRoamIfAny();
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          _dx += details.delta.dx;
                          _dy += details.delta.dy;
                          // 拖拽摇晃：按水平拖动方向倾斜，±0.2 rad
                          _tilt = (_tilt + details.delta.dx * 0.012).clamp(
                            -0.2,
                            0.2,
                          );
                        });
                      },
                      onPanEnd: (_) {
                        final nx = maxX <= 0 ? 0.0 : _dx / maxX;
                        final ny = maxY <= 0 ? 0.0 : _dy / maxY;
                        widget.pet.setPosition(nx, ny);
                        setState(() => _tilt = 0); // 松手回正（不做贴边吸附）
                        _playNudge(); // 落地小跳
                        _onDragEnd(); // 拖动台词 + 可能的生气
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: snapLeft
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.end,
                        children: [
                          if (_line != null)
                            Container(
                              constraints: const BoxConstraints(maxWidth: 200),
                              // 气泡朝屏幕内侧生长：贴右留左距，贴左留右距
                              margin: EdgeInsets.only(
                                bottom: 6,
                                left: snapLeft ? 4 : 0,
                                right: snapLeft ? 0 : 4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: .96),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                _line!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          AnimatedBuilder(
                            animation: Listenable.merge([_bobber, _celebrate]),
                            builder: (context, child) => Transform.translate(
                              // 呼吸浮动 + 奔跑时的上下起伏
                              offset: Offset(
                                0,
                                _bobber.value * 4 -
                                    2 -
                                    (_roaming && _runPhase == 1 ? 5 : 0),
                              ),
                              child: Transform.rotate(
                                angle: _tilt,
                                child: Transform.scale(
                                  // 庆祝 / 小跳的弹跳缩放（1 → 1.12）；
                                  // alignment = 缩放锚点（固定不动的边）：
                                  // 贴右 → 锚右缘（向左/屏幕内扩张）；
                                  // 贴左 → 锚左缘（向右/屏幕内扩张）——永不出屏
                                  scale: 1 + _celebrate.value * .12,
                                  alignment: nearRight
                                      ? Alignment.bottomRight
                                      : (nearLeft
                                            ? Alignment.bottomLeft
                                            : Alignment.bottomCenter),
                                  child: child,
                                ),
                              ),
                            ),
                            child: SizedBox(
                              width: _size,
                              height: _size,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // 摸头飘心（在人物下方，向上飘 + 淡出）
                                  if (_showHearts)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: _PetHearts(animation: _hearts),
                                      ),
                                    ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Stack(
                                      key: ValueKey<int>(_faceIndex),
                                      fit: StackFit.expand,
                                      children: [
                                        // 轮廓阴影：同一张立绘染黑 + 模糊 + 轻微下移。
                                        // 阴影形状跟随人物剪影（不是矩形投影，避免"黑圈"）。
                                        Transform.translate(
                                          offset: const Offset(0, 3),
                                          child: ImageFiltered(
                                            imageFilter: ui.ImageFilter.blur(
                                              sigmaX: 2.5,
                                              sigmaY: 2.5,
                                            ),
                                            child: ColorFiltered(
                                              colorFilter: ColorFilter.mode(
                                                Colors.black.withValues(
                                                  alpha: .13,
                                                ),
                                                BlendMode.srcIn,
                                              ),
                                              child: Image.asset(
                                                _petFaces[_faceIndex],
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Image.asset(
                                          _petFaces[_faceIndex],
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ==================== 摸头飘心 ====================

/// 摸头飘心：3 颗爱心从头顶向上飘 + 淡出。
class _PetHearts extends StatelessWidget {
  const _PetHearts({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: 20.0 + i * 16,
                bottom: 64 + t * (46 + i * 12),
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 15.0 - i * 2,
                    color: const Color(0xFFFF7EB6).withValues(alpha: .92),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ==================== 看板娘面板（长按打开） ====================

/// 根导航键：供挂载在 MaterialApp.builder 层的全局覆盖层（桌宠）使用。
/// 桌宠的 context 不含 Navigator（它是 Navigator 的兄弟层），必须用 key 导航。
final GlobalKey<NavigatorState> kRootNavigatorKey = GlobalKey<NavigatorState>();

/// 打开看板娘面板（设置页等普通页面入口，用页面自己的 context）。
Future<void> showPetPanel(BuildContext context, PetStore pet) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => _PetPanelPage(pet: pet)));
}

/// 打开看板娘面板（全局覆盖层入口，走根导航）。
Future<void> showPetPanelGlobal(PetStore pet) {
  final nav = kRootNavigatorKey.currentState;
  if (nav == null) return Future<void>.value();
  return nav.push(MaterialPageRoute(builder: (_) => _PetPanelPage(pet: pet)));
}

/// 桌宠面板：亲密度概览 + 投喂食物 + 摆回原位。
class _PetPanelPage extends StatefulWidget {
  const _PetPanelPage({required this.pet});

  final PetStore pet;

  @override
  State<_PetPanelPage> createState() => _PetPanelPageState();
}

class _PetPanelPageState extends State<_PetPanelPage> {
  final _snack = ValueNotifier<String?>(null);
  Timer? _snackTimer;

  @override
  void dispose() {
    _snackTimer?.cancel();
    _snack.dispose();
    super.dispose();
  }

  void _toast(String message) {
    _snackTimer?.cancel();
    _snack.value = message;
    _snackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _snack.value = null;
    });
  }

  void _feed(FoodDef food) {
    final result = widget.pet.feed(food.id);
    if (result.reason == 'no_food') {
      _toast('${food.emoji} ${food.name}吃完了，阅读可以换更多点心哦');
      return;
    }
    if (result.leveledUp) {
      _toast('亲密度升级！现在是「${widget.pet.levelName}」🎉');
    } else {
      _toast('${food.emoji} 投喂成功 +${result.points} 亲密度');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('看板娘'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '让桌宠回到默认位置',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () {
              widget.pet.resetPosition();
              _toast('桌宠已回到默认位置');
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.pet,
        builder: (context, _) {
          final pet = widget.pet;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 头像 + 等级
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: Image.asset(_petFaces[2], fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '亲密度 · Lv.${pet.level}「${pet.levelName}」',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 进度条
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: pet.levelProgress,
                              minHeight: 8,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            pet.level >= kAffinityLevels.length
                                ? '已经是最高的「挚爱」啦'
                                : '${pet.affinity} / ${pet.nextLevelAt} · '
                                      '再攒 ${pet.nextLevelAt - pet.affinity} 点升级',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点一点：+1 亲密度（每天 20 次）· 双击摸头：+2（每天 10 次）',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // 统计数据
              Row(
                children: [
                  _statCard(
                    '互动次数',
                    '${pet.interactions} 次',
                    Icons.touch_app_rounded,
                  ),
                  const SizedBox(width: 10),
                  _statCard('投喂次数', '${pet.feeds} 次', Icons.restaurant_rounded),
                  const SizedBox(width: 10),
                  _statCard(
                    '获得点心',
                    '${pet.totalFoodEarned} 份',
                    Icons.card_giftcard_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 食物背包
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bakery_dining_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '点心盒',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '阅读时长会自动换来点心：樱饼 20 分钟 / 团子 1 小时 / '
                      '大福 5 小时 / 蛋糕 20 小时',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final food in kPetFoods)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              food.emoji,
                              style: const TextStyle(fontSize: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '+${food.affinity} 亲密度 · '
                                    '库存 ${pet.foodCount(food.id)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: pet.foodCount(food.id) > 0
                                  ? () => _feed(food)
                                  : null,
                              child: Text(
                                pet.foodCount(food.id) > 0 ? '投喂' : '暂无',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // 悬浮气泡提示
              ValueListenableBuilder<String?>(
                valueListenable: _snack,
                builder: (context, value, _) => AnimatedOpacity(
                  opacity: value == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: value == null
                      ? const SizedBox(height: 20)
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: .6,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            value,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
