import 'dart:math' as math;

/// 一次「人名出现」的位置：章节下标 + 章内字符偏移。
class XrayMention {
  const XrayMention(this.chapter, this.offset, this.length);

  /// 章节下标（0 起）。
  final int chapter;

  /// 章内字符偏移。
  final int offset;

  /// 名字长度（用于判断较短候选是否被更长的名字覆盖）。
  final int length;

  int get end => offset + length;
}

/// 识别出的一个人名及其出现位置。
class XrayEntity {
  XrayEntity(
    this.name,
    this.mentions, {
    required this.ownCount,
    this.aliases = const <String>[],
  });

  /// 人名（原文写法，2~4 个汉字）。
  final String name;

  /// 归并进来的别名（「西蒙先生」「老马丁」这类称呼）。
  final List<String> aliases;

  /// 正文高亮用的全部写法（本名 + 别名，长名在前）。
  List<String> get allNames => <String>[name, ...aliases];

  /// 所有出现位置，按正文顺序排列。
  final List<XrayMention> mentions;

  /// 扣掉「被更长的名字包含」之后的独立出现次数（用于排序）。
  final int ownCount;

  int get count => mentions.length;

  int get firstChapter => mentions.isEmpty ? 0 : mentions.first.chapter;

  int get firstOffset => mentions.isEmpty ? 0 : mentions.first.offset;

  /// 出现在多少个不同的章节里。
  int get chapterSpread => mentions.map((m) => m.chapter).toSet().length;
}

/// 一本书的人名索引：实体列表 + 用于正文高亮的正则。
class XrayIndex {
  const XrayIndex(this.entities, this.pattern);

  final List<XrayEntity> entities;

  /// 将所有实体拼成的匹配正则（按长度降序，长名优先），无实体时为 null。
  final RegExp? pattern;

  bool get isEmpty => entities.isEmpty;

  /// 供 UI 展示：按独立出现次数降序。
  List<XrayEntity> get ranked =>
      entities.toList()..sort((a, b) => b.ownCount.compareTo(a.ownCount));
}

/// 按关键字过滤人物：本名或任一别名包含关键字就算命中（空关键字返回全部）。
List<XrayEntity> filterXrayEntities(List<XrayEntity> entities, String keyword) {
  final k = keyword.trim();
  if (k.isEmpty) return entities;
  return entities
      .where((e) => e.name.contains(k) || e.aliases.any((a) => a.contains(k)))
      .toList();
}

/// 人物面板的排序方式。
enum XraySortOrder {
  /// 按独立出现次数降序（默认）。
  count,

  /// 按首次出场先后，读长篇小说时更贴合时间线。
  firstAppear,
}

int _byPosition(XrayEntity a, XrayEntity b) {
  if (a.firstChapter != b.firstChapter) {
    return a.firstChapter.compareTo(b.firstChapter);
  }
  return a.firstOffset.compareTo(b.firstOffset);
}

/// 按 [_order] 整理人物列表（和 filterXrayEntities 串起来用）。
List<XrayEntity> rankXrayEntities(
  List<XrayEntity> entities,
  XraySortOrder order,
) {
  final list = entities.toList();
  switch (order) {
    case XraySortOrder.count:
      list.sort((a, b) {
        final byCount = b.ownCount.compareTo(a.ownCount);
        return byCount != 0 ? byCount : _byPosition(a, b);
      });
    case XraySortOrder.firstAppear:
      list.sort(_byPosition);
  }
  return list;
}

/// 一组人物里，跟某个人「常在同一章出现」的同伴。
class XrayCompanion {
  const XrayCompanion(this.entity, this.sharedChapters);

  /// 同伴本尊。
  final XrayEntity entity;

  /// 两人共同出现的章节数。
  final int sharedChapters;
}

/// 找到跟 [target] 常同场的人：默认只保留共同出场 >= 2 章、且重合度不太低的。
///
/// 只按「同一章出现过」算，不做段落级共现：章节粒度足够做人物关系提示，
/// 又不会被单人独白章节的噪声带偏。
List<XrayCompanion> companionsOf(
  XrayEntity target,
  List<XrayEntity> all, {
  int limit = 4,
  int minShared = 2,
}) {
  final mine = <int>{for (final m in target.mentions) m.chapter};
  if (mine.isEmpty) return const <XrayCompanion>[];
  final result = <XrayCompanion>[];
  for (final e in all) {
    if (e.name == target.name) continue;
    final theirs = <int>{for (final m in e.mentions) m.chapter};
    if (theirs.isEmpty) continue;
    final shared = theirs.where(mine.contains).length;
    if (shared < minShared) continue;
    // 两人都各自出场很多章、但几乎不重叠时，不算同场（避免误报）。
    if (shared * 2 < theirs.length && shared * 2 < mine.length) continue;
    result.add(XrayCompanion(e, shared));
  }
  result.sort((a, b) {
    final byShared = b.sharedChapters.compareTo(a.sharedChapters);
    if (byShared != 0) return byShared;
    return b.entity.ownCount.compareTo(a.entity.ownCount);
  });
  return result.take(limit).toList();
}

