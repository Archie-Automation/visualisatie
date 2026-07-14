import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// A frosted, translucent surface – the visual workhorse of the app.
///
/// The effect is built from three stacked layers:
///   1. `BackdropFilter` (sigma 24) to blur whatever sits behind it.
///   2. A near-white warm tint so text stays readable on any backdrop.
///   3. A 1px inner "light rim" (top-left) that mimics glass refraction.
///
/// Use sparingly on large surfaces – heavy blurs are expensive on web/low-end.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(24),
    this.tint,
    this.onTap,
    this.shadows = LuxeShadows.soft,
    this.blurSigma = 18,
    this.heroTag,
    this.border = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final VoidCallback? onTap;
  final List<BoxShadow> shadows;
  final double blurSigma;
  final Object? heroTag;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final effectiveTint = tint ?? LuxeColors.surface.withValues(alpha: 0.72);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              color: effectiveTint,
              borderRadius: BorderRadius.circular(radius),
              border: border
                  ? Border.all(color: LuxeColors.glassRim, width: 1)
                  : null,
            ),
            child: Stack(
              children: [
                // Top inner highlight – gives glass its refractive feel.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: radius + 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(radius)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );

    if (heroTag != null) card = Hero(tag: heroTag!, child: card);

    if (onTap != null) {
      card = PressScale(
        onTap: onTap!,
        radius: radius,
        child: card,
      );
    }

    return card;
  }
}

/// A warm, dense variant: nearly opaque, used when we stack it over busy
/// images (like the cover art tile) where we still need readable text.
class SolidGlassCard extends StatelessWidget {
  const SolidGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
    this.color,
    this.onTap,
    this.shadows = LuxeShadows.soft,
    this.heroTag,
    this.hairline = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final List<BoxShadow> shadows;
  final Object? heroTag;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? LuxeColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: hairline
            ? Border.all(color: LuxeColors.lineSoft, width: 1)
            : null,
        boxShadow: shadows,
      ),
      child: child,
    );

    if (heroTag != null) card = Hero(tag: heroTag!, child: card);

    if (onTap != null) {
      card = PressScale(
        onTap: onTap!,
        radius: radius,
        child: card,
      );
    }

    return card;
  }
}

/// Subtle scale-on-press wrapper. Feels considerably more "premium" than a
/// splash effect and doesn't clash with the glass refraction.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    required this.radius,
    this.onPressedChanged,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final ValueChanged<bool>? onPressedChanged;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onPressedChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.985 : 1.0,
        child: widget.child,
      ),
    );
  }
}
