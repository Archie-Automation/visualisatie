import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// open / half / dicht voor status-iconen; `half` voor installateur-chips.
enum ShadingArtState { open, half, closed }

/// Custom icoon per zonweringstype (installateur + tegel).
class ShadingSubtypeGlyph extends StatelessWidget {
  const ShadingSubtypeGlyph({
    super.key,
    required this.subtype,
    this.size = 28,
    this.color,
    this.state = ShadingArtState.half,
  });

  final ShadingSubtype subtype;
  final double size;
  final Color? color;
  final ShadingArtState state;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(
      size: Size.square(size),
      painter: ShadingSubtypeGlyphPainter(
        style: subtype.positionIconStyle,
        state: state,
        color: c,
      ),
    );
  }
}

class ShadingSubtypeGlyphPainter extends CustomPainter {
  ShadingSubtypeGlyphPainter({
    required this.style,
    required this.state,
    required this.color,
  });

  final ShadingPositionIconStyle style;
  final ShadingArtState state;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case ShadingPositionIconStyle.curtain:
        _paintCurtain(canvas, size, sheers: false);
      case ShadingPositionIconStyle.sheers:
        _paintCurtain(canvas, size, sheers: true);
      case ShadingPositionIconStyle.blinds:
        _paintBlinds(canvas, size);
      case ShadingPositionIconStyle.roller:
        _paintRoller(canvas, size);
      case ShadingPositionIconStyle.awning:
        _paintAwning(canvas, size);
      case ShadingPositionIconStyle.shutter:
        _paintShutter(canvas, size);
      case ShadingPositionIconStyle.screen:
        _paintScreen(canvas, size);
    }
  }

  double _stroke(Size size) => math.max(1.1, size.shortestSide * 0.07);

  void _paintShutter(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = w * 0.14;
    final right = w * 0.86;
    final track = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left - w * 0.04, h * 0.08, w * 0.04, h * 0.84),
        Radius.circular(w * 0.02),
      ),
      track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(right, h * 0.08, w * 0.04, h * 0.84),
        Radius.circular(w * 0.02),
      ),
      track,
    );

    final slatCount = switch (state) {
      ShadingArtState.open => 2,
      ShadingArtState.half => 4,
      ShadingArtState.closed => 6,
    };
    final top = h * 0.12;
    final bottom = switch (state) {
      ShadingArtState.open => h * 0.28,
      ShadingArtState.half => h * 0.58,
      ShadingArtState.closed => h * 0.88,
    };
    final gap = (bottom - top) / slatCount;
    final slatPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < slatCount; i++) {
      final y = top + i * gap;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y, right - left, gap * 0.55),
          Radius.circular(w * 0.02),
        ),
        slatPaint,
      );
    }
  }

  void _paintScreen(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = w * 0.20;
    final right = w * 0.80;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.12, h * 0.06, w * 0.76, h * 0.10),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = color.withValues(alpha: 0.9),
    );

    final (top, bottom) = switch (state) {
      ShadingArtState.open => (0.18, 0.32),
      ShadingArtState.half => (0.18, 0.58),
      ShadingArtState.closed => (0.18, 0.90),
    };

    final fabric = Rect.fromLTWH(left, h * top, right - left, h * (bottom - top));
    canvas.drawRRect(
      RRect.fromRectAndRadius(fabric, Radius.circular(w * 0.03)),
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );

    final mesh = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = _stroke(size) * 0.65
      ..style = PaintingStyle.stroke;
    for (var i = 0; i <= 4; i++) {
      final y = fabric.top + fabric.height * i / 4;
      canvas.drawLine(Offset(fabric.left, y), Offset(fabric.right, y), mesh);
    }
    for (var i = 0; i <= 3; i++) {
      final x = fabric.left + fabric.width * i / 3;
      canvas.drawLine(Offset(x, fabric.top), Offset(x, fabric.bottom), mesh);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(fabric, Radius.circular(w * 0.03)),
      Paint()
        ..color = color
        ..strokeWidth = _stroke(size)
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintBlinds(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = w * 0.12;
    final right = w * 0.88;
    final line = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _stroke(size)
      ..style = PaintingStyle.stroke;

    void slat(double yFactor) {
      canvas.drawLine(
        Offset(left, h * yFactor),
        Offset(right, h * yFactor),
        line,
      );
    }

    slat(0.14);
    final slats = switch (state) {
      ShadingArtState.open => [0.26, 0.36],
      ShadingArtState.half => [0.26, 0.40, 0.54, 0.68],
      ShadingArtState.closed => [0.26, 0.40, 0.54, 0.68, 0.82],
    };
    for (final t in slats) {
      slat(t);
    }
  }

  void _paintCurtain(Canvas canvas, Size size, {required bool sheers}) {
    final w = size.width;
    final h = size.height;
    final baseAlpha = sheers ? 0.38 : 1.0;
    final fill = Paint()
      ..color = color.withValues(alpha: baseAlpha)
      ..style = PaintingStyle.fill;

    void panel(double x, double width) {
      final rect = Rect.fromLTWH(x, h * 0.10, width, h * 0.80);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w * 0.05)),
        fill,
      );
      if (sheers) {
        final stripe = Paint()
          ..color = color.withValues(alpha: 0.25)
          ..strokeWidth = _stroke(size) * 0.55
          ..style = PaintingStyle.stroke;
        for (var i = 1; i <= 3; i++) {
          final sx = rect.left + rect.width * i / 4;
          canvas.drawLine(
            Offset(sx, rect.top + h * 0.04),
            Offset(sx, rect.bottom - h * 0.04),
            stripe,
          );
        }
      } else {
        final pleat = Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = _stroke(size) * 0.5
          ..style = PaintingStyle.stroke;
        for (var i = 1; i <= 4; i++) {
          final px = rect.left + rect.width * i / 5;
          canvas.drawLine(
            Offset(px, rect.top),
            Offset(px, rect.bottom),
            pleat,
          );
        }
      }
    }

    switch (state) {
      case ShadingArtState.open:
        panel(w * 0.06, w * 0.22);
        panel(w * 0.72, w * 0.22);
      case ShadingArtState.half:
        panel(w * 0.06, w * 0.38);
        panel(w * 0.56, w * 0.38);
      case ShadingArtState.closed:
        panel(w * 0.14, w * 0.72);
    }
  }

  void _paintRoller(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final left = w * 0.22;
    final right = w * 0.78;
    final (top, bottom) = switch (state) {
      ShadingArtState.open => (0.10, 0.28),
      ShadingArtState.half => (0.10, 0.55),
      ShadingArtState.closed => (0.10, 0.88),
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, h * top, right - left, h * (bottom - top)),
        Radius.circular(w * 0.05),
      ),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.06, w * 0.72, h * 0.08),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = color.withValues(alpha: 0.85),
    );
  }

  void _paintAwning(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color;

    // Uitvalscherm: cassette aan gevel, doek schuin naar beneden.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.08, w * 0.84, h * 0.07),
        Radius.circular(w * 0.02),
      ),
      Paint()..color = color.withValues(alpha: 0.85),
    );

    final path = Path();
    switch (state) {
      case ShadingArtState.open:
        path
          ..moveTo(w * 0.12, h * 0.16)
          ..lineTo(w * 0.88, h * 0.16)
          ..lineTo(w * 0.82, h * 0.26)
          ..lineTo(w * 0.18, h * 0.26);
      case ShadingArtState.half:
        path
          ..moveTo(w * 0.10, h * 0.16)
          ..lineTo(w * 0.90, h * 0.16)
          ..lineTo(w * 0.78, h * 0.52)
          ..lineTo(w * 0.22, h * 0.52);
      case ShadingArtState.closed:
        path
          ..moveTo(w * 0.08, h * 0.16)
          ..lineTo(w * 0.92, h * 0.16)
          ..lineTo(w * 0.76, h * 0.86)
          ..lineTo(w * 0.24, h * 0.86);
    }
    path.close();
    canvas.drawPath(path, fill);

    final seam = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = _stroke(size) * 0.6
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= 3; i++) {
      final t = i / 4;
      final y = h * (0.16 + (state == ShadingArtState.closed ? 0.70 : 0.36) * t);
      canvas.drawLine(Offset(w * 0.14, y), Offset(w * 0.86, y), seam);
    }
  }

  @override
  bool shouldRepaint(covariant ShadingSubtypeGlyphPainter old) =>
      old.style != style || old.state != state || old.color != color;
}
