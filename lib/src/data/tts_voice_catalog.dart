import 'dart:io';

/// 单个「说话人预设」：多说话人模型里的一个 sid。
class TtsVoicePreset {
  const TtsVoicePreset({
    required this.label,
    required this.sid,
    required this.hint,
  });

  /// 界面上显示的名字，例如「男声 · 沉稳」。
  final String label;

  /// 传给 sherpa `generate(sid: ...)` 的说话人编号。
  final int sid;

  /// 一句话说明，帮助用户挑。
  final String hint;
}

/// 一个可下载的语音包（离线 TTS 模型）。
///
/// 用户反馈「语音模型应该是选择下载的，不是打在包里」——所以除了随包的
/// 小体积基础音色，其余都做成「点了才下载、可单独删除」的语音包。
class TtsVoicePack {
  const TtsVoicePack({
    required this.id,
    required this.name,
    required this.tagline,
    required this.sizeMb,
    required this.license,
    required this.mirrors,
    required this.bundled,
    this.archiveName = '',
    this.presets = const <TtsVoicePreset>[],
    this.speakerCount = 1,
  });

  /// 稳定 id，同时是落盘目录名：`<files>/tts/<id>/`。
  final String id;

  /// 显示名，例如「小雅」。
  final String name;

  /// 一句话卖点，例如「女声 · 轻快」。
  final String tagline;

  /// 展示用的体积（MB）。
  final double sizeMb;

  final String license;

  /// 下载地址（按顺序重试）。
  final List<String> mirrors;

  /// 是否随 APK 内置（内置包不需要下载，镜像为空）。
  final bool bundled;

  /// 压缩包内层目录名（tar.bz2 里通常有一层同名目录）。
  final String archiveName;

  /// 多说话人模型的可选音色；单说话人模型为空。
  final List<TtsVoicePreset> presets;

  /// 说话人总数（1 = 单说话人）。
  final int speakerCount;

  bool get isMultiSpeaker => speakerCount > 1;

  /// 默认 sid（多说话人取第一个预设，否则 0）。
  int get defaultSid => presets.isEmpty ? 0 : presets.first.sid;
}

/// 内置基础音色（随 APK 提供，开箱即用，避免「装了没声音」）。
const TtsVoicePack builtinVoicePack = TtsVoicePack(
  id: 'chaowen',
  name: '超文',
  tagline: '女声 · 平稳耐听，随 APK 内置',
  sizeMb: 20,
  license: 'CC0',
  mirrors: <String>[],
  bundled: true,
  presets: <TtsVoicePreset>[TtsVoicePreset(label: '女声', sid: 0, hint: '默认音色')],
);

/// 可下载的语音包清单（都来自 sherpa-onnx 官方模型库，Apache-2.0 / CC 系授权）。
///
/// 体积按「压缩包 + 解压后」取整展示，实测下载速度在 1~3 MB/s。
const List<TtsVoicePack> downloadableVoicePacks = <TtsVoicePack>[
  TtsVoicePack(
    id: 'aishell3',
    name: '百变音色（174 人）',
    tagline: '男声 / 女声随意挑，一个包顶几十种',
    sizeMb: 32,
    license: 'Apache-2.0',
    archiveName: 'vits-icefall-zh-aishell3',
    mirrors: <String>[
      'https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-icefall-zh-aishell3.tar.bz2',
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-icefall-zh-aishell3.tar.bz2',
    ],
    bundled: false,
    speakerCount: 174,
    presets: <TtsVoicePreset>[
      TtsVoicePreset(label: '男声 · 低沉', sid: 74, hint: 'SSB0623，约 106Hz'),
      TtsVoicePreset(label: '男声 · 清亮', sid: 124, hint: 'SSB1136，约 121Hz'),
      TtsVoicePreset(label: '女声 · 温和', sid: 113, hint: 'SSB1055，约 200Hz'),
      TtsVoicePreset(label: '女声 · 明亮', sid: 131, hint: 'SSB1253，约 242Hz'),
    ],
  ),
  TtsVoicePack(
    id: 'xiaoya',
    name: '小雅',
    tagline: '女声 · 年轻轻快，体积只有 14 MB',
    sizeMb: 14,
    license: 'Apache-2.0',
    archiveName: 'vits-piper-zh_CN-xiao_ya-medium-int8',
    mirrors: <String>[
      'https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2',
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2',
    ],
    bundled: false,
    presets: <TtsVoicePreset>[
      TtsVoicePreset(label: '女声', sid: 0, hint: '单说话人'),
    ],
  ),
];

/// 全部语音包（内置的排第一）。
List<TtsVoicePack> get ttsVoiceCatalog => <TtsVoicePack>[
  builtinVoicePack,
  ...downloadableVoicePacks,
];

/// 按 id 找语音包；找不到返回 null。
TtsVoicePack? ttsVoicePackById(String id) {
  for (final pack in ttsVoiceCatalog) {
    if (pack.id == id) return pack;
  }
  return null;
}

/// 一个语音包解压后需要的最小文件集合（sherpa-onnx VITS 配置）。
class TtsVoiceFiles {
  const TtsVoiceFiles({
    required this.model,
    required this.lexicon,
    required this.tokens,
    required this.ruleFsts,
  });

  final String model;
  final String lexicon;
  final String tokens;

  /// 逗号分隔的 fst 列表；没有就为空串。
  final String ruleFsts;
}

/// 在解压后的目录里找出 sherpa 需要的文件。
///
/// 不同语音包的文件名不统一（`model.onnx`、`zh_CN-xxx.onnx`、`espeak-ng-data` 等），
/// 所以这里按后缀扫描，而不是写死文件名。
TtsVoiceFiles? resolveTtsVoiceFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return null;
  final entries = d
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList();
  String? onnx;
  for (final name in entries) {
    if (name.endsWith('.onnx')) {
      onnx = name;
      // 有 model.onnx 就优先用（多说话人模型常见命名）
      if (name == 'model.onnx') break;
    }
  }
  if (onnx == null) return null;
  final has = entries.contains;

  final lexicon = has('lexicon.txt') ? 'lexicon.txt' : '';
  final tokens = has('tokens.txt') ? 'tokens.txt' : '';
  if (tokens.isEmpty) return null;

  final fsts = <String>[
    for (final name in const <String>['number.fst', 'date.fst', 'phone.fst'])
      if (has(name)) name,
  ];

  return TtsVoiceFiles(
    model: onnx,
    lexicon: lexicon,
    tokens: tokens,
    ruleFsts: fsts.join(','),
  );
}
