import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Kampvuur: twee stronken stil, vlam erboven flikkert.
class CampfireIcon extends StatefulWidget {
  const CampfireIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  State<CampfireIcon> createState() => _CampfireIconState();
}

class _CampfireIconState extends State<CampfireIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _CampfirePainter(
            color: widget.color,
            t: _ctrl.value,
          ),
        ),
      ),
    );
  }
}

class _CampfirePainter extends CustomPainter {
  _CampfirePainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final logStroke = (w * 0.042).clamp(0.85, 1.45);
    final logs = Paint()
      ..color = color.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = logStroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.20, h * 0.78),
      Offset(w * 0.82, h * 0.90),
      logs,
    );
    canvas.drawLine(
      Offset(w * 0.18, h * 0.90),
      Offset(w * 0.78, h * 0.76),
      logs,
    );

    final phase = t * 2 * math.pi;
    final flicker = 0.90 + 0.10 * ((math.sin(phase * 1.7) + 1) / 2);
    final sway = math.sin(phase * 1.2) * w * 0.02;
    final baseY = h * 0.72;

    canvas.save();
    canvas.translate(w * 0.5 + sway, baseY);
    canvas.scale(1, flicker);
    canvas.translate(-w * 0.5, -baseY);

    final flameStroke = (w * 0.062).clamp(1.15, 1.9);
    final flame = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = flameStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Punt, zijlob en inkeping — geen symmetrische druppel.
    final outer = Path()
      ..moveTo(w * 0.50, h * 0.06)
      ..cubicTo(w * 0.70, h * 0.20, w * 0.78, h * 0.36, w * 0.62, h * 0.46)
      ..cubicTo(w * 0.82, h * 0.52, w * 0.68, h * 0.66, w * 0.54, h * 0.70)
      ..quadraticBezierTo(w * 0.46, h * 0.74, w * 0.40, h * 0.68)
      ..cubicTo(w * 0.24, h * 0.60, w * 0.18, h * 0.44, w * 0.34, h * 0.36)
      ..cubicTo(w * 0.26, h * 0.24, w * 0.36, h * 0.12, w * 0.50, h * 0.06);
    canvas.drawPath(outer, flame);

    final innerPulse = 0.75 + 0.25 * ((math.sin(phase * 2.1 + 1.2) + 1) / 2);
    final inner = Path()
      ..moveTo(w * 0.50, h * 0.28)
      ..cubicTo(w * 0.60, h * 0.40, w * 0.58, h * 0.54, w * 0.50, h * 0.62)
      ..cubicTo(w * 0.40, h * 0.52, w * 0.40, h * 0.38, w * 0.50, h * 0.28);
    canvas.drawPath(
      inner,
      Paint()
        ..color = color.withValues(alpha: innerPulse.clamp(0.35, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = flameStroke * 0.65
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampfirePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.t != t;
}
