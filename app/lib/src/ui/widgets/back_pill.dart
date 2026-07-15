import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';

const _headerButtonRadius = 14.0;

/// Shared chrome for header icon buttons (back, refresh, …).
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

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final size = isPhone ? 44.0 : 48.0;
    final iconSize = isPhone ? 20.0 : 22.0;
    final radius = BorderRadius.circular(_headerButtonRadius);

    final button = Material(
      color: Colors.transparent,
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: LuxeColors.surface.withValues(alpha: 0.96),
          border: Border.all(
            color: LuxeColors.ink.withValues(alpha: 0.08),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Center(
            child: Icon(icon, size: iconSize, color: LuxeColors.ink),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Back control — shared by room, category and log headers.
class BackPill extends StatelessWidget {
  const BackPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HeaderIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      onTap: onTap,
      tooltip: 'Terug',
    );
  }
}
