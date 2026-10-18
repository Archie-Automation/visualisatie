import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Dubbele inrijpoort: twee stijlen, regels en een schoor per vleugel.
class GateIcon extends StatelessWidget {
  const GateIcon({
    super.key,
    required this.size,
    required this.color,
    this.strokeScale = 1,
  });

  final double size;
  final Color color;

  /// 1 naast een Material-icoon van dezelfde maat. [gateButtonStrokeScale] op de belknop.
  final double strokeScale;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GateIconPainter(color, strokeScale),
    );
  }
}

class _GateIconPainter extends CustomPainter {
  _GateIconPainter(this.color, this.strokeScale);

  final Color color;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final stroke = materialOutlineStroke(size.width) * strokeScale;
    final bar = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double x, double y) => Offset(x * u, y * u);
    void line(double x1, double y1, double x2, double y2, Paint paint) {
      canvas.drawLine(p(x1, y1), p(x2, y2), paint);
    }

    line(3.6, 2.6, 3.6, 21.4, bar);
    line(20.4, 2.6, 20.4, 21.4, bar);

    line(3.6, 6.4, 20.4, 6.4, bar);
    line(3.6, 19.2, 20.4, 19.2, bar);

    line(7.0, 6.4, 7.0, 19.2, bar);
    line(10.5, 6.4, 10.5, 19.2, bar);
    line(13.5, 6.4, 13.5, 19.2, bar);
    line(17.0, 6.4, 17.0, 19.2, bar);

    line(5.2, 19.2, 10.5, 6.4, bar);
    line(18.8, 19.2, 13.5, 6.4, bar);
  }

  @override
  bool shouldRepaint(covariant _GateIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeScale != strokeScale;
}
