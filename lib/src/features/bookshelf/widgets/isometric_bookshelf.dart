import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/sakura_layout.dart';
import '../../../core/theme/sakura_tokens.dart';
import '../../../core/theme/visual_style_preset.dart';
import '../../../data/models.dart';
import '../../../ui/widgets/book_cover.dart';

/// 立体等轴测书架几何方程（参考 AzukiReader / Wenku8_Flutter 平行投影设计）。
class IsometricShelfGeometry {
  const IsometricShelfGeometry._();

  static const double depthX = 0.66;
  static const double depthY = -0.30;

  static double spine(double width) => (width * 0.046).clamp(16.0, 21.0);

  static double cover(double width) => (width * 0.33).clamp(104.0, 134.0);

  static double height(double cover) => (cover - 20.0) * 166.0 / 118.0 + 54.0;

  static double baseY(double cover, double height) =>
      -cover * depthY + height * 0.56 + 12.0;

  static double rail(double distance) {
    final d = distance.clamp(-7.0, 7.0);
    return d * 2.4 + d * d * 0.42;
  }

  static double weight(double distance) {
    if (distance.abs() >= 1.48) return 0.0;
    final c = math.cos(distance / 1.48 * math.pi / 2);
    return c * c;
  }

  /// 当前书目向左上拉出并抬升的弧线偏移。
  static Offset origin(double cover, double height, double w) {
    final pull = cover * 0.84 * w * (1.24 - 0.24 * w);
    final lift = w * w * (3 - 2 * w);
    return Offset(
      -pull * depthX,
      baseY(cover, height) - pull * depthY - height * 0.56 * lift,
    );
  }

  /// 命中测试：判定点击坐标是否落在书脊或倾斜封面构成的多边形内。
  static bool contains(
    Offset point,
    double spineWidth,
    double coverWidth,
    double height,
  ) {
    final dx = coverWidth * depthX;
    final dy = -coverWidth * depthY;
    final x = point.dx;
    final y = point.dy;
    if (x < 0 || x > spineWidth + dx) return false;
    final top = x <= dx ? dy - x * dy / dx : (x - dx) * 0.1;
    final bottom = x <= spineWidth
        ? dy + x * 0.1 + height
        : dy + spineWidth * 0.1 - (x - spineWidth) * dy / dx + height;
    return y >= top && y <= bottom;
  }

  static int bookIndex(int lane, int count) => ((lane % count) + count) % count;

  static double laneRound(double value) =>
      value.sign * (value.abs() + 0.5).floorToDouble();
}

/// 惯性滑行 + 三次曲线稳态落点物理模型。
class IsometricShelfSimulation {
  IsometricShelfSimulation(
    this.start,
    double velocity, {
    this.pitch = 1.0,
    double minimumVelocity = 50.0,
    double? destination,
  }) : assert(pitch > 0) {
    final directional =
        velocity.abs() >= minimumVelocity && destination == null;
    _release = directional ? velocity : 0.0;
    var end =
        destination ??
        (IsometricShelfGeometry.laneRound((start + _release / 4.4) / pitch) *
            pitch);
    if (directional && (end - start) * _release.sign < _release.abs() / 12.0) {
      final runway = (start + _release / 12.0) / pitch;
      end =
          (_release > 0 ? runway.ceilToDouble() : runway.floorToDouble()) *
          pitch;
    }
    target = end;
    _coastDuration = directional && _release.abs() > pitch * 4.0
        ? math.log(_release.abs() / (pitch * 4.0)) / 4.4
        : 0.0;
    _handoffPosition = _coast(_coastDuration);
    _handoffVelocity = _release * math.exp(-4.4 * _coastDuration);
    _landingDuration = directional && _handoffVelocity.abs() > 1e-6
        ? 3.0 * (target - _handoffPosition) / _handoffVelocity
        : 0.0;
  }

  final double start;
  final double pitch;
  late final double _release;
  late final double target;
  late final double _coastDuration;
  late final double _handoffPosition;
  late final double _handoffVelocity;
  late final double _landingDuration;

  double _coast(double time) =>
      start + _release / 4.4 * (1.0 - math.exp(-4.4 * time));

