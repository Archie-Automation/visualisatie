import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';
import 'honeycomb_pattern.dart';

/// Page canvas only (gradient + honeycomb). No child — used by [LuxeBackdrop]
/// and by sticky headers so they match the page instead of a flat bar.
class LuxeCanvas extends StatelessWidget {
  const LuxeCanvas({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final useDark = dark || brightness == Brightness.dark;
    final p = Theme.of(context).extension<LuxePalette>() ??
        (useDark ? LuxePalette.dark : LuxePalette.light);

    final phoneLight = !useDark && context.isPhone;
    final cream = phoneLight ? LuxePalette.phoneCream : p.cream;
    final creamLight = phoneLight ? LuxePalette.phoneCreamLight : p.creamLight;
    final creamDeep = phoneLight ? LuxePalette.phoneCreamDeep : p.creamDeep;
    final brassWash = useDark ? 0.14 : (phoneLight ? 0.02 : 0.055);
    final glowWash = useDark ? 0.12 : (phoneLight ? 0.015 : 0.04);

    return Stack(
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
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: useDark ? 0.28 : 0.10),
                ],
                stops: const [0.0, 0.18, 0.78, 1.0],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: HoneycombPattern.ambient(context, dark: useDark),
        ),
      ],
    );
  }
}

/// Sticky header: same [LuxeCanvas] as the page, clipped to the bar.
/// Do not OverflowBox a full-screen canvas — that paints honeycomb for the
/// whole viewport every scroll frame, and the clip already hides it.
class StickyHeaderSurface extends StatelessWidget {
  const StickyHeaderSurface({
    super.key,
    required this.child,
    this.height,
    this.boxShadow,
  });

  final Widget child;
  final double? height;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    Widget canvas = const RepaintBoundary(
      child: IgnorePointer(child: LuxeCanvas()),
    );
    if (boxShadow != null && boxShadow!.isNotEmpty) {
      canvas = DecoratedBox(
        decoration: BoxDecoration(boxShadow: boxShadow),
        child: canvas,
      );
    }
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            canvas,
            child,
          ],
        ),
      ),
    );
  }
}

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
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          LuxeCanvas(dark: dark),
          child,
        ],
      ),
    );
  }
}
