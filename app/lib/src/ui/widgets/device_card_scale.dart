import 'package:flutter/material.dart';

import '../responsive.dart';

/// Responsive schaal voor device-kaarten — phone / tablet / desktop-web.
abstract final class DeviceCardScale {
  /// Uniforme knopmaat — gelijk aan audio ([DeviceControlBar.buttonSize]).
  static double buttonSize(BuildContext context) => 56;

  static double iconBadgeSize(BuildContext context) => buttonSize(context);

  static double glyphSize(BuildContext context) {
    if (context.isPhone) return 22;
    if (context.isTablet) return 24;
    return 22;
  }

  static double iconRadius(BuildContext context) => 14.0;

  static EdgeInsets cardPadding(BuildContext context) {
    if (context.isPhone) return const EdgeInsets.all(16);
    if (context.isTablet) return const EdgeInsets.all(22);
    return const EdgeInsets.fromLTRB(24, 20, 24, 20);
  }

  static double sectionSpacing(BuildContext context) {
    if (context.isPhone) return 14;
    if (context.isTablet) return 18;
    return 16;
  }

  static double listGap(BuildContext context) =>
      context.isPhone ? 14 : 18;

  static double setpointFontSize(BuildContext context) {
    if (context.isPhone) return 34;
    if (context.isTablet) return 56;
    return 48;
  }

  /// Gemeten temperatuur op climate-tegels — tussen titel en setpoint in.
  static double measuredTempFontSize(BuildContext context) {
    if (context.isPhone) return 20;
    if (context.isTablet) return 24;
    return 22;
  }

  /// ± knoppen — vierkant, niet de brede climate-chip.
  static double setpointStepButtonSize(BuildContext context) =>
      buttonSize(context);

  /// Breedte van het gemeten-temp-vakje.
  static double climateChipWidth(BuildContext context) {
    if (context.isPhone) return 148;
    if (context.isTablet) return 164;
    return 156;
  }

  static double heroValueFontSize(BuildContext context) {
    if (context.isPhone) return 36;
    if (context.isTablet) return 48;
    return 42;
  }

  static int maxGridColumns(BuildContext context) {
    if (context.isPhone) return 5;
    return 4;
  }

  static double numericFontSize(BuildContext context, String text) {
    if (text.length >= 3) {
      return context.isPhone ? 12.0 : 14.0;
    }
    if (context.isPhone) return 15.0;
    if (context.isTablet) return 17.0;
    return 16.0;
  }

  /// Max breedte bedieningszone op desktop — voorkomt uitgerekte knoppen.
  static double? controlMaxWidth(BuildContext context) {
    if (context.isDesktop) return 520;
    return null;
  }

  /// Max breedte van een kaart in een lijst.
  static double listCardMaxWidth(BuildContext context) {
    if (context.isPhone) return double.infinity;
    if (context.isTablet) return 720;
    return 640;
  }

  static double sliderMaxWidth(BuildContext context) {
    if (context.isDesktop) return 360;
    return double.infinity;
  }

  static double heroImageSize(BuildContext context) {
    if (context.isPhone) return 120;
    if (context.isTablet) return 160;
    return 140;
  }

  static double colorWheelSize(BuildContext context) {
    if (context.isPhone) return 200;
    if (context.isTablet) return 240;
    return 220;
  }
}
