import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ultra-chic palette. Warm linen base, deep graphite type, brass accents.
/// All surface colours have a touch of warmth so no tile ever feels sterile.
class LuxeColors {
  // Ambient canvas (gradient pulls between these three)
  static const cream = Color(0xFFF5F0E6);
  static const creamLight = Color(0xFFFBF8F1);
  static const creamDeep = Color(0xFFE5DCC9);

  // Surfaces (glass defaults)
  static const surface = Color(0xFFFFFBF5);
  static const surfaceDim = Color(0xFFF0E9DB);
  static const surfaceDark = Color(0xFF18181C);
  static const surfaceDarkElev = Color(0xFF23232A);

  // Ink
  static const ink = Color(0xFF1A1A1F);
  static const inkSoft = Color(0xFF5E5F66);
  static const inkFaint = Color(0xFF98989F);

  // Brass accents
  static const brass = Color(0xFFB08A4E);
  static const brassGlow = Color(0xFFE0C38A);
  static const brassSoft = Color(0xFFE8D7B4);
  static const brassDeep = Color(0xFF8C6E36);

  // Hairlines & dividers
  static const line = Color(0x14000000);
  static const lineSoft = Color(0x08000000);
  static const glassRim = Color(0x40FFFFFF);

  // Legacy aliases kept to avoid touching every file that used the old palette.
  static const paper = cream;
  static const paperDim = surfaceDim;

  // Signal colour
  static const danger = Color(0xFFD64545);
}

/// Shared look for icons inside device control buttons (seg rows, +/- pads).
class DeviceControlIcons {
  DeviceControlIcons._();

  static const double size = 20;
  /// Stroke width for custom-painted icons at [size] px.
  static const double graphicStroke = 1.5;

  /// Solid triangle — icon-only knoppen zonder schacht (play).
  static const IconData triangle = Icons.play_arrow_rounded;
  /// Sonos skip — alleen media.
  static const IconData skipPrevious = Icons.skip_previous_rounded;
  static const IconData skipNext = Icons.skip_next_rounded;

  /// Rotaties voor [triangle].
  static const double rotUp = -1.5707963267948966;
  static const double rotDown = 1.5707963267948966;

  static double graphicStrokeFor(double graphicSize) =>
      graphicSize * (graphicStroke / size);

  static Color color({bool active = false, bool disabled = false}) {
    if (disabled) return LuxeColors.inkSoft.withValues(alpha: 0.35);
    if (active) return LuxeColors.brass;
    return LuxeColors.ink;
  }
}

/// Reusable multi-layer "shadow stacks". All extremely soft to preserve
/// the airy feel – the depth comes from *three* stacked blurs, not one
/// chunky drop-shadow.
class LuxeShadows {
  /// Subtle lift for default resting cards.
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x10000000), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 64, offset: Offset(0, 32)),
  ];

  /// Compact lift for 56px device control buttons.
  static const List<BoxShadow> controlButton = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0C000000), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 36, offset: Offset(0, 18)),
  ];

  /// Elevated/floating surfaces (e.g. hero cards, modal pills).
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 90, offset: Offset(0, 48)),
  ];

  /// Brass halo for "on" / attention states.
  static const List<BoxShadow> brassGlow = [
    BoxShadow(
        color: Color(0x33B08A4E),
        blurRadius: 48,
        spreadRadius: -6,
        offset: Offset(0, 8)),
    BoxShadow(
        color: Color(0x14000000), blurRadius: 28, offset: Offset(0, 12)),
  ];

  /// For dark surfaces on the black intercom/camera screens.
  static const List<BoxShadow> darkLift = [
    BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 16)),
  ];
}

/// Standard corner radii used across the whole app – never reach for a bare
/// `BorderRadius.circular` in feature files, grab a token here instead.
class LuxeRadius {
  static const pill = Radius.circular(999);
  static const lg = Radius.circular(28);
  static const md = Radius.circular(22);
  static const sm = Radius.circular(16);
}

class LuxeSpacing {
  static const double xs = 8;
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 28;
  static const double xl = 40;
  static const double xxl = 56;
}

ThemeData buildLuxeTheme() {
  final baseText = GoogleFonts.interTextTheme().apply(
    bodyColor: LuxeColors.ink,
    displayColor: LuxeColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: LuxeColors.cream,
    colorScheme: const ColorScheme.light(
      primary: LuxeColors.ink,
      onPrimary: Colors.white,
      secondary: LuxeColors.brass,
      onSecondary: Colors.white,
      surface: LuxeColors.surface,
      onSurface: LuxeColors.ink,
    ),
    textTheme: baseText.copyWith(
      displayLarge: GoogleFonts.lexendDeca(
        fontSize: 64,
        fontWeight: FontWeight.w200,
        letterSpacing: -2.0,
        color: LuxeColors.ink,
        height: 1.02,
      ),
      displayMedium: GoogleFonts.lexendDeca(
        fontSize: 44,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.2,
        color: LuxeColors.ink,
        height: 1.08,
      ),
      headlineLarge: GoogleFonts.lexendDeca(
        fontSize: 32,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.4,
        color: LuxeColors.ink,
      ),
      headlineMedium: GoogleFonts.lexendDeca(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.2,
        color: LuxeColors.ink,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: LuxeColors.ink,
        letterSpacing: 0.05,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: LuxeColors.ink,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: LuxeColors.ink,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: LuxeColors.inkSoft,
        height: 1.45,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 2.6,
        color: LuxeColors.inkSoft,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 2.4,
        color: LuxeColors.inkSoft,
      ),
    ),
    dividerColor: LuxeColors.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    cardTheme: const CardThemeData(
      color: LuxeColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: LuxeColors.ink,
    ),
  );
}
