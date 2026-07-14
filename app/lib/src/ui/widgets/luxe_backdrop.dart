import 'package:flutter/material.dart';

import '../../theme.dart';

/// Ambient, cinematic backdrop for the whole app. A warm linen gradient with
/// two subtle brass "hotspots" that imply sunlight falling through a
/// floor-to-ceiling window – the hallmark of a Bang & Olufsen-style room.
///
/// Wrap any `Scaffold(body: ...)` with this to immediately lift the page
/// from "flat UI" to "editorial interior".
class LuxeBackdrop extends StatelessWidget {
  const LuxeBackdrop({
    super.key,
    required this.child,
    this.dark = false,
  });

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (dark) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: LuxeColors.surfaceDark),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -1.0),
                  radius: 1.4,
                  colors: [
                    LuxeColors.brass.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                LuxeColors.creamLight,
                LuxeColors.cream,
                LuxeColors.creamDeep,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.1, -1.0),
                radius: 1.1,
                colors: [
                  LuxeColors.brassGlow.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-1.0, 1.2),
                radius: 0.9,
                colors: [
                  LuxeColors.brass.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
