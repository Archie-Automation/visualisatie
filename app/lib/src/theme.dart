import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic palette for light / dark. Bound into [LuxeColors] at runtime so
/// existing `LuxeColors.ink` call-sites follow the active theme.
@immutable
class LuxePalette extends ThemeExtension<LuxePalette> {
  const LuxePalette({
    required this.cream,
    required this.creamLight,
    required this.creamDeep,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceDark,
    required this.surfaceDarkElev,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.brass,
    required this.brassGlow,
    required this.brassSoft,
    required this.brassDeep,
    required this.line,
    required this.lineSoft,
    required this.glassRim,
    required this.danger,
    required this.glassHighlight,
  });

  final Color cream;
  final Color creamLight;
  final Color creamDeep;
  final Color surface;
  final Color surfaceDim;
  final Color surfaceDark;
  final Color surfaceDarkElev;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color brass;
  final Color brassGlow;
  final Color brassSoft;
  final Color brassDeep;
  final Color line;
  final Color lineSoft;
  final Color glassRim;
  final Color danger;
  /// Top inner rim on glass cards (lower on dark to avoid glare).
  final Color glassHighlight;

  /// Pre–quiet-luxury light (warm linen). Rollback: use in [buildLuxeTheme]
  /// instead of [light].
  static const lightLegacy = LuxePalette(
    cream: Color(0xFFB9B1A2),
    creamLight: Color(0xFFC6BEAF),
    creamDeep: Color(0xFFA69E8F),
    surface: Color(0xFFF7F2E9),
    surfaceDim: Color(0xFFE4DDD0),
    surfaceDark: Color(0xFF18181C),
    surfaceDarkElev: Color(0xFF23232A),
    ink: Color(0xFF0A0908),
    inkSoft: Color(0xFF2A2722),
    inkFaint: Color(0xFF4A453E),
    brass: Color(0xFF8F7040),
    brassGlow: Color(0xFFB8975C),
    brassSoft: Color(0xFFD0BFA0),
    brassDeep: Color(0xFF6F5630),
    line: Color(0x33000000),
    lineSoft: Color(0x1A000000),
    glassRim: Color(0x2E000000),
    danger: Color(0xFFB83A3A),
    glassHighlight: Color(0x14FFFFFF),
  );

  /// Quiet luxury light — steen-canvas + papier, minder geel/beige (iPhone P3).
  static const light = LuxePalette(
    cream: Color(0xFF87847C), // koeler steen (was warmer beige)
    creamLight: Color(0xFF9C9992),
    creamDeep: Color(0xFF726E67),
    surface: Color(0xFFF7F6F2), // koeler papier
    surfaceDim: Color(0xFFE6E4DE),
    surfaceDark: Color(0xFF18181C),
    surfaceDarkElev: Color(0xFF23232A),
    ink: Color(0xFF090807),
    inkSoft: Color(0xFF2F2A24),
    inkFaint: Color(0xFF5C554A),
    brass: Color(0xFFA67C3D),
    brassGlow: Color(0xFFD4B06E),
    brassSoft: Color(0xFFD8D0C2), // minder peach
    brassDeep: Color(0xFF5E4722),
    line: Color(0x3A000000),
    lineSoft: Color(0x1E000000),
    glassRim: Color(0x32000000),
    danger: Color(0xFFB83A3A),
    glassHighlight: Color(0x22FFFFFF),
  );

  /// Phone-only light canvas — lichter Nardo-grijs (geen beige steen).
  static const Color phoneCream = Color(0xFFC2C2BE);
  static const Color phoneCreamLight = Color(0xFFD0D0CC);
  static const Color phoneCreamDeep = Color(0xFFB4B4B0);

  /// Older cool-charcoal dark. Rollback: [buildLuxeTheme] → darkCharcoal.
  static const darkCharcoal = LuxePalette(
    cream: Color(0xFF1A1C1F),
    creamLight: Color(0xFF22252A),
    creamDeep: Color(0xFF121417),
    surface: Color(0xFF3A3C41),
    surfaceDim: Color(0xFF2C2E33),
    surfaceDark: Color(0xFF0E1012),
    surfaceDarkElev: Color(0xFF484A50),
    ink: Color(0xFFF0EFED),
    inkSoft: Color(0xFFC9C7C4),
    inkFaint: Color(0xFFB0AEAB),
    brass: Color(0xFFC9A65E),
    brassGlow: Color(0xFFD8BC7A),
    brassSoft: Color(0xFF2A2E33),
    brassDeep: Color(0xFFE2C88A),
    line: Color(0x38C9C7C4),
    lineSoft: Color(0x22C9C7C4),
    glassRim: Color(0x38C9C7C4),
    danger: Color(0xFFFF8888),
    glassHighlight: Color(0x14F0EFED),
  );

