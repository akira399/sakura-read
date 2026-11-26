import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/sakura_tokens.dart';
import '../../data/pet_mood.dart';
import '../../data/pet_store.dart';
import '../../features/pet/live_sakura_pet.dart';
import '../../features/pet/pet_mood_bus.dart';
import '../ai_chat_page.dart';

/// 全局悬浮桌宠 2.0：60/120fps 矢量动态小樱、智能贴边探头、轻巧快捷菜单与情绪总线联动。
///
/// 通过 MaterialApp 的 builder 覆盖层承载，任何页面（除阅读器默认隐藏外）都能看到。
class PetOverlay extends StatefulWidget {
  const PetOverlay({super.key, required this.pet, this.hostReady});

  final PetStore pet;

  /// 宿主就绪开关（开屏 / 权限页时不显示）。
  final ValueListenable<bool>? hostReady;

  @override
  State<PetOverlay> createState() => _PetOverlayState();
}

/// 智能贴边判定：靠近左缘返回 -1，靠近右缘返回 1，否则返回 0。
int petDockSideFor({
  required double dx,
  required double maxX,
  double edgeFraction = 0.22,
}) {
  if (maxX <= 0) return 0;
  final ratio = (dx / maxX).clamp(0.0, 1.0);
  if (ratio <= edgeFraction) return -1;
  if (ratio >= 1.0 - edgeFraction) return 1;
  return 0;
}

/// hostReady 缺省值（避免每次 build 新建 ValueNotifier）。
final ValueNotifier<bool> _alwaysReady = ValueNotifier<bool>(true);

/// 彩蛋是否激活（保留给 PetEggOverlay API 兼容；常规桌宠互动永不触发永久锁屏）。
final ValueNotifier<bool> kPetEggActive = ValueNotifier<bool>(false);

/// 摸头台词。
const _petPatLines = ['诶嘿……被摸头啦', '呜……好舒服呀', '呀！别、别突然摸头啦', '再摸一下也不是不可以……'];

/// 可爱鼓嘴求点心台词（取代旧版惩罚锁屏）。
const _petPoutSnackLines = [
  '哼！戳太多次啦，给颗樱饼就原谅你～',
  '呜……手手别一直戳嘛，人家想吃团子啦',
  '鼓嘴抗议！投喂一份小点心就和好～',
  '哼哼，再捣乱我就要躲去屏幕边边偷看你啦',
];

