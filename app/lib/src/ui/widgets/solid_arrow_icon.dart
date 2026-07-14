import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Richting van een pijl met lijn + solid driehoekpunt (zoals oorspronkelijke iconen).
enum DeviceArrowDirection {
  up,
  down,
  southWest,
  northEast,
  /// Gordijn open: ← → (pijlen naar buiten, lange schacht).
  horizontalOpen,
  /// Gordijn dicht: → ← (pijlen naar binnen, lange schacht).
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

  bool get _isHorizontalPair =>
      direction == DeviceArrowDirection.horizontalOpen ||
      direction == DeviceArrowDirection.horizontalClose;

  @override
  Widget build(BuildContext context) {
    // Gordijn: twee pijlen naast elkaar — breder canvas voor zichtbare punten.
    final width = _isHorizontalPair ? size * 1.65 : size;
    return SizedBox(
      width: width,
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

  bool get _isVertical =>
      direction == DeviceArrowDirection.up ||
      direction == DeviceArrowDirection.down;

  @override
  void paint(Canvas canvas, Size size) {
    switch (direction) {
      case DeviceArrowDirection.horizontalOpen:
        _drawHorizontalPair(canvas, size, outward: true);
      case DeviceArrowDirection.horizontalClose:
        _drawHorizontalPair(canvas, size, outward: false);
      default:
        final (Offset tip, Offset tail) = _tipAndTail(size);
        _drawArrow(
          canvas,
          size,
          tip: tip,
          tail: tail,
          headFraction: 0.42,
          headCap: size.shortestSide * 0.44,
          headWidth: 0.62,
        );
    }
  }

  /// Gordijn: ← → of → ← met duidelijke driehoekpunten aan de buiten-/binnenkant.
  void _drawHorizontalPair(Canvas canvas, Size size, {required bool outward}) {
    final cy = size.height / 2;
    final w = size.width;
    final tipPad = 1.5;
    final centerGap = w * 0.06;
    final mid = w / 2;
    final leftInner = mid - centerGap;
    final rightInner = mid + centerGap;
    final headCap = size.height * 0.46;

    if (outward) {
      _drawArrow(
        canvas,
        size,
        tip: Offset(tipPad, cy),
        tail: Offset(leftInner, cy),
        headFraction: 0.48,
        headCap: headCap,
        headWidth: 0.58,
      );
      _drawArrow(
        canvas,
        size,
        tip: Offset(w - tipPad, cy),
        tail: Offset(rightInner, cy),
        headFraction: 0.48,
        headCap: headCap,
        headWidth: 0.58,
      );
    } else {
      _drawArrow(
        canvas,
        size,
        tip: Offset(leftInner, cy),
        tail: Offset(tipPad, cy),
        headFraction: 0.48,
        headCap: headCap,
        headWidth: 0.58,
      );
      _drawArrow(
        canvas,
        size,
        tip: Offset(rightInner, cy),
        tail: Offset(w - tipPad, cy),
        headFraction: 0.48,
        headCap: headCap,
        headWidth: 0.58,
      );
    }
  }

  void _drawArrow(
    Canvas canvas,
    Size size, {
    required Offset tip,
    required Offset tail,
    double headFraction = 0.38,
    double headCap = 0,
    double headWidth = 0.55,
  }) {
    final vec = tail - tip;
    final shaftLen = vec.distance;
    if (shaftLen < 0.5) return;

    final shaft = Offset(vec.dx / shaftLen, vec.dy / shaftLen);
    final maxHead = headCap > 0 ? headCap : size.shortestSide * 0.38;
    final headLen = math.min(maxHead, shaftLen * headFraction);
    if (headLen < 1.2) return;

    final halfBase = headLen * headWidth;
    final baseCenter = tip + shaft * headLen;
    final normal = Offset(-shaft.dy, shaft.dx);

    final strokeW = DeviceControlIcons.graphicStrokeFor(size.shortestSide);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = _isVertical ? strokeW * 1.15 : strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (shaftLen > headLen + 0.5) {
      canvas.drawLine(tail, baseCenter, stroke);
    }

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
    final tipPad = size.shortestSide * 0.1;
    final tailPad = size.shortestSide * 0.14;
    return switch (direction) {
      DeviceArrowDirection.up => (
          Offset(w / 2, tipPad),
          Offset(w / 2, h - tailPad),
        ),
      DeviceArrowDirection.down => (
          Offset(w / 2, h - tipPad),
          Offset(w / 2, tailPad),
        ),
      DeviceArrowDirection.southWest => (
          Offset(tipPad, h - tipPad),
          Offset(w - tailPad, tailPad),
        ),
      DeviceArrowDirection.northEast => (
          Offset(w - tipPad, tipPad),
          Offset(tailPad, h - tailPad),
        ),
      DeviceArrowDirection.horizontalOpen ||
      DeviceArrowDirection.horizontalClose =>
        (Offset.zero, Offset.zero),
    };
  }

  @override
  bool shouldRepaint(covariant _SolidArrowPainter oldDelegate) =>
      oldDelegate.direction != direction || oldDelegate.color != color;
}
