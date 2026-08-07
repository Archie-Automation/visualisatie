import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Indoor split-unit: body stil, 3 dunne verticale luchtstrepen animeren.
class SplitUnitIcon extends StatefulWidget {
  const SplitUnitIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  State<SplitUnitIcon> createState() => _SplitUnitIconState();
}

class _SplitUnitIconState extends State<SplitUnitIcon>
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
          painter: _SplitUnitIconPainter(
            color: widget.color,
            t: _ctrl.value,
          ),
        ),
      ),
    );
  }
}

class _SplitUnitIconPainter extends CustomPainter {
  _SplitUnitIconPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.078).clamp(1.4, 2.4);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bodyTop = h * 0.10;
    final bodyBottom = h * 0.52;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.08, bodyTop, w * 0.92, bodyBottom),
      Radius.circular(w * 0.07),
    );
    canvas.drawRRect(body, paint);

    final ventY = bodyTop + (bodyBottom - bodyTop) * 0.72;
    canvas.drawLine(
      Offset(w * 0.18, ventY),
      Offset(w * 0.82, ventY),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.9
        ..strokeCap = StrokeCap.round,
    );

    final ledY = bodyTop + (bodyBottom - bodyTop) * 0.28;
    canvas.drawLine(
      Offset(w * 0.72, ledY),
      Offset(w * 0.82, ledY),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.85
        ..strokeCap = StrokeCap.round,
    );

    // Drie dunne verticale luchtstrepen — opacity/lengte pulse, unit stil.
    final airTop = bodyBottom + h * 0.07;
    final airBottom = h * 0.94;
    final xs = [w * 0.32, w * 0.50, w * 0.68];
    final bends = [-w * 0.04, 0.0, w * 0.04];

    for (var i = 0; i < 3; i++) {
      final phase = t * 2 * math.pi + i * 0.9;
      final pulse = 0.35 + 0.65 * ((math.sin(phase) + 1) / 2);
      final length = 0.55 + 0.45 * pulse;
      final bottomY = airTop + (airBottom - airTop) * length;
      final x = xs[i];
      final bend = bends[i];

      final path = Path()
        ..moveTo(x, airTop)
        ..quadraticBezierTo(
          x + bend,
          (airTop + bottomY) / 2,
          x + bend * 0.35,
          bottomY,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: pulse.clamp(0.25, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.72
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplitUnitIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.t != t;
}