  double position(double time) {
    if (_landingDuration <= 0.0) {
      return target +
          (start - target) * (1.0 + 12.0 * time) * math.exp(-12.0 * time);
    }
    if (time < _coastDuration) return _coast(time);
    final remaining = (1.0 - (time - _coastDuration) / _landingDuration).clamp(
      0.0,
      1.0,
    );
    return target - (target - _handoffPosition) * math.pow(remaining, 3);
  }

  double velocityAt(double time) {
    if (_landingDuration <= 0.0) {
      return -(start - target) * 144.0 * time * math.exp(-12.0 * time);
    }
    if (time < _coastDuration) return _release * math.exp(-4.4 * time);
    final remaining = (1.0 - (time - _coastDuration) / _landingDuration).clamp(
      0.0,
      1.0,
    );
    return _handoffVelocity * remaining * remaining;
  }

  double get duration {
    if (_landingDuration > 0.0) return _coastDuration + _landingDuration;
    var time = 0.0;
    while (time < 3.0 &&
        ((position(time) - target).abs() > 0.0001 ||
            velocityAt(time).abs() > 0.001)) {
      time += 0.016;
    }
    return math.max(0.016, time);
  }
}

/// 樱读美学适配版立体等轴测书架：
/// - 平行投影书脊队列 + 当前书目浮出抬升；
/// - 适配 4 套视觉预设与日/夜主题配色；
/// - 支持水平滑动惯性、点选抽书、双击/按钮续读与长按菜单。
class SakuraIsometricShelf extends StatefulWidget {
  const SakuraIsometricShelf({
    super.key,
    required this.books,
    required this.visualStyle,
    required this.sortLabel,
    required this.onOpenDetail,
    required this.onContinueReading,
    required this.onMenu,
    required this.onArrangeTap,
    this.initialIndex = 0,
  });

  final List<Book> books;
  final VisualStylePreset visualStyle;
  final String sortLabel;
  final ValueChanged<Book> onOpenDetail;
  final ValueChanged<Book> onContinueReading;
  final ValueChanged<Book> onMenu;
  final VoidCallback onArrangeTap;
  final int initialIndex;

  @override
  State<SakuraIsometricShelf> createState() => _SakuraIsometricShelfState();
}

