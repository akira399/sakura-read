// 桌宠 · 亲密度养成系统：数据层。
//
// - 亲密度：点击互动 / 投喂食物增长，7 级阶梯（初遇 → 挚爱）；
// - 食物：只通过阅读时长获得（20min 樱饼 / 1h 团子 / 5h 大福 / 20h 蛋糕），
//   每天首次阅读额外送 1 个团子；
// - 点击互动有每日上限（防刷），投喂无上限但依赖库存。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/native_bridge.dart';

/// 桌宠宿主就绪标志：**开屏结束 + 权限就绪**后才显示悬浮桌宠。
final ValueNotifier<bool> kPetHostReady = ValueNotifier<bool>(false);

bool _petSplashDone = false;
bool _petHomeReady = false;

/// 开屏（冷启动动画）结束时调用；未播放开屏（进程内二次进入）时挂载后也应调用。
void petMarkSplashDone() {
  _petSplashDone = true;
  _syncPetHostReady();
}

/// 主界面权限就绪状态变化时调用（进入书架 = ready）。
void petMarkHomeReady(bool ready) {
  _petHomeReady = ready;
  _syncPetHostReady();
}

void _syncPetHostReady() {
  kPetHostReady.value = _petSplashDone && _petHomeReady;
}

/// 桌宠是否应该打瞌睡：深夜时段（23:00~6:00），或超过 [idleMinutes] 分钟无互动。
bool shouldPetDoze({
  required DateTime now,
  required DateTime lastInteraction,
  int idleMinutes = 5,
}) {
  final h = now.hour;
  if (h >= 23 || h < 6) return true;
  return now.difference(lastInteraction) >= Duration(minutes: idleMinutes);
}

/// 按小时选择时段问候语。
String petGreetingForHour(int hour) {
  if (hour < 5) return '夜深了，别熬夜太晚哦';
  if (hour < 11) return '早上好呀，今天想读点什么？';
  if (hour < 14) return '午后适合来一段故事呢';
  if (hour < 18) return '下午好呀，累了吗？';
  if (hour < 23) return '晚上好，忙完就来了一起看书吧';
  return '快休息啦，睡前看一小段就好哦';
}

/// 仅供测试：重置桌宠宿主就绪状态。
@visibleForTesting
void debugResetPetHostReady() {
  _petSplashDone = false;
  _petHomeReady = false;
  kPetHostReady.value = false;
}

/// 一种食物。
class FoodDef {
  const FoodDef(this.id, this.name, this.emoji, this.affinity, this.perSeconds);

  final String id;
  final String name;
  final String emoji;

  /// 投喂增加的亲密度。
  final int affinity;

  /// 每累计阅读这么多秒可获得 1 个（0 = 不通过阅读获得）。
  final int perSeconds;
}

/// 食物表（按价值从低到高）。
const List<FoodDef> kPetFoods = [
  FoodDef('mochi', '樱饼', '🍪', 5, 20 * 60),
  FoodDef('dango', '三色团子', '🍡', 8, 60 * 60),
  FoodDef('daifuku', '草莓大福', '🍓', 12, 5 * 60 * 60),
  FoodDef('cake', '樱花蛋糕', '🍰', 20, 20 * 60 * 60),
];

/// 亲密度等级阈值（下标 = 等级 - 1）。
const List<int> kAffinityLevels = [0, 30, 90, 200, 400, 700, 1200];

/// 等级名。
const List<String> kAffinityLevelNames = [
  '初遇',
  '相识',
  '书友',
  '好友',
  '知己',
  '亲密',
  '挚爱',
];

/// 点击互动：每次 +1 亲密度，每日上限。
const int kPetClickPoints = 1;
const int kPetDailyClickCap = 20;

/// 摸头（双击）：每次 +2 亲密度，每日上限。
const int kPetPatPoints = 2;
const int kPetDailyPatCap = 10;

/// 互动 / 投喂的结果。
class PetActionResult {
  const PetActionResult({
    this.points = 0,
    this.leveledUp = false,
    this.level = 1,
    this.reason = 'ok',
  });

  /// 本次获得的亲密度（0 = 没得到）。
  final int points;

  /// 是否升级了。
  final bool leveledUp;
  final int level;

  /// 'ok' / 'daily_cap'（今日互动已满）/ 'no_food'（没这种食物了）。
  final String reason;
}

/// 桌宠数据仓库（进程内共享实例 + JSON 持久化）。
class PetStore extends ChangeNotifier {
  PetStore({AppDirs? dirsOverride}) : _dirsOverride = dirsOverride;

  static PetStore? shared;

  final AppDirs? _dirsOverride;
  File? _file;
  Timer? _saveTimer;

