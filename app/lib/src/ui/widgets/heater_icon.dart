import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Gebaseerd op [Icons.wb_iridescent_outlined] (skylight) — zelfde balk,
/// warmtestralen **alleen omlaag**.
class HeaterIcon extends StatelessWidget {
  const HeaterIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeaterIconPainter(color: color),
      ),
    );
  }
}

/// Custom icoon voor `universal.icon == 'heater'`.
Widget? universalIconGlyph(
  String? name, {
  required double size,
  required Color color,
}) {
  if (name == 'heater') return HeaterIcon(size: size, color: color);
  return null;
}

Widget? iconWidgetForData(
  IconData? icon, {
  required double size,
  required Color color,
}) {
  if (icon == heaterIconData) return HeaterIcon(size: size, color: color);
  return null;
}

class _HeaterIconPainter extends CustomPainter {
  _HeaterIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.085).clamp(1.6, 2.6);

    // Horizontale balk — zelfde positie/vorm als wb_iridescent / skylight.
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.14, h * 0.22, w * 0.86, h * 0.38),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final rayPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.92
      ..strokeCap = StrokeCap.round;

    final rayTop = h * 0.42;
    final rayBottom = h * 0.9;
    final amplitude = w * 0.055;
    for (final cx in [w * 0.28, w * 0.5, w * 0.72]) {
      _drawDownWave(
        canvas,
        cx: cx,
        top: rayTop,
        bottom: rayBottom,
        amplitude: amplitude,
        paint: rayPaint,
      );
    }
  }

  /// Eén sinusachtige lijn die alleen naar beneden loopt (geen stralen omhoog).
  void _drawDownWave(
    Canvas canvas, {
    required double cx,
    required double top,
    required double bottom,
    required double amplitude,
    required Paint paint,
  }) {
    final path = Path()..moveTo(cx, top);
    const steps = 8;
    final dy = (bottom - top) / steps;
    for (var i = 1; i <= steps; i++) {
      final y = top + dy * i;
      final phase = i / steps * math.pi;
      final x = cx + math.sin(phase * 2.4 + cx) * amplitude;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
