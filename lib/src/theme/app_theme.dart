import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/sakura_tokens.dart';

/// 二次元风格主题：2.0 日式轻编辑美学（Editorial Anime Minimalism）。
class SakuraTheme {
  static const Color sakura = SakuraAccents.sakura;
  static const Color lavender = SakuraAccents.wisteria;

  static ThemeData build(Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark
        ? SakuraColors.dark(accent)
        : SakuraColors.light(accent);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: tokens.card,
        surfaceContainerLowest: tokens.canvas,
        surfaceContainerLow: tokens.surfaceSubtle,
        primary: accent,
        secondary: lavender,
        outlineVariant: tokens.hairline,
        onSurface: tokens.inkPrimary,
        onSurfaceVariant: tokens.inkSecondary,
      ),
      extensions: [tokens],
    );
    final titleColor = tokens.inkPrimary;
    // 顶栏标题从 textTheme.titleLarge 派生，而不是写一个「裸 TextStyle」：
    // 裸样式会把主题里的字体族覆盖成 null（回到系统默认），派生写法能保持
    // 与正文一致的字体设置。
    final titleStyle = base.textTheme.titleLarge!.copyWith(
      color: titleColor,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: .4,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(titleLarge: titleStyle),
      scaffoldBackgroundColor: tokens.canvas,
      dividerColor: tokens.hairline,
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.hairline, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: titleColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? accent : tokens.inkSecondary,
            size: 23,
          );
        }),
        // 同样从 textTheme 派生：裸 TextStyle 会把字体族覆盖成 null，
        // 导致底栏文字与正文不是同一套字体（离线渲染时更是直接变成方框）。
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return base.textTheme.labelMedium!.copyWith(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : tokens.inkSecondary,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surfaceSubtle,
        selectedColor: tokens.accentSoft,
        side: BorderSide(color: tokens.hairline),
        shape: const StadiumBorder(),
        labelStyle: base.textTheme.labelMedium?.copyWith(
          color: tokens.inkPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: base.textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.hairline),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: accent,
        inactiveTrackColor: tokens.hairline,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: .14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
    );
  }

  /// 顶部渐变（书架 / 章节列表头图）。
  ///
  /// 使用**对角**渐变（topLeft → bottomRight）。
  ///
  /// 头部使用时把渐变容器铺满**整个头部**（含状态栏区域）——应用运行在
  /// 「边到边」模式下，状态栏本身透明，头部渐变会直接透到状态栏底下，
  /// 效果是「状态栏与头部浑然一体」（用户偏好这种透明观感）。
  static LinearGradient headerGradient(BuildContext context, {Color? accent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = accent ?? Theme.of(context).colorScheme.primary;
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(const Color(0xFF271C33), a, 0.16)!,
          const Color(0xFF181422),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(const Color(0xFFFFF8F5), a, 0.08)!,
        Color.lerp(const Color(0xFFFBF6F1), a, 0.03)!,
      ],
    );
  }
}
