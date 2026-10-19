import 'package:flutter/material.dart';

/// Values pinned to the personal MediaFlow v410 foundation stylesheet.
/// This is the baseline palette, not a claim of full custom/dynamic theme parity.
abstract final class MediaFlowColors {
  static const background = Color(0xFF0E111A);
  static const panel = Color(0xFF161B29);
  static const raised = Color(0xFF1D2436);
  static const border = Color(0xFF2A3149);
  static const borderSoft = Color(0xFF232A40);
  static const text = Color(0xFFEDEFF6);
  static const muted = Color(0xFF9AA3BC);
  static const quiet = Color(0xFF6A7290);
  static const accent = Color(0xFFE8A94A);
  static const accentDim = Color(0xFF8A6A35);
  static const healthy = Color(0xFF3FC7A6);
  static const neglect = Color(0xFF9C8CF5);
  static const overused = Color(0xFFE8607A);
  static const due = Color(0xFF5AA9E6);
}

abstract final class MediaFlowSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class MediaFlowRadius {
  static const small = 6.0;
  static const medium = 13.0;
  static const large = 20.0;
}

abstract final class MediaFlowBreakpoints {
  // Original v410 responsive navigation switches at 1080 CSS pixels.
  static const desktop = 1081.0;
  // Native intermediate devices have a compact rail to preserve discoverability.
  static const tablet = 700.0;
  static const compactPhone = 390.0;
  static const contentMax = 1200.0;

  static double pagePadding(double width) =>
      width < compactPhone ? 10 : width < tablet ? 14 : 20;
}

enum MediaFlowAppearance { dark, light, amoled }

/// All native components read this extension, avoiding hardcoded dark colors
/// in individual pages. v410 custom and cover-derived themes are future work.
@immutable
class MediaFlowTokens extends ThemeExtension<MediaFlowTokens> {
  const MediaFlowTokens({
    required this.background,
    required this.panel,
    required this.raised,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.muted,
    required this.quiet,
    required this.accent,
    required this.accentDim,
    required this.healthy,
    required this.neglect,
    required this.overused,
    required this.due,
  });

  final Color background, panel, raised, border, borderSoft;
  final Color text, muted, quiet, accent, accentDim;
  final Color healthy, neglect, overused, due;

  static MediaFlowTokens of(BuildContext context) =>
      Theme.of(context).extension<MediaFlowTokens>()!;

  @override
  MediaFlowTokens copyWith({
    Color? background, Color? panel, Color? raised, Color? border,
    Color? borderSoft, Color? text, Color? muted, Color? quiet,
    Color? accent, Color? accentDim, Color? healthy, Color? neglect,
    Color? overused, Color? due,
  }) => MediaFlowTokens(
    background: background ?? this.background,
    panel: panel ?? this.panel,
    raised: raised ?? this.raised,
    border: border ?? this.border,
    borderSoft: borderSoft ?? this.borderSoft,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    quiet: quiet ?? this.quiet,
    accent: accent ?? this.accent,
    accentDim: accentDim ?? this.accentDim,
    healthy: healthy ?? this.healthy,
    neglect: neglect ?? this.neglect,
    overused: overused ?? this.overused,
    due: due ?? this.due,
  );

