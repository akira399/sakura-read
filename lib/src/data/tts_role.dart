import 'dart:math' as math;

/// 一段朗读文本的「角色」判定结果。
class TtsRoleLine {
  const TtsRoleLine({required this.speaker, required this.isDialogue});

  /// 说话人（空串 = 旁白 / 没能识别出是谁）。
  final String speaker;

  /// 是否是对白（引号或「人名：」开头）。
  final bool isDialogue;
}

/// 本地「分角色朗读」规划器。
///
/// 用户反馈：「番茄的那种自动分角色阅读功能支持吗？自己买 token 也可以的」。
/// 那类功能靠大模型做角色识别，这里给一个**完全离线、零成本**的近似方案：
///
/// - 对白 / 旁白用不同音高区分（旁白用用户设定的音高，对白略微抬高）；
/// - 同一角色在整个章节里音高稳定（按名字做稳定散列，不会忽高忽低）；
/// - 识别不出来是谁的也能标成「对白」，至少旁白和说话声能分开。
///
/// 局限（会写进说明）：真正的多音色需要系统引擎提供多个音色，
/// 这里只动音高，所以听起来更像「换了个调」，不是换了个人。
/// 朗读音色风格。
///
/// 内置离线语音（sherpa 超文）只有一个说话人，想要「男声 / 女声」只能靠音调
/// 近似；系统引擎能真换音色时优先用它自己的 voices 列表，这里作为兜底。

class TtsRolePlanner {
  const TtsRolePlanner._();

  /// 对白的音高偏移档位（相对用户设定音高）。
  static const List<double> _voiceSteps = [-0.12, -0.06, 0.0, 0.06, 0.12];

  /// 旁白音高偏移（略微压低一点，让对白更跳出来）。
  static const double _narratorStep = -0.03;

  /// 对白但没识别出说话人时的偏移。
  static const double _anonymousStep = 0.05;

  /// 引号：中日文直角引号 / 弯引号都算。
  static final RegExp _quoteRe = RegExp(r'[「『“"”]');

  /// 「人名：」「人名:」 这类说话人前缀。
  static final RegExp _speakerPrefixRe = RegExp(
    r'^[\s\u3000]*([\u4e00-\u9fa5]{1,4})[：:]',
  );

  /// 判定单段文本的角色。
  static TtsRoleLine classify(String text, List<String> names) {
    final line = text.trim();
    if (line.isEmpty) {
      return const TtsRoleLine(speaker: '', isDialogue: false);
    }
    // 先看「人名：」前缀，这是译制小说最常见的排版
    final prefix = _speakerPrefixRe.firstMatch(line);
    if (prefix != null) {
      final who = prefix.group(1) ?? '';
      if (who.isNotEmpty) {
        return TtsRoleLine(speaker: who, isDialogue: true);
      }
    }
    final isDialogue = _quoteRe.hasMatch(line);
    if (!isDialogue) {
      return const TtsRoleLine(speaker: '', isDialogue: false);
    }
    // 对白里找最早出现的已知人名当说话人
    var best = -1;
    var bestName = '';
    for (final name in names) {
      if (name.isEmpty) continue;
      final at = line.indexOf(name);
      if (at < 0) continue;
      if (best < 0 || at < best) {
        best = at;
        bestName = name;
      }
    }
    return TtsRoleLine(speaker: bestName, isDialogue: true);
  }

  /// 给整章的段落规划音高表（长度与 [paragraphs] 一致）。
  ///
  /// [base] 是用户在朗读设置里选的音高；结果会被夹在 0.5~2.0（系统引擎范围）。
  static List<double> planPitches(
    List<String> paragraphs, {
    List<String> names = const [],
    double base = 1.0,
  }) {
    final pitches = List<double>.filled(paragraphs.length, base);
    if (paragraphs.isEmpty) return pitches;
    for (var i = 0; i < paragraphs.length; i++) {
      final role = classify(paragraphs[i], names);
      var offset = _narratorStep;
      if (role.isDialogue) {
        offset = role.speaker.isEmpty
            ? _anonymousStep
            : _voiceSteps[_stableIndex(role.speaker, _voiceSteps.length)];
      }
      pitches[i] = _clampPitch(base + offset);
    }
    return pitches;
  }

  /// 同一角色名 → 固定档位（用字符码求和，简单且稳定）。
  static int _stableIndex(String name, int length) {
    var sum = 0;
    for (final unit in name.codeUnits) {
      sum += unit;
    }
    return sum % length;
  }

  static double _clampPitch(double v) => v.clamp(0.5, 2.0).toDouble();

  /// 该音高是否与用户设定有明显区别（UI 上用来提示「已启用分角色」）。
  static bool differsFromBase(List<double> pitches, double base) {
    for (final p in pitches) {
      if ((p - base).abs() > 0.01) return true;
    }
    return false;
  }

  /// 调试用：统计一段文本里识别出的角色数（按行找「人名：」前缀）。
  static int countSpeakers(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final names = <String>{};
    for (final line in trimmed.split('\n')) {
      final who = _speakerPrefixRe.firstMatch(line)?.group(1);
      if (who != null && who.isNotEmpty) names.add(who);
    }
    return math.min(names.length, 99);
  }
}
