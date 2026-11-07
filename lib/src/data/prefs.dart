import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'persistence.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/native_bridge.dart';
import '../source/online_repo.dart';
import 'shelf_sort.dart';
import '../platform/credential_store.dart';

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
class AppPrefs extends ChangeNotifier with ReliablePersistence {
  AppPrefs({this._dirsOverride, CredentialStore? credentials})
    : _credentials = credentials ?? CredentialStore();

  final CredentialStore _credentials;
  bool _credentialsReady = false;

  final AppDirs? _dirsOverride;
  File? _file;
  Timer? _saveTimer;

  // ---- 外观 ----
  ThemeMode themeMode = ThemeMode.system;
  int accentIndex = 0;
  bool showSplashAnimation = true;

  // ---- 书架排列 ----
  ShelfSortMode shelfSort = ShelfSortMode.recentRead;
  bool shelfAscending = false;
  ShelfViewMode shelfView = ShelfViewMode.grid;

  // ---- 阅读 ----
  double fontSize = 18;
  double lineHeight = 1.75;
  double letterSpacing = 0;
  double readerMarginH = 20;

  /// 段间距（每段之间的额外空隙，单位 px）。
  ///
  /// 用户反馈：「行距、段距不能调到负的，间隔还是有点大」——原先行距最小
  /// 只能到 1.2、段间距写死 12px，想让排版更紧凑也没办法。这里把行距下限
  /// 放开到 1.0，并把段间距做成可调（0 = 完全紧贴）。
  double paragraphSpacing = 12;

  /// 书源搜索并发数（1~32）。
  ///
  /// 用户反馈：「书源搜索能不能设置线程，搜索太难了」——多书源搜索时同时
  /// 请求的书源个数，调大能更快出结果，但弱网/低端机上容易被限流。
  int searchConcurrency = 8;

  /// 「人物」X-Ray：正文里的人名是否高亮。
  ///
  /// 只在阅读器内生效；识别结果为空时自然不高亮。默认开启，
  /// 不喜欢的用户在「人物」面板里一键关掉。
  bool xrayHighlight = true;

  /// 顶部 / 底部工具条是否用「磨砂玻璃」（实时模糊）观感。
  ///
  /// 用户反馈：「调来调去都没有磨砂」——以前只有半透明蒙层，没有真模糊。
  /// 实时模糊要每帧采样一次背景，低端机会掉帧，所以做成开关（默认关）。
  bool frostedGlass = false;

  /// 正文区距屏幕顶部的留白（上边距）。
  ///
  /// 用户反馈：希望能自己定「正文离顶部多远」（原先是写死的 30）。
  /// 页眉（章节名）也挂在这块留白里。
  double readerPaddingTop = 30;

  /// 正文区距屏幕底部的留白（下边距；页脚挂在这里）。
  double readerPaddingBottom = 46;

  /// 是否显示页眉（章节名）。
  bool readerHeaderVisible = true;

  /// 是否显示页脚（时间 / 页码 / 电量）。
  bool readerFooterVisible = true;

  /// 字体：默认使用内置「霞鹜文楷」，空串 = 系统默认。
  String fontFamily = 'LXGWWenKai';
  int readerBgIndex = 0;

  /// 日间模式使用的阅读背景（日夜切换时记忆 / 恢复）。
  int lightBgIndex = 0;
  PageTurnMode pageMode = PageTurnMode.slide;
  bool keepScreenOn = true;
  bool paragraphIndent = true;

  /// 音量键翻页：打开后阅读页内音量上/下键 = 上一页/下一页。
  ///
  /// 用户反馈「音量键翻页」——很多人习惯单手用音量键翻页，所以默认开启；
  /// 只在阅读页内生效，退出阅读页立刻解绑，不影响其它页面调音量。
  bool volumeKeyPaging = true;

  // ---- 朗读（TTS） ----
  /// 语速（0.5~3.0）。用户反馈：「倍速能加到 3 倍吗」。
  double ttsRate = 1.0;

  /// 音调（0.5~2.0）。
  double ttsPitch = 1.0;

  /// 朗读时自动跟随（翻页 / 滚动到当前段落）。
  bool ttsAutoFollow = true;

