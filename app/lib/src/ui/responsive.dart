import 'package:flutter/widgets.dart';

import 'responsive_platform.dart' as platform;

/// Breakpoints (dp):
///   phone   < 600
///   tablet  600 – 900
///   desktop > 900
///
/// Usage:
///   context.isPhone
///   context.hPad       // horizontal page padding
///   context.favTileW   // favourite tile width in horizontal carousel
extension ResponsiveX on BuildContext {
  double get _w => MediaQuery.sizeOf(this).width;
  double get _shortest => MediaQuery.sizeOf(this).shortestSide;

  /// Phone layout — shortestSide for orientation, width for narrow viewports,
  /// plus mobile user-agent on web (PWA in browser).
  bool get isPhone =>
      _shortest < 600 || _w < 600 || platform.isMobileWebUserAgent;

  bool get isTablet => !isPhone && _shortest >= 600 && _shortest < 900;
  bool get isDesktop => !isPhone && _shortest >= 900;

  /// Horizontal padding used on top-level page content.
  double get hPad => isPhone ? 20.0 : 40.0;

  /// Inner horizontal padding for device tiles / cards.
  double get cardHPad => isPhone ? 18.0 : 28.0;

  /// Horizontal padding on device lists (room / category screens).
  double get listHPad => isPhone ? 14.0 : 28.0;

  /// Bleed past card + list padding so controls can span the screen edge.
  double get deviceTileBleed => cardHPad + listHPad;

  /// Inner vertical padding for device tiles.
  double get cardVPad => isPhone ? 18.0 : 26.0;

  /// Width of a favourite shortcut tile in the horizontal carousel.
  double get favTileW => isPhone ? 152.0 : 190.0;

  /// Height of the favourite carousel.
  double get favCarouselH => isPhone ? 136.0 : 150.0;

  /// Height of the pinned room header (back + titles).
  double get roomStickyHeaderH => isPhone ? 88.0 : 100.0;

  /// Height of the SliverAppBar on a room screen.
  double get roomHeaderH => isPhone ? 200.0 : 280.0;

  /// Font size for the large dashboard project title.
  double get displayLargeFontSize => isPhone ? 34.0 : 64.0;

  /// Font size for room / medium titles.
  double get displayMediumFontSize => isPhone ? 28.0 : 44.0;
}
