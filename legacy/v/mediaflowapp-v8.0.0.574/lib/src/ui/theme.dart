import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// MediaFlow's colours. They follow the account's theme (the website's theme
/// system, see theme_palette.dart and theme_controller.dart); [apply] switches
/// them and the whole app is redrawn.
class MF {
  static Color background = const Color(0xFF0B0E14);
  static Color surface = const Color(0xFF141922);
  static Color raised = const Color(0xFF1C2330);
  static Color border = const Color(0xFF343D4D);
  static Color accent = const Color(0xFFE8A94A);
  static Color accentSoft = const Color(0x33E8A94A);
  static Color text = const Color(0xFFF2F4F8);
  static Color textDim = const Color(0xFFB6BECB);
  static Color textMute = const Color(0xFF7F8999);
  static bool light = false;

  static const Color good = Color(0xFF3FB98B);
  static const Color warn = Color(0xFFE0A33C);
  static const Color bad = Color(0xFFE0606C);

  /// Switches every colour to [p].
  static void apply(Palette p) {
    background = p.bg;
    surface = p.panel;
    raised = p.raised;
    border = p.border;
    accent = p.flow;
    accentSoft = p.flow.withValues(alpha: .2);
    text = p.text;
    textDim = p.dim;
    textMute = p.mute;
    light = p.isLight;
  }

  static ThemeData theme() {
    final brightness = light ? Brightness.light : Brightness.dark;
    final onAccent = luminance(accent) > .45 ? const Color(0xFF1B1405) : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textDim,
      outline: border,
      surfaceContainerHighest: raised,
      surfaceContainerHigh: raised,
      surfaceContainer: surface,
      surfaceContainerLow: surface,
      surfaceContainerLowest: background,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent, width: 1.5)),
        labelStyle: TextStyle(color: textDim),
        hintStyle: TextStyle(color: textDim),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: raised,
        selectedColor: accentSoft,
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, modalBackgroundColor: surface),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      popupMenuTheme: PopupMenuThemeData(color: raised),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: raised,
        contentTextStyle: TextStyle(color: text),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    );
  }

  static Color parseColor(String hex, {Color? fallback}) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6) return fallback ?? accent;
    final v = int.tryParse(h, radix: 16);
    return v == null ? (fallback ?? accent) : Color(0xFF000000 | v);
  }
}