/// 人物表文本（复制 / 导出用）：一行一个，字段用制表符分隔。
String formatXrayTable(List<XrayEntity> entities) {
  final lines = <String>['人物\t出现\t章节\t别名'];
  for (final e in entities) {
    lines.add(
      <String>[
        e.name,
        '${e.count}',
        '${e.chapterSpread}',
        e.aliases.join('、'),
      ].join('\t'),
    );
  }
  return lines.join('\n');
}

/// 说话动词：只在它们前面找人名，精度高、几乎不会误伤。
final RegExp _speechVerb = RegExp(
  r'(咕哝道|喃喃道|低声说|大声说|说道|问道|答道|喊道|笑道|叹道|嚷道|叫道|说|道|问|答|喊|叫|笑|叹|嚷|点头|摇头)',
);

/// 「西蒙：」「西蒙先生说：」这种台词排版：冒号 / 左引号前的人名。
final RegExp _quoteLead = RegExp(r'([\u4e00-\u9fa5]{1,4})(?=[：:「“『])');

/// 台词提示语里可以剥掉的动词尾字（「西蒙说道：」先去掉「说道」再看人名）。
const String _tailVerbs = '说道问答喊叫笑嚷';

/// 「对 / 向 / 跟 XX 说」：介词引出的人名。
final RegExp _preposition = RegExp(
  r'(?:对|向|跟|和|与|朝|冲)([\u4e00-\u9fa5]{1,4})(?=说|道|笑|点头|摇头|喊|叫|问)',
);

/// 高频虚词 / 通名：经常出现在「说」前面，但绝不是人名。
const Set<String> _stopCandidates = {
  '我们',
  '你们',
  '他们',
  '她们',
  '它们',
  '大家',
  '众人',
  '旁人',
  '两人',
  '三人',
  '有人',
  '没人',
  '别人',
  '对方',
  '自己',
  '老人',
  '男人',
  '女人',
  '孩子',
  '小孩',
  '朋友',
  '先生',
  '小姐',
  '太太',
  '夫人',
  '老师',
  '医生',
  '母亲',
  '父亲',
  '妈妈',
  '爸爸',
  '哥哥',
  '姐姐',
  '弟弟',
  '妹妹',
  '儿子',
  '女儿',
  '老婆',
  '丈夫',
  '妻子',
  '一个',
  '这个',
  '那个',
  '哪个',
  '什么',
  '怎么',
  '这样',
  '那样',
  '如此',
  '然后',
  '于是',
  '接着',
  '最后',
  '突然',
  '忽然',
  '终于',
  '已经',
  '一直',
  '还是',
  '只是',
  '但是',
  '可是',
  '所以',
  '因为',
  '如果',
  '虽然',
  '就是',
  '不是',
  '没有',
  '可以',
  '可能',
  '应该',
  '必须',
  '需要',
  '觉得',
  '认为',
  '知道',
  '看到',
  '听见',
  '想着',
  '说道',
  '问道',
  '答道',
  '笑道',
  '喊道',
  '叫道',
  '叹道',
  '轻声',
  '低声',
  '大声',
  '小声',
  '声音',
  '心里',
  '心中',
  '脸上',
  '眼里',
  '手中',
  '点头',
  '摇头',
  '回头',
  '转身',
  '站起',
  '坐下',
  '走过',
  '来到',
  '回去',
  '出来',
  '进去',
  '起来',
  '下去',
  '上来',
  '开口',
  '继续',
  '同时',
  '随后',
  '不久',
  '当时',
  '此刻',
  '此时',
  '这时',
  '一面',
  '一边',
  '一旁',
  '那些',
  '这些',
  '诸位',
  '各位',
  '众位',
  '某些',
  '谁',
  '是他',
  '是她',
  '回答',
  '说着',
  '一听',
  '想到',
  '看见',
  '望着',
  '看着',
  '盯着',
  '笑了',
  '哭着',
  '高声',
  '柔声',
};

