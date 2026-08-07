import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';
import 'honeycomb_pattern.dart';

/// Ambient backdrop. Follows the active light/dark palette.
///
/// Uses **linear** washes only — stacked radial gradients produce visible
/// circular banding on Impeller / wall-tablet panels, and are expensive to
/// repaint under scroll.
class LuxeBackdrop extends StatelessWidget {
  const LuxeBackdrop({
    super.key,
    required this.child,
    this.dark = false,
  });

  final Widget child;
  /// Force the dark ambient treatment (camera / intercom), ignoring theme.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final useDark = dark || brightness == Brightness.dark;
    final p = Theme.of(context).extension<LuxePalette>() ??
        (useDark ? LuxePalette.dark : LuxePalette.light);

    // Phone light: Nardo-grijs canvas (lichter, geen beige). Tablet behoudt steen.
    final phoneLight = !useDark && context.isPhone;
    final cream = phoneLight ? LuxePalette.phoneCream : p.cream;
    final creamLight = phoneLight ? LuxePalette.phoneCreamLight : p.creamLight;
    final creamDeep = phoneLight ? LuxePalette.phoneCreamDeep : p.creamDeep;
    final brassWash = useDark
        ? 0.14
        : (phoneLight ? 0.02 : 0.055);
    final glowWash = useDark
        ? 0.12
        : (phoneLight ? 0.015 : 0.04);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: creamDeep),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [creamLight, cream, creamDeep],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Soft brass wash — linear, no radial rings.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.centerRight,
                  colors: [
                    p.brass.withValues(alpha: brassWash),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomRight,
                  end: Alignment.center,
                  colors: [
                    p.brassGlow.withValues(alpha: glowWash),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Edge falloff (top/bottom only) — recessed canvas without circles.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: useDark ? 0.22 : 0.08),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: useDark ? 0.28 : 0.10),
                  ],
                  stops: const [0.0, 0.18, 0.78, 1.0],
                ),
              ),
            ),
          ),
          // Subtiel honingraat-profiel over de washes.
          HoneycombPattern.ambient(context, dark: useDark),
          child,
        ],
      ),
    );
  }
}
