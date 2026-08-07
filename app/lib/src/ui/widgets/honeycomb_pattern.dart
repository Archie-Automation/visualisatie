import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../responsive.dart';

/// Heel subtiel honingraat-raster. Goedkoop: grote cellen, alleen strokes.
class HoneycombPattern extends StatelessWidget {
  const HoneycombPattern({
    super.key,
    required this.color,
    this.opacity = 0.035,
    this.hexSize = 52,
  });

  final Color color;
  final double opacity;
  final double hexSize;

  /// Zelfde dichtheid/tint als [LuxeBackdrop] — voor overlays op sticky bars.
  static HoneycombPattern ambient(BuildContext context, {bool? dark}) {
    final useDark =
        dark ?? Theme.of(context).brightness == Brightness.dark;
    final p = Theme.of(context).extension<LuxePalette>() ??
        (useDark ? LuxePalette.dark : LuxePalette.light);
    return HoneycombPattern(
      color: useDark ? Colors.white : p.ink,
      opacity: useDark ? 0.028 : 0.07,
      hexSize: context.isPhone ? 40 : 56,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HoneycombPainter(
            color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
            hexSize: hexSize,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Sticky header fill die scroll-content afdekt maar het honingraat-profiel houdt.
/// Canvas-kleur volgt [LuxeBackdrop] (cream), niet chip-surface — anders oogt de balk anders.
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

  Color _canvasColor(BuildContext context) {
    final useDark = Theme.of(context).brightness == Brightness.dark;
    final p = Theme.of(context).extension<LuxePalette>() ??
        (useDark ? LuxePalette.dark : LuxePalette.light);
    final phoneLight = !useDark && context.isPhone;
    final base = phoneLight ? LuxePalette.phoneCream : p.cream;
    // Dark: lichter over de canvas laten schemeren — opaque cream oogt te zwaar.
    if (useDark) return base.withValues(alpha: 0.62);
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: height,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: _canvasColor(context),
          border: Border(
            bottom: BorderSide(
              color: LuxeColors.line.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          boxShadow: boxShadow,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            HoneycombPattern.ambient(context),
            child,
          ],
        ),
      ),
    );
  }
}

class _HoneycombPainter extends CustomPainter {
  _HoneycombPainter({required this.color, required this.hexSize});

  final Color color;
  final double hexSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || hexSize <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..isAntiAlias = true;

    // Pointy-top hex grid.
    final w = math.sqrt(3) * hexSize;
    final h = 1.5 * hexSize;
    final cols = (size.width / w).ceil() + 2;
    final rows = (size.height / h).ceil() + 2;

    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final cx = col * w + (row.isOdd ? w * 0.5 : 0);
        final cy = row * h;
        _drawHex(canvas, Offset(cx, cy), hexSize, paint);
      }
    }
  }

  void _drawHex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      // Pointy-top: start at -90°.
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = Offset(
        center.dx + r * math.cos(a),
        center.dy + r * math.sin(a),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HoneycombPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.hexSize != hexSize;
}
