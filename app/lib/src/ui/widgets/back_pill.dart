import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';

/// Circular back control — shared by room and category headers.
class BackPill extends StatelessWidget {
  const BackPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final size = isPhone ? 44.0 : 48.0;
    final iconSize = isPhone ? 20.0 : 22.0;
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
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
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: iconSize,
              color: LuxeColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
