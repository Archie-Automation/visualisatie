import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Richting van een pijl met lijn + solid driehoekpunt (zoals oorspronkelijke iconen).
enum DeviceArrowDirection {
  up,
  down,
  southWest,
  northEast,
  /// Gordijn open: ← → van elkaar af.
  horizontalOpen,
  /// Gordijn dicht: → ← naar elkaar toe.
  horizontalClose,
}

/// Pijl met dunne schacht en gevuld driehoekpunt — zelfde richtingen als de
/// oorspronkelijke Material-pijlen, solid tip zoals Sonos play.
class SolidArrowIcon extends StatelessWidget {
  const SolidArrowIcon({
    super.key,
    required this.direction,
    this.size = DeviceControlIcons.size,
    required this.color,
  });

  final DeviceArrowDirection direction;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SolidArrowPainter(direction: direction, color: color),
      ),
    );
  }
}

class _SolidArrowPainter extends CustomPainter {
  _SolidArrowPainter({required this.direction, required this.color});

  final DeviceArrowDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (direction) {
      case DeviceArrowDirection.horizontalOpen:
        _drawArrow(canvas, size, tip: Offset(2.5, size.height / 2), tail: Offset(size.width * 0.42, size.height / 2));
        _drawArrow(canvas, size, tip: Offset(size.width - 2.5, size.height / 2), tail: Offset(size.width * 0.58, size.height / 2));
      case DeviceArrowDirection.horizontalClose:
        _drawArrow(canvas, size, tip: Offset(size.width * 0.42, size.height / 2), tail: Offset(2.5, size.height / 2));
        _drawArrow(canvas, size, tip: Offset(size.width * 0.58, size.height / 2), tail: Offset(size.width - 2.5, size.height / 2));
      default:
        final (Offset tip, Offset tail) = _tipAndTail(size);
        _drawArrow(canvas, size, tip: tip, tail: tail);
    }
  }

  void _drawArrow(Canvas canvas, Size size, {required Offset tip, required Offset tail}) {
    final shaft = _unit(tail - tip);
    // Gelijkzijdige driehoek: hoogte = headLen, half basis = hoogte / √3.
    final headLen = size.shortestSide * 0.32;
    final halfBase = headLen / math.sqrt(3);
    final baseCenter = tip + shaft * headLen;
    final normal = Offset(-shaft.dy, shaft.dx);

    final stroke = Paint()
      ..color = color
      ..strokeWidth = DeviceControlIcons.graphicStroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawLine(tail, baseCenter, stroke);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseCenter.dx + normal.dx * halfBase,
          baseCenter.dy + normal.dy * halfBase)
      ..lineTo(baseCenter.dx - normal.dx * halfBase,
          baseCenter.dy - normal.dy * halfBase)
      ..close();
    canvas.drawPath(path, fill);
  }

  (Offset, Offset) _tipAndTail(Size size) {
    final w = size.width;
    final h = size.height;
    const p = 3.0;
    return switch (direction) {
      DeviceArrowDirection.up => (Offset(w / 2, p), Offset(w / 2, h - p)),
      DeviceArrowDirection.down => (Offset(w / 2, h - p), Offset(w / 2, p)),
      DeviceArrowDirection.southWest => (Offset(p, h - p), Offset(w - p, p)),
      DeviceArrowDirection.northEast => (Offset(w - p, p), Offset(p, h - p)),
      DeviceArrowDirection.horizontalOpen ||
      DeviceArrowDirection.horizontalClose =>
        (Offset.zero, Offset.zero),
    };
  }

  Offset _unit(Offset v) {
    final len = v.distance;
    if (len == 0) return Offset.zero;
    return Offset(v.dx / len, v.dy / len);
  }

  @override
  bool shouldRepaint(covariant _SolidArrowPainter oldDelegate) =>
      oldDelegate.direction != direction || oldDelegate.color != color;
}