  /// Flat Nardo (pre–quiet-luxury). Rollback: [buildLuxeTheme] → darkNardo.
  static const darkNardo = LuxePalette(
    cream: Color(0xFF121312),
    creamLight: Color(0xFF2C2C2A),
    creamDeep: Color(0xFF121312),
    surface: Color(0xFF1E1E1C),
    surfaceDim: Color(0xFF181817),
    surfaceDark: Color(0xFF121312),
    surfaceDarkElev: Color(0xFF2C2C2A),
    ink: Color(0xFFE8E8E6),
    inkSoft: Color(0xFF9B9B97),
    inkFaint: Color(0xFF9B9B97),
    brass: Color(0xFFD1B48C),
    brassGlow: Color(0xFFD1B48C),
    brassSoft: Color(0xFF2C2C2A),
    brassDeep: Color(0xFFD1B48C),
    line: Color(0xFF3C3C39),
    lineSoft: Color(0x993C3C39),
    glassRim: Color(0xFF3C3C39),
    danger: Color(0xFFFF8888),
    glassHighlight: Color(0x12E8E8E6),
  );

  /// Quiet luxury dark — diepere canvas, lichtere kaarten, rijker goud.
  static const dark = LuxePalette(
    cream: Color(0xFF0A0A09), // diepere canvas
    creamLight: Color(0xFF383834), // hover wash
    creamDeep: Color(0xFF0A0A09),
    surface: Color(0xFF2C2C28), // duidelijk gelift t.o.v. canvas
    surfaceDim: Color(0xFF1C1C1A),
    surfaceDark: Color(0xFF0A0A09),
    surfaceDarkElev: Color(0xFF383834),
    ink: Color(0xFFF2F1EC),
    inkSoft: Color(0xFFB0AFA8),
    inkFaint: Color(0xFF8F8E86),
    brass: Color(0xFFD8BC90), // warmer titanium body
    brassGlow: Color(0xFFEBD4B0), // champagne highlight
    brassSoft: Color(0xFF383834),
    brassDeep: Color(0xFFC49A5E), // deep metal
    line: Color(0xFF4A4A44),
    lineSoft: Color(0x994A4A44),
    glassRim: Color(0xFF4A4A44),
    danger: Color(0xFFFF8888),
    glassHighlight: Color(0x28F2F1EC),
  );

  @override
  LuxePalette copyWith({
    Color? cream,
    Color? creamLight,
    Color? creamDeep,
    Color? surface,
    Color? surfaceDim,
    Color? surfaceDark,
    Color? surfaceDarkElev,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? brass,
    Color? brassGlow,
    Color? brassSoft,
    Color? brassDeep,
    Color? line,
    Color? lineSoft,
    Color? glassRim,
    Color? danger,
    Color? glassHighlight,
  }) {
    return LuxePalette(
      cream: cream ?? this.cream,
      creamLight: creamLight ?? this.creamLight,
      creamDeep: creamDeep ?? this.creamDeep,
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      surfaceDarkElev: surfaceDarkElev ?? this.surfaceDarkElev,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      brass: brass ?? this.brass,
      brassGlow: brassGlow ?? this.brassGlow,
      brassSoft: brassSoft ?? this.brassSoft,
      brassDeep: brassDeep ?? this.brassDeep,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      glassRim: glassRim ?? this.glassRim,
      danger: danger ?? this.danger,
      glassHighlight: glassHighlight ?? this.glassHighlight,
    );
  }

  @override
  LuxePalette lerp(ThemeExtension<LuxePalette>? other, double t) {
    if (other is! LuxePalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LuxePalette(
      cream: l(cream, other.cream),
      creamLight: l(creamLight, other.creamLight),
      creamDeep: l(creamDeep, other.creamDeep),
      surface: l(surface, other.surface),
      surfaceDim: l(surfaceDim, other.surfaceDim),
      surfaceDark: l(surfaceDark, other.surfaceDark),
      surfaceDarkElev: l(surfaceDarkElev, other.surfaceDarkElev),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      inkFaint: l(inkFaint, other.inkFaint),
      brass: l(brass, other.brass),
      brassGlow: l(brassGlow, other.brassGlow),
      brassSoft: l(brassSoft, other.brassSoft),
      brassDeep: l(brassDeep, other.brassDeep),
      line: l(line, other.line),
      lineSoft: l(lineSoft, other.lineSoft),
      glassRim: l(glassRim, other.glassRim),
      danger: l(danger, other.danger),
      glassHighlight: l(glassHighlight, other.glassHighlight),
    );
  }
}

/// Ultra-chic palette accessors. Values follow the last [bind] call from the
/// active [ThemeData] (quiet luxury light / dark).
class LuxeColors {
  static LuxePalette _active = LuxePalette.light;

