import 'package:flutter/material.dart';

/// 2.0 精选低饱和主题色板（日语轻编辑美学）。
abstract final class SakuraAccents {
  static const Color sakura = Color(0xFFE86A92); // 樱绯
  static const Color wisteria = Color(0xFF7E6EE6); // 紫藤
  static const Color sky = Color(0xFF4A9BE8); // 晴空
  static const Color bamboo = Color(0xFF46A884); // 若竹
  static const Color apricot = Color(0xFFE58E49); // 暖杏

  static const List<Color> all = [sakura, wisteria, sky, bamboo, apricot];
  static const List<String> names = ['樱绯', '紫藤', '晴空', '若竹', '暖杏'];
}

/// Sakura Read 2.0 语义化色彩 Token。
@immutable
class SakuraColors extends ThemeExtension<SakuraColors> {
  const SakuraColors({
    required this.canvas,
    required this.card,
    required this.surfaceSubtle,
    required this.hairline,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.glassFill,
    required this.glassBorder,
    required this.accentSoft,
    required this.coverShadow,
  });

  final Color canvas;
  final Color card;
  final Color surfaceSubtle;
  final Color hairline;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color glassFill;
  final Color glassBorder;
  final Color accentSoft;
  final Color coverShadow;

  factory SakuraColors.light(Color accent) => SakuraColors(
    canvas: const Color(0xFFFBF8F6),
    card: const Color(0xFFFFFFFF),
    surfaceSubtle: const Color(0xFFF4EEF1),
    hairline: const Color(0xFFEAE1E6),
    inkPrimary: const Color(0xFF241B25),
    inkSecondary: const Color(0xFF7A6B78),
    glassFill: const Color(0xD6FBF8F6),
    glassBorder: const Color(0x14241B25),
    accentSoft: accent.withValues(alpha: 0.11),
    coverShadow: const Color(0x1F2B1928),
  );

  factory SakuraColors.dark(Color accent) => SakuraColors(
    canvas: const Color(0xFF121018),
    card: const Color(0xFF1C1825),
    surfaceSubtle: const Color(0xFF252030),
    hairline: const Color(0xFF2E273B),
    inkPrimary: const Color(0xFFF3EDF4),
    inkSecondary: const Color(0xFF9E90A6),
    glassFill: const Color(0xCC181421),
    glassBorder: const Color(0x18FFFFFF),
    accentSoft: accent.withValues(alpha: 0.18),
    coverShadow: const Color(0x66000000),
  );

  @override
  SakuraColors copyWith({
    Color? canvas,
    Color? card,
    Color? surfaceSubtle,
    Color? hairline,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? glassFill,
    Color? glassBorder,
    Color? accentSoft,
    Color? coverShadow,
  }) => SakuraColors(
    canvas: canvas ?? this.canvas,
    card: card ?? this.card,
    surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    hairline: hairline ?? this.hairline,
    inkPrimary: inkPrimary ?? this.inkPrimary,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    glassFill: glassFill ?? this.glassFill,
    glassBorder: glassBorder ?? this.glassBorder,
    accentSoft: accentSoft ?? this.accentSoft,
    coverShadow: coverShadow ?? this.coverShadow,
  );

  @override
  SakuraColors lerp(covariant ThemeExtension<SakuraColors>? other, double t) {
    if (other is! SakuraColors) return this;
    return SakuraColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      coverShadow: Color.lerp(coverShadow, other.coverShadow, t)!,
    );
  }
}

/// 便捷读取当前主题的 SakuraColors，孤立测试未注册 Extension 时安全回落默认色板。
extension SakuraColorsX on BuildContext {
  SakuraColors get sakura {
    final ext = Theme.of(this).extension<SakuraColors>();
    if (ext != null) return ext;
    final theme = Theme.of(this);
    final accent = theme.colorScheme.primary;
    return theme.brightness == Brightness.dark
        ? SakuraColors.dark(accent)
        : SakuraColors.light(accent);
  }
}
