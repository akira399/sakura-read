import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../data/book_source.dart';
import '../../data/book_store.dart';
import '../../data/models.dart';
import '../../data/paginator.dart';
import '../../data/pet_store.dart';
import '../../data/prefs.dart';
import '../../data/stats_store.dart';
import '../../platform/native_bridge.dart';
import '../../platform/tts_service.dart';
import '../../source/source_store.dart';
import '../source/source_switch_sheet.dart';
import '../widgets/battery_badge.dart';
import 'cover_turn.dart';
import 'page_snap_physics.dart';
import 'reader_settings_panel.dart';
import 'tts_bar.dart';

/// 沉浸式小说阅读器：分页 / 覆盖 / 淡入 / 滚动四种模式。
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.store,
    required this.prefs,
    required this.bookId,
    this.chapterIndex,
    this.charOffset,
  });

  final BookStore store;
  final AppPrefs prefs;
  final String bookId;
  final int? chapterIndex;
  final int? charOffset;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  BookContent? _content;
  String _chapterText = '';
  List<PageSlice> _pages = [];
  int _chapterIndex = 0;
  int _pageIndex = 0;
  int _targetOffset = 0;
  bool _loading = true;
  bool _revealed = false;
  bool _paginationComplete = false;
  String? _error;
  bool _barsVisible = true;
  Timer? _hideTimer;
  Timer? _saveTimer;
  String _layoutSig = '';
  int _paginateGen = 0;
  Size _viewport = Size.zero;
  final Map<String, List<PageSlice>> _pagesCache = {};
  final Map<int, String> _rawTextCache = {};
  final Map<String, String> _processedCache = {};
  final Set<String> _preloading = {};

  // ---- 跨章连页（翻越章界时无缝衔接） ----
  List<_FlowPage> _flow = [];
  int _flowChapterStart = 0;
  int _flowIndex = 0;
  bool _flowDirty = false;
  bool _pendingCross = false;
  GlobalKey<_PagedReaderState> _pagerKey = GlobalKey<_PagedReaderState>();
  GlobalKey<_ScrollReaderState> _scrollKey = GlobalKey<_ScrollReaderState>();
  bool? _lastKeepAwake;
  Timer? _clockTimer;
  String _clock = '';
  int? _batteryLevel;
  bool _batteryCharging = false;

  // ---- 阅读计时（统计用；仅前台活跃时累计，单次 ≤90 秒防挂机） ----
  Timer? _readTimer;
  bool _readingActive = true;
  DateTime _lastActiveAt = DateTime.now();

  // ---- 朗读（TTS） ----
  final TtsService _tts = TtsService.instance;

  /// 是否处于朗读模式（显示控制条）。
  bool _ttsActive = false;

  /// 当前章节的朗读段落（含原文偏移，用于自动跟随）。
  List<SpeechParagraph> _ttsParagraphs = const [];

  Book? get _book => widget.store.byId(widget.bookId);

  TextStyle get _textStyle => TextStyle(
    fontSize: widget.prefs.fontSize,
    height: widget.prefs.lineHeight,
    letterSpacing: widget.prefs.letterSpacing,
    fontFamily: widget.prefs.fontFamily.isEmpty
        ? null
        : widget.prefs.fontFamily,
    color: widget.prefs.readerBg.textColor,
  );

  @override
  void initState() {
    super.initState();
    final book = _book;
    _chapterIndex = widget.chapterIndex ?? book?.safeChapterIndex ?? 0;
    _targetOffset = widget.charOffset ?? book?.charOffset ?? 0;
    WidgetsBinding.instance.addObserver(this);
    widget.prefs.addListener(_onPrefsChanged);
    _enterImmersive();
    _loadChapter(revealBars: true);
    _scheduleHide();
    _startClock();
    _startReadingTimer();
    // 桌宠：进入阅读器隐藏悬浮物；每天首次阅读送点心
    final pet = PetStore.shared;
    if (pet != null) {
      pet.setReaderActive(true);
      pet.onReadingSessionStart();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _clockTimer?.cancel();
    _saveTimer?.cancel();
    _readTimer?.cancel();
    _settleReading();
    // 退出阅读器时停止朗读，避免后台继续播报
    if (_tts.speaking || _ttsActive) {
      _tts.onParagraph = null;
      _tts.onFinished = null;
      unawaited(_tts.stop());
    }
    PetStore.shared?.setReaderActive(false);
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    widget.prefs.removeListener(_onPrefsChanged);
    NativeBridge.setKeepScreenOn(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _content?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readingActive = true;
      _lastActiveAt = DateTime.now();
    } else if (state == AppLifecycleState.paused) {
      _settleReading();
      _readingActive = false;
    }
  }

  // ---------- 阅读计时 ----------

  void _startReadingTimer() {
    _lastActiveAt = DateTime.now();
    _readTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _settleReading();
    });
  }

  /// 把上次结算以来的活跃阅读时长记入统计（未在前台时忽略）。
  void _settleReading() {
    final stats = StatsStore.shared;
    if (!_readingActive || stats == null) return;
    final now = DateTime.now();
    final delta = now.difference(_lastActiveAt).inSeconds;
    _lastActiveAt = now;
    if (delta > 0) {
      stats.addReadingSeconds(delta);
      // 桌宠：本次阅读时长兑换点心（增量式累计）
      PetStore.shared?.onReadingTick(delta);
    }
  }

  void _onPrefsChanged() {
    if (!mounted) return;
    _syncKeepAwake();
    setState(() {});
  }

  Future<void> _enterImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _syncKeepAwake();
  }

  void _syncKeepAwake() {
    final value = widget.prefs.keepScreenOn;
    if (_lastKeepAwake == value) return;
    _lastKeepAwake = value;
    NativeBridge.setKeepScreenOn(value);
  }

  // ---------- 页脚状态（时间 / 电量） ----------

  void _startClock() {
    _tickClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _tickClock();
    });
  }

  void _tickClock() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _clock =
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
      });
    }
    NativeBridge.batteryStatus().then((status) {
      if (!mounted || status == null) return;
      setState(() {
        _batteryLevel = status.level;
        _batteryCharging = status.charging;
      });
    });
  }

  // ---------- 内容加载 ----------

  Future<void> _loadChapter({bool revealBars = false}) async {
    setState(() {
      _loading = true;
      _revealed = false;
      _paginationComplete = false;
      _error = null;
      if (revealBars) _barsVisible = true;
    });
    try {
      final book = _book;
      if (book == null) throw '这本书不在书架里了';
      _content ??= createBookContent(book, widget.store);
      var raw = _rawTextCache[_chapterIndex];
      final rawCached = raw != null;
      raw ??= await _content!.chapterText(_chapterIndex);
      _rawTextCache[_chapterIndex] = raw;
      if (!mounted) return;
      _chapterText = _processText(_chapterIndex, raw);
      _layoutSig = '';
      // 预加载命中时直接同帧切换（消除翻到章尾时的"顿一下"）
      List<PageSlice>? prePages;
      String? preSig;
      if (rawCached && widget.prefs.pageMode != PageTurnMode.scroll) {
        preSig = _layoutSigFor(_chapterIndex, _chapterText);
        prePages = _pagesCache[preSig];
      }
      setState(() {
        _loading = false;
        if (prePages != null && preSig != null) {
          _pages = prePages;
          _pageIndex = _pageForOffset(prePages, _targetOffset);
          _pagerKey = GlobalKey<_PagedReaderState>();
          _revealed = true;
          _paginationComplete = true;
          _layoutSig = preSig;
          _reconcileFlow();
        }
      });
      if (prePages != null) {
        _afterPageChanged();
        unawaited(_preloadChapter(_chapterIndex + 1));
        unawaited(_preloadChapter(_chapterIndex - 1));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _processText(int chapterIndex, String raw) {
    final key = '${chapterIndex}_${widget.prefs.paragraphIndent}';
    final cached = _processedCache[key];
    if (cached != null) return cached;
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (widget.prefs.paragraphIndent) {
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        if (line.startsWith('　') || line.startsWith('［')) continue;
        lines[i] = '　　$line';
      }
      text = lines.join('\n');
    }
    _processedCache[key] = text;
    if (_processedCache.length > 6) {
      _processedCache.remove(_processedCache.keys.first);
    }
    return text;
  }

  Future<void> _goToChapter(int index, int offset) async {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapterCount) return;
    _saveProgress();
    setState(() {
      _chapterIndex = index;
      _targetOffset = offset < 0 ? 1 << 30 : offset;
      _pageIndex = 0;
      _pages = [];
      _pagerKey = GlobalKey<_PagedReaderState>();
      _scrollKey = GlobalKey<_ScrollReaderState>();
    });
    await _loadChapter();
  }

  // ---------- 分页 ----------

  void _maybeRelayout(BoxConstraints constraints) {
    if (_loading || _error != null) return;
    if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) return;
    _viewport = Size(constraints.maxWidth, constraints.maxHeight);
    final sig = _layoutSigFor(_chapterIndex, _chapterText);
    if (sig == _layoutSig) return;
    _layoutSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutSig != sig) return;
      _startLayout();
    });
  }

  /// 布局签名（章节号 + 视口 + 阅读设置），用于分页缓存键与预加载对齐。
  String _layoutSigFor(int chapterIndex, String chapterText) {
    final p = widget.prefs;
    return '$chapterIndex|${widget.bookId}|'
        '${_viewport.width.round()}x${_viewport.height.round()}|'
        '${p.fontSize}|${p.lineHeight}|${p.letterSpacing}|${p.readerMarginH}|'
        '${p.fontFamily}|${p.paragraphIndent}|${p.pageMode.name}|'
        '${chapterText.length}|${chapterText.hashCode}';
  }

  Size _bodySize() {
    final h = widget.prefs.readerMarginH;
    final width = (_viewport.width - h * 2).clamp(60, 4000).toDouble();
    final height = (_viewport.height - _topReserve - _bottomReserve)
        .clamp(60, 4000)
        .toDouble();
    return Size(width, height);
  }

  static const double _topReserve = 30;
  static const double _bottomReserve = 46;

  Future<void> _startLayout() async {
    final gen = ++_paginateGen;
    final sig = _layoutSig;
    if (widget.prefs.pageMode == PageTurnMode.scroll) {
      setState(() {
        _revealed = true;
        _paginationComplete = true;
      });
      return;
    }
    final text = _chapterText;
    if (text.isEmpty) {
      setState(() {
        _pages = [];
        _revealed = true;
        _paginationComplete = true;
      });
      return;
    }
    final cached = _pagesCache[sig];
    if (cached != null) {
      final idx = _pageForOffset(cached, _targetOffset);
      setState(() {
        _pages = cached;
        _pageIndex = idx;
        _pagerKey = GlobalKey<_PagedReaderState>();
        _revealed = true;
        _paginationComplete = true;
        _reconcileFlow();
      });
      _afterPageChanged();
      unawaited(_preloadChapter(_chapterIndex + 1));
      unawaited(_preloadChapter(_chapterIndex - 1));
      return;
    }

    final session = PaginatorSession(style: _textStyle, size: _bodySize());
    final pages = <PageSlice>[];
    setState(() {
      _pages = pages;
      _pageIndex = 0;
      _pagerKey = GlobalKey<_PagedReaderState>();
    });

    var offset = 0;
    var count = 0;
    while (offset < text.length && gen == _paginateGen && mounted) {
      var end = session.fitEnd(text, offset);
      if (end <= offset) end = offset + 1;
      if (end > text.length) end = text.length;
      pages.add(PageSlice(offset, end));
      offset = session.skipLeadingNewlines(text, end);
      count++;
      if (!_revealed && (offset >= text.length || offset > _targetOffset)) {
        setState(() {
          _revealed = true;
          _pageIndex = _pageForOffset(pages, _targetOffset);
          _reconcileFlow();
        });
        _afterPageChanged();
      }
      if (count % 2 == 0) {
        setState(_reconcileFlow);
        await Future<void>.delayed(Duration.zero);
      }
    }
    session.dispose();
    if (!mounted || gen != _paginateGen) return;
    _pagesCache[sig] = pages;
    if (_pagesCache.length > 8) {
      _pagesCache.remove(_pagesCache.keys.first);
    }
    setState(() {
      _paginationComplete = true;
      if (!_revealed) {
        _revealed = true;
        _pageIndex = _pageForOffset(pages, _targetOffset);
      }
      _reconcileFlow();
    });
    _afterPageChanged();
    // 静默预加载相邻章节：翻到章尾继续滑动时可以“秒进”下一章
    unawaited(_preloadChapter(_chapterIndex + 1));
    unawaited(_preloadChapter(_chapterIndex - 1));
  }

  // ---------- 跨章连页（翻越章界时无缝衔接） ----------

  /// 取某章处理后的正文（未加载时返回 null）。
  String? _textOfChapter(int chapter) {
    if (chapter < 0) return null;
    final raw = _rawTextCache[chapter];
    if (raw == null) return null;
    return _processText(chapter, raw);
  }

  /// 取某章已缓存的分页结果（未分页 / 未加载时返回 null）。
  List<PageSlice>? _cachedPagesOf(int chapter) {
    final text = _textOfChapter(chapter);
    if (text == null) return null;
    return _pagesCache[_layoutSigFor(chapter, text)];
  }

  static String _sliceText(String text, PageSlice p) =>
      text.substring(p.start, p.end <= text.length ? p.end : text.length);

  /// 重建跨章页流：`[上一章最后一页? | 本章全部页 | 下一章全部页?]`。
  /// 若当前页在新流中的下标发生变化，做一次“无动画对齐”
  /// （视觉内容不变，只在静止状态下执行，因此不会打断手势或动画）。
  void _reconcileFlow() {
    final book = _book;
    if (book == null) return;
    if (_pages.isEmpty) {
      _flow = const <_FlowPage>[];
      _flowChapterStart = 0;
      _flowIndex = 0;
      return;
    }
    final flow = <_FlowPage>[];
    // 头部：上一章最后一页（用于往回翻的平滑衔接）
    final prevPages = _cachedPagesOf(_chapterIndex - 1);
    final prevText = _textOfChapter(_chapterIndex - 1);
    if (prevPages != null && prevPages.isNotEmpty && prevText != null) {
      flow.add(
        _FlowPage(_chapterIndex - 1, _sliceText(prevText, prevPages.last)),
      );
    }
    final head = flow.length;
    // 本章全部页
    final curText = _textOfChapter(_chapterIndex) ?? _chapterText;
    for (final p in _pages) {
      flow.add(_FlowPage(_chapterIndex, _sliceText(curText, p)));
    }
    // 下一章全部页（已预加载时纳入，可以连续向前翻过章界）
    final nextPages = _cachedPagesOf(_chapterIndex + 1);
    final nextText = _textOfChapter(_chapterIndex + 1);
    if (nextPages != null && nextText != null) {
      for (final p in nextPages) {
        flow.add(_FlowPage(_chapterIndex + 1, _sliceText(nextText, p)));
      }
    }
    final newIndex = (head + _pageIndex).clamp(0, flow.length - 1).toInt();
    final delta = newIndex - _flowIndex;
    _flow = flow;
    _flowChapterStart = head;
    _flowIndex = newIndex;
    if (delta != 0) {
      _pagerKey.currentState?.shiftPages(delta.toDouble());
    }
  }

  /// 预加载完成后的页流刷新：静止时立即执行，否则等本次滚动结束。
  void _requestFlowExtend() {
    if (!mounted) return;
    final pager = _pagerKey.currentState;
    if (pager != null && !pager.isIdle) {
      _flowDirty = true;
      return;
    }
    setState(_reconcileFlow);
  }

  void _onFlowPageChanged(int flowIdx) {
    _flowIndex = flowIdx;
    final local = flowIdx - _flowChapterStart;
    if (local >= 0 && local < _pages.length) {
      _pendingCross = false;
      setState(() => _pageIndex = local);
      _afterPageChanged();
    } else {
      // 越过章界：先不动数据，让手势 / 动画自然完成，落稳后再落章
      _pendingCross = true;
    }
  }

  /// 滚动 / 动画停止后：处理跨章落章与延后的页流刷新。
  void _onReaderSettled() {
    if (!_pendingCross && !_flowDirty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pendingCross) {
        _commitCross();
      }
      if (_flowDirty) {
        final pager = _pagerKey.currentState;
        if (pager == null || pager.isIdle) {
          _flowDirty = false;
          setState(_reconcileFlow);
        }
      }
    });
  }

  /// 落章：把“已经翻到的那一页”正式记到相邻章节上（无动画、无重挂载）。
  void _commitCross() {
    _pendingCross = false;
    final book = _book;
    if (book == null) return;
    final local = _flowIndex - _flowChapterStart;
    if (local >= 0 && local < _pages.length) return; // 又翻回本章了
    if (local >= _pages.length) {
      // —— 向前翻入下一章 ——
      final nextIdx = _chapterIndex + 1;
      final nextPages = _cachedPagesOf(nextIdx);
      if (nextPages == null || nextPages.isEmpty) {
        _goToChapter(nextIdx.clamp(0, book.chapterCount - 1), 0);
        return;
      }
      final nextLocal = (local - _pages.length)
          .clamp(0, nextPages.length - 1)
          .toInt();
      setState(() {
        _chapterIndex = nextIdx;
        _pages = nextPages;
        _pageIndex = nextLocal;
        _chapterText = _textOfChapter(nextIdx) ?? _chapterText;
        _layoutSig = _layoutSigFor(nextIdx, _chapterText);
        _revealed = true;
        _paginationComplete = true;
        _reconcileFlow();
      });
      _afterPageChanged();
      unawaited(_preloadChapter(_chapterIndex + 1));
      unawaited(_preloadChapter(_chapterIndex - 1));
    } else {
      // —— 向后翻回上一章（落在最后一页） ——
      final prevIdx = _chapterIndex - 1;
      final prevPages = _cachedPagesOf(prevIdx);
      if (prevPages == null || prevPages.isEmpty) {
        _goToChapter(prevIdx.clamp(0, book.chapterCount - 1), -1);
        return;
      }
      setState(() {
        _chapterIndex = prevIdx;
        _pages = prevPages;
        _pageIndex = prevPages.length - 1;
        _chapterText = _textOfChapter(prevIdx) ?? _chapterText;
        _layoutSig = _layoutSigFor(prevIdx, _chapterText);
        _revealed = true;
        _paginationComplete = true;
        _reconcileFlow();
      });
      _afterPageChanged();
      unawaited(_preloadChapter(_chapterIndex + 1));
      unawaited(_preloadChapter(_chapterIndex - 1));
    }
  }

  // ---------- 相邻章节预加载 ----------

  /// 静默预加载相邻章节（文本 + 分页结果），
  /// 这样翻到章尾继续滑动时可以“秒进”下一章，不再出现“顿一下”的等待。
  Future<void> _preloadChapter(int index) async {
    final book = _book;
    if (book == null || index < 0 || index >= book.chapterCount) return;
    if (widget.prefs.pageMode == PageTurnMode.scroll) return;
    if (_viewport.width <= 0) return;
    // 稍作等待，避免与当前章节的首次渲染/分页抢时间
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _content ??= createBookContent(book, widget.store);
    var raw = _rawTextCache[index];
    if (raw == null) {
      try {
        raw = await _content!.chapterText(index);
      } catch (_) {
        return;
      }
      if (!mounted) return;
      _rawTextCache[index] = raw;
    }
    final text = _processText(index, raw);
    final sig = _layoutSigFor(index, text);
    if (_pagesCache.containsKey(sig) || _preloading.contains(sig)) return;
    _preloading.add(sig);
    try {
      final session = PaginatorSession(style: _textStyle, size: _bodySize());
      final pages = <PageSlice>[];
      var offset = 0;
      while (offset < text.length && mounted) {
        var end = session.fitEnd(text, offset);
        if (end <= offset) end = offset + 1;
        if (end > text.length) end = text.length;
        pages.add(PageSlice(offset, end));
        offset = session.skipLeadingNewlines(text, end);
        // 每页让出一次事件循环，避免预加载造成掉帧
        await Future<void>.delayed(Duration.zero);
      }
      session.dispose();
      if (!mounted) return;
      _pagesCache[sig] = pages;
      if (_pagesCache.length > 8) {
        _pagesCache.remove(_pagesCache.keys.first);
      }
      // 相邻章就绪：并入连页流（翻越章界可以连续进行）
      if (index == _chapterIndex + 1 || index == _chapterIndex - 1) {
        _requestFlowExtend();
      }
    } finally {
      _preloading.remove(sig);
    }
  }

  int _pageForOffset(List<PageSlice> pages, int offset) {
    if (pages.isEmpty) return 0;
    for (var i = 0; i < pages.length; i++) {
      if (offset < pages[i].end) return i;
    }
    return pages.length - 1;
  }

  int get _currentOffset =>
      _pages.isEmpty ? 0 : _pages[_pageIndex.clamp(0, _pages.length - 1)].start;

  void _afterPageChanged() {
    _saveProgressSoon();
    final book = _book;
    if (book == null) return;
    final lastChapter = _chapterIndex >= book.chapterCount - 1;
    final lastPage =
        _paginationComplete &&
        _pageIndex >= _pages.length - 1 &&
        _pages.isNotEmpty;
    if (lastChapter && lastPage && !book.finished) {
      widget.store.updateProgress(book.id, finished: true);
      StatsStore.shared?.addFinishedBook();
    }
  }

  void _saveProgressSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveProgress);
  }

  void _saveProgress() {
    final book = _book;
    if (book == null || _loading || _error != null) return;
    if (widget.prefs.pageMode == PageTurnMode.scroll) {
      widget.store.updateProgress(
        book.id,
        chapter: _chapterIndex,
        offset: _scrollOffset,
      );
    } else {
      widget.store.updateProgress(
        book.id,
        chapter: _chapterIndex,
        offset: _currentOffset,
      );
    }
  }

  int _scrollOffset = 0;

  // ---------- 翻页 ----------

  void _nextPage() {
    if (widget.prefs.pageMode == PageTurnMode.scroll) {
      _scrollKey.currentState?.scrollPageDown();
      return;
    }
    if (_flowIndex < _flow.length - 1) {
      _pagerKey.currentState?.animateNext();
    } else if (!_paginationComplete) {
      // 还在分页，稍等
    } else {
      final book = _book;
      if (book != null && _chapterIndex < book.chapterCount - 1) {
        _goToChapter(_chapterIndex + 1, 0);
      } else {
        _toastLate('已经读完最后一章啦 🎉');
      }
    }
  }

  void _prevPage() {
    if (widget.prefs.pageMode == PageTurnMode.scroll) {
      _scrollKey.currentState?.scrollPageUp();
      return;
    }
    if (_flowIndex > 0) {
      _pagerKey.currentState?.animatePrev();
    } else if (_chapterIndex > 0) {
      _goToChapter(_chapterIndex - 1, -1);
    }
  }

  void _toastLate(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 220,
      ),
    );
  }

  // ---------- 界面 ----------

  void _toggleBars() {
    setState(() => _barsVisible = !_barsVisible);
    if (_barsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _barsVisible) setState(() => _barsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.prefs.readerBg;
    return Scaffold(
      backgroundColor: bg.color,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _maybeRelayout(constraints);
                return _buildContent(context, bg);
              },
            ),
          ),
          _buildTopBar(bg),
          _buildBottomBar(bg),
          // 朗读控制条（朗读时悬浮在底部，位于底栏之上）
          if (_ttsActive)
            Positioned(
              left: 12,
              right: 12,
              bottom: _barsVisible ? 168 : 24,
              child: SafeArea(
                top: false,
                child: TtsBar(
                  service: _tts,
                  onPrev: _ttsPrev,
                  onNext: _ttsNext,
                  onToggle: _toggleTts,
                  onStop: _stopTts,
                  onOpenSettings: _showTtsSettings,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ReaderBg bg) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '加载中…',
              style: TextStyle(
                color: bg.textColor.withValues(alpha: .6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sentiment_dissatisfied_rounded,
              size: 46,
              color: bg.textColor.withValues(alpha: .5),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: bg.textColor.withValues(alpha: .7),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _loadChapter(revealBars: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_chapterText.isEmpty) {
      return Center(
        child: Text(
          '这一章没有内容',
          style: TextStyle(color: bg.textColor.withValues(alpha: .6)),
        ),
      );
    }

    final mode = widget.prefs.pageMode;
    final book = _book;
    final chapter = book?.chapters[_chapterIndex];

    Widget reader;
    if (mode == PageTurnMode.scroll) {
      reader = _ScrollReader(
        key: _scrollKey,
        text: _chapterText,
        style: _textStyle,
        marginH: widget.prefs.readerMarginH,
        topReserve: _topReserve,
        bottomReserve: _bottomReserve,
        initialOffset: _targetOffset,
        onOffsetChanged: (offset) {
          _scrollOffset = offset;
          _saveProgressSoon();
        },
        onToggleBars: _toggleBars,
      );
    } else if (!_revealed || _pages.isEmpty) {
      reader = Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    } else {
      // 页面全屏出血（文字左右边距在页面内部实现），翻页动画才能像
      // 阅读 3.0 一样覆盖到屏幕最左 / 最右边缘，两侧不留静止的空白缝。
      reader = _PagedReader(
        key: _pagerKey,
        pages: _flow,
        style: _textStyle,
        backdrop: bg.color,
        marginH: widget.prefs.readerMarginH,
        initialPage: _flowChapterStart + _pageIndex,
        mode: mode,
        topReserve: _topReserve,
        bottomReserve: _bottomReserve,
        onPageChanged: _onFlowPageChanged,
        onSettled: _onReaderSettled,
        onBeyondNext: () {
          if (_paginationComplete) {
            _nextPage();
          }
        },
        onBeyondPrev: _prevPage,
        onToggleBars: _toggleBars,
      );
    }

    final footColor = bg.textColor.withValues(alpha: .45);
    final footStyle = TextStyle(fontSize: 11, color: footColor);
    return Stack(
      children: [
        Positioned.fill(child: reader),
        // 页眉：章节名（呼出菜单时自动隐藏，避免与菜单叠字）
        Positioned(
          left: widget.prefs.readerMarginH,
          right: widget.prefs.readerMarginH,
          top: _topReserve - 24,
          child: AnimatedOpacity(
            opacity: _barsVisible ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: Text(
              chapter?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: bg.textColor.withValues(alpha: .45),
              ),
            ),
          ),
        ),
        // 页脚：页码 / 进度（呼出菜单时自动隐藏）
        Positioned(
          left: widget.prefs.readerMarginH,
          right: widget.prefs.readerMarginH,
          bottom: _bottomReserve - 30,
          child: AnimatedOpacity(
            opacity: _barsVisible ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: Row(
              children: [
                // 左下：时间
                Expanded(child: Text(_clock, style: footStyle)),
                // 中：页码 · 进度
                Expanded(
                  child: Text(
                    mode == PageTurnMode.scroll || _pages.isEmpty
                        ? '${(progress * 100).toStringAsFixed(1)}%'
                        : '${_pageIndex + 1} / ${_pages.length}  ·  ${(progress * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: footStyle,
                  ),
                ),
                // 右下：电量
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: BatteryBadge(
                      level: _batteryLevel,
                      charging: _batteryCharging,
                      color: footColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 全书进度（0~1）。
  double get progress {
    final book = _book;
    if (book == null || book.chapterCount == 0) return 0;
    final chapter = book.chapters[_chapterIndex];
    final local = widget.prefs.pageMode == PageTurnMode.scroll
        ? (chapter.charCount > 0
              ? (_scrollOffset / chapter.charCount).clamp(0.0, 1.0)
              : 0.0)
        : (chapter.charCount > 0 && _pages.isNotEmpty
              ? (_currentOffset / chapter.charCount).clamp(0.0, 1.0)
              : 0.0);
    return ((_chapterIndex + local) / book.chapterCount).clamp(0.0, 1.0);
  }

  Widget _buildTopBar(ReaderBg bg) {
    final book = _book;
    final dark =
        ThemeData.estimateBrightnessForColor(bg.color) == Brightness.dark;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      top: _barsVisible ? 0 : -140,
      child: IgnorePointer(
        ignoring: !_barsVisible,
        child: Container(
          decoration: BoxDecoration(
            color: bg.color,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .30 : .10),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 10, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                    tooltip: '返回',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        if (book != null)
                          Text(
                            '第 ${_chapterIndex + 1}/${book.chapterCount} 章',
                            style: TextStyle(
                              color: (dark ? Colors.white : Colors.black87)
                                  .withValues(alpha: .65),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _showChapterSheet,
                    icon: Icon(
                      Icons.format_list_bulleted_rounded,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                    tooltip: '目录',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderBg bg) {
    final book = _book;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      bottom: _barsVisible ? 0 : -230,
      child: IgnorePointer(
        ignoring: !_barsVisible,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BookSlider(
                    progress: progress,
                    onJump: (value) => _jumpToProgress(value),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _barButton(
                        icon: Icons.skip_previous_rounded,
                        label: '上一章',
                        enabled: _chapterIndex > 0,
                        onTap: () => _goToChapter(_chapterIndex - 1, 0),
                      ),
                      _barButton(
                        icon: Icons.format_list_bulleted_rounded,
                        label: '目录',
                        onTap: _showChapterSheet,
                      ),
                      _barButton(
                        icon: Icons.bookmark_border_rounded,
                        label: '书签',
                        onTap: _showBookmarkSheet,
                      ),
                      _barButton(
                        icon: _ttsActive
                            ? Icons.record_voice_over_rounded
                            : Icons.record_voice_over_outlined,
                        label: '朗读',
                        onTap: _startTts,
                      ),
                      if (book?.format == BookFormat.online)
                        _barButton(
                          icon: Icons.swap_horiz_rounded,
                          label: '换源',
                          onTap: _showSourceSwitch,
                        ),
                      _barButton(
                        icon: Icons.text_fields_rounded,
                        label: '设置',
                        onTap: () => _showSettingsSheet(scheme),
                      ),
                      _barButton(
                        icon: Icons.skip_next_rounded,
                        label: '下一章',
                        enabled:
                            book != null &&
                            _chapterIndex < book.chapterCount - 1,
                        onTap: () => _goToChapter(_chapterIndex + 1, 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barButton({
    required IconData icon,
    required String label,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    final color = enabled ? Colors.white : Colors.white38;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  void _jumpToProgress(double value) {
    final book = _book;
    if (book == null || book.totalChars <= 0) return;
    final target = (value.clamp(0.0, 1.0) * book.totalChars).round();
    var acc = 0;
    for (var i = 0; i < book.chapterCount; i++) {
      final count = book.chapters[i].charCount;
      if (target <= acc + count || i == book.chapterCount - 1) {
        final offset = (target - acc).clamp(0, count).toInt();
        _goToChapter(i, offset);
        return;
      }
      acc += count;
    }
  }

  void _showChapterSheet() {
    final book = _book;
    if (book == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.62,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.format_list_bulleted_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '目录 · 共 ${book.chapterCount} 章',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: book.chapterCount,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _chapterIndex;
                    final chapter = book.chapters[index];
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      title: Text(
                        chapter.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w900
                              : FontWeight.w500,
                        ),
                      ),
                      trailing: chapter.charCount > 0
                          ? Text(
                              '${chapter.charCount} 字',
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _goToChapter(index, 0);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 朗读（TTS） ----------

  /// 从当前位置开始朗读本章。
  Future<void> _startTts() async {
    if (_chapterText.isEmpty) {
      _toastLate('本章暂时没有可朗读的内容');
      return;
    }
    // 用「当前阅读位置」作为朗读起点
    final startOffset = _readingOffset;
    _ttsParagraphs = splitForSpeechWithOffsets(_chapterText);
    if (_ttsParagraphs.isEmpty) {
      _toastLate('本章暂时没有可朗读的内容');
      return;
    }
    var from = 0;
    for (var i = 0; i < _ttsParagraphs.length; i++) {
      if (_ttsParagraphs[i].offset <= startOffset) {
        from = i;
      } else {
        break;
      }
    }

    final ok = await _tts.ensureReady();
    if (!mounted) return;
    if (!ok) {
      // 设备没有可用引擎：给出可操作提示
      final engines = await _tts.engines();
      if (!mounted) return;
      _showTtsUnavailable(engines);
      return;
    }

    // 朗读进度回调：自动跟随 + 章节末尾续播
    _tts.onParagraph = _onTtsParagraph;
    _tts.onFinished = _onTtsChapterFinished;
    setState(() => _ttsActive = true);
    await _tts.start(
      _ttsParagraphs.map((p) => p.text).toList(),
      from: from,
      rate: widget.prefs.ttsRate,
      pitch: widget.prefs.ttsPitch,
    );
  }

  /// 朗读进行到某一段：可选自动跟随（翻到对应页 / 滚动到位）。
  void _onTtsParagraph(int index) {
    if (!widget.prefs.ttsAutoFollow) return;
    if (index < 0 || index >= _ttsParagraphs.length) return;
    final offset = _ttsParagraphs[index].offset;
    if (widget.prefs.pageMode == PageTurnMode.scroll) {
      _scrollKey.currentState?.scrollToOffset(offset);
    } else {
      final page = _pageForOffset(_pages, offset);
      if (page != _pageIndex) {
        setState(() => _pageIndex = page);
      }
    }
  }

  /// 本章读完：按设置自动进入下一章继续朗读。
  Future<void> _onTtsChapterFinished() async {
    if (!mounted) return;
    final book = _book;
    if (book == null) return;
    if (!widget.prefs.ttsAutoNextChapter) {
      _toastLate('本章读完啦');
      return;
    }
    if (_chapterIndex >= book.chapterCount - 1) {
      _toastLate('整本书都读完啦 🎉');
      setState(() => _ttsActive = false);
      return;
    }
    _toastLate('本章读完，继续下一章');
    await _goToChapter(_chapterIndex + 1, 0);
    if (!mounted) return;
    await _restartTtsForChapter();
  }

  /// 换章后重新装载朗读段落并从开头继续。
  Future<void> _restartTtsForChapter() async {
    if (_chapterText.isEmpty) return;
    _ttsParagraphs = splitForSpeechWithOffsets(_chapterText);
    if (_ttsParagraphs.isEmpty) return;
    _tts.onParagraph = _onTtsParagraph;
    _tts.onFinished = _onTtsChapterFinished;
    await _tts.start(
      _ttsParagraphs.map((p) => p.text).toList(),
      rate: widget.prefs.ttsRate,
      pitch: widget.prefs.ttsPitch,
    );
  }

  Future<void> _toggleTts() async {
    if (_tts.speaking) {
      await _tts.pause();
    } else {
      if (_tts.total == 0) {
        await _startTts();
      } else {
        await _tts.resume(
          rate: widget.prefs.ttsRate,
          pitch: widget.prefs.ttsPitch,
        );
      }
    }
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    _tts.onParagraph = null;
    _tts.onFinished = null;
    if (mounted) setState(() => _ttsActive = false);
  }

  Future<void> _ttsPrev() async {
    await _tts.previous(rate: widget.prefs.ttsRate);
  }

  Future<void> _ttsNext() async {
    if (_tts.index >= _tts.total - 1) {
      await _onTtsChapterFinished();
      return;
    }
    await _tts.next(rate: widget.prefs.ttsRate);
  }

  /// 朗读设置弹层（语速 / 音调 / 自动跟随 / 自动下一章）。
  void _showTtsSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: AnimatedBuilder(
          animation: widget.prefs,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.record_voice_over_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '朗读设置',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(
                      width: 52,
                      child: Text('语速', style: TextStyle(fontSize: 12.5)),
                    ),
                    Expanded(
                      child: Slider(
                        value: widget.prefs.ttsRate.clamp(0.5, 2.0),
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: '${widget.prefs.ttsRate.toStringAsFixed(1)}x',
                        onChanged: (v) async {
                          widget.prefs.setTtsRate(v);
                          await _tts.setRate(v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${widget.prefs.ttsRate.toStringAsFixed(1)}x',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(
                      width: 52,
                      child: Text('音调', style: TextStyle(fontSize: 12.5)),
                    ),
                    Expanded(
                      child: Slider(
                        value: widget.prefs.ttsPitch.clamp(0.5, 2.0),
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: widget.prefs.ttsPitch.toStringAsFixed(1),
                        onChanged: (v) {
                          widget.prefs.setTtsPitch(v);
                          _tts.setPitch(v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        widget.prefs.ttsPitch.toStringAsFixed(1),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: widget.prefs.ttsAutoFollow,
                  onChanged: widget.prefs.setTtsAutoFollow,
                  title: const Text(
                    '朗读时自动跟随（翻到正在读的位置）',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: widget.prefs.ttsAutoNextChapter,
                  onChanged: widget.prefs.setTtsAutoNextChapter,
                  title: const Text(
                    '读完整章自动下一章',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 设备无可用语音引擎时的引导弹窗。
  void _showTtsUnavailable(List<String> engines) {
    final hasEngine = engines.isNotEmpty;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          '朗读暂时不可用',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          hasEngine
              ? '检测到语音引擎，但无法初始化中文朗读。\n\n'
                    '请到「系统设置 → 无障碍 / 语音合成」安装中文语音数据后重试。\n\n'
                    '已检测到：${engines.join('、')}'
              : '系统未安装语音合成（TTS）引擎。\n\n'
                    '请安装语音引擎（如「Google 语音服务」或手机厂商语音服务），'
                    '并在系统设置里设为默认后重试。',
          style: const TextStyle(height: 1.6, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(ColorScheme scheme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: ReaderSettingsPanel(
            prefs: widget.prefs,
            petStore: PetStore.shared,
          ),
        ),
      ),
    );
  }

  // ---------- 书签 ----------

  /// 当前阅读位置的章内偏移（滚动 / 翻页两种模式取各自值）。
  int get _readingOffset => widget.prefs.pageMode == PageTurnMode.scroll
      ? _scrollOffset
      : _currentOffset;

  /// 当前位置附近的正文摘录（书签预览用）。
  String _excerptAt(int offset) {
    final text = _chapterText;
    if (text.isEmpty) return '';
    final start = offset.clamp(0, text.length).toInt();
    final end = (start + 36).clamp(0, text.length).toInt();
    return text
        .substring(start, end)
        .replaceAll('\n', ' ')
        .replaceAll('　', ' ')
        .trim();
  }

  /// 添加当前位置书签；返回给调用方展示的提示文案。
  String _addBookmarkAtCurrent() {
    final book = _book;
    final store = BookmarkStore.shared;
    if (book == null || store == null) return '书签服务未就绪';
    final existing = store.nearby(widget.bookId, _chapterIndex, _readingOffset);
    if (existing != null) return '这个位置已经收藏过啦～';
    final chapterTitle = book.chapters.isEmpty
        ? ''
        : book.chapters[_chapterIndex].title;
    store.add(
      Bookmark(
        id: Bookmark.newId(),
        bookId: widget.bookId,
        chapterIndex: _chapterIndex,
        charOffset: _readingOffset,
        chapterTitle: chapterTitle,
        excerpt: _excerptAt(_readingOffset),
      ),
    );
    return '书签已添加 🔖';
  }

  void _showBookmarkSheet() {
    final book = _book;
    final store = BookmarkStore.shared;
    if (book == null || store == null) return;
    final hint = ValueNotifier<String?>(null); // 添加结果提示（内联展示）
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.62,
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final bookmarks = store.forBook(widget.bookId);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_border_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '书签 · 共 ${bookmarks.length} 条',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => hint.value = _addBookmarkAtCurrent(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('当前位置'),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '第 ${_chapterIndex + 1} 章 · 点右侧按钮收藏当前位置',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: hint,
                    builder: (context, value, _) => value == null
                        ? const SizedBox(height: 6)
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              value,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: bookmarks.isEmpty
                        ? const Center(
                            child: Text(
                              '还没有书签，去收藏一个吧～',
                              style: TextStyle(fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: bookmarks.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final b = bookmarks[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.bookmark_rounded,
                                  size: 18,
                                ),
                                title: Text(
                                  b.chapterTitle.isEmpty
                                      ? '第 ${b.chapterIndex + 1} 章'
                                      : b.chapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: b.excerpt.isEmpty
                                    ? null
                                    : Text(
                                        b.excerpt,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  tooltip: '删除',
                                  onPressed: () => store.remove(b.id),
                                ),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  _goToChapter(b.chapterIndex, b.charOffset);
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- 换源 ----------

  Future<void> _showSourceSwitch() async {
    final book = _book;
    if (book == null || book.format != BookFormat.online) return;
    final sourceStore = SourceStore.shared;
    if (sourceStore == null) {
      _toastLate('书源未就绪');
      return;
    }
    final ok = await showSourceSwitchSheet(
      context,
      bookStore: widget.store,
      sourceStore: sourceStore,
      book: book,
    );
    if (ok && mounted) _afterSourceSwitch();
  }

  /// 换源成功后：清空全部章节缓存并重新加载当前章节。
  void _afterSourceSwitch() {
    final book = _book;
    if (book == null) return;
    _content?.dispose();
    _content = null;
    _rawTextCache.clear();
    _processedCache.clear();
    _pagesCache.clear();
    _preloading.clear();
    _flow = const <_FlowPage>[];
    _flowIndex = 0;
    _flowChapterStart = 0;
    _pendingCross = false;
    _flowDirty = false;
    _chapterIndex = book.chapterCount == 0
        ? 0
        : _chapterIndex.clamp(0, book.chapterCount - 1).toInt();
    _pageIndex = 0;
    _targetOffset = 0;
    _pagerKey = GlobalKey<_PagedReaderState>();
    _scrollKey = GlobalKey<_ScrollReaderState>();
    _toastLate('已换源，正在重新加载本章…');
    _loadChapter(revealBars: true);
  }
}

// ==================== 翻页视图 ====================

class _PagedReader extends StatefulWidget {
  const _PagedReader({
    super.key,
    required this.pages,
    required this.style,
    required this.backdrop,
    required this.marginH,
    required this.initialPage,
    required this.mode,
    required this.topReserve,
    required this.bottomReserve,
    required this.onPageChanged,
    required this.onSettled,
    required this.onBeyondNext,
    required this.onBeyondPrev,
    required this.onToggleBars,
  });

  final List<_FlowPage> pages;
  final TextStyle style;

  /// 页面不透明底色（阅读背景色），保证覆盖 / 淡入动画不会透出下页文字。
  final Color backdrop;

  /// 文字左右边距（页面全屏出血，边距在页面内部实现）。
  final double marginH;
  final int initialPage;
  final PageTurnMode mode;
  final double topReserve;
  final double bottomReserve;
  final ValueChanged<int> onPageChanged;

  /// 滚动 / 动画落稳后回调（用于跨章落章与页流刷新）。
  final VoidCallback onSettled;
  final VoidCallback onBeyondNext;
  final VoidCallback onBeyondPrev;
  final VoidCallback onToggleBars;

  @override
  State<_PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<_PagedReader> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );

  // ---- 拖过边缘自动翻章：累积超过边缘的拖动距离 ----
  static const double _beyondPullPx = 24;
  double _pullNext = 0;
  double _pullPrev = 0;
  bool _beyondFired = false;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _pullNext = 0;
      _pullPrev = 0;
      _beyondFired = false;
    } else if (notification is ScrollEndNotification) {
      widget.onSettled();
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        !_beyondFired) {
      final metrics = notification.metrics;
      final atEnd = metrics.pixels >= metrics.maxScrollExtent - 0.5;
      final atStart = metrics.pixels <= metrics.minScrollExtent + 0.5;
      final pull = notification.overscroll.abs();
      if (atEnd) {
        // 已在本章最后一页，还在继续拖 → 进下一章
        _pullPrev = 0;
        _pullNext += pull;
        if (_pullNext > _beyondPullPx) {
          _beyondFired = true;
          widget.onBeyondNext();
        }
      } else if (atStart) {
        // 已在本章第一页，还在往回拖 → 上一章
        _pullNext = 0;
        _pullPrev += pull;
        if (_pullPrev > _beyondPullPx) {
          _beyondFired = true;
          widget.onBeyondPrev();
        }
      }
    }
    return false;
  }

  /// 无动画平移若干页（跨章落章时对齐页流用；视觉内容保持不变）。
  /// 注意不要按旧范围裁剪：调用方会在同一帧内换成新页流，
  /// 目标位置对新页流的范围是合法的。
  void shiftPages(double deltaPages) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (!pos.hasPixels || !pos.hasViewportDimension) return;
    var target = pos.pixels + deltaPages * pos.viewportDimension;
    if (target < 0) target = 0;
    pos.jumpTo(target);
  }

  /// 是否处于静止状态（无拖拽 / 无惯性动画）。
  bool get isIdle =>
      !(_controller.hasClients &&
          _controller.position.isScrollingNotifier.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void animateNext() {
    final current = (_controller.page ?? widget.initialPage.toDouble()).round();
    if (current >= widget.pages.length - 1) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void animatePrev() {
    final current = (_controller.page ?? widget.initialPage.toDouble()).round();
    if (current <= 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOut,
    );
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final x = size.width <= 0 ? .5 : details.localPosition.dx / size.width;
    if (x < .3) {
      widget.onBeyondPrev();
    } else if (x > .7) {
      widget.onBeyondNext();
    } else {
      widget.onToggleBars();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTapUp(details, size),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              controller: _controller,
              // 阅读 3.0 风格吸附：固定速率（约 300ms/页）取代默认弹簧，
              // 消除翻页末段 400~500ms 的“磨蹭尾巴”（跨章落章时尤其明显）。
              physics: const PageSnapPhysics(),
              itemCount: widget.pages.length,
              onPageChanged: widget.onPageChanged,
              itemBuilder: (context, index) {
                final pageText = widget.pages[index].text;
                final content = Container(
                  color: widget.backdrop,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.marginH,
                      widget.topReserve,
                      widget.marginH,
                      widget.bottomReserve,
                    ),
                    child: SizedBox.expand(
                      child: Text(
                        pageText,
                        style: widget.style,
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
                );
                if (widget.mode == PageTurnMode.slide) return content;
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    var delta = 0.0;
                    if (_controller.position.haveDimensions) {
                      delta =
                          index -
                          (_controller.page ??
                              _controller.initialPage.toDouble());
                    } else {
                      delta = index - _controller.initialPage.toDouble();
                    }
                    if (widget.mode == PageTurnMode.cover) {
                      // == 覆盖翻页：对照阅读 3.0 的 CoverPageDelegate 逐行移植 ==
                      // NEXT：当前页跟手向左滑出（cur 以 offsetX 平移），
                      //       下一页固定在底层、从右侧逐渐露出（next 原位 + clipRect）；
                      // PREV：上一页从左侧滑入，盖住原地不动的当前页。
                      // 钉住页渲染细节见 cover_turn.dart（含显式裁剪与像素级回归测试）。
                      return CoverTurnItem(
                        delta: delta,
                        width: size.width,
                        shadowWidth:
                            30 / MediaQuery.devicePixelRatioOf(context),
                        child: child ?? content,
                      );
                    }
                    // 淡入：所有页吸附原地（抵消 PageView 位移），仅上层页切换透明度
                    final opacity = delta > 0
                        ? (1 - delta).clamp(0.0, 1.0).toDouble()
                        : 1.0;
                    return Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(-delta * size.width, 0),
                        child: child,
                      ),
                    );
                  },
                  child: content,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 跨章连页中的一页：切好的正文文本 + 所属章节（章节号用于调试与校验）。
class _FlowPage {
  const _FlowPage(this.chapter, this.text);

  final int chapter;
  final String text;
}

// ==================== 滚动视图 ====================

class _ScrollReader extends StatefulWidget {
  const _ScrollReader({
    super.key,
    required this.text,
    required this.style,
    required this.marginH,
    required this.topReserve,
    required this.bottomReserve,
    required this.initialOffset,
    required this.onOffsetChanged,
    required this.onToggleBars,
  });

  final String text;
  final TextStyle style;
  final double marginH;
  final double topReserve;
  final double bottomReserve;
  final int initialOffset;
  final ValueChanged<int> onOffsetChanged;
  final VoidCallback onToggleBars;

  @override
  State<_ScrollReader> createState() => _ScrollReaderState();
}

class _ScrollReaderState extends State<_ScrollReader> {
  late final List<String> _paragraphs;
  late final List<int> _cumulative;
  final Map<int, GlobalKey> _keys = {};
  ScrollController? _scroll;
  Timer? _settleTimer;
  double _viewportHeight = 0;
  int _pendingParagraph = -1;
  int _correctAttempts = 0;

  @override
  void initState() {
    super.initState();
    _paragraphs = widget.text.split('\n');
    _cumulative = List.filled(_paragraphs.length + 1, 0);
    var acc = 0;
    for (var i = 0; i < _paragraphs.length; i++) {
      _cumulative[i] = acc;
      acc += _paragraphs[i].length + 1;
    }
    _cumulative[_paragraphs.length] = acc;
    _pendingParagraph = _paragraphForOffset(widget.initialOffset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scroll == null) {
      _viewportHeight = MediaQuery.sizeOf(context).height;
      final estimate = _viewportHeight * 0.9;
      _scroll = ScrollController(
        initialScrollOffset: _pendingParagraph * estimate,
      );
      if (_pendingParagraph > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _correctAttempts = 10;
          _tryCorrect();
        });
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _scroll?.dispose();
    super.dispose();
  }

  int _paragraphForOffset(int offset) {
    var lo = 0;
    var hi = _paragraphs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_cumulative[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _tryCorrect() {
    if (!mounted || _correctAttempts <= 0 || _pendingParagraph < 0) return;
    _correctAttempts--;
    final ctx = _keys[_pendingParagraph]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return;
    }
    Future.delayed(const Duration(milliseconds: 140), _tryCorrect);
  }

  void scrollPageDown() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final target = (scroll.offset + _viewportHeight * 0.85).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void scrollPageUp() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final target = (scroll.offset - _viewportHeight * 0.85).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  /// 朗读自动跟随：把指定原文偏移处的段落滚动到视口顶部。
  void scrollToOffset(int offset) {
    final index = _paragraphForOffset(offset);
    if (index < 0 || index >= _paragraphs.length) return;
    _pendingParagraph = index;
    _correctAttempts = 6;
    _tryCorrect();
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(milliseconds: 180), _settle);
    }
    return false;
  }

  void _settle() {
    if (!mounted) return;
    final index = _firstVisibleParagraph();
    final offset = index < _cumulative.length ? _cumulative[index] : 0;
    widget.onOffsetChanged(offset);
  }

  int _firstVisibleParagraph() {
    final indices = _keys.keys.toList()..sort();
    for (final i in indices) {
      final ctx = _keys[i]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      if (dy + h > 8) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          widget.marginH,
          widget.topReserve,
          widget.marginH,
          widget.bottomReserve + 60,
        ),
        itemCount: _paragraphs.length,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
        itemBuilder: (context, index) {
          final paragraph = _paragraphs[index];
          final key = _keys.putIfAbsent(index, () => GlobalKey());
          if (paragraph.trim().isEmpty) {
            return SizedBox(key: key, height: widget.style.fontSize ?? 16);
          }
          return GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggleBars,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph,
                style: widget.style,
                textScaler: TextScaler.noScaling,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== 全书进度滑杆 ====================

class _BookSlider extends StatefulWidget {
  const _BookSlider({required this.progress, required this.onJump});

  final double progress;
  final ValueChanged<double> onJump;

  @override
  State<_BookSlider> createState() => _BookSliderState();
}

class _BookSliderState extends State<_BookSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.progress.clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onJump(v);
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
