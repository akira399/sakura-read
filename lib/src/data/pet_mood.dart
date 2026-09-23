// 桌宠「心情 / 互动」状态机：生气判定、彩蛋触发、随机台词。
//
// 设计目标（可单测，与 UI 解耦）：
//  - 拖动、睡觉被叫醒（必触发）、频繁点击 → 生气；
//  - 生气次数 ≥2 时高概率进入「彩蛋」（全黑锁定界面）；
//  - 各种互动都有随机台词池。
import 'dart:math';

/// 互动类型（用于挑选台词与判定生气）。
enum PetAction {
  /// 点击（换表情 / 蹦跳）
  tap,

  /// 双击摸头
  pat,

  /// 拖动后被放下
  drag,

  /// 睡觉时被叫醒
  wake,

  /// 投喂
  feed,

  /// 长时间没互动后自己打瞌睡
  doze,
}

/// 一次互动的判定结果。
class PetReaction {
  const PetReaction({
    required this.action,
    this.angry = false,
    this.egg = false,
    this.line,
  });

  final PetAction action;

  /// 本次是否触发生气。
  final bool angry;

  /// 本次是否触发彩蛋（全黑锁定）。
  final bool egg;

  /// 随机台词（null = 由调用方决定）。
  final String? line;
}

/// 桌宠互动状态机。
class PetMood {
  PetMood({Random? random}) : _rnd = random ?? Random();

  final Random _rnd;

  /// 生气累计次数（驱动彩蛋概率）。
  int angryCount = 0;

  /// 最近点击时间戳（判定"频繁点击"）。
  final List<DateTime> _recentTaps = [];

  /// 频繁点击判定：[window] 内点击超过 [threshold] 次。
  static const int spamThreshold = 8;
  static const Duration spamWindow = Duration(seconds: 5);

  /// 锁屏彩蛋门槛：第 [eggFromCount] 次生气起才有概率触发，概率随次数递增。
  static const int eggFromCount = 4;
  static const double eggChanceAt4 = 0.35;
  static const double eggChanceAt5 = 0.55;
  static const double eggChanceMax = 0.90;

  /// 单次拖动即生气的概率（很低：只有"频繁拖动"才明显）。
  static const double dragAngryChance = 0.06;

  /// 频繁拖动判定：短时间内拖动次数达到 [dragSpamThreshold] 时，
  /// 生气概率提升到 [dragSpamChance]。
  static const int dragSpamThreshold = 5;
  static const Duration dragSpamWindow = Duration(seconds: 12);
  static const double dragSpamChance = 0.45;

  /// 拖动结束时刻（汇总「频繁拖动」判定）。
  final List<DateTime> _recentDrags = [];

  /// 记录一次点击并判断是否「频繁点击」。
  bool registerTap(DateTime now) {
    _recentTaps.add(now);
    _recentTaps.removeWhere((t) => now.difference(t) > spamWindow);
    return _recentTaps.length >= spamThreshold;
  }

  /// 当前是否处于「频繁拖动」状态。
  bool get isDraggingALot {
    final now = DateTime.now();
    _recentDrags.removeWhere((t) => now.difference(t) > dragSpamWindow);
    return _recentDrags.length >= dragSpamThreshold;
  }

  /// 按当前生气次数计算彩蛋概率（未达门槛 = 0）。
  double get eggChance {
    if (angryCount < eggFromCount) return 0;
    if (angryCount == eggFromCount) return eggChanceAt4;
    if (angryCount == eggFromCount + 1) return eggChanceAt5;
    // 之后线性逼近上限
    final extra = angryCount - (eggFromCount + 1);
    return (eggChanceAt5 + extra * 0.15).clamp(0.0, eggChanceMax);
  }

  /// 触发一次生气：返回是否进入彩蛋（门槛 + 递增概率）。
  bool escalate() {
    angryCount++;
    return _rnd.nextDouble() < eggChance;
  }

  /// 彩蛋结束后重置计数（避免连续锁定）。
  void reset() {
    angryCount = 0;
    _recentTaps.clear();
  }

  /// 拖动互动：低频生气（频繁拖动才明显）。
  PetReaction onDrag() {
    final now = DateTime.now();
    _recentDrags.add(now);
    _recentDrags.removeWhere((t) => now.difference(t) > dragSpamWindow);
    final spammy = _recentDrags.length >= dragSpamThreshold;
    final chance = spammy ? dragSpamChance : dragAngryChance;
    final angry = _rnd.nextDouble() < chance;
    if (!angry) {
      return PetReaction(action: PetAction.drag, line: _pick(petDragLines));
    }
    return PetReaction(
      action: PetAction.drag,
      angry: true,
      egg: escalate(),
      line: _pick(petAngryDragLines),
    );
  }

