import 'package:flutter/material.dart';

/// Core v410 tokens transcribed from assets/css/00-foundation.css.
/// Dynamic cover-derived themes remain a future parity task.
abstract final class MediaFlowColors {
  static const background = Color(0xFF0E111A);
  static const panel = Color(0xFF161B29);
  static const raised = Color(0xFF1D2436);
  static const border = Color(0xFF2A3149);
  static const text = Color(0xFFEDEFF6);
  static const muted = Color(0xFF9AA3BC);
  static const accent = Color(0xFFE8A94A);
  static const healthy = Color(0xFF3FC7A6);
}

enum MediaFlowAppearance { dark, light, amoled }

abstract final class MediaFlowTheme {
  static ThemeData build(MediaFlowAppearance appearance) {
    final dark = appearance != MediaFlowAppearance.light;
    final background = switch (appearance) {
      MediaFlowAppearance.dark => MediaFlowColors.background,
      MediaFlowAppearance.light => const Color(0xFFF5F6F8),
      MediaFlowAppearance.amoled => Colors.black,
    };
    final panel = switch (appearance) {
      MediaFlowAppearance.dark => MediaFlowColors.panel,
      MediaFlowAppearance.light => Colors.white,
      MediaFlowAppearance.amoled => const Color(0xFF050505),
    };
    final foreground = dark ? MediaFlowColors.text : const Color(0xFF171A21);
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: MediaFlowColors.accent,
        brightness: dark ? Brightness.dark : Brightness.light,
        surface: panel,
        onSurface: foreground,
      ),
      appBarTheme: AppBarTheme(backgroundColor: background, foregroundColor: foreground),
      cardTheme: CardThemeData(color: panel, shape: RoundedRectangleBorder(
        side: BorderSide(color: dark ? MediaFlowColors.border : const Color(0xFFD7DCE5)),
        borderRadius: BorderRadius.circular(12),
      )),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: panel),
      dividerColor: dark ? MediaFlowColors.border : const Color(0xFFD7DCE5),
    );
  }
}