  /// 朗读到章节末尾时自动进入下一章。
  bool ttsAutoNextChapter = true;

  /// 朗读引擎包名（空 = 系统默认）。
  ///
  /// 用户反馈：一加等机型自带引擎不会被系统选为默认 → 朗读不可用。
  /// 允许手动指定，并持久化。
  String ttsEngine = '';

  /// 系统 TTS 的音色名（空 = 引擎默认音色）。
  ///
  /// 用户反馈：「不能自己选择男声和女声」——系统引擎都支持 voices 列表，
  /// 以前没有入口，这里记下用户选的音色名（引擎重连后自动套用）。
  String ttsVoice = '';

  /// 朗读音色风格：neutral / female / male / deep（内置离线语音靠音调模拟）。
  /// 内置离线朗读用的语音包 id（'chaowen' = 内置超文；其余为下载的包）。
  String ttsVoicePack = 'chaowen';

  /// 多说话人语音包的说话人编号。
  int ttsVoiceSid = 0;

  /// AI 分角色朗读：对白 / 旁白用不同音色朗读。
  ///
  /// 用户反馈：「番茄那种自动分角色阅读功能支持吗」——本地用规则识别
  /// 对白（「」『』"" 开头或「人名：」开头）并给每个人分配稳定的音高，
  /// 不需要联网、不需要 token。
  bool ttsRolePlay = false;

  // ---- 备份 / WebDAV ----
  /// WebDAV 服务器地址（如 https://dav.jianguoyun.com/dav）。
  String webdavUrl = '';
  String webdavUser = '';
  String webdavPass = '';

  /// 云端目录（相对 WebDAV 根，末尾自动补 /）。
  String webdavDir = 'sakura-read/';

  /// 最近一次成功备份的时间（ISO 字符串，空 = 从未备份）。
  String lastBackupAt = '';

  // ---- AI 助手（小樱） ----
  /// 兼容 OpenAI Chat Completions 的接口地址（如 https://api.openai.com/v1）。

  int searchTimeout = 15;
  String customFontPath = '';
  String customBackgroundPath = '';
  String get customFontFamily =>
      'UserFont-${File(customFontPath).uri.pathSegments.last}';

  Future<void> importReaderAsset(String path, {required bool font}) async {
    final source = File(path);
    if (await source.length() > 20 * 1024 * 1024) {
      throw StateError('文件不能超过 20 MB');
    }
    final dirs = _dirsOverride ?? await NativeBridge.appDirs();
    final target = File(
      '${dirs.files}/reader-assets/${DateTime.now().microsecondsSinceEpoch}.${font ? 'ttf' : 'img'}',
    );
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    if (font) {
      final old = customFontPath;
      customFontPath = target.path;
      try {
        await _loadUserFont();
      } catch (_) {
        customFontPath = old;
        rethrow;
      }
      fontFamily = customFontFamily;
    } else {
      customBackgroundPath = target.path;
    }
    await flush();
    notifyListeners();
  }