  @override
  MediaFlowTokens lerp(ThemeExtension<MediaFlowTokens>? other, double t) {
    if (other is! MediaFlowTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MediaFlowTokens(
      background: mix(background, other.background),
      panel: mix(panel, other.panel),
      raised: mix(raised, other.raised),
      border: mix(border, other.border),
      borderSoft: mix(borderSoft, other.borderSoft),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      quiet: mix(quiet, other.quiet),
      accent: mix(accent, other.accent),
      accentDim: mix(accentDim, other.accentDim),
      healthy: mix(healthy, other.healthy),
      neglect: mix(neglect, other.neglect),
      overused: mix(overused, other.overused),
      due: mix(due, other.due),
    );
  }
}

abstract final class MediaFlowTheme {
  static MediaFlowTokens palette(MediaFlowAppearance appearance) {
    switch (appearance) {
      case MediaFlowAppearance.dark:
        return const MediaFlowTokens(
          background: MediaFlowColors.background,
          panel: MediaFlowColors.panel,
          raised: MediaFlowColors.raised,
          border: MediaFlowColors.border,
          borderSoft: MediaFlowColors.borderSoft,
          text: MediaFlowColors.text,
          muted: MediaFlowColors.muted,
          quiet: MediaFlowColors.quiet,
          accent: MediaFlowColors.accent,
          accentDim: MediaFlowColors.accentDim,
          healthy: MediaFlowColors.healthy,
          neglect: MediaFlowColors.neglect,
          overused: MediaFlowColors.overused,
          due: MediaFlowColors.due,
        );
      case MediaFlowAppearance.light:
        return const MediaFlowTokens(
          background: Color(0xFFF5F6F8),
          panel: Colors.white,
          raised: Color(0xFFEEF1F5),
          border: Color(0xFFD7DCE5),
          borderSoft: Color(0xFFE4E7ED),
          text: Color(0xFF171A21),
          muted: Color(0xFF596274),
          quiet: Color(0xFF7B8496),
          accent: MediaFlowColors.accent,
          accentDim: MediaFlowColors.accentDim,
          healthy: MediaFlowColors.healthy,
          neglect: MediaFlowColors.neglect,
          overused: MediaFlowColors.overused,
          due: MediaFlowColors.due,
        );
      case MediaFlowAppearance.amoled:
        return const MediaFlowTokens(
          background: Colors.black,
          panel: Color(0xFF050505),
          raised: Color(0xFF0A0A0A),
          border: Color(0xFF202020),
          borderSoft: Color(0xFF151515),
          text: Color(0xFFF5F5F5),
          muted: Color(0xFFA0A0A0),
          quiet: Color(0xFF666666),
          accent: MediaFlowColors.accent,
          accentDim: MediaFlowColors.accentDim,
          healthy: MediaFlowColors.healthy,
          neglect: MediaFlowColors.neglect,
          overused: MediaFlowColors.overused,
          due: MediaFlowColors.due,
        );
    }
  }

  static ThemeData build(MediaFlowAppearance appearance) {
    final colors = palette(appearance);
    final dark = appearance != MediaFlowAppearance.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: colors.panel,
      onSurface: colors.text,
      primary: colors.accent,
      onPrimary: const Color(0xFF21190D),
    );
    final outline = BorderSide(color: colors.border);
    final rounded = RoundedRectangleBorder(
      side: outline, borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.borderSoft,
      extensions: <ThemeExtension<dynamic>>[colors],
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: colors.text,
        displayColor: colors.text,
      ).copyWith(
        headlineLarge: TextStyle(fontSize: 36, fontFamily: 'Georgia', fontWeight: FontWeight.w700,
          color: colors.text, letterSpacing: -0.7),
        headlineMedium: TextStyle(fontSize: 29, fontFamily: 'Georgia', fontWeight: FontWeight.w700,
          color: colors.text, letterSpacing: -0.4),
        titleLarge: TextStyle(fontSize: 20, fontFamily: 'Georgia', fontWeight: FontWeight.w700,
          color: colors.text),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
          color: colors.text),
        bodySmall: TextStyle(fontSize: 12, color: colors.muted),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: colors.text, letterSpacing: 0.2),
      ),
      iconTheme: IconThemeData(color: colors.muted, size: 21),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.text, fontSize: 19, fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.panel, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 2),
        shape: rounded,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.panel,
        shape: RoundedRectangleBorder(
          side: outline, borderRadius: BorderRadius.circular(MediaFlowRadius.large),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.panel,
        modalBackgroundColor: colors.panel,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.large),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.panel,
        indicatorColor: colors.accent.withValues(alpha: 0.15),
        selectedIconTheme: IconThemeData(color: colors.accent),
        unselectedIconTheme: IconThemeData(color: colors.muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.panel,
        elevation: 0,
        indicatorColor: colors.accent.withValues(alpha: 0.17),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? colors.accent : colors.muted,
          size: 22,
        )),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.raised,
        shape: RoundedRectangleBorder(
          side: outline, borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
          borderSide: outline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
          borderSide: outline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: colors.muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.raised,
        selectedColor: colors.accent.withValues(alpha: 0.17),
        side: outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: const Color(0xFF21190D),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
        ),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        minimumSize: const Size(44, 44),
        side: outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
        ),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        minimumSize: const Size(44, 44),
      )),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        selectedColor: colors.accent,
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.border,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: colors.raised,
          borderRadius: BorderRadius.circular(MediaFlowRadius.small),
          border: Border.all(color: colors.border)),
        textStyle: TextStyle(color: colors.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.raised,
        contentTextStyle: TextStyle(color: colors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MediaFlowRadius.medium),
          side: BorderSide(color: colors.border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          colors.accent.withValues(alpha: 0.35)),
        radius: const Radius.circular(999),
        thickness: WidgetStateProperty.all(6),
      ),
      dividerTheme: DividerThemeData(color: colors.borderSoft, thickness: 1),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
