import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 二次元风格主题：樱粉 + 薰衣草渐变。
class SakuraTheme {
  static const Color sakura = Color(0xFFFF7EB6);
  static const Color lavender = Color(0xFF9D8CFF);

  static ThemeData build(Color accent, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF211A29) : Colors.white;
    final background = isDark
        ? const Color(0xFF171220)
        : const Color(0xFFFFF6FA);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: surface,
        primary: accent,
        secondary: lavender,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF3A2B3D),
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : const Color(0xFF3A2B3D),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: isDark ? const Color(0xFF1D1626) : Colors.white,
        indicatorColor: accent.withValues(alpha: .18),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: .12),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
    );
  }

  /// 顶部渐变（书架 / 章节列表头图）。
  ///
  /// 使用**纵向**渐变（topCenter → bottomCenter）：顶部边缘颜色均匀。
  ///
  /// 注意：头部使用时把渐变容器放到「状态栏下沿→底部」的区域内
  /// （见 shelf_page / book_detail_page 的头部结构）——渐变从该区域顶部
  /// （即状态栏下沿）以 [headerTopColor] 为起点向下延展，与状态栏底块
  /// **无缝衔接**，避免「状态栏纯色 + 头部中间色」的色阶跳变。
  static LinearGradient headerGradient(BuildContext context, {Color? accent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = accent ?? Theme.of(context).colorScheme.primary;
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          a.withValues(alpha: .40),
          const Color(0xFF3A2B52).withValues(alpha: .95),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [a.withValues(alpha: .88), lavender.withValues(alpha: .80)],
    );
  }

  /// 头部渐变顶部对应的「不透明」固体色（状态栏底块 / 头部顶部静区用）。
  ///
  /// 把渐变首色按同参数 alpha 混到页面底色上，得到与头部顶部边缘一致的
  /// 不透明颜色——状态栏区域与其下方拼接处不会出现色差。
  static Color headerTopColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final a = Theme.of(context).colorScheme.primary;
    final top = isDark ? a.withValues(alpha: .40) : a.withValues(alpha: .88);
    return Color.alphaBlend(top, bg);
  }
}
