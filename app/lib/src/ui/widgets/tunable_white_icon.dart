import 'package:flutter/material.dart';

/// Kleurtemperatuur: cirkel van warm wit naar koud wit.
///
/// Uit: alleen de ring, zoals een outlined icoon.
/// Aan: de schijf is gevuld.
class TunableWhiteIcon extends StatelessWidget {
  const TunableWhiteIcon({
    super.key,
    required this.size,
    required this.color,
    this.filled = false,
  });

  final double size;
  final Color color;
  final bool filled;

  static const warm = Color(0xFFFF9A3C);
  static const mid = Color(0xFFFFF3DC);
  static const cool = Color(0xFFCCE8FF);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TunableWhitePainter(color: color, filled: filled),
      ),
    );
  }
}

class _TunableWhitePainter extends CustomPainter {
  const _TunableWhitePainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = side * 0.36;
    final stroke = side * 0.075;
    final inner = filled ? radius - stroke * 0.45 : radius - stroke * 1.35;
    final disc = Rect.fromCircle(center: center, radius: inner);
    final shader = const LinearGradient(
      colors: [
        TunableWhiteIcon.warm,
        TunableWhiteIcon.mid,
        TunableWhiteIcon.cool,
      ],
    ).createShader(disc);

    canvas.drawCircle(center, inner, Paint()..shader = shader);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = filled ? stroke * 0.55 : stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TunableWhitePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.filled != filled;
  }
}
