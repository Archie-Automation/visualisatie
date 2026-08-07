import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';

const _headerButtonRadius = 12.0;

/// Shared chrome for header icon buttons (back, refresh, …).
///
/// Uses a plain [GestureDetector] (no InkWell / Tooltip) so the first
/// touch on wall tablets and phones registers immediately.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Matches floor-chip height (_FloorTabBar) and header glass buttons.
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final iconSize = isPhone ? 20.0 : 22.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillAlpha = isDark ? 0.96 : LuxeChipChrome.lightFill();
    final fill = LuxeColors.surface.withValues(alpha: fillAlpha);

    return Semantics(
      button: true,
      label: tooltip ?? 'Terug',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LuxeRimBox(
          width: size,
          height: size,
          radius: _headerButtonRadius,
          rimWidth: 1,
          rimColor: LuxeBorders.solid(LuxeColors.ink.withValues(alpha: 0.12)),
          fillColor: fill,
          shadows: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
          child: Center(
            child: Icon(icon, size: iconSize, color: LuxeColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Back control — shared by room, category and log headers.
class BackPill extends StatelessWidget {
  const BackPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HeaderIconButton(
      icon: Icons.arrow_back_ios_new,
      onTap: onTap,
      tooltip: 'Terug',
    );
  }
}
