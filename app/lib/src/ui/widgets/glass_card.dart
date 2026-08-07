import 'dart:ui';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../../theme.dart';

/// Frosted / elevated surface — the visual workhorse of the app.
///
/// Near-opaque tint + optional hairline. [BackdropFilter] is skipped on
/// Android (wall tablet / Impeller): blur is expensive under scroll and can
/// amplify banding against the ambient backdrop. Web/iOS keep a light blur.
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

  /// Blur is skipped on Android/web — Impeller + many cards while scrolling
  /// causes jank and can amplify backdrop banding.
  bool get _useBackdropBlur {
    if (blurSigma <= 0) return false;
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<LuxePalette>() ?? LuxeColors.active;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Light: zelfde luchtigheid als scene/systeem-chips (canvas doorschijnt).
    final alpha = _useBackdropBlur
        ? (isDark ? 0.88 : LuxeChipChrome.lightFill())
        : (isDark ? 0.90 : LuxeChipChrome.lightFill());
    final effectiveTint = tint ?? p.surface.withValues(alpha: alpha);
    final highlight = p.glassHighlight;

    Widget content = Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: radius + (isDark ? 14 : 10),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(radius)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    highlight,
                    highlight.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );

    if (_useBackdropBlur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      );
    }

    // Rim-box i.p.v. Border.all — voorkomt korrelige AA op Impeller.
    Widget card = border
        ? LuxeRimBox(
            radius: radius,
            rimWidth: 1,
            rimColor: LuxeBorders.solid(p.line),
            fillColor: effectiveTint,
            shadows: shadows,
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: effectiveTint,
              boxShadow: shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: content,
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
    final fill = color ?? LuxeColors.surface;
    Widget card = hairline
        ? LuxeRimBox(
            radius: radius,
            rimWidth: 1,
            rimColor: LuxeColors.lineSoft,
            fillColor: fill,
            shadows: shadows,
            padding: padding,
            child: child,
          )
        : Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: shadows,
            ),
            child: child,
          );

    if (heroTag != null) card = Hero(tag: heroTag!, child: card);
    if (onTap != null) {
      card = PressScale(onTap: onTap!, radius: radius, child: card);
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
