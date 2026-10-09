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
    final stroke = (w * 0.09).clamp(1.5, 2.8);

    final logs = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.14, h * 0.74),
      Offset(w * 0.86, h * 0.92),
      logs,
    );
    canvas.drawLine(
      Offset(w * 0.14, h * 0.92),
      Offset(w * 0.86, h * 0.74),
      logs,
    );

    final phase = t * 2 * math.pi;
    final flicker = 0.84 + 0.16 * ((math.sin(phase * 1.7) + 1) / 2);
    final sway = math.sin(phase * 1.3) * w * 0.035;
    final baseY = h * 0.70;

    canvas.save();
    canvas.translate(w * 0.5 + sway, baseY);
    canvas.scale(0.92 + 0.08 * flicker, flicker);
    canvas.translate(-w * 0.5, -baseY);

    final flame = Path()
      ..moveTo(w * 0.50, h * 0.06)
      ..cubicTo(w * 0.78, h * 0.28, w * 0.70, h * 0.52, w * 0.58, h * 0.66)
      ..quadraticBezierTo(w * 0.50, h * 0.72, w * 0.42, h * 0.66)
      ..cubicTo(w * 0.30, h * 0.52, w * 0.22, h * 0.28, w * 0.50, h * 0.06)
      ..close();
    canvas.drawPath(flame, Paint()..color = color);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampfirePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.t != t;
}