class _SakuraIsometricShelfState extends State<SakuraIsometricShelf>
    with TickerProviderStateMixin {
  late double _focus;
  late final AnimationController _settleCtrl;
  late final AnimationController _entranceCtrl;
  IsometricShelfSimulation? _activeSim;
  double? _targetDest;
  double _targetStart = 0;

  @override
  void initState() {
    super.initState();
    final maxIdx = math.max(0, widget.books.length - 1);
    _focus = widget.initialIndex.clamp(0, maxIdx).toDouble();
    _settleCtrl = AnimationController(vsync: this)..addListener(_onSettleTick);
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceCtrl.value = 1.0;
    } else if (_entranceCtrl.value == 0.0 && !_entranceCtrl.isAnimating) {
      _entranceCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SakuraIsometricShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.books.length == 1) {
      _focus = 0.0;
    }
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final t = _settleCtrl.value;
    if (_targetDest != null) {
      final eased = const Cubic(0.2, 1.06, 0.35, 1.0).transform(t);
      setState(() {
        _focus = _targetStart + (_targetDest! - _targetStart) * eased;
      });
    } else if (_activeSim != null) {
      final sim = _activeSim!;
      setState(() {
        _focus = sim.position(t * sim.duration);
      });
    }
  }

  Future<void> _settle({
    double? target,
    double velocity = 0.0,
    double minimumVelocity = 0.0,
  }) async {
    _settleCtrl.stop();
    final count = widget.books.length;
    if (count == 0) return;
    if (count == 1) {
      setState(() => _focus = 0.0);
      return;
    }

    final sim = IsometricShelfSimulation(
      _focus,
      velocity,
      minimumVelocity: minimumVelocity,
      destination: target,
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _focus = sim.target);
      return;
    }

    if (target != null) {
      _activeSim = null;
      _targetStart = _focus;
      _targetDest = sim.target;
      _settleCtrl.duration = const Duration(milliseconds: 380);
    } else {
      _targetDest = null;
      _activeSim = sim;
      final ms = (sim.duration * 1000).round().clamp(120, 1400);
      _settleCtrl.duration = Duration(milliseconds: ms);
    }

    try {
      await _settleCtrl.forward(from: 0.0);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _focus = sim.target);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    if (books.isEmpty) return const SizedBox.shrink();

    final count = books.length;
    final activeLane = IsometricShelfGeometry.laneRound(_focus).toInt();
    final activeIndex = IsometricShelfGeometry.bookIndex(activeLane, count);
    final activeBook = books[activeIndex];

    final sakura = context.sakura;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWashi = widget.visualStyle == VisualStylePreset.kyotoWashi;
    final isAnime = widget.visualStyle == VisualStylePreset.animePop;
    final isWide = SakuraLayout.isWide(context);

    final paperColor = isWashi
        ? (isDark ? const Color(0xFF2B221D) : const Color(0xFFFFFBF4))
        : isDark
        ? Color.lerp(sakura.card, const Color(0xFF282230), 0.35)!
        : Color.lerp(sakura.card, const Color(0xFFFFFBFD), 0.72)!;
    final spineTint = isDark
        ? sakura.surfaceSubtle
        : Color.lerp(sakura.accentSoft, sakura.hairline, 0.45)!;

    final stageCard = _buildStage(
      context: context,
      books: books,
      count: count,
      activeLane: activeLane,
      paperColor: paperColor,
      spineTint: spineTint,
      sakura: sakura,
      scheme: scheme,
      isDark: isDark,
      isWashi: isWashi,
      isAnime: isAnime,
    );

    final infoAndNav = _buildFocusedDetails(
      context: context,
      book: activeBook,
      activeIndex: activeIndex,
      activeLane: activeLane,
      count: count,
      sakura: sakura,
      scheme: scheme,
      isWashi: isWashi,
      isAnime: isAnime,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 12, child: stageCard),
              const SizedBox(width: 18),
              Expanded(flex: 9, child: infoAndNav),
            ],
          )
        else ...[
          stageCard,
          const SizedBox(height: 10),
          infoAndNav,
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SHELF / CATALOGUE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      letterSpacing: 1.0,
                      color: sakura.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '书籍列表',
                    style: TextStyle(
                      color: sakura.inkPrimary,
                      fontFamily: isWashi ? 'serif' : null,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: widget.onArrangeTap,
              icon: const Icon(Icons.sort_rounded, size: 17),
              label: Text(
                widget.sortLabel,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildStage({
    required BuildContext context,
    required List<Book> books,
    required int count,
    required int activeLane,
    required Color paperColor,
    required Color spineTint,
    required SakuraColors sakura,
    required ColorScheme scheme,
    required bool isDark,
    required bool isWashi,
    required bool isAnime,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isAnime
            ? (isDark ? const Color(0xFF1E293B) : Colors.white)
            : sakura.card.withValues(alpha: isDark ? 0.62 : 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isAnime
              ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F172A))
              : sakura.hairline,
          width: isAnime ? 1.6 : 1.0,
        ),
        boxShadow: isAnime
            ? [
                BoxShadow(
                  color: isDark
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.30)
                      : const Color(0xFF0F172A),
                  offset: const Offset(4, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: sakura.coverShadow.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(280.0, 520.0);
          final spine = IsometricShelfGeometry.spine(width);
          final cover = IsometricShelfGeometry.cover(width);
          final height = IsometricShelfGeometry.height(cover);
          final pitch = spine + 11.0;
          final rowHeight =
              IsometricShelfGeometry.baseY(cover, height) + height + 54.0;
          final footprint = spine + cover * IsometricShelfGeometry.depthX;
          final center =
              constraints.maxWidth / 2 -
              footprint / 2 +
              cover * 0.84 * IsometricShelfGeometry.depthX;
          final radius =
              ((constraints.maxWidth / 2 + footprint + cover) / pitch).ceil();
          final poolCenter = _focus.floor();
          final lanes = count == 1
              ? const <int>[0]
              : [
                  for (
                    var i = poolCenter - radius;
                    i <= poolCenter + radius + 1;
                    i++
                  )
                    i,
                ];

          Offset positionFor(int lane, double entranceVal) {
            final distance = lane - _focus;
            final crest = Curves.easeOutCubic.transform(
              ((entranceVal - 0.38) / 0.62).clamp(0.0, 1.0),
            );
            final origin = IsometricShelfGeometry.origin(
              cover,
              height,
              IsometricShelfGeometry.weight(distance) * crest,
            );
            final order = (distance + width / pitch / 2 + 2).clamp(0.0, 16.0);
            final arrival = Curves.easeOutCubic.transform(
              ((entranceVal - order * 0.018) / 0.52).clamp(0.0, 1.0),
            );
            final assembly = 52.0 * (1.0 - arrival);
            final x = center + distance * pitch + origin.dx + assembly * 0.66;
            final y =
                origin.dy +
                IsometricShelfGeometry.rail(distance) -
                assembly * 0.30;
            return Offset(x, y);
          }

          int? hitTest(Offset localPoint, double entranceVal) {
            for (final lane in lanes.reversed) {
              final pos = positionFor(lane, entranceVal);
              final local = Offset(
                localPoint.dx - pos.dx,
                localPoint.dy - pos.dy + cover * 0.30,
              );
              if (IsometricShelfGeometry.contains(
                local,
                spine,
                cover,
                height,
              )) {
                return lane;
              }
            }
            return null;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: count > 1
                ? (_) {
                    _settleCtrl.stop();
                    _entranceCtrl.value = 1.0;
                  }
                : null,
            onHorizontalDragUpdate: count > 1
                ? (details) {
                    final oldLane = IsometricShelfGeometry.laneRound(_focus)
                        .toInt();
                    setState(() {
                      _focus -= details.delta.dx / pitch;
                    });
                    final newLane = IsometricShelfGeometry.laneRound(_focus)
                        .toInt();
                    if (newLane != oldLane) {
                      HapticFeedback.selectionClick();
                    }
                  }
                : null,
            onHorizontalDragEnd: count > 1
                ? (details) {
                    final vx = details.velocity.pixelsPerSecond.dx;
                    _settle(
                      velocity: -vx / pitch,
                      minimumVelocity: 50.0 / pitch,
                    );
                  }
                : null,
            onTapUp: (details) {
              _entranceCtrl.value = 1.0;
              final hitLane = hitTest(
                details.localPosition,
                _entranceCtrl.value,
              );
              if (hitLane == null) return;
              if ((hitLane - _focus).abs() >= 0.03) {
                _settle(target: hitLane.toDouble());
              } else {
                final idx = IsometricShelfGeometry.bookIndex(hitLane, count);
                widget.onOpenDetail(books[idx]);
              }
            },
            onLongPressStart: (details) {
              final hitLane = hitTest(
                details.localPosition,
                _entranceCtrl.value,
              );
              if (hitLane == null) return;
              if (hitLane == activeLane) {
                final idx = IsometricShelfGeometry.bookIndex(hitLane, count);
                widget.onMenu(books[idx]);
              }
            },
            child: AnimatedBuilder(
              animation: _entranceCtrl,
              builder: (context, _) {
                final entranceVal = _entranceCtrl.value;
                return SizedBox(
                  height: rowHeight,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BlueprintGridPainter(
                            lineColor: sakura.hairline.withValues(
                              alpha: isDark ? 0.35 : 0.65,
                            ),
                            accentColor: scheme.primary.withValues(alpha: 0.28),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GroundShadowsPainter(
                            lanes: lanes,
                            focus: _focus,
                            center: center,
                            pitch: pitch,
                            spine: spine,
                            cover: cover,
                            height: height,
                            shadowColor: isDark
                                ? Colors.black.withValues(alpha: 0.28)
                                : sakura.coverShadow.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      for (final lane in lanes)
                        _buildPositionedBook(
                          lane: lane,
                          bookIndex: IsometricShelfGeometry.bookIndex(
                            lane,
                            count,
                          ),
                          book:
                              books[IsometricShelfGeometry.bookIndex(
                                lane,
                                count,
                              )],
                          position: positionFor(lane, entranceVal),
                          focused: lane == activeLane,
                          showCover: (lane - activeLane).abs() <= 2,
                          spine: spine,
                          cover: cover,
                          height: height,
                          footprint: footprint,
                          paperColor: paperColor,
                          spineTint: spineTint,
                          ink: sakura.inkPrimary,
                          accent: scheme.primary,
                          isWashi: isWashi,
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPositionedBook({
    required int lane,
    required int bookIndex,
    required Book book,
    required Offset position,
    required bool focused,
    required bool showCover,
    required double spine,
    required double cover,
    required double height,
    required double footprint,
    required Color paperColor,
    required Color spineTint,
    required Color ink,
    required Color accent,
    required bool isWashi,
  }) {
    final dy = cover * 0.30;
    final boxHeight = height + dy + spine * 0.10;
    final coverProj = Matrix4.identity()
      ..setEntry(0, 0, IsometricShelfGeometry.depthX)
      ..setEntry(1, 0, IsometricShelfGeometry.depthY)
      ..setEntry(0, 3, spine)
      ..setEntry(1, 3, dy + spine * 0.10);
    final spineShear = Matrix4.identity()..setEntry(1, 0, 0.10);

    final glyphs = book.title.runes
        .take(7)
        .map((r) => String.fromCharCode(r))
        .toList();
    final spineText =
        glyphs.join('\n') + (book.title.runes.length > 7 ? '\n…' : '');

    return Positioned(
      key: ValueKey('iso-$lane-${book.id}'),
      left: position.dx,
      top: position.dy - dy,
      width: footprint,
      height: boxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform(
              transform: coverProj,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cover,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: paperColor,
                    border: Border.all(
                      color: focused
                          ? accent.withValues(alpha: 0.45)
                          : ink.withValues(alpha: 0.16),
                      width: 0.6,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'NO.${(bookIndex + 1).toString().padLeft(3, '0')}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: focused
                                    ? accent
                                    : ink.withValues(alpha: 0.7),
                              ),
                            ),
                            const Spacer(),
                            if (focused)
                              Icon(Icons.auto_awesome, size: 8, color: accent),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: showCover
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: BookCover(
                                    book: book,
                                    radius: 4,
                                    elevated: false,
                                    showFormatBadge: false,
                                  ),
                                )
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: spineTint.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SAKURA / ${(bookIndex + 1).toString().padLeft(3, '0')}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 7,
                            color: ink.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _IsometricBookShellPainter(
                spine: spine,
                dx: cover * IsometricShelfGeometry.depthX,
                dy: dy,
                height: height,
                paperColor: paperColor,
                lineColor: spineTint,
                inkColor: ink,
                accentColor: accent,
                focused: focused,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: dy,
            width: spine,
            height: height,
            child: Transform(
              transform: spineShear,
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      (bookIndex + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 6.5,
                        fontWeight: FontWeight.w700,
                        color: focused ? accent : ink.withValues(alpha: 0.72),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          spineText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1.05,
                            fontFamily: isWashi ? 'serif' : null,
                            fontWeight: focused
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      focused ? '●' : '○',
                      style: TextStyle(
                        fontSize: 6.5,
                        color: focused ? accent : ink.withValues(alpha: 0.5),
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
  }

  Widget _buildFocusedDetails({
    required BuildContext context,
    required Book book,
    required int activeIndex,
    required int activeLane,
    required int count,
    required SakuraColors sakura,
    required ColorScheme scheme,
    required bool isWashi,
    required bool isAnime,
  }) {
    final percent = (book.progress * 100).round();
    final chapterTitle = book.chapter?.title.trim() ?? '';
    final subParts = <String>[
      book.author.isEmpty ? '佚名' : book.author,
      book.formatLabel,
      if (book.lastReadAt > 0) '$percent%' else '未读',
      if (chapterTitle.isNotEmpty) chapterTitle,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 10),
      decoration: BoxDecoration(
        color: isAnime
            ? (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E293B)
                  : Colors.white)
            : sakura.card.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sakura.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onOpenDetail(book),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sakura.inkPrimary,
                          fontFamily: isWashi ? 'serif' : null,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sakura.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: sakura.inkSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => widget.onContinueReading(book),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  book.lastReadAt > 0 ? '继续阅读' : '开始阅读',
                  style: const TextStyle(fontSize: 12.5),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              if (count > 1)
                IconButton(
                  tooltip: '上一本',
                  onPressed: () => _settle(target: (activeLane - 1).toDouble()),
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: sakura.inkSecondary,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              Text(
                '${(activeIndex + 1).toString().padLeft(2, '0')} / ${count.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: sakura.inkSecondary,
                ),
              ),
              if (count > 1)
                IconButton(
                  tooltip: '下一本',
                  onPressed: () => _settle(target: (activeLane + 1).toDouble()),
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: sakura.inkSecondary,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlueprintGridPainter extends CustomPainter {
  const _BlueprintGridPainter({
    required this.lineColor,
    required this.accentColor,
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.6;
    const step = 34.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final mark = Paint()
      ..color = accentColor
      ..strokeWidth = 1.2;
    for (final pt in [const Offset(18, 22), Offset(size.width - 18, 22)]) {
      canvas.drawLine(pt + const Offset(-4, 0), pt + const Offset(4, 0), mark);
      canvas.drawLine(pt + const Offset(0, -4), pt + const Offset(0, 4), mark);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintGridPainter old) =>
      old.lineColor != lineColor || old.accentColor != accentColor;
}

class _GroundShadowsPainter extends CustomPainter {
  const _GroundShadowsPainter({
    required this.lanes,
    required this.focus,
    required this.center,
    required this.pitch,
    required this.spine,
    required this.cover,
    required this.height,
    required this.shadowColor,
  });

  final List<int> lanes;
  final double focus;
  final double center;
  final double pitch;
  final double spine;
  final double cover;
  final double height;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = IsometricShelfGeometry.baseY(cover, height) + height;
    for (final lane in lanes) {
      final d = lane - focus;
      final x = center + d * pitch;
      final y = baseY + IsometricShelfGeometry.rail(d);
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + spine, y + spine * 0.10)
        ..lineTo(x + spine + cover * 0.66, y - cover * 0.30 + spine * 0.10)
        ..lineTo(x + cover * 0.66, y - cover * 0.30)
        ..lineTo(x - 10, y + 10)
        ..close();
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [shadowColor, shadowColor.withValues(alpha: 0.0)],
        ).createShader(path.getBounds());
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GroundShadowsPainter old) =>
      old.focus != focus ||
      old.center != center ||
      old.lanes.length != lanes.length ||
      old.shadowColor != shadowColor;
}

class _IsometricBookShellPainter extends CustomPainter {
  const _IsometricBookShellPainter({
    required this.spine,
    required this.dx,
    required this.dy,
    required this.height,
    required this.paperColor,
    required this.lineColor,
    required this.inkColor,
    required this.accentColor,
    required this.focused,
  });

  final double spine;
  final double dx;
  final double dy;
  final double height;
  final Color paperColor;
  final Color lineColor;
  final Color inkColor;
  final Color accentColor;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final top = Path()
      ..moveTo(0, dy)
      ..lineTo(spine, dy + spine * 0.10)
      ..lineTo(spine + dx, spine * 0.10)
      ..lineTo(dx, 0)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = LinearGradient(colors: [lineColor, paperColor])
            .createShader(top.getBounds()),
    );
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..color = inkColor.withValues(alpha: 0.18),
    );

    final face = Path()
      ..moveTo(0, dy)
      ..lineTo(spine, dy + spine * 0.10)
      ..lineTo(spine, dy + spine * 0.10 + height)
      ..lineTo(0, dy + height)
      ..close();
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          colors: [paperColor, lineColor.withValues(alpha: 0.85), paperColor],
        ).createShader(face.getBounds()),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..color = focused
            ? accentColor.withValues(alpha: 0.55)
            : inkColor.withValues(alpha: 0.22),
    );
    canvas.drawLine(
      Offset(3, dy + 15),
      Offset(spine - 3, dy + 15 + (spine - 6) * 0.08),
      Paint()
        ..strokeWidth = focused ? 1.2 : 0.8
        ..color = focused
            ? accentColor.withValues(alpha: 0.65)
            : inkColor.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _IsometricBookShellPainter old) =>
      old.focused != focused ||
      old.paperColor != paperColor ||
      old.accentColor != accentColor;
}