/// 候选名不能以这些词开头（「对他」「于是」「但是」的前缀）。
const Set<String> _badHeads = {
  '他',
  '她',
  '它',
  '我',
  '你',
  '咱',
  '俺',
  '谁',
  '这',
  '那',
  '哪',
  '什',
  '怎',
  '为',
  '因',
  '但',
  '可',
  '所',
  '如',
  '虽',
  '已',
  '正',
  '刚',
  '曾',
  '将',
  '会',
  '能',
  '要',
  '想',
  '说',
  '问',
  '答',
  '看',
  '听',
  '见',
  '走',
  '来',
  '去',
  '站',
  '坐',
  '转',
  '回',
  '心',
  '眼',
  '脸',
  '手',
  '声',
  '于',
  '是',
  '的',
  '了',
  '着',
  '又',
  '也',
  '都',
  '便',
  '就',
  '才',
  '还',
  '只',
  '不',
  '没',
  '很',
  '太',
  '更',
  '最',
  '再',
  '先',
  '却',
  '并',
  '且',
  '或',
  '而',
  '则',
  '把',
  '被',
  '让',
  '给',
  '对',
  '向',
  '跟',
  '和',
  '与',
  '朝',
  '冲',
  '在',
  '从',
  '到',
  '往',
  '过',
};

/// 翻译小说里常见的姓名尾字：命中时提高候选权重。
const Set<String> _foreignTailChars = {
  '尔',
  '特',
  '娜',
  '丝',
  '斯',
  '夫',
  '达',
  '克',
  '恩',
  '莉',
  '亚',
  '娃',
  '卡',
  '罗',
  '拉',
  '德',
  '格',
  '姆',
  '曼',
  '莎',
  '塔',
  '洛',
  '美',
  '蒙',
  '妮',
  '蒂',
  '瑟',
  '雷',
  '加',
  '林',
  '凡',
  '桑',
  '托',
  '伦',
  '内',
  '奇',
  '森',
  '丹',
  '琳',
  '伯',
  '逊',
  '顿',
  '基',
  '文',
};

bool _isCjk(int code) => code >= 0x4E00 && code <= 0x9FFF;

/// 候选是否像一个名字：2~4 个汉字、不是虚词、首字不是代词/虚词。
bool _plausible(String s) {
  if (s.length < 2 || s.length > 4) return false;
  for (final code in s.codeUnits) {
    if (!_isCjk(code)) return false;
  }
  if (_stopCandidates.contains(s)) return false;
  if (_badHeads.contains(s[0])) return false;
  if (s.split('').toSet().length == 1) return false;
  return true;
}

