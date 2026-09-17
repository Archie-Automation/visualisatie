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
      // Phone: grotere cellen = minder paths onder scroll.
      hexSize: context.isPhone ? 64 : 56,
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
            antiAlias: !context.isPhone,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _HoneycombPainter extends CustomPainter {
  _HoneycombPainter({
    required this.color,
    required this.hexSize,
    required this.antiAlias,
  });

  final Color color;
  final double hexSize;
  final bool antiAlias;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || hexSize <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..isAntiAlias = antiAlias;

    // Pointy-top hex grid — one path, one stroke.
    final w = math.sqrt(3) * hexSize;
    final h = 1.5 * hexSize;
    final cols = (size.width / w).ceil() + 2;
    final rows = (size.height / h).ceil() + 2;
    final path = Path();

    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final cx = col * w + (row.isOdd ? w * 0.5 : 0);
        final cy = row * h;
        _addHex(path, Offset(cx, cy), hexSize);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _addHex(Path path, Offset center, double r) {
    for (var i = 0; i < 6; i++) {
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
  }

  @override
  bool shouldRepaint(covariant _HoneycombPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.hexSize != hexSize ||
      oldDelegate.antiAlias != antiAlias;
}