  Future<void> _loadUserFont() async {
    if (customFontPath.isEmpty) return;
    final bytes = await File(customFontPath).readAsBytes();
    await (FontLoader(
      customFontFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  void clearReaderBackground() {
    customBackgroundPath = '';
    _saveSoon();
    notifyListeners();
  }

  void setSearchOptions(int count, int seconds) {
    searchConcurrency = count.clamp(1, 999);
    OnlineRepo.defaultConcurrency = searchConcurrency;
    searchTimeout = seconds.clamp(5, 30);
    _saveSoon();
    notifyListeners();
  }

  String aiBaseUrl = '';

  /// API Key（只保存在本机设置文件里）。
  String aiApiKey = '';

  /// 模型名（如 gpt-4o-mini / deepseek-chat）。
  String aiModel = '';

  /// 聊天时把书架 / 进度 / 时长等阅读数据一起发给模型。
  bool aiIncludeReading = true;

  /// 使用内置的本地小模型（离线运行，不联网、不需要 Key）。
  ///
  /// 用户反馈集中在两点：不想额外花钱配 API Key、担心阅读数据被上传。
  /// 打开后整个对话都在本机跑（模型文件需要先下载，见 [aiLocalModelId]）。
  bool aiUseLocalModel = false;

  /// 选中的本地模型 id（空 = 用 [localModelCatalog] 里推荐的默认模型）。
  String aiLocalModelId = '';

  // ---- 新手引导 ----
  /// 是否已看过新手引导（看完或跳过后都为 true，只首次启动引导一次）。
  bool guideSeen = false;

  // ---- 首次启动 ----
  /// 是否已同意首启的「使用条款与声明」（同意后才进入新手引导）。
  bool agreementAccepted = false;

  // ---- 更新检查 ----
  /// 启动时自动检查更新（默认开启；设置页可关闭）。
  bool autoCheckUpdate = true;

  /// 显示帧率/耗时浮层（排查卡顿用；默认关闭）。
  bool showPerformanceOverlay = false;

  /// 高刷新率渲染（默认开启）：有 120Hz 屏幕时按最高刷新率出帧，
  /// 而不是被系统钉在 60Hz。关掉更省电。
  bool highRefreshRate = true;

  /// 用户点过「以后再说」的版本（该版本不再自动弹窗；空 = 无）。
  ///
  /// 只影响自动弹窗：设置页「检查更新」仍会展示。
  String skipUpdateVersion = '';

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
        final data = await readJson(_file!);
        if (data is Map) {
          themeMode = _themeModeFrom(data['themeMode'] as String?);
          accentIndex = (data['accentIndex'] as num?)?.toInt() ?? 0;
          showSplashAnimation = data['showSplashAnimation'] as bool? ?? true;
          fontSize = (data['fontSize'] as num?)?.toDouble() ?? 18;
          lineHeight = (data['lineHeight'] as num?)?.toDouble() ?? 1.75;
          letterSpacing = (data['letterSpacing'] as num?)?.toDouble() ?? 0;
          readerMarginH = (data['readerMarginH'] as num?)?.toDouble() ?? 20;
          xrayHighlight = data['xrayHighlight'] as bool? ?? true;
          // v10：段间距可调（用户反馈：段与段之间的空隙太大）
          paragraphSpacing =
              ((data['paragraphSpacing'] as num?)?.toDouble() ?? 12).clamp(
                0,
                40,
              );
          searchConcurrency =
              ((data['searchConcurrency'] as num?)?.toInt() ?? 8).clamp(1, 999);
          // v8：正文上下留白 + 页眉页脚开关（用户反馈：想自己定这些距离）
          readerPaddingTop =
              ((data['readerPaddingTop'] as num?)?.toDouble() ?? 30).clamp(
                0,
                160,
              );
          readerPaddingBottom =
              ((data['readerPaddingBottom'] as num?)?.toDouble() ?? 46).clamp(
                0,
                160,
              );
          readerHeaderVisible = data['readerHeaderVisible'] as bool? ?? true;
          readerFooterVisible = data['readerFooterVisible'] as bool? ?? true;
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
          volumeKeyPaging = data['volumeKeyPaging'] as bool? ?? true;
          // v3：书架排列（老版本无此键时保持默认）
          shelfSort = shelfSortModeFrom(data['shelfSort'] as String?);
          shelfAscending = data['shelfAscending'] as bool? ?? false;
          shelfView = shelfViewModeFrom(data['shelfView'] as String?);
          // v4：朗读设置
          ttsRate = ((data['ttsRate'] as num?)?.toDouble() ?? 1.0).clamp(
            0.5,
            3.0,
          );
          ttsPitch = ((data['ttsPitch'] as num?)?.toDouble() ?? 1.0).clamp(
            0.5,
            2.0,
          );
          ttsAutoFollow = data['ttsAutoFollow'] as bool? ?? true;
          ttsAutoNextChapter = data['ttsAutoNextChapter'] as bool? ?? true;
          // v8：朗读引擎（空 = 系统默认）
          ttsEngine = data['ttsEngine'] as String? ?? '';
          // v15：音色 / 分角色 / 磨砂 / 备份
          ttsVoice = data['ttsVoice'] as String? ?? '';
          ttsVoicePack = data['ttsVoicePack'] as String? ?? 'chaowen';
          ttsVoiceSid = (data['ttsVoiceSid'] as num?)?.toInt() ?? 0;
          ttsRolePlay = data['ttsRolePlay'] as bool? ?? false;
          frostedGlass = data['frostedGlass'] as bool? ?? false;
          webdavUrl = data['webdavUrl'] as String? ?? '';
          webdavUser = data['webdavUser'] as String? ?? '';
          webdavPass = data['webdavPass'] as String? ?? '';
          webdavDir = data['webdavDir'] as String? ?? 'sakura-read/';
          lastBackupAt = data['lastBackupAt'] as String? ?? '';
          // v5：新手引导是否已看过
          guideSeen = data['guideSeen'] as bool? ?? false;
          // v6：首启使用条款
          agreementAccepted = data['agreementAccepted'] as bool? ?? false;
          // v7：更新检查
          autoCheckUpdate = data['autoCheckUpdate'] as bool? ?? true;
          showPerformanceOverlay =
              data['showPerformanceOverlay'] as bool? ?? false;
          highRefreshRate = data['highRefreshRate'] as bool? ?? true;
          skipUpdateVersion = data['skipUpdateVersion'] as String? ?? '';
          // v9：AI 助手接口配置
          searchTimeout = ((data['searchTimeout'] as num?)?.toInt() ?? 15)
              .clamp(5, 30);
          customFontPath = data['customFontPath'] as String? ?? '';
          customBackgroundPath = data['customBackgroundPath'] as String? ?? '';
          aiBaseUrl = data['aiBaseUrl'] as String? ?? '';
          aiApiKey = data['aiApiKey'] as String? ?? '';
          aiModel = data['aiModel'] as String? ?? '';
          aiIncludeReading = data['aiIncludeReading'] as bool? ?? true;
          // v10：本地小模型（离线 AI）
          aiUseLocalModel = data['aiUseLocalModel'] as bool? ?? false;
          aiLocalModelId = data['aiLocalModelId'] as String? ?? '';
        }
      }
    } catch (_) {
      // 读取失败时使用默认设置
    }
    try {
      final stored = await _credentials.read();
      _credentialsReady = true;
      if (stored != null) {
        Map<String, dynamic>? secrets;
        try {
          final value = jsonDecode(stored);
          if (value is Map && value['credentialVersion'] == 1) {
            secrets = Map<String, dynamic>.from(value);
          }
        } catch (_) {}
        if (secrets != null) {
          aiApiKey = secrets['aiApiKey'] as String? ?? '';
          webdavPass = secrets['webdavPass'] as String? ?? '';
        } else {
          aiApiKey = stored;
        }
      } else if (aiApiKey.isNotEmpty || webdavPass.isNotEmpty) {
        await _credentials.write(
          jsonEncode({
            "credentialVersion": 1,
            "aiApiKey": aiApiKey,
            "webdavPass": webdavPass,
          }),
        );
      }
      // Secure write must succeed before removing a legacy plaintext key.
      if (await _file!.exists()) await flush();
    } catch (error) {
      lastPersistenceError = error;
      persistenceFailures.value = {...persistenceFailures.value, _file!.path};
    }
    try {
      await _loadUserFont();
    } catch (_) {
      fontFamily = 'LXGWWenKai';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(flush().catchError((Object _) {}));
    super.dispose();
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
    v = v.clamp(0.5, 3.0).toDouble();
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

  /// 音色风格：neutral / female / male / deep。
  void setTtsVoicePack(String v) {
    if (ttsVoicePack == v) return;
    ttsVoicePack = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsVoiceSid(int v) {
    if (ttsVoiceSid == v) return;
    ttsVoiceSid = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsVoice(String v) {
    if (ttsVoice == v) return;
    ttsVoice = v;
    _saveSoon();
    notifyListeners();
  }

  void setTtsRolePlay(bool v) {
    if (ttsRolePlay == v) return;
    ttsRolePlay = v;
    _saveSoon();
    notifyListeners();
  }

  void setFrostedGlass(bool v) {
    if (frostedGlass == v) return;
    frostedGlass = v;
    _saveSoon();
    notifyListeners();
  }

  void setWebdav({String? url, String? user, String? pass, String? dir}) {
    var changed = false;
    if (url != null && url != webdavUrl) {
      webdavUrl = url;
      changed = true;
    }
    if (user != null && user != webdavUser) {
      webdavUser = user;
      changed = true;
    }
    if (pass != null && pass != webdavPass) {
      webdavPass = pass;
      changed = true;
    }
    if (dir != null && dir != webdavDir) {
      webdavDir = dir;
      changed = true;
    }
    if (!changed) return;
    _saveSoon();
    notifyListeners();
  }

  void setLastBackupAt(String v) {
    if (lastBackupAt == v) return;
    lastBackupAt = v;
    _saveSoon();
    notifyListeners();
  }

  /// 朗读引擎（空 = 系统默认）。
  void setTtsEngine(String v) {
    if (ttsEngine == v) return;
    ttsEngine = v;
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
    // 下限放到 1.0：用户反馈想把行距调得更紧凑（原来最小 1.2）
    v = v.clamp(1.0, 2.6).toDouble();
    if (lineHeight == v) return;
    lineHeight = v;
    _saveSoon();
    notifyListeners();
  }

  void setSearchConcurrency(int v) {
    v = v.clamp(1, 999);
    if (searchConcurrency == v) return;
    searchConcurrency = v;
    OnlineRepo.defaultConcurrency = v;
    _saveSoon();
    notifyListeners();
  }

  void setParagraphSpacing(double v) {
    v = v.clamp(0, 40).toDouble();
    if (paragraphSpacing == v) return;
    paragraphSpacing = v;
    _saveSoon();
    notifyListeners();
  }

  void setXrayHighlight(bool v) {
    if (xrayHighlight == v) return;
    xrayHighlight = v;
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

  /// 正文距顶部留白（页眉也挂在这里）。
  void setReaderPaddingTop(double v) {
    v = v.clamp(0, 160).toDouble();
    if (readerPaddingTop == v) return;
    readerPaddingTop = v;
    _saveSoon();
    notifyListeners();
  }

  /// 正文距底部留白（页脚挂在这里）。
  void setReaderPaddingBottom(double v) {
    v = v.clamp(0, 160).toDouble();
    if (readerPaddingBottom == v) return;
    readerPaddingBottom = v;
    _saveSoon();
    notifyListeners();
  }

  void setReaderHeaderVisible(bool v) {
    if (readerHeaderVisible == v) return;
    readerHeaderVisible = v;
    _saveSoon();
    notifyListeners();
  }

  void setReaderFooterVisible(bool v) {
    if (readerFooterVisible == v) return;
    readerFooterVisible = v;
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

  void setVolumeKeyPaging(bool v) {
    if (volumeKeyPaging == v) return;
    volumeKeyPaging = v;
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

  /// 启动时自动检查更新开关。
  void setShowSplashAnimation(bool value) {
    if (showSplashAnimation == value) return;
    showSplashAnimation = value;
    _saveSoon();
    notifyListeners();
  }

  void setAutoCheckUpdate(bool v) {
    if (autoCheckUpdate == v) return;
    autoCheckUpdate = v;
    _saveSoon();
    notifyListeners();
  }

  /// 高刷新率渲染开关。
  void setHighRefreshRate(bool v) {
    if (highRefreshRate == v) return;
    highRefreshRate = v;
    _saveSoon();
    notifyListeners();
  }

  /// 显示帧率浮层开关。
  void setShowPerformanceOverlay(bool v) {
    if (showPerformanceOverlay == v) return;
    showPerformanceOverlay = v;
    _saveSoon();
    notifyListeners();
  }

  /// 记住用户点过「以后再说」的版本（该版本不再自动弹窗）。
  void setSkipUpdateVersion(String v) {
    if (skipUpdateVersion == v) return;
    skipUpdateVersion = v;
    _saveSoon();
    notifyListeners();
  }

  /// 保存 AI 助手接口配置（地址 / Key / 模型 / 是否附带阅读数据）。
  void setAiConfig({
    required String baseUrl,
    required String apiKey,
    required String model,
    required bool includeReading,
  }) {
    aiBaseUrl = baseUrl.trim();
    aiApiKey = apiKey.trim();
    _credentialsReady = true;
    aiModel = model.trim();
    aiIncludeReading = includeReading;
    _saveSoon();
    notifyListeners();
  }

  /// 切换「内置本地模型 / 在线接口」。
  void setAiUseLocalModel(bool value) {
    aiUseLocalModel = value;
    _saveSoon();
    notifyListeners();
  }

  /// 选择要用的本地模型（空字符串 = 用推荐默认模型）。
  void setAiLocalModelId(String id) {
    aiLocalModelId = id.trim();
    _saveSoon();
    notifyListeners();
  }

  /// 是否已填好可用的在线 AI 接口配置。
  ///
  /// Key 允许为空：Ollama 等本机服务通常不需要鉴权。
  bool get aiHttpConfigured =>
      aiBaseUrl.trim().isNotEmpty && aiModel.trim().isNotEmpty;

  /// AI 助手是否已经可用（在线接口已填 / 或选了本地模型）。
  ///
  /// 本地模型还要看模型文件有没有下载好，那是 LocalModelManager 的事，
  /// 这里只回答「用户选了哪种方式」。
  bool get aiConfigured => aiUseLocalModel || aiHttpConfigured;

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_save().catchError((Object _) {}));
    });
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    return _save();
  }

  Future<void> _save() {
    final file = _file;
    if (file == null) return Future.value();
    final key = jsonEncode({
      "credentialVersion": 1,
      "aiApiKey": aiApiKey,
      "webdavPass": webdavPass,
    });
    return writeJson(
      file,
      jsonEncode({
        'v': 2,
        'themeMode': themeModeName,
        'accentIndex': accentIndex,
        'showSplashAnimation': showSplashAnimation,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'readerMarginH': readerMarginH,
        'paragraphSpacing': paragraphSpacing,
        'readerPaddingTop': readerPaddingTop,
        'readerPaddingBottom': readerPaddingBottom,
        'readerHeaderVisible': readerHeaderVisible,
        'readerFooterVisible': readerFooterVisible,
        'fontFamily': fontFamily,
        'readerBgIndex': readerBgIndex,
        'lightBgIndex': lightBgIndex,
        'pageMode': pageMode.name,
        'keepScreenOn': keepScreenOn,
        'volumeKeyPaging': volumeKeyPaging,
        'paragraphIndent': paragraphIndent,
        'shelfSort': shelfSort.name,
        'shelfAscending': shelfAscending,
        'shelfView': shelfView.name,
        'ttsRate': ttsRate,
        'ttsPitch': ttsPitch,
        'ttsAutoFollow': ttsAutoFollow,
        'ttsAutoNextChapter': ttsAutoNextChapter,
        'ttsEngine': ttsEngine,
        'guideSeen': guideSeen,
        'agreementAccepted': agreementAccepted,
        'autoCheckUpdate': autoCheckUpdate,
        'showPerformanceOverlay': showPerformanceOverlay,
        'highRefreshRate': highRefreshRate,
        'skipUpdateVersion': skipUpdateVersion,
        'customFontPath': customFontPath,
        'customBackgroundPath': customBackgroundPath,
        'searchConcurrency': searchConcurrency,
        'searchTimeout': searchTimeout,
        'xrayHighlight': xrayHighlight,
        'ttsVoice': ttsVoice,
        'ttsVoicePack': ttsVoicePack,
        'ttsVoiceSid': ttsVoiceSid,
        'ttsRolePlay': ttsRolePlay,
        'frostedGlass': frostedGlass,
        'webdavUrl': webdavUrl,
        'webdavUser': webdavUser,
        'webdavDir': webdavDir,
        'lastBackupAt': lastBackupAt,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'aiIncludeReading': aiIncludeReading,
        'aiUseLocalModel': aiUseLocalModel,
        'aiLocalModelId': aiLocalModelId,
      }),
      beforeWrite: () async {
        if (!_credentialsReady) {
          throw StateError("Secure credentials could not be loaded");
        }
        await _credentials.write(key);
      },
    );
  }
}
