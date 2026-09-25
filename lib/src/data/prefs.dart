import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../platform/native_bridge.dart';
import 'shelf_sort.dart';

/// 翻页方式。
enum PageTurnMode { slide, cover, fade, scroll }

/// 阅读背景预设。
class ReaderBg {
  const ReaderBg(this.name, this.color, this.textColor);

  final String name;
  final Color color;
  final Color textColor;
}

const List<ReaderBg> kReaderBgs = [
  ReaderBg('纸白', Color(0xFFF7F3EA), Color(0xFF33302B)),
  ReaderBg('米黄', Color(0xFFF3E5C8), Color(0xFF4A3F2D)),
  ReaderBg('护眼绿', Color(0xFFCFE8CF), Color(0xFF2E4230)),
  ReaderBg('浅灰', Color(0xFFE9E9E9), Color(0xFF333333)),
  ReaderBg('夜间', Color(0xFF15161A), Color(0xFFB9BCC4)),
  ReaderBg('纯黑', Color(0xFF000000), Color(0xFF9A9A9A)),
];

/// 字体选项（label, fontFamily）。
const List<(String, String)> kFontOptions = [
  ('默认', ''),
  ('霞鹜文楷', 'LXGWWenKai'),
  ('宋体', 'serif'),
  ('黑体', 'sans-serif'),
  ('等宽', 'monospace'),
];

/// 应用与阅读设置（本地 JSON 持久化）。
class AppPrefs extends ChangeNotifier {
  AppPrefs({AppDirs? dirsOverride}) : _dirsOverride = dirsOverride;

  final AppDirs? _dirsOverride;
  File? _file;
  Timer? _saveTimer;

  // ---- 外观 ----
  ThemeMode themeMode = ThemeMode.system;
  int accentIndex = 0;

  // ---- 书架排列 ----
  ShelfSortMode shelfSort = ShelfSortMode.recentRead;
  bool shelfAscending = false;
  ShelfViewMode shelfView = ShelfViewMode.grid;

  // ---- 阅读 ----
  double fontSize = 18;
  double lineHeight = 1.75;
  double letterSpacing = 0;
  double readerMarginH = 20;

  /// 字体：默认使用内置「霞鹜文楷」，空串 = 系统默认。
  String fontFamily = 'LXGWWenKai';
  int readerBgIndex = 0;

  /// 日间模式使用的阅读背景（日夜切换时记忆 / 恢复）。
  int lightBgIndex = 0;
  PageTurnMode pageMode = PageTurnMode.slide;
  bool keepScreenOn = true;
  bool paragraphIndent = true;

  // ---- 朗读（TTS） ----
  /// 语速（0.5~2.0）。
  double ttsRate = 1.0;

  /// 音调（0.5~2.0）。
  double ttsPitch = 1.0;

  /// 朗读时自动跟随（翻页 / 滚动到当前段落）。
  bool ttsAutoFollow = true;

  /// 朗读到章节末尾时自动进入下一章。
  bool ttsAutoNextChapter = true;

  // ---- 新手引导 ----
  /// 是否已看过新手引导（看完或跳过后都为 true，只首次启动引导一次）。
  bool guideSeen = false;

  // ---- 首次启动 ----
  /// 是否已同意首启的「使用条款与声明」（同意后才进入新手引导）。
  bool agreementAccepted = false;

  static const List<Color> accents = [
    Color(0xFFFF7EB6), // 樱粉
    Color(0xFF9D8CFF), // 薰衣草
    Color(0xFF66C6FF), // 天空蓝
    Color(0xFF5ED6A5), // 薄荷绿
    Color(0xFFFFA34E), // 蜜柑橙
  ];

  static const List<String> accentNames = ['樱粉', '薰衣草', '天空蓝', '薄荷绿', '蜜柑橙'];

  Color get accent => accents[accentIndex.clamp(0, accents.length - 1)];

  ReaderBg get readerBg =>
      kReaderBgs[readerBgIndex.clamp(0, kReaderBgs.length - 1)];