/// 从若干章正文里提取人名（纯函数，便于单测与 `compute()` 调用）。
///
/// 思路：
/// 1. 只在「说话动词 / 台词冒号」前取候选（`XX 说`、`XX：`），精度天然很高；
/// 2. 每次取动词前 2~4 个字的**所有后缀**当候选，靠全书出现频次来收敛；
/// 3. 由长到短收编；出现位置几乎都被更长名字覆盖的短候选（如「洛美」之于
///    「萨洛美」）丢弃，长候选（「萨洛美」）保留。
XrayIndex buildXrayIndex(List<String> chapterTexts, {int maxEntities = 60}) {
  // ---- 1. 收集候选 ----
  final candidateHits = <String, int>{};

  void offer(String run) {
    if (run.isEmpty) return;
    final maxLen = math.min(run.length, 4);
    for (var len = 2; len <= maxLen; len++) {
      final cand = run.substring(run.length - len);
      if (!_plausible(cand)) continue;
      candidateHits[cand] = (candidateHits[cand] ?? 0) + 1;
    }
  }

  for (final text in chapterTexts) {
    for (final m in _speechVerb.allMatches(text)) {
      final start = m.start;
      if (start <= 0) continue;
      var from = start;
      while (from > 0 &&
          start - from < 6 &&
          _isCjk(text.codeUnitAt(from - 1))) {
        from--;
      }
      offer(text.substring(from, start));
    }
    for (final m in _preposition.allMatches(text)) {
      offer(m.group(1) ?? '');
    }
    // 「人名：台词」这种译制小说常见排版，不写「说」也能定位人物。
    for (final m in _quoteLead.allMatches(text)) {
      var run = m.group(1) ?? '';
      while (run.length > 2 && _tailVerbs.contains(run[run.length - 1])) {
        run = run.substring(0, run.length - 1);
      }
      offer(run);
    }
  }

  if (candidateHits.isEmpty) return const XrayIndex(<XrayEntity>[], null);

  // ---- 2. 全书统计每个候选的真实出现位置 ----
  final namesByLength = candidateHits.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final scan = RegExp(namesByLength.map(RegExp.escape).join('|'));
  final mentions = <String, List<XrayMention>>{
    for (final n in candidateHits.keys) n: <XrayMention>[],
  };

  for (var i = 0; i < chapterTexts.length; i++) {
    for (final m in scan.allMatches(chapterTexts[i])) {
      final name = m.group(0)!;
      ((mentions[name] ??= <XrayMention>[])).add(
        XrayMention(i, m.start, name.length),
      );
    }
  }

  // ---- 2.5 别名折叠：把「西蒙先生」「老马丁」并到本名「西蒙」「马丁」上 ----
  // 同一个人的不同称呼分散出现时，单看某一种写法次数往往不够阈值；先合并再判定，
  // 既提高召回，又让面板里显示成一个条目（附别名）。
  final aliasByCore = <String, List<String>>{};
  for (final name in candidateHits.keys.toList()) {
    final core = _coreOf(name);
    if (core == name || core.length < 2) continue;
    if (!candidateHits.containsKey(core)) continue;
    final aliasList = mentions[name];
    if (aliasList == null || aliasList.isEmpty) continue;
    final coreList = mentions[core] ??= <XrayMention>[];
    for (final m in aliasList) {
      // 同一起点只留更长的那个，避免「西蒙先生」和「西蒙」各算一次。
      final dup = coreList.any(
        (x) => x.chapter == m.chapter && x.offset == m.offset,
      );
      if (!dup) coreList.add(m);
    }
    coreList.sort(
      (a, b) => a.chapter != b.chapter
          ? a.chapter.compareTo(b.chapter)
          : a.offset.compareTo(b.offset),
    );
    mentions.remove(name);
    (aliasByCore[core] ??= <String>[]).add(name);
  }

  // ---- 3. 由长到短收编，短名被长名覆盖时丢弃 ----
  final accepted = <XrayEntity>[];
  final chapterCount = chapterTexts.length;

  for (final name in namesByLength) {
    final list = mentions[name];
    if (list == null || list.isEmpty) continue;

    // 独立出现（不被已收编的更长名字覆盖）的次数。
    var own = 0;
    var ownChapters = <int>{};
    for (final m in list) {
      final covered = accepted.any(
        (a) => a.mentions.any(
          (x) =>
              x.chapter == m.chapter && x.offset <= m.offset && x.end >= m.end,
        ),
      );
      if (!covered) {
        own++;
        ownChapters.add(m.chapter);
      }
    }

    final aliases = aliasByCore[name] ?? const <String>[];
    final tail = name[name.length - 1];
    final looksForeign = _foreignTailChars.contains(tail);

    // 阈值：至少 2~3 次独立出现；长篇还要求跨章（或足够高频）。
    final minOcc = chapterCount >= 4 ? 3 : 2;
    if (own < minOcc) continue;
    if (chapterCount >= 4 && ownChapters.length < 2 && own < 6) continue;
    // 两次说话动词 + 一次偶遇的 2 字词，容易是误伤（带称呼的别名算作加分项）。
    if (!looksForeign && own < 3 && aliases.isEmpty) continue;
    final evidence =
        candidateHits[name]! +
        aliases.fold<int>(0, (sum, a) => sum + (candidateHits[a] ?? 0));
    if (evidence < 2 && own < 5) continue;

    accepted.add(XrayEntity(name, list, ownCount: own, aliases: aliases));
  }

  accepted.sort((a, b) => b.ownCount.compareTo(a.ownCount));
  final finalList = accepted.take(maxEntities).toList();

  final patternNames = <String>[for (final e in finalList) ...e.allNames]
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = patternNames.isEmpty
      ? null
      : RegExp(patternNames.map(RegExp.escape).join('|'));

  return XrayIndex(finalList, pattern);
}

/// 称呼后缀：出现时把它从名字上剥掉，用来判断「西蒙先生」和「西蒙」是同一个人。
const Set<String> _honorifics = {
  '先生',
  '女士',
  '小姐',
  '太太',
  '夫人',
  '老师',
  '教授',
  '医生',
  '博士',
  '大人',
  '阁下',
  '伯爵',
  '公爵',
  '子爵',
  '男爵',
  '王子',
  '公主',
  '船长',
  '上校',
  '少校',
  '中尉',
  '上尉',
  '队长',
};

/// 名字的「核心部分」：去掉称呼后缀与「老 / 小 / 阿」前缀。
String _coreOf(String name) {
  var core = name;
  for (final h in _honorifics) {
    if (core.length >= h.length + 2 && core.endsWith(h)) {
      core = core.substring(0, core.length - h.length);
      break;
    }
  }
  if (core.length > 2) {
    final head = core[0];
    if (head == '老' || head == '小' || head == '阿') {
      core = core.substring(1);
    }
  }
  return core;
}
