/// Sakura Read 2.5 书房视觉风格预设与书架层板样式。
enum VisualStylePreset {
  /// Style D（默认推荐）：樱花书房 · 混搭旗舰
  sakuraAtelier(
    code: 'D',
    label: '樱花书房 · 混搭旗舰',
    shortLabel: '混搭旗舰',
    badge: 'D · ★推荐',
    subtitle: '和纸书香 + 液态玻璃底栏 + 丝绸书签与樱瓣微风',
  ),

  /// Style A：液态流光书阁
  liquidGlass(
    code: 'A',
    label: '液态流光书阁',
    shortLabel: '液态流光',
    badge: 'A · 流光',
    subtitle: '封面取色极光 + 悬浮折射晶石 + 空灵通透',
  ),

  /// Style B：京都和纸手账
  kyotoWashi(
    code: 'B',
    label: '京都和纸手账',
    shortLabel: '京都和纸',
    badge: 'B · 和纸',
    subtitle: '暖木书架层板 + 朱红藏书印 + 和纸胶带分组',
  ),

  /// Style C：蔚蓝轻漫斜切
  animePop(
    code: 'C',
    label: '蔚蓝轻漫斜切',
    shortLabel: '蔚蓝轻漫',
    badge: 'C · 轻漫',
    subtitle: '6° 斜切视觉头图 + 轻小说书腰 + 明快波普动感',
  );

  const VisualStylePreset({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.badge,
    required this.subtitle,
  });

  final String code;
  final String label;
  final String shortLabel;
  final String badge;
  final String subtitle;

  bool get isRecommended => this == VisualStylePreset.sakuraAtelier;
}

/// 从持久化字符串解析 [VisualStylePreset]（未知值安全回落到 [VisualStylePreset.sakuraAtelier]）。
VisualStylePreset visualStylePresetFrom(String? raw) => switch (raw) {
  'liquidGlass' => VisualStylePreset.liquidGlass,
  'kyotoWashi' => VisualStylePreset.kyotoWashi,
  'animePop' => VisualStylePreset.animePop,
  'sakuraAtelier' || _ => VisualStylePreset.sakuraAtelier,
};

/// 书架书籍陈列与层板样式。
enum ShelfPlankStyle {
  /// 透光磨砂层板（Style D 默认）
  frostedGlass(
    label: '透光磨砂层板',
    shortLabel: '透光磨砂',
    subtitle: '半透明樱色磨砂托板 + 3D 纸张侧边',
  ),

  /// 实体樱木层板（Style B）
  warmWood(label: '实体樱木层板', shortLabel: '实体樱木', subtitle: '温润樱桃木斜切层板 + 真实落影'),

  /// 轻小说书腰（Style C）
  obiBand(label: '轻小说书腰', shortLabel: '轻小说书腰', subtitle: '日系轻小说封面腰封 + 波普偏置阴影'),

  /// 极简留白（Style A）
  minimal(label: '极简留白', shortLabel: '极简留白', subtitle: '无层板悬浮流光画框');

  const ShelfPlankStyle({
    required this.label,
    required this.shortLabel,
    required this.subtitle,
  });

  final String label;
  final String shortLabel;
  final String subtitle;
}

/// 从持久化字符串解析 [ShelfPlankStyle]（未知值安全回落到 [ShelfPlankStyle.frostedGlass]）。
ShelfPlankStyle shelfPlankStyleFrom(String? raw) => switch (raw) {
  'warmWood' => ShelfPlankStyle.warmWood,
  'obiBand' => ShelfPlankStyle.obiBand,
  'minimal' => ShelfPlankStyle.minimal,
  'frostedGlass' || _ => ShelfPlankStyle.frostedGlass,
};
