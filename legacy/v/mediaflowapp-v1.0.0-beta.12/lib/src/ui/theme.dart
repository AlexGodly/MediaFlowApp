import 'package:flutter/material.dart';

/// MediaFlow's dark look: deep navy surfaces with the website's amber accent.
class MF {
  static const Color background = Color(0xFF0B0E16);
  static const Color surface = Color(0xFF131824);
  static const Color raised = Color(0xFF1A2130);
  static const Color border = Color(0xFF2A3245);
  static const Color accent = Color(0xFFE8A84A);
  static const Color accentSoft = Color(0x33E8A84A);
  static const Color text = Color(0xFFF2F4F8);
  static const Color textDim = Color(0xFF9AA4B6);
  static const Color good = Color(0xFF3FB98B);
  static const Color warn = Color(0xFFE0A33C);
  static const Color bad = Color(0xFFE0606C);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: const Color(0xFF1B1405),
      secondary: accent,
      surface: surface,
      onSurface: text,
      outline: border,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
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
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accent, width: 1.5)),
        labelStyle: const TextStyle(color: textDim),
        hintStyle: const TextStyle(color: textDim),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: raised,
        selectedColor: accentSoft,
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: raised,
        contentTextStyle: TextStyle(color: text),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
    );
  }

  static Color parseColor(String hex, {Color fallback = accent}) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(0xFF000000 | v);
  }
}