  int _affinity = 0;
  final Map<String, int> _inventory = {}; // foodId -> 数量
  final Map<String, int> _rewarded = {}; // foodId -> 已发放次数（按阅读时长里程碑）
  int _readSeconds = 0; // 宠物系统启用后累计的阅读秒数
  String _clickDay = '';
  int _clickToday = 0;
  String _patDay = '';
  int _patToday = 0;
  String _giftDay = '';
  int _interactions = 0; // 累计点击互动
  int _feeds = 0; // 累计投喂
  int _totalFoodEarned = 0;
  int _unseenGains = 0; // 桌宠还没"告诉"主人的新点心数
  int _lastFeedAt = 0; // 最近一次投喂时间（毫秒时间戳；运行时状态，不持久化）

  /// 桌宠位置（0~1 屏幕比例）。
  double petX = 0.86;
  double petY = 0.62;

  /// 是否正在阅读器里（运行时状态，不持久化）。
  bool _readerActive = false;

  /// 阅读时是否显示桌宠（用户可在阅读设置 / 软件设置里开启）。
  bool showPetInReader = false;

  // ---- 只读视图 ----
  int get affinity => _affinity;
  int get interactions => _interactions;
  int get feeds => _feeds;
  int get totalFoodEarned => _totalFoodEarned;
  int get unseenGains => _unseenGains;
  bool get readerActive => _readerActive;
  Map<String, int> get inventory => Map.unmodifiable(_inventory);

  /// 最近一次投喂时间（毫秒时间戳；0 = 从未投喂）。
  int get lastFeedAt => _lastFeedAt;

  /// 桌宠系统启用以来累计的阅读秒数（用于兑换点心）。
  int get readSeconds => _readSeconds;

  int foodCount(String id) => _inventory[id] ?? 0;

  /// 当前等级（1 起）。
  int get level {
    var lv = 1;
    for (var i = 1; i < kAffinityLevels.length; i++) {
      if (_affinity >= kAffinityLevels[i]) {
        lv = i + 1;
      } else {
        break;
      }
    }
    return lv;
  }

  String get levelName =>
      kAffinityLevelNames[(level - 1).clamp(0, kAffinityLevelNames.length - 1)];

  /// 升到下一级需要的亲密度（满级时返回当前值）。
  int get nextLevelAt =>
      level >= kAffinityLevels.length ? _affinity : kAffinityLevels[level];