  Future<void> load() async {
    final dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${dirs.files}/settings.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map) {
          themeMode = _themeModeFrom(data['themeMode'] as String?);
          accentIndex = (data['accentIndex'] as num?)?.toInt() ?? 0;
          fontSize = (data['fontSize'] as num?)?.toDouble() ?? 18;
          lineHeight = (data['lineHeight'] as num?)?.toDouble() ?? 1.75;
          letterSpacing = (data['letterSpacing'] as num?)?.toDouble() ?? 0;
          readerMarginH = (data['readerMarginH'] as num?)?.toDouble() ?? 20;
          fontFamily = data['fontFamily'] as String? ?? 'LXGWWenKai';
          // v2 迁移：老版本未主动选过字体（空串）时，默认切换到内置霞鹜文楷
          if (fontFamily.isEmpty && ((data['v'] as num?)?.toInt() ?? 0) < 2) {
            fontFamily = 'LXGWWenKai';
          }
          readerBgIndex = (data['readerBgIndex'] as num?)?.toInt() ?? 0;
          lightBgIndex = ((data['lightBgIndex'] as num?)?.toInt() ?? 0)
              .clamp(0, 3)
              .toInt();
          pageMode = _pageModeFrom(data['pageMode'] as String?);
          keepScreenOn = data['keepScreenOn'] as bool? ?? true;
          paragraphIndent = data['paragraphIndent'] as bool? ?? true;
          // v3：书架排列（老版本无此键时保持默认）
          shelfSort = shelfSortModeFrom(data['shelfSort'] as String?);
          shelfAscending = data['shelfAscending'] as bool? ?? false;
          shelfView = shelfViewModeFrom(data['shelfView'] as String?);
          // v4：朗读设置
          ttsRate = ((data['ttsRate'] as num?)?.toDouble() ?? 1.0).clamp(
            0.5,
            2.0,
          );
          ttsPitch = ((data['ttsPitch'] as num?)?.toDouble() ?? 1.0).clamp(
            0.5,
            2.0,
          );
          ttsAutoFollow = data['ttsAutoFollow'] as bool? ?? true;
          ttsAutoNextChapter = data['ttsAutoNextChapter'] as bool? ?? true;
          // v5：新手引导是否已看过
          guideSeen = data['guideSeen'] as bool? ?? false;
          // v6：首启使用条款
          agreementAccepted = data['agreementAccepted'] as bool? ?? false;
        }
      }
    } catch (_) {
      // 读取失败时使用默认设置
    }
    notifyListeners();
  }

  ThemeMode _themeModeFrom(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  PageTurnMode _pageModeFrom(String? value) => switch (value) {
    'cover' => PageTurnMode.cover,
    'fade' => PageTurnMode.fade,
    'scroll' => PageTurnMode.scroll,
    _ => PageTurnMode.slide,
  };

  String get themeModeName => switch (themeMode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    _ => 'system',
  };

  // ---- setters ----

  /// 设置书架排序方式；沿用该方式的默认方向（如从「书名」切换时恢复升序）。
  void setShelfSort(ShelfSortMode v) {
    if (shelfSort == v) return;
    shelfSort = v;
    shelfAscending = v.defaultAscending;
    _saveSoon();
    notifyListeners();
  }

  /// 翻转当前排序方向。
  void toggleShelfAscending() {
    shelfAscending = !shelfAscending;
    _saveSoon();
    notifyListeners();
  }

  void setShelfView(ShelfViewMode v) {
    if (shelfView == v) return;
    shelfView = v;
    _saveSoon();
    notifyListeners();
  }

  // ---- 朗读 setter ----

  void setTtsRate(double v) {
    v = v.clamp(0.5, 2.0).toDouble();
    if (ttsRate == v) return;
    ttsRate = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsPitch(double v) {
    v = v.clamp(0.5, 2.0).toDouble();
    if (ttsPitch == v) return;
    ttsPitch = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsAutoFollow(bool v) {
    if (ttsAutoFollow == v) return;
    ttsAutoFollow = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsAutoNextChapter(bool v) {
    if (ttsAutoNextChapter == v) return;
    ttsAutoNextChapter = v;
    _saveSoon();
    notifyListeners();
  }

  void setThemeMode(ThemeMode v) {
    if (themeMode == v) return;
    themeMode = v;
    _saveSoon();
    notifyListeners();
  }

  void setAccentIndex(int v) {
    if (accentIndex == v) return;
    accentIndex = v;
    _saveSoon();
    notifyListeners();
  }

  void setFontSize(double v) {
    v = v.clamp(12, 34).toDouble();
    if (fontSize == v) return;
    fontSize = v;
    _saveSoon();
    notifyListeners();
  }

  void setLineHeight(double v) {
    v = v.clamp(1.2, 2.6).toDouble();
    if (lineHeight == v) return;
    lineHeight = v;
    _saveSoon();
    notifyListeners();
  }

  void setLetterSpacing(double v) {
    v = v.clamp(0, 3).toDouble();
    if (letterSpacing == v) return;
    letterSpacing = v;
    _saveSoon();
    notifyListeners();
  }

  void setReaderMarginH(double v) {
    v = v.clamp(8, 48).toDouble();
    if (readerMarginH == v) return;
    readerMarginH = v;
    _saveSoon();
    notifyListeners();
  }

  void setFontFamily(String v) {
    if (fontFamily == v) return;
    fontFamily = v;
    _saveSoon();
    notifyListeners();
  }

  void setReaderBgIndex(int v) {
    if (readerBgIndex == v) return;
    readerBgIndex = v;
    // 用户手动选择浅色背景时，记入「日间背景」（供日夜切换恢复）
    if (v < 4) lightBgIndex = v;
    _saveSoon();
    notifyListeners();
  }

  /// 当前是否为「夜间」：深色阅读背景（夜间 / 纯黑）或全局深色主题。
  bool get isNight => readerBgIndex >= 4 || themeMode == ThemeMode.dark;

  /// 一键切换日夜：阅读背景与全局主题同步。
  void setNightMode(bool night) {
    if (night) {
      if (readerBgIndex < 4) lightBgIndex = readerBgIndex;
      readerBgIndex = 4; // 夜间
      themeMode = ThemeMode.dark;
    } else {
      readerBgIndex = lightBgIndex.clamp(0, 3).toInt();
      themeMode = ThemeMode.light;
    }
    _saveSoon();
    notifyListeners();
  }

  void setPageMode(PageTurnMode v) {
    if (pageMode == v) return;
    pageMode = v;
    _saveSoon();
    notifyListeners();
  }

  void setKeepScreenOn(bool v) {
    if (keepScreenOn == v) return;
    keepScreenOn = v;
    _saveSoon();
    notifyListeners();
  }

  void setParagraphIndent(bool v) {
    if (paragraphIndent == v) return;
    paragraphIndent = v;
    _saveSoon();
    notifyListeners();
  }

  /// 标记新手引导已看过（看完 / 跳过都算）。
  void setGuideSeen(bool v) {
    if (guideSeen == v) return;
    guideSeen = v;
    _saveSoon();
    notifyListeners();
  }

  /// 标记首启使用条款已同意。
  void setAgreementAccepted(bool v) {
    if (agreementAccepted == v) return;
    agreementAccepted = v;
    _saveSoon();
    notifyListeners();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'v': 2,
          'themeMode': themeModeName,
          'accentIndex': accentIndex,
          'fontSize': fontSize,
          'lineHeight': lineHeight,
          'letterSpacing': letterSpacing,
          'readerMarginH': readerMarginH,
          'fontFamily': fontFamily,
          'readerBgIndex': readerBgIndex,
          'lightBgIndex': lightBgIndex,
          'pageMode': pageMode.name,
          'keepScreenOn': keepScreenOn,
          'paragraphIndent': paragraphIndent,
          'shelfSort': shelfSort.name,
          'shelfAscending': shelfAscending,
          'shelfView': shelfView.name,
          'ttsRate': ttsRate,
          'ttsPitch': ttsPitch,
          'ttsAutoFollow': ttsAutoFollow,
          'ttsAutoNextChapter': ttsAutoNextChapter,
          'guideSeen': guideSeen,
          'agreementAccepted': agreementAccepted,
        }),
      );
    } catch (_) {
      // 忽略保存失败
    }
  }
}
