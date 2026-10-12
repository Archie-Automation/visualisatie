import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Statuslamp: de omtrek blijft stil. Het draadje in de bol
/// dooft en komt terug.
class LightStatusIcon extends StatefulWidget {
  const LightStatusIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  State<LightStatusIcon> createState() => _LightStatusIconState();
}

class _LightStatusIconState extends State<LightStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
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
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: widget.size,
                color: widget.color,
              ),
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _FilamentPainter(
                  color: widget.color,
                  t: _ctrl.value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilamentPainter extends CustomPainter {
  _FilamentPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final phase = t * math.pi * 2;
    final glow = ((math.sin(phase) + 1) / 2).clamp(0.0, 1.0);
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.04).clamp(0.85, 1.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: glow);

    final cx = w * 0.50;
    final half = w * 0.075;
    final crown = h * 0.30;
    final foot = h * 0.46;
    final path = Path()
      ..moveTo(cx - half, foot)
      ..lineTo(cx - half, crown + half)
      ..arcToPoint(
        Offset(cx + half, crown + half),
        radius: Radius.circular(half),
        clockwise: false,
      )
      ..lineTo(cx + half, foot);
    canvas.drawPath(path, wire);
  }

  @override
  bool shouldRepaint(covariant _FilamentPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.t != t;
}