class _PetOverlayState extends State<PetOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _size = 76;
  static const double _dockPeekHide = 18;

  late final AnimationController _celebrate;
  late final AnimationController _hearts;

  Timer? _lineTimer;
  Timer? _dozeTimer;
  Timer? _moodResetTimer;
  Timer? _greetTimer;
  Timer? _dockTimer;
  Timer? _menuTimer;
  Timer? _lookResetTimer;
  Timer? _idleActionTimer;

  final math.Random _rng = math.Random();

  String? _line;
  PetLiveMood _mood = PetLiveMood.idle;
  String? _assetOverride;
  DateTime _lastInteractionAt = DateTime.now();
  bool _dozing = false;
  double _tilt = 0;
  int _seenFeedAt = 0;
  int _seenActivity = 0;
  bool _greeted = false;
  bool _showHearts = false;
  bool _menuOpen = false;
  bool _dragging = false;

  /// 贴边探头状态：-1 贴左缘，1 贴右缘，0 正常悬浮。
  int _dockedSide = 0;
  Size? _lastBoundsSize;

  /// 归一化视线追踪向量（-1..1）。
  Offset _lookTarget = Offset.zero;

  final PetMood _moodMachine = PetMood();

  double _dx = 0;
  double _dy = 0;
  bool _positioned = false;
  bool _foreground = true;
  bool _reduceMotion = false;
  double _maxX = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _celebrate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
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
    widget.hostReady?.addListener(_syncActivity);
    kPetMoodBus.addListener(_onMoodBusChanged);
    kPetEggActive.addListener(_onEggClosed);

    _checkPendingGains();
    _startDozeTimer();
    _scheduleIdleDock();
    _startIdleActionTimer();
    _greetTimer = Timer(const Duration(milliseconds: 900), _greetByTime);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pet.removeListener(_onPetChanged);
    widget.hostReady?.removeListener(_syncActivity);
    kPetMoodBus.removeListener(_onMoodBusChanged);
    kPetEggActive.removeListener(_onEggClosed);
    _lineTimer?.cancel();
    _dozeTimer?.cancel();
    _moodResetTimer?.cancel();
    _greetTimer?.cancel();
    _dockTimer?.cancel();
    _menuTimer?.cancel();
    _lookResetTimer?.cancel();
    _idleActionTimer?.cancel();
    _celebrate.dispose();
    _hearts.dispose();
    super.dispose();
  }

  void _syncActivity() {
    final active =
        (widget.hostReady?.value ?? true) &&
        _foreground &&
        widget.pet.enabled &&
        !widget.pet.paused &&
        !(widget.pet.readerActive && !widget.pet.showPetInReader);
    if (!active) {
      _tilt = 0;
      _menuOpen = false;
      _celebrate.stop();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  void _onMoodBusChanged() {
    if (!mounted) return;
    final busMood = kPetMoodBus.value;
    setState(() {
      _mood = _dozing && busMood == PetLiveMood.idle
          ? PetLiveMood.sleepy
          : busMood;
    });
    final line = kPetMoodBus.latestLine.value;
    if (line != null && line.isNotEmpty && busMood == PetLiveMood.happy) {
      _showLine(line);
      _playHearts();
    }
  }

  void _greetByTime() {
    if (!mounted || _greeted) return;
    _greeted = true;
    if (_dozing) return;
    _showLine(petGreetingForHour(DateTime.now().hour));
  }

  void _setTemporaryMood(
    PetLiveMood mood, {
    String? assetOverride,
    Duration duration = const Duration(seconds: 3),
  }) {
    _moodResetTimer?.cancel();
    setState(() {
      _mood = mood;
      _assetOverride = assetOverride;
    });
    _moodResetTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _assetOverride = null;
        _mood = _dozing
            ? PetLiveMood.sleepy
            : (kPetMoodBus.value != PetLiveMood.idle
                  ? kPetMoodBus.value
                  : (widget.pet.readerActive
                        ? PetLiveMood.reading
                        : PetLiveMood.idle));
      });
    });
  }

  Future<void> _playCelebrate() async {
    if (!mounted ||
        !widget.pet.motionEnabled ||
        _reduceMotion ||
        !_foreground) {
      return;
    }
    _setTemporaryMood(PetLiveMood.happy, duration: const Duration(seconds: 3));
    try {
      _celebrate.value = 0;
      await _celebrate.animateTo(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
      );
      await _celebrate.animateBack(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _playNudge() async {
    if (!widget.pet.motionEnabled || _reduceMotion || !_foreground) return;
    try {
      await _celebrate.animateTo(
        0.34,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      await _celebrate.animateBack(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
      );
    } catch (_) {}
  }

  void _playHearts() {
    if (!mounted ||
        !widget.pet.motionEnabled ||
        _reduceMotion ||
        !_foreground) {
      return;
    }
    setState(() => _showHearts = true);
    _hearts.forward(from: 0);
  }

  void _startDozeTimer() {
    _checkDoze();
    _dozeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkDoze();
      if (mounted) {
        _syncActivity();
      }
    });
  }

  void _startIdleActionTimer() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _idleActionTimer?.cancel();
    _idleActionTimer = Timer.periodic(const Duration(seconds: 22), (_) {
      if (!mounted ||
          !(widget.hostReady?.value ?? true) ||
          !_foreground ||
          !widget.pet.enabled ||
          widget.pet.paused ||
          !widget.pet.motionEnabled ||
          _reduceMotion ||
          _dragging ||
          _menuOpen ||
          _dozing ||
          _assetOverride != null) {
        return;
      }
      const idlePool = <(PetLiveMood, String)>[
        (PetLiveMood.reading, 'assets/images/pet_read.png'),
        (PetLiveMood.reading, 'assets/images/pet_read.png'),
        (PetLiveMood.idle, 'assets/images/pet_tea.png'),
        (PetLiveMood.thinking, 'assets/images/pet_curious.png'),
        (PetLiveMood.idle, 'assets/images/pet_stretch.png'),
      ];
      final pick = idlePool[_rng.nextInt(idlePool.length)];
      _setTemporaryMood(
        pick.$1,
        assetOverride: pick.$2,
        duration: const Duration(seconds: 8),
      );
    });
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
        if (shouldDoze) {
          _mood = PetLiveMood.sleepy;
          _menuOpen = false;
        }
      });
    }
  }

  /// 闲置 6 秒后自动优雅贴边探头，避免挡住书架封面。
  void _scheduleIdleDock() {
    _dockTimer?.cancel();
    _dockTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _dragging || _menuOpen || _maxX <= 0) return;
      final side = _dx < _maxX / 2 ? -1 : 1;
      setState(() {
        _dockedSide = side;
        _dx = side < 0 ? 0 : _maxX;
      });
    });
  }

  void _scheduleMenuAutoClose() {
    _menuTimer?.cancel();
    _menuTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_menuOpen) {
        setState(() => _menuOpen = false);
        _scheduleIdleDock();
      }
    });
  }

  void _updateLookFromGlobal(Offset globalPos) {
    if (_maxX <= 0) return;
    final petCenter = Offset(_dx + _size / 2, _dy + _size / 2);
    final diff = globalPos - petCenter;
    final target = Offset(
      (diff.dx / 120).clamp(-1.0, 1.0),
      (diff.dy / 120).clamp(-1.0, 1.0),
    );
    if ((target - _lookTarget).distanceSquared > 0.002) {
      setState(() => _lookTarget = target);
    }
    _lookResetTimer?.cancel();
    _lookResetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && !_dragging) {
        setState(() => _lookTarget = Offset.zero);
      }
    });
  }

  /// 温和鼓嘴反馈（取代旧版惩罚锁屏：绝不锁死软件！）。
  void _enterPout({String? customLine}) {
    _setTemporaryMood(
      PetLiveMood.pouting,
      duration: const Duration(milliseconds: 2800),
    );
    _showLine(customLine ?? _pickLine(_petPoutSnackLines));
  }

  void _onDragEnd() {
    if (_dozing) return;
    final r = _moodMachine.onDrag();
    if (r.angry) {
      _enterPout(customLine: _pickLine(_petPoutSnackLines));
    } else if (r.line != null) {
      _showLine(r.line!);
    }
  }

  void _onEggClosed() {
    if (kPetEggActive.value) return;
    _moodMachine.reset();
    if (mounted) setState(() => _mood = PetLiveMood.idle);
  }

  bool _markInteraction() {
    _lastInteractionAt = DateTime.now();
    _dockTimer?.cancel();
    if (_dockedSide != 0) {
      setState(() => _dockedSide = 0);
    }
    if (!_dozing) return false;
    setState(() {
      _dozing = false;
      _mood = PetLiveMood.pouting;
    });
    _moodMachine.onWake();
    _enterPout(customLine: '呜……人家刚睡着，给颗小点心哄哄嘛～');
    return true;
  }

  void _onPetChanged() {
    if (!mounted) return;
    _syncActivity();
    if (widget.pet.quiet) {
      _lineTimer?.cancel();
      _line = null;
    }
    if (_seenActivity != widget.pet.activitySequence) {
      _seenActivity = widget.pet.activitySequence;
      _lastInteractionAt = DateTime.now();
      _dozing = false;
      final action = widget.pet.activity;
      if (action == 'pat') {
        _performPat();
      } else {
        final sprite = petInteractionSprites[action];
        final mood = switch (action) {
          'dance' || 'encourage' || 'wave' => PetLiveMood.happy,
          'read' => PetLiveMood.reading,
          'rest' => PetLiveMood.sleepy,
          'curious' => PetLiveMood.thinking,
          _ => PetLiveMood.idle,
        };
        _setTemporaryMood(
          mood,
          assetOverride: sprite,
          duration: const Duration(seconds: 5),
        );
        _showLine(
          {
                'wave': '嗨，今天也一起读一点吧！',
                'dance': '给认真读书的你跳一支小舞～',
                'read': '我会安静陪你，把故事交给书页。',
                'rest': '稍微休息一下，眼睛也需要放松。',
                'tea': '喝口茶，让故事慢一点。',
                'curious': '这里有什么线索呢？一起回原文找找。',
                'stretch': '伸个懒腰，肩膀也放松一下～',
                'encourage': '读完一小段也是进步，我陪你。',
              }[action] ??
              '我在这里',
        );
        if (action == 'dance' || action == 'wave') {
          _playCelebrate();
          _playHearts();
        }
      }
    }
    _checkPendingGains();
    final feedAt = widget.pet.lastFeedAt;
    if (feedAt != _seenFeedAt) {
      _seenFeedAt = feedAt;
      _playCelebrate();
      _setTemporaryMood(
        PetLiveMood.happy,
        assetOverride: 'assets/images/pet_snack.png',
        duration: const Duration(seconds: 4),
      );
      _playHearts();
      _showLine('好吃！谢谢投喂～（+亲密度）');
    }
    setState(() {});
  }

  void _checkPendingGains() {
    if (widget.pet.unseenGains <= 0) return;
    final n = widget.pet.takeUnseenGains();
    _showLine('书本里有惊喜！+$n 份点心 🍡');
    _playHearts();
  }

  void _showLine(String text) {
    if (widget.pet.quiet || widget.pet.paused || !_foreground) return;
    _lineTimer?.cancel();
    setState(() => _line = text);
    _lineTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _line = null);
    });
  }

  String _pickLine(List<String> pool) =>
      pool[DateTime.now().microsecond % pool.length];

  void _onTap() {
    if (_markInteraction()) {
      setState(() => _menuOpen = true);
      _scheduleMenuAutoClose();
      return;
    }
    if (_moodMachine.registerTap(DateTime.now())) {
      _moodMachine.onSpam();
      _enterPout();
      setState(() => _menuOpen = true);
      _scheduleMenuAutoClose();
      return;
    }

    final result = widget.pet.interact();
    setState(() {
      _menuOpen = !_menuOpen;
    });
    if (_menuOpen) {
      _scheduleMenuAutoClose();
    } else {
      _scheduleIdleDock();
    }

    switch (result.reason) {
      case 'daily_cap':
        _setTemporaryMood(PetLiveMood.happy);
        _showLine('今天互动好多次啦，点气泡可以摸头或问我问题哦～');
      default:
        if (result.leveledUp) {
          _playCelebrate();
          _playHearts();
          _showLine('亲密度升级！现在是「${widget.pet.levelName}」啦 🎉');
        } else {
          _setTemporaryMood(PetLiveMood.happy);
          _playNudge();
          _showLine(_pickLine(petHopLines));
        }
    }
  }

  void _performPat() {
    if (_markInteraction()) return;
    final result = widget.pet.pat();
    if (result.reason == 'pat_cap') {
      _setTemporaryMood(PetLiveMood.shy);
      _showLine('呜……今天被摸太多次了啦');
      return;
    }
    _setTemporaryMood(PetLiveMood.shy, duration: const Duration(seconds: 3));
    _playHearts();
    _playNudge();
    if (result.leveledUp) {
      _playCelebrate();
      _showLine('亲密度升级！现在是「${widget.pet.levelName}」啦 🎉');
    } else {
      _showLine('${_pickLine(_petPatLines)}（+$kPetPatPoints）');
    }
  }

  void _quickFeedSnack() {
    FoodDef? chosen;
    for (final food in kPetFoods) {
      if (widget.pet.foodCount(food.id) > 0) {
        chosen = food;
        break;
      }
    }
    if (chosen == null) {
      _enterPout(customLine: '点心盒空啦～看 20 分钟书就能换樱饼哦 🍪');
      return;
    }
    final res = widget.pet.feed(chosen.id);
    if (res.leveledUp) {
      _playCelebrate();
      _playHearts();
      _showLine('${chosen.emoji} 好吃到升级啦！「${widget.pet.levelName}」🎉');
    } else {
      _playCelebrate();
      _playHearts();
      _showLine('${chosen.emoji} 啊呜～谢谢投喂 ${chosen.name}（+${res.points}）');
    }
  }

  void _openAskSakura() {
    setState(() => _menuOpen = false);
    final nav = kRootNavigatorKey.currentState;
    if (nav == null) return;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final store = container.read(bookStoreProvider);
      final prefs = container.read(prefsProvider);
      final stats = container.read(statsStoreProvider);
      final db = container.read(sakuraDatabaseProvider);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => AiConversationPage(
            store: store,
            prefs: prefs,
            statsStore: stats,
            database: db,
          ),
        ),
      );
      return;
    } catch (_) {
      // 孤立测试环境没有 ProviderScope 时安全回退到看板娘面板
      showPetPanelGlobal(widget.pet);
    }
  }

  void _onLongPress() {
    _markInteraction();
    setState(() => _menuOpen = false);
    showPetPanelGlobal(widget.pet);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncActivity();
      });
    }

    // 透明 Material 避免气泡文本继承 MaterialApp 根调试样式（黄双下划线）。
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const margin = 8.0;
          final maxX = math.max(0.0, constraints.maxWidth - _size - margin);
          final maxY = math.max(
            0.0,
            constraints.maxHeight - _size - 96 - margin,
          );
          if (!_positioned || _lastBoundsSize != constraints.biggest) {
            _dx = (widget.pet.petX * maxX).clamp(0.0, maxX);
            _dy = (widget.pet.petY * maxY).clamp(0.0, maxY);
            _positioned = true;
            _lastBoundsSize = constraints.biggest;
          }
          _dx = _dx.clamp(0.0, maxX);
          _dy = _dy.clamp(0.0, maxY);
          _maxX = maxX;

          final snapLeft = _dx < maxX / 2;
          final effectiveLeft = _dockedSide < 0
              ? -_dockPeekHide
              : (_dockedSide > 0
                    ? constraints.maxWidth - _size + _dockPeekHide
                    : _dx);

          return ValueListenableBuilder<bool>(
            valueListenable: widget.hostReady ?? _alwaysReady,
            builder: (context, ready, _) {
              if (!ready || !widget.pet.enabled || widget.pet.paused) {
                return const SizedBox.shrink();
              }
              if (widget.pet.readerActive && !widget.pet.showPetInReader) {
                return const SizedBox.shrink();
              }
              final sakura = context.sakura;
              final accent = Theme.of(context).colorScheme.primary;
              final motionOn = widget.pet.motionEnabled && !_reduceMotion;

              // 快捷操作条定位（独立兄弟 Positioned，保证 pet_positioned 内仅气泡含 RichText）
              final menuTop = (_dy - 50)
                  .clamp(16.0, math.max(16.0, constraints.maxHeight - 140))
                  .toDouble();

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_menuOpen)
                      Positioned(
                        key: const ValueKey('pet_quick_actions'),
                        left: snapLeft ? 10 : null,
                        right: snapLeft ? null : 10,
                        top: menuTop,
                        child: _QuickActionStrip(
                          sakura: sakura,
                          accent: accent,
                          quiet: widget.pet.quiet,
                          onPat: () {
                            setState(() => _menuOpen = false);
                            _performPat();
                            _scheduleIdleDock();
                          },
                          onFeed: () {
                            setState(() => _menuOpen = false);
                            _quickFeedSnack();
                            _scheduleIdleDock();
                          },
                          onAsk: _openAskSakura,
                          onToggleQuiet: () {
                            widget.pet.setQuiet(!widget.pet.quiet);
                            setState(() => _menuOpen = false);
                            if (!widget.pet.quiet) {
                              _showLine('好哒，我又可以和你说话啦～');
                            }
                            _scheduleIdleDock();
                          },
                          onHide: () {
                            setState(() => _menuOpen = false);
                            widget.pet.setPetHidden(true);
                          },
                        ),
                      ),
                    AnimatedPositioned(
                      key: const ValueKey('pet_positioned'),
                      duration: _dragging || !motionOn
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      left: snapLeft ? effectiveLeft : null,
                      right: snapLeft
                          ? null
                          : (_dockedSide > 0
                                ? -_dockPeekHide
                                : constraints.maxWidth - _dx - _size),
                      top: _dy,
                      child: Listener(
                        onPointerDown: (e) => _updateLookFromGlobal(e.position),
                        onPointerMove: (e) => _updateLookFromGlobal(e.position),
                        onPointerHover: (e) =>
                            _updateLookFromGlobal(e.position),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _onTap,
                          onDoubleTap: () {
                            setState(() => _menuOpen = false);
                            _performPat();
                            _scheduleIdleDock();
                          },
                          onLongPress: _onLongPress,
                          onPanStart: (_) {
                            _dockTimer?.cancel();
                            setState(() {
                              _dragging = true;
                              _dockedSide = 0;
                              _menuOpen = false;
                            });
                          },
                          onPanUpdate: (details) {
                            _updateLookFromGlobal(details.globalPosition);
                            setState(() {
                              _dx = (_dx + details.delta.dx).clamp(0.0, maxX);
                              _dy = (_dy + details.delta.dy).clamp(0.0, maxY);
                              _tilt = (_tilt + details.delta.dx * 0.012).clamp(
                                -0.18,
                                0.18,
                              );
                            });
                          },
                          onPanEnd: (_) {
                            final dockSide = petDockSideFor(
                              dx: _dx,
                              maxX: maxX,
                            );
                            if (dockSide < 0) _dx = 0;
                            if (dockSide > 0) _dx = maxX;
                            final nx = maxX <= 0 ? 0.0 : _dx / maxX;
                            final ny = maxY <= 0 ? 0.0 : _dy / maxY;
                            widget.pet.setPosition(nx, ny);
                            setState(() {
                              _dragging = false;
                              _tilt = 0;
                              _dockedSide = dockSide;
                            });
                            _playNudge();
                            _onDragEnd();
                            if (dockSide == 0) {
                              _scheduleIdleDock();
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: snapLeft
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            children: [
                              if (_line != null)
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 204,
                                  ),
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
                                    color: sakura.card.withValues(alpha: 0.96),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: sakura.hairline),
                                    boxShadow: [
                                      BoxShadow(
                                        color: sakura.coverShadow,
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _line!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sakura.inkPrimary,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              AnimatedBuilder(
                                animation: _celebrate,
                                builder: (context, child) => Transform.rotate(
                                  angle: _tilt,
                                  child: Transform.scale(
                                    scale: 1 + _celebrate.value * 0.12,
                                    alignment: Alignment.bottomCenter,
                                    child: child,
                                  ),
                                ),
                                child: SizedBox(
                                  width: _size,
                                  height: _size,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      if (_showHearts)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: _PetHearts(
                                              animation: _hearts,
                                            ),
                                          ),
                                        ),
                                      LiveSakuraPet(
                                        size: _size,
                                        mood: _mood,
                                        assetOverride: _assetOverride,
                                        lookTarget: _lookTarget,
                                        motionEnabled: motionOn,
                                        showSparkles: _showHearts,
                                        peekingSide: _dockedSide,
                                        accentColor: accent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 轻盈浮气泡快捷操作条：摸头 / 喂点心 / 问小樱 / 安静陪伴 / 隐藏。
class _QuickActionStrip extends StatelessWidget {
  const _QuickActionStrip({
    required this.sakura,
    required this.accent,
    required this.quiet,
    required this.onPat,
    required this.onFeed,
    required this.onAsk,
    required this.onToggleQuiet,
    required this.onHide,
  });

  final SakuraColors sakura;
  final Color accent;
  final bool quiet;
  final VoidCallback onPat;
  final VoidCallback onFeed;
  final VoidCallback onAsk;
  final VoidCallback onToggleQuiet;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: sakura.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: sakura.hairline),
            boxShadow: [
              BoxShadow(
                color: sakura.coverShadow,
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionPill(
                icon: Icons.favorite_outline_rounded,
                label: '摸头',
                accent: accent,
                sakura: sakura,
                onTap: onPat,
              ),
              _ActionPill(
                icon: Icons.bakery_dining_outlined,
                label: '喂点心',
                accent: accent,
                sakura: sakura,
                onTap: onFeed,
              ),
              _ActionPill(
                icon: Icons.auto_awesome_rounded,
                label: '问小樱',
                accent: accent,
                sakura: sakura,
                highlighted: true,
                onTap: onAsk,
              ),
              _ActionPill(
                icon: quiet
                    ? Icons.volume_off_rounded
                    : Icons.nightlight_outlined,
                label: '安静陪伴',
                accent: accent,
                sakura: sakura,
                highlighted: quiet,
                onTap: onToggleQuiet,
              ),
              _ActionPill(
                icon: Icons.visibility_off_outlined,
                label: '隐藏',
                accent: accent,
                sakura: sakura,
                onTap: onHide,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.accent,
    required this.sakura,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final SakuraColors sakura;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: highlighted ? sakura.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: highlighted ? accent : sakura.inkSecondary,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
                color: highlighted ? accent : sakura.inkPrimary,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
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

// ==================== 看板娘面板（长按或设置页打开） ====================

/// 根导航键：供挂载在 MaterialApp.builder 层的全局覆盖层（桌宠）使用。
final GlobalKey<NavigatorState> kRootNavigatorKey = GlobalKey<NavigatorState>();

/// 打开看板娘面板（设置页等普通页面入口，用页面自己的 context）。
Future<void> showPetPanel(BuildContext context, PetStore pet) {
  return Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => _PetPanelPage(pet: pet)));
}

/// 打开看板娘面板（全局覆盖层入口，走根导航）。
Future<void> showPetPanelGlobal(PetStore pet) {
  final nav = kRootNavigatorKey.currentState;
  if (nav == null) return Future<void>.value();
  return nav.push(MaterialPageRoute(builder: (_) => _PetPanelPage(pet: pet)));
}

/// 桌宠面板：实时动态小樱预览 + 亲密度概览 + 投喂食物 + 摆回原位。
class _PetPanelPage extends StatefulWidget {
  const _PetPanelPage({required this.pet});

  final PetStore pet;

  @override
  State<_PetPanelPage> createState() => _PetPanelPageState();
}

class _PetPanelPageState extends State<_PetPanelPage> {
  final _snack = ValueNotifier<String?>(null);
  Timer? _snackTimer;
  PetLiveMood _previewMood = PetLiveMood.happy;
  String? _previewAsset = 'assets/images/pet_read.png';

  @override
  void dispose() {
    _snackTimer?.cancel();
    _snack.dispose();
    super.dispose();
  }

  void _toast(String message, {PetLiveMood? mood, String? assetOverride}) {
    _snackTimer?.cancel();
    _snack.value = message;
    if (mounted && (mood != null || assetOverride != null)) {
      setState(() {
        if (mood != null) _previewMood = mood;
        _previewAsset = assetOverride;
      });
    }
    _snackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _snack.value = null;
    });
  }

  void _feed(FoodDef food) {
    final result = widget.pet.feed(food.id);
    if (result.reason == 'no_food') {
      _toast(
        '${food.emoji} ${food.name}吃完了，阅读可以换更多点心哦',
        mood: PetLiveMood.pouting,
        assetOverride: 'assets/images/pet_angry.png',
      );
      return;
    }
    if (result.leveledUp) {
      _toast(
        '亲密度升级！现在是「${widget.pet.levelName}」🎉',
        mood: PetLiveMood.happy,
        assetOverride: 'assets/images/pet_cheer.png',
      );
    } else {
      _toast(
        '${food.emoji} 投喂成功 +${result.points} 亲密度',
        mood: PetLiveMood.happy,
        assetOverride: 'assets/images/pet_snack.png',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('看板娘 · 小樱'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '让桌宠回到默认位置',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () {
              widget.pet.resetPosition();
              _toast('桌宠已回到默认位置', mood: PetLiveMood.idle);
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
              Center(
                child: Column(
                  children: [
                    LiveSakuraPet(
                      size: 138,
                      mood: _previewMood,
                      assetOverride: _previewAsset,
                      motionEnabled: pet.motionEnabled,
                      showSparkles:
                          _previewMood == PetLiveMood.happy ||
                          _previewMood == PetLiveMood.shy,
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
                            '轻点呼出快捷条 · 双击摸头 +2 · 靠边自动贴边探头不挡书架',
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'wave': ('打招呼', PetLiveMood.happy),
                    'pat': ('摸摸头', PetLiveMood.shy),
                    'dance': ('跳支舞', PetLiveMood.happy),
                    'read': ('一起读书', PetLiveMood.reading),
                    'rest': ('打个盹', PetLiveMood.sleepy),
                    'tea': ('喝口茶', PetLiveMood.idle),
                    'curious': ('想一想', PetLiveMood.thinking),
                    'stretch': ('伸懒腰', PetLiveMood.idle),
                    'encourage': ('给我打气', PetLiveMood.speaking),
                  }.entries)
                    ActionChip(
                      label: Text(entry.value.$1),
                      onPressed: () {
                        pet.perform(entry.key);
                        _toast(
                          '小樱：${entry.value.$1}',
                          mood: entry.value.$2,
                          assetOverride: entry.key == 'pat'
                              ? 'assets/images/pet_shy.png'
                              : petInteractionSprites[entry.key],
                        );
                      },
                    ),
                ],
              ),
              SwitchListTile(
                title: const Text('安静陪伴'),
                subtitle: const Text('不主动冒泡；仍可轻点呼出快捷操作'),
                value: pet.quiet,
                onChanged: pet.setQuiet,
              ),
              SwitchListTile(
                title: const Text('柔和动画'),
                subtitle: const Text('呼吸、眨眼、瞳孔跟随与微动效；关闭后省电静止'),
                value: pet.motionEnabled,
                onChanged: pet.setMotionEnabled,
              ),
              TextButton.icon(
                onPressed: () {
                  if (pet.paused) {
                    pet.resumeCompanion();
                  } else {
                    pet.pauseForMinutes(15);
                  }
                },
                icon: const Icon(Icons.snooze),
                label: Text(pet.paused ? '恢复陪伴' : '暂停显示 15 分钟'),
              ),
              const SizedBox(height: 12),
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
              Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  value: !pet.petHidden,
                  onChanged: (v) => pet.setPetHidden(!v),
                  secondary: Icon(
                    pet.petHidden
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  title: const Text('在屏幕上显示桌宠'),
                  subtitle: const Text(
                    '关掉后小樱不出现在桌面上，亲密度和点心都还留着，随时能再打开',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
