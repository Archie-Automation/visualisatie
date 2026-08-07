import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Outline-lampje + vaste dunne lichtstraaltjes (geen animatie).
class LightStatusIcon extends StatelessWidget {
  const LightStatusIcon({
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
        painter: _LightRaysPainter(color: color),
        child: Center(
          child: Icon(
            Icons.lightbulb_outline_rounded,
            size: size * 0.82,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _LightRaysPainter extends CustomPainter {
  _LightRaysPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.40;
    final r = w * 0.32;
    // Dunner dan het Material-lampje (~1.5–2px stroke).
    final stroke = (w * 0.045).clamp(0.9, 1.5);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Vijf stralen tot voorbij horizontaal.
    const angles = <double>[
      -math.pi * 1.08,
      -math.pi * 0.78,
      -math.pi * 0.5,
      -math.pi * 0.22,
      math.pi * 0.08,
    ];

    const innerPad = 0.02;
    const outerPad = 0.20;

    for (final a in angles) {
      final inner = r + w * innerPad;
      final outer = r + w * outerPad;
      final ox = math.cos(a);
      final oy = math.sin(a);
      canvas.drawLine(
        Offset(cx + ox * inner, cy + oy * inner),
        Offset(cx + ox * outer, cy + oy * outer),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LightRaysPainter oldDelegate) =>
      oldDelegate.color != color;
}
