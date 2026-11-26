import 'dart:async';

import 'package:flutter/material.dart';
import 'package:paper_curl/paper_curl.dart';

/// 基于 `paper_curl` GPU 着色器的 3D 仿真卷页视图。
///
/// 桥接阅读器的跨章连页流、点击翻页区（左 30% 上页 / 中 40% 菜单 / 右 30% 下页）、
/// 边界继续滑动触发跨章，以及昼夜纸张背面色板适配。
class SimulationTurnView extends StatefulWidget {
  const SimulationTurnView({
    super.key,
    required this.itemCount,
    required this.initialPage,
    required this.backdrop,
    required this.itemBuilder,
    required this.onPageChanged,
    required this.onSettled,
    required this.onBeyondNext,
    required this.onBeyondPrev,
    required this.onToggleBars,
    this.onLongPress,
  });

  final int itemCount;
  final int initialPage;
  final Color backdrop;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onSettled;
  final VoidCallback onBeyondNext;
  final VoidCallback onBeyondPrev;
  final VoidCallback onToggleBars;
  final VoidCallback? onLongPress;

  @override
  State<SimulationTurnView> createState() => SimulationTurnViewState();
}

class SimulationTurnViewState extends State<SimulationTurnView> {
  late final PageCurlController _controller = PageCurlController(
    initialPage: widget.itemCount == 0
        ? 0
        : widget.initialPage.clamp(0, widget.itemCount - 1),
  );

  bool _wasTurning = false;
  Offset? _pointerDown;
  bool _edgeTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final turning = _controller.isTurning;
    if (_wasTurning && !turning) {
      widget.onSettled();
    }
    _wasTurning = turning;
  }

  /// 是否静止（无卷页拖拽或动画）。
  bool get isIdle => !_controller.isTurning;

  /// 当前页索引。
  int get currentPage => _controller.page;

  /// 翻到下一页（若已在流末尾则回调跨章）。
  void animateNext() {
    if (_controller.isTurning) return;
    if (_controller.page < widget.itemCount - 1) {
      unawaited(_controller.nextPage());
    } else {
      widget.onBeyondNext();
    }
  }

  /// 翻到上一页（若已在流开头则回调跨章）。
  void animatePrev() {
    if (_controller.isTurning) return;
    if (_controller.page > 0) {
      unawaited(_controller.previousPage());
    } else {
      widget.onBeyondPrev();
    }
  }

  /// 无动画跳至指定页。
  void jumpToIndex(int index) {
    if (widget.itemCount <= 0) return;
    final target = index.clamp(0, widget.itemCount - 1);
    if (target == _controller.page) return;
    _controller.jumpToPage(target);
  }

  /// 跨章流重排时无动画对齐索引。
  void shiftPages(int deltaPages) {
    if (deltaPages == 0 || widget.itemCount <= 0) return;
    final target = (_controller.page + deltaPages).clamp(
      0,
      widget.itemCount - 1,
    );
    _controller.jumpToPage(target);
  }

  void _onTapUp(TapUpDetails details, Size size) {
    if (_controller.isTurning) return;
    final x = size.width <= 0 ? 0.5 : details.localPosition.dx / size.width;
    if (x < 0.30) {
      animatePrev();
    } else if (x > 0.70) {
      animateNext();
    } else {
      widget.onToggleBars();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerDown = event.localPosition;
    _edgeTriggered = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_edgeTriggered || _pointerDown == null || _controller.isTurning) return;
    final dx = event.localPosition.dx - _pointerDown!.dx;
    final dy = (event.localPosition.dy - _pointerDown!.dy).abs();
    if (dx.abs() < 42 || dy > dx.abs() * 0.85) return;
    if (dx < -42 && _controller.page >= widget.itemCount - 1) {
      _edgeTriggered = true;
      widget.onBeyondNext();
    } else if (dx > 42 && _controller.page <= 0) {
      _edgeTriggered = true;
      widget.onBeyondPrev();
    }
  }

  void _onPointerUp(PointerEvent _) {
    _pointerDown = null;
    _edgeTriggered = false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        ThemeData.estimateBrightnessForColor(widget.backdrop) ==
        Brightness.dark;
    final backColor = isDark
        ? Color.lerp(widget.backdrop, const Color(0xFF0A0B0F), 0.35)!
        : Color.lerp(widget.backdrop, const Color(0xFFE5DAC2), 0.38)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) => _onTapUp(details, size),
            onLongPress: widget.onLongPress,
            child: PageCurlView(
              controller: _controller,
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
              pageColor: widget.backdrop,
              backColor: backColor,
              ink: isDark ? 0.06 : 0.13,
              shadow: isDark ? 0.65 : 0.95,
              maxRadius: 54,
              duration: const Duration(milliseconds: 420),
              onPageChanged: (index) {
                widget.onPageChanged(index);
                widget.onSettled();
              },
            ),
          ),
        );
      },
    );
  }
}
