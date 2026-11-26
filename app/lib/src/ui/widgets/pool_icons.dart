import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData poolCoverIconData = IconData(0xF003);

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData jetstreamIconData = IconData(0xF004);

/// Zwembad met roldek: oprolas bovenaan, twee lamellen over het bad en
/// open water eronder.
class PoolCoverIcon extends StatelessWidget {
  const PoolCoverIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PoolCoverPainter(color),
        size: Size(size, size),
      );
}

/// Tegenstroominstallatie: wandunit met spuitmond, waterstralen naar rechts
/// en een golf eronder.
class JetstreamIcon extends StatelessWidget {
  const JetstreamIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _JetstreamPainter(color),
        size: Size(size, size),
      );
}

Path _wave({
  required double left,
  required double right,
  required double y,
  required double amp,
  double periods = 2,
}) {
  const steps = 32;
  final path = Path();
  for (var k = 0; k <= steps; k++) {
    final f = k / steps;
    final x = left + (right - left) * f;
    final dy = math.sin(f * math.pi * 2 * periods) * amp;
    if (k == 0) {
      path.moveTo(x, y + dy);
    } else {
      path.lineTo(x, y + dy);
    }
  }
  return path;
}

Paint _pen(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _PoolCoverPainter extends CustomPainter {
  _PoolCoverPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = materialOutlineStroke(s);
    final line = _pen(color, stroke);

    // Oprolas: gevulde capsule over de volle breedte.
    final roller = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.08, s * 0.10, s * 0.92, s * 0.24),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(roller, Paint()..color = color);

    // Bak: U-vorm onder de as.
    final l = s * 0.16;
    final r = s * 0.84;
    final b = s * 0.90;
    final corner = s * 0.08;
    final basin = Path()
      ..moveTo(l, s * 0.24)
      ..lineTo(l, b - corner)
      ..quadraticBezierTo(l, b, l + corner, b)
      ..lineTo(r - corner, b)
      ..quadraticBezierTo(r, b, r, b - corner)
      ..lineTo(r, s * 0.24);
    canvas.drawPath(basin, line);

    // Lamellen van het afgerolde dek.
    final slat = _pen(color, stroke * 0.8);
    for (final y in const [0.38, 0.52]) {
      canvas.drawLine(Offset(l, s * y), Offset(r, s * y), slat);
    }

    // Open water onder het dek.
    canvas.drawPath(
      _wave(
        left: l + stroke * 1.2,
        right: r - stroke * 1.2,
        y: s * 0.71,
        amp: s * 0.035,
      ),
      _pen(color, stroke * 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _PoolCoverPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _JetstreamPainter extends CustomPainter {
  _JetstreamPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = materialOutlineStroke(s);
    final line = _pen(color, stroke);

    // Wandunit met spuitmond.
    final unit = Rect.fromLTRB(s * 0.08, s * 0.14, s * 0.30, s * 0.62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(unit, Radius.circular(s * 0.06)),
      line,
    );
    canvas.drawCircle(unit.center, s * 0.045, Paint()..color = color);

    // Stralen: middelste het langst, met pijlpunt.
    final jet = _pen(color, stroke * 0.85);
    final x0 = s * 0.40;
    final yMid = unit.center.dy;
    final gap = s * 0.15;
    canvas.drawLine(Offset(x0, yMid - gap), Offset(s * 0.76, yMid - gap), jet);
    canvas.drawLine(Offset(x0, yMid + gap), Offset(s * 0.76, yMid + gap), jet);
    final tip = Offset(s * 0.92, yMid);
    canvas.drawLine(Offset(x0, yMid), tip, jet);
    final head = s * 0.09;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - head, yMid - head)
        ..lineTo(tip.dx, yMid)
        ..lineTo(tip.dx - head, yMid + head),
      jet,
    );

    // Wateroppervlak.
    canvas.drawPath(
      _wave(left: s * 0.08, right: s * 0.92, y: s * 0.82, amp: s * 0.04),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _JetstreamPainter oldDelegate) =>
      oldDelegate.color != color;
}