  static void bind(LuxePalette palette) => _active = palette;

  static LuxePalette get active => _active;

  static Color get cream => _active.cream;
  static Color get creamLight => _active.creamLight;
  static Color get creamDeep => _active.creamDeep;
  static Color get surface => _active.surface;
  static Color get surfaceDim => _active.surfaceDim;
  static Color get surfaceDark => _active.surfaceDark;
  static Color get surfaceDarkElev => _active.surfaceDarkElev;
  static Color get ink => _active.ink;
  static Color get inkSoft => _active.inkSoft;
  static Color get inkFaint => _active.inkFaint;
  /// Text/icon on solid [ink] fills. In dark mode [ink] is light — never use
  /// hard-coded white there (white-on-cream).
  static Color get onInk =>
      _active.ink.computeLuminance() > 0.45
          ? _active.creamDeep
          : const Color(0xFFF5F0E6);
  static Color get brass => _active.brass;
  static Color get brassGlow => _active.brassGlow;
  static Color get brassSoft => _active.brassSoft;
  static Color get brassDeep => _active.brassDeep;
  static Color get line => _active.line;
  static Color get lineSoft => _active.lineSoft;
  static Color get glassRim => _active.glassRim;
  static Color get danger => _active.danger;
  static Color get glassHighlight => _active.glassHighlight;

  static Color get paper => cream;
  static Color get paperDim => surfaceDim;
}

/// Shared look for icons inside device control buttons (seg rows, +/- pads).
class DeviceControlIcons {
  DeviceControlIcons._();

  static const double size = 20;
  static const double graphicStroke = 1.9;

  static const IconData triangle = Icons.play_arrow_rounded;
  static const IconData skipPrevious = Icons.skip_previous_rounded;
  static const IconData skipNext = Icons.skip_next_rounded;

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

class LuxeShadows {
  /// Soft lift — keeps cards above a recessed canvas.
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x18000000), blurRadius: 32, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x14000000), blurRadius: 60, offset: Offset(0, 30)),
  ];

  static const List<BoxShadow> controlButton = [
    BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x10000000), blurRadius: 36, offset: Offset(0, 18)),
  ];

  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5)),
    BoxShadow(color: Color(0x1C000000), blurRadius: 44, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x1E000000), blurRadius: 90, offset: Offset(0, 48)),
  ];

  static const List<BoxShadow> brassGlow = [
    BoxShadow(
        color: Color(0x40D4B06E),
        blurRadius: 44,
        spreadRadius: -6,
        offset: Offset(0, 6)),
    BoxShadow(
        color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
  ];

  /// Subtle dark lift — depth without heavy black blobs.
  static const List<BoxShadow> darkLift = [
    BoxShadow(color: Color(0x38000000), blurRadius: 10, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x2A000000), blurRadius: 24, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x1C000000), blurRadius: 40, offset: Offset(0, 20)),
  ];

  static List<BoxShadow> chip(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkLift : soft;
}

/// Shared chrome for dashboard scene / system / room-category chips.
abstract final class LuxeChipChrome {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Light-mode “luchtige” surface — canvas schemert erdoorheen.
  static double lightFill({bool pressed = false}) => pressed ? 0.88 : 0.78;

  static Color fill(BuildContext context, {required bool pressed}) {
    final a = isDark(context)
        ? (pressed ? 1.0 : 0.88)
        : lightFill(pressed: pressed);
    return LuxeColors.surface.withValues(alpha: a);
  }

  static Color border(
    BuildContext context, {
    required bool pressed,
    Color? accent,
  }) {
    // Altijd ondoorzichtig — semi-transparante Border.all wordt korrelig (Impeller).
    if (pressed && accent != null) {
      return LuxeBorders.solid(
        accent.withValues(alpha: isDark(context) ? 0.55 : 0.65),
      );
    }
    return isDark(context)
        ? LuxeColors.glassRim
        : LuxeBorders.solid(LuxeColors.ink.withValues(alpha: 0.22));
  }
}

/// Hairline / accent borders without grainy anti-alias on wall tablets.
abstract final class LuxeBorders {
  /// Opaque stand-in for a translucent [tinted] drawn over [over].
  static Color solid(Color tinted, [Color? over]) =>
      Color.alphaBlend(tinted, over ?? LuxeColors.surface);
}

/// Sharp rounded frame: translucent fill + opaque rim ring (no [Border.all]).
///
/// Impeller AA’s thin strokes into grain. The rim is an even-odd filled ring
/// so a translucent [fillColor] still composites against the backdrop — not
/// against a full opaque slab underneath.
class LuxeRimBox extends StatelessWidget {
  const LuxeRimBox({
    super.key,
    required this.radius,
    required this.rimColor,
    required this.fillColor,
    required this.child,
    this.rimWidth = 1.25,
    this.width,
    this.height,
    this.padding,
    this.shadows,
  });