  /// 睡觉被叫醒：必定生气。
  PetReaction onWake() => PetReaction(
    action: PetAction.wake,
    angry: true,
    egg: escalate(),
    line: _pick(petAngryWakeLines),
  );

  /// 频繁点击：生气。
  PetReaction onSpam() => PetReaction(
    action: PetAction.tap,
    angry: true,
    egg: escalate(),
    line: _pick(petAngrySpamLines),
  );

  String _pick(List<String> pool) => pool[_rnd.nextInt(pool.length)];
}

// ==================== 台词池 ====================

/// 拖动时的随机台词（正常情况）。
const petDragLines = [
  '呜哇——！别晃了别晃了',
  '放、放我下来啦……',
  '头晕啦，人家会掉下去的',
  '这是要把我搬到哪里去呀',
  '我、我可不是行李哦',
  '慢一点慢一点，裙摆要乱了',
  '拎着我的时候要温柔一点嘛',
  '你要带我去看什么好玩的吗？',
  '呼……终于能换个地方待着了',
];

/// 拖动时生气的台词。
const petAngryDragLines = [
  '喂！很过分诶，都说了别晃了',
  '再这样我真的要生气了哦',
  '你、你把我当成什么了！',
  '哼！不跟你玩了',
  '放、开、我！',
];

/// 被吵醒时生气的台词。
const petAngryWakeLines = [
  '谁啊……！好不容易睡着的',
  '你、你把我的美梦吵醒了！',
  '呜呜……人家正睡得香呢',
  '知不知道吵醒别人是很失礼的事！',
  '讨厌啦！我要回去睡了',
];

/// 频繁点击时生气的台词。
const petAngrySpamLines = [
  '够了！别一直戳我',
  '手指头不累吗……',
  '你再点一下试试看？',
  '哼，我可不是按钮',
  '戳戳戳，戳够了没有！',
];

/// 彩蛋（全黑锁定）时的阴沉台词。
const petEggLine = '你以为我是好惹的？';

/// 彩蛋底部血字。
const petEggFooter = '小樱禁止你使用该软件';

/// 新手指引：用户不按引导操作时的劝告（语气逐次变差，第 6 次触发锁屏）。
const petGuideNags = [
  '……请点一下这里好吗？',
  '那个，是这里哦。',
  '喂，你到底有没有在看啊。',
  '我说，点、这、里。听不懂吗？',
  '呵……最后一次机会了哦。',
];

/// 点击时随机蹦跳的台词（可爱向）。
const petHopLines = [
  '哎哟！',
  '哇！跳起来了',
  '嘿咻～',
  '呀！吓我一跳',
  '蹦蹦跳跳～',
  '啊——又飞起来了',
  '轻一点啦，人家会摔的',
  '噗，被弹起来了',
];

// ==================== 乱跑（奔跑捣乱） ====================

/// 主界面：每隔这么久检查一次是否要乱跑。
const Duration petRoamCheckInterval = Duration(seconds: 25);

/// 主界面单次检查触发乱跑的概率（较低）。
const double petRoamChanceHome = 0.18;

/// 阅读界面：单次检查触发乱跑的概率（较高，"故意捣乱"）。
const double petRoamChanceReader = 0.55;

/// 阅读界面检查间隔更短（更频繁地跑来跑去）。
const Duration petRoamCheckIntervalReader = Duration(seconds: 14);

/// 一次乱跑持续多久（连续跑动的秒数区间）。
const int petRoamDurationMinSec = 3;
const int petRoamDurationMaxSec = 7;

/// 乱跑时的台词。
const petRoamLines = [
  '跑呀跑呀～',
  '追不上我～',
  '嘿嘿，抓不到我吧',
  '哇——！冲啊',
  '这里跑跑，那里跳跳',
  '看我看我，我在飞～',
  '哼着小曲散步中～',
  '一圈又一圈～',
];

/// 阅读时捣乱的台词（更调皮）。
const petRoamReaderLines = [
  '你专心看书，我专心捣乱～',
  '看书有什么意思，陪我玩嘛',
  '我在你书上跑一圈～',
  '喂——！看我这边啦',
  '嘿嘿，挡到你了没有？',
  '呼——好无聊，我跑两圈',
];