  /// 当前等级内的进度 0~1。
  double get levelProgress {
    final lv = level;
    if (lv >= kAffinityLevels.length) return 1;
    final cur = kAffinityLevels[lv - 1];
    final next = kAffinityLevels[lv];
    return ((_affinity - cur) / (next - cur)).clamp(0.0, 1.0);
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---------- 持久化 ----------

  Future<void> load() async {
    final dirs = _dirsOverride ?? await NativeBridge.appDirs();
    _file = File('${dirs.files}/pet.json');
    try {
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString());
        if (data is Map) {
          _affinity = (data['affinity'] as num?)?.toInt() ?? 0;
          _readSeconds = (data['readSeconds'] as num?)?.toInt() ?? 0;
          _clickDay = data['clickDay'] as String? ?? '';
          _clickToday = (data['clickToday'] as num?)?.toInt() ?? 0;
          _patDay = data['patDay'] as String? ?? '';
          _patToday = (data['patToday'] as num?)?.toInt() ?? 0;
          _giftDay = data['giftDay'] as String? ?? '';
          _interactions = (data['interactions'] as num?)?.toInt() ?? 0;
          _feeds = (data['feeds'] as num?)?.toInt() ?? 0;
          _totalFoodEarned = (data['totalFoodEarned'] as num?)?.toInt() ?? 0;
          _unseenGains = (data['unseenGains'] as num?)?.toInt() ?? 0;
          petX = ((data['petX'] as num?)?.toDouble() ?? 0.86).clamp(0.0, 1.0);
          petY = ((data['petY'] as num?)?.toDouble() ?? 0.62).clamp(0.0, 1.0);
          showPetInReader = data['showPetInReader'] as bool? ?? false;
          final inv = data['inventory'];
          if (inv is Map) {
            inv.forEach((k, v) {
              if (v is num) _inventory[k.toString()] = v.toInt();
            });
          }
          final rew = data['rewarded'];
          if (rew is Map) {
            rew.forEach((k, v) {
              if (v is num) _rewarded[k.toString()] = v.toInt();
            });
          }
        }
      }
    } catch (_) {
      // 读取失败时从零开始
    }
    notifyListeners();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save());
    });
  }

  /// 仅供测试：立即落盘（跳过防抖，消除时序脆弱）。
  @visibleForTesting
  Future<void> debugFlush() => _save();

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'affinity': _affinity,
          'inventory': _inventory,
          'rewarded': _rewarded,
          'readSeconds': _readSeconds,
          'clickDay': _clickDay,
          'clickToday': _clickToday,
          'patDay': _patDay,
          'patToday': _patToday,
          'giftDay': _giftDay,
          'interactions': _interactions,
          'feeds': _feeds,
          'totalFoodEarned': _totalFoodEarned,
          'unseenGains': _unseenGains,
          'petX': petX,
          'petY': petY,
          'showPetInReader': showPetInReader,
        }),
      );
    } catch (_) {
      // 忽略保存失败
    }
  }

  // ---------- 互动 / 投喂 ----------

  /// 点击互动：+1 亲密度（每日上限 [kPetDailyClickCap]）。
  PetActionResult interact({DateTime? now}) {
    final day = _dateKey(now ?? DateTime.now());
    if (_clickDay != day) {
      _clickDay = day;
      _clickToday = 0;
    }
    if (_clickToday >= kPetDailyClickCap) {
      return PetActionResult(level: level, reason: 'daily_cap');
    }
    _clickToday++;
    _interactions++;
    final leveled = _addAffinity(kPetClickPoints);
    return PetActionResult(
      points: kPetClickPoints,
      leveledUp: leveled,
      level: level,
    );
  }

  /// 摸头（双击）：+2 亲密度，每日独立上限 [kPetDailyPatCap]。
  PetActionResult pat({DateTime? now}) {
    final day = _dateKey(now ?? DateTime.now());
    if (_patDay != day) {
      _patDay = day;
      _patToday = 0;
    }
    if (_patToday >= kPetDailyPatCap) {
      return PetActionResult(level: level, reason: 'pat_cap');
    }
    _patToday++;
    _interactions++;
    final leveled = _addAffinity(kPetPatPoints);
    return PetActionResult(
      points: kPetPatPoints,
      leveledUp: leveled,
      level: level,
    );
  }

  /// 投喂一种食物（消耗 1 个）。
  PetActionResult feed(String foodId) {
    FoodDef? def;
    for (final f in kPetFoods) {
      if (f.id == foodId) {
        def = f;
        break;
      }
    }
    if (def == null || (_inventory[foodId] ?? 0) <= 0) {
      return PetActionResult(level: level, reason: 'no_food');
    }
    _inventory[foodId] = _inventory[foodId]! - 1;
    _feeds++;
    _lastFeedAt = DateTime.now().millisecondsSinceEpoch;
    final leveled = _addAffinity(def.affinity);
    _saveSoon();
    return PetActionResult(
      points: def.affinity,
      leveledUp: leveled,
      level: level,
    );
  }

  /// 增加亲密度；返回是否升级。
  bool _addAffinity(int points) {
    if (points <= 0) return false;
    final before = level;
    _affinity += points;
    _saveSoon();
    notifyListeners();
    return level > before;
  }

  // ---------- 阅读奖励 ----------

  /// 打开阅读器时调用：每天首次阅读送 1 个团子。
  void onReadingSessionStart({DateTime? now}) {
    final day = _dateKey(now ?? DateTime.now());
    if (_giftDay == day) return;
    _giftDay = day;
    _give('dango', 1);
  }

  /// 阅读计时回调（传**本次新增**的阅读秒数；内部累计并按时长里程碑发点心，
  /// 顺带获得对应数量的食物）。
  void onReadingTick(int deltaSeconds) {
    if (deltaSeconds <= 0) return;
    _readSeconds += deltaSeconds;
    var gained = 0;
    for (final f in kPetFoods) {
      if (f.perSeconds <= 0) continue;
      final earned = _readSeconds ~/ f.perSeconds;
      final given = _rewarded[f.id] ?? 0;
      if (earned > given) {
        final add = earned - given;
        _inventory[f.id] = (_inventory[f.id] ?? 0) + add;
        _rewarded[f.id] = earned;
        gained += add;
      }
    }
    if (gained > 0) {
      _totalFoodEarned += gained;
      _unseenGains += gained;
      notifyListeners();
    }
    _saveSoon();
  }

  void _give(String foodId, int count) {
    _inventory[foodId] = (_inventory[foodId] ?? 0) + count;
    _totalFoodEarned += count;
    _unseenGains += count;
    _saveSoon();
    notifyListeners();
  }

  /// 取走"未告知"的新点心数（桌宠播报后调用）。
  int takeUnseenGains() {
    if (_unseenGains <= 0) return 0;
    final n = _unseenGains;
    _unseenGains = 0;
    _saveSoon();
    return n;
  }

  // ---------- 桌宠状态 ----------

  void setReaderActive(bool value) {
    if (_readerActive == value) return;
    _readerActive = value;
    notifyListeners();
  }

  /// 设置「阅读时是否显示桌宠」。
  void setShowPetInReader(bool value) {
    if (showPetInReader == value) return;
    showPetInReader = value;
    _saveSoon();
    notifyListeners();
  }

  /// 拖动结束提交位置（0~1 屏幕比例）。
  void setPosition(double x, double y) {
    petX = x.clamp(0.0, 1.0).toDouble();
    petY = y.clamp(0.0, 1.0).toDouble();
    _saveSoon();
  }

  /// 把桌宠放回右下角默认位置。
  void resetPosition() {
    petX = 0.86;
    petY = 0.62;
    _saveSoon();
    notifyListeners();
  }

  /// 仅供测试：直接加亲密度。
  @visibleForTesting
  void debugAddAffinity(int points) {
    _affinity += points;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