  final double radius;
  final Color rimColor;
  final Color fillColor;
  final Widget child;
  final double rimWidth;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final opaqueRim = Color.alphaBlend(rimColor, LuxeColors.surface);
    final borderRadius = BorderRadius.circular(radius);
    final innerR = (radius - rimWidth).clamp(0.0, radius);

    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    content = Padding(
      padding: EdgeInsets.all(rimWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerR),
        clipBehavior: Clip.hardEdge,
        child: content,
      ),
    );

    Widget body = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: fillColor,
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _LuxeRimRingPainter(
              color: opaqueRim,
              rimWidth: rimWidth,
              radius: radius,
            ),
          ),
        ),
        content,
      ],
    );

    if (shadows != null && shadows!.isNotEmpty) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadows,
        ),
        child: body,
      );
    }

    if (width != null || height != null) {
      body = SizedBox(width: width, height: height, child: body);
    }
    return body;
  }
}

class _LuxeRimRingPainter extends CustomPainter {
  _LuxeRimRingPainter({
    required this.color,
    required this.rimWidth,
    required this.radius,
  });

  final Color color;
  final double rimWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || rimWidth <= 0) return;
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final inset = rimWidth;
    final innerRect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    if (innerRect.width <= 0 || innerRect.height <= 0) {
      canvas.drawRRect(outer, Paint()..color = color);
      return;
    }
    final inner = RRect.fromRectAndRadius(
      innerRect,
      Radius.circular((radius - rimWidth).clamp(0.0, radius)),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(inner);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _LuxeRimRingPainter old) =>
      old.color != color || old.rimWidth != rimWidth || old.radius != radius;
}

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

ThemeData buildLuxeTheme([Brightness brightness = Brightness.light]) {
  // Quiet luxury active. Rollback:
  //   light → LuxePalette.lightLegacy
  //   dark  → LuxePalette.darkNardo  (of darkCharcoal voor oudere charcoal)
  final p = brightness == Brightness.dark ? LuxePalette.dark : LuxePalette.light;
  final baseText = GoogleFonts.interTextTheme().apply(
    bodyColor: p.ink,
    displayColor: p.ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.cream,
    extensions: <ThemeExtension<dynamic>>[p],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: p.ink,
      onPrimary: brightness == Brightness.dark ? p.cream : const Color(0xFFF5F0E6),
      secondary: p.brass,
      onSecondary: brightness == Brightness.dark ? p.cream : Colors.white,
      surface: p.surface,
      onSurface: p.ink,
      error: p.danger,
      onError: Colors.white,
    ),
    textTheme: baseText.copyWith(
      // Brand display (Archie): Lexend — luxe licht, cijfer-1 ≠ I.
      // Overige headlines: Cormorant (quiet luxury serif).
      displayLarge: GoogleFonts.lexendDeca(
        fontSize: 58,
        fontWeight: FontWeight.w200,
        letterSpacing: -1.4,
        color: p.ink,
        height: 1.05,
      ),
      displayMedium: GoogleFonts.cormorantGaramond(
        fontSize: 42,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.4,
        color: p.ink,
        height: 1.08,
      ),
      headlineLarge: GoogleFonts.cormorantGaramond(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.2,
        color: p.ink,
      ),
      headlineMedium: GoogleFonts.cormorantGaramond(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: p.ink,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: p.ink,
        letterSpacing: 0,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.ink,
        height: 1.35,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: p.inkSoft,
        height: 1.35,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.inkSoft,
        height: 1.35,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: p.inkSoft,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: p.inkSoft,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: p.inkFaint,
      ),
    ),
    dividerColor: p.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.ink,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return p.brass;
        return p.inkSoft;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) {
          return p.brass.withValues(alpha: 0.45);
        }
        return p.line;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          // Selected segment sits on [surface]; ink is always readable there.
          // Unselected: softer ink.
          if (s.contains(WidgetState.selected)) return p.ink;
          return p.inkSoft;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return p.surface.withValues(alpha: 0.95);
          }
          return Colors.transparent;
        }),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(p.ink),
        foregroundColor: WidgetStatePropertyAll(
          p.ink.computeLuminance() > 0.45
              ? p.creamDeep
              : const Color(0xFFF5F0E6),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(
        color: p.ink.computeLuminance() > 0.45
            ? p.creamDeep
            : const Color(0xFFF5F0E6),
      ),
      actionTextColor: p.brass,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface.withValues(alpha: 0.85),
      hintStyle: TextStyle(color: p.inkFaint),
      labelStyle: TextStyle(color: p.inkSoft),
      floatingLabelStyle: TextStyle(color: p.inkSoft),
    ),
  );
}
