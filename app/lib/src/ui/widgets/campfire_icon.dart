import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Oude flikkerende vlam, met twee lichtere stronken eronder.
/// Alleen de contour, zodat het hout niet massief ingekleurd is.
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
        builder: (_, __) {
          final t = _ctrl.value * 2 * math.pi;
          final scale =
              0.82 + 0.18 * ((math.sin(t * 1.7) + math.sin(t * 2.3) + 2) / 4);
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _CampfireLogsPainter(color: widget.color),
              ),
              Align(
                alignment: const Alignment(0, -0.48),
                child: Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    size: widget.size * 0.86,
                    color: widget.color,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CampfireLogsPainter extends CustomPainter {
  _CampfireLogsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final logs = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.07).clamp(1.15, 1.7)
      ..strokeJoin = StrokeJoin.round;

    _drawLog(
      canvas,
      logs,
      Offset(w * 0.14, h * 0.74),
      Offset(w * 0.86, h * 0.90),
      w * 0.22,
    );
    _drawLog(
      canvas,
      logs,
      Offset(w * 0.14, h * 0.90),
      Offset(w * 0.86, h * 0.74),
      w * 0.22,
    );
  }

  void _drawLog(Canvas canvas, Paint paint, Offset a, Offset b, double girth) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: (b - a).distance,
          height: girth,
        ),
        Radius.circular(girth / 2),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampfireLogsPainter oldDelegate) =>
      oldDelegate.color != color;
}
