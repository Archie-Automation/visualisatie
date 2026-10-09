import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Terrasheater: reflector, paal en voet. Warmteslierten onder de kap
/// animeren als [animate].
class HeaterIcon extends StatefulWidget {
  const HeaterIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = false,
  });

  final double size;
  final Color color;
  final bool animate;

  @override
  State<HeaterIcon> createState() => _HeaterIconState();
}

class _HeaterIconState extends State<HeaterIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1750),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant HeaterIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        _ctrl ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1750),
        )..repeat();
      } else {
        _ctrl?.dispose();
        _ctrl = null;
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget paint(double t) => CustomPaint(
          painter: _HeaterIconPainter(
            color: widget.color,
            t: t,
            animate: widget.animate,
          ),
        );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _ctrl == null
          ? paint(0)
          : AnimatedBuilder(
              animation: _ctrl!,
              builder: (_, __) => paint(_ctrl!.value),
            ),
    );
  }
}

/// Custom icoon voor `universal.icon == 'heater'`.
Widget? universalIconGlyph(
  String? name, {
  required double size,
  required Color color,
}) {
  if (name == 'heater') return HeaterIcon(size: size, color: color);
  return null;
}

Widget? iconWidgetForData(
  IconData? icon, {
  required double size,
  required Color color,
}) {
  if (icon == heaterIconData) return HeaterIcon(size: size, color: color);
  return null;
}

class _HeaterIconPainter extends CustomPainter {
  _HeaterIconPainter({
    required this.color,
    required this.t,
    required this.animate,
  });

  final Color color;
  final double t;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.072).clamp(1.3, 2.2);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dome = Path()
      ..moveTo(w * 0.16, h * 0.32)
      ..quadraticBezierTo(w * 0.50, h * 0.02, w * 0.84, h * 0.32);
    canvas.drawPath(dome, line);
    canvas.drawLine(
      Offset(w * 0.12, h * 0.34),
      Offset(w * 0.88, h * 0.34),
      line,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.40, h * 0.37, w * 0.60, h * 0.50),
        Radius.circular(w * 0.04),
      ),
      line,
    );

    canvas.drawLine(
      Offset(w * 0.50, h * 0.50),
      Offset(w * 0.50, h * 0.74),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.50, h * 0.70),
      Offset(w * 0.22, h * 0.94),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.50, h * 0.70),
      Offset(w * 0.78, h * 0.94),
      line,
    );

    final heat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.72
      ..strokeCap = StrokeCap.round;
    const slots = <(double, double)>[
      (0.28, -1),
      (0.72, 1),
    ];
    for (var i = 0; i < slots.length; i++) {
      final (xFrac, bendSign) = slots[i];
      var pulse = 1.0;
      if (animate) {
        final phase = t * 2 * math.pi + i * 1.4;
        pulse = 0.35 + 0.65 * ((math.sin(phase) + 1) / 2);
      }
      final len = h * 0.16 * (animate ? (0.55 + 0.45 * pulse) : 1.0);
      heat.color = color.withValues(
        alpha: animate ? pulse.clamp(0.3, 1.0) : 0.85,
      );
      final x = w * xFrac;
      final top = h * 0.38;
      final bend = w * 0.05 * bendSign;
      final path = Path()
        ..moveTo(x, top)
        ..quadraticBezierTo(
          x + bend,
          top + len * 0.55,
          x + bend * 0.25,
          top + len,
        );
      canvas.drawPath(path, heat);
    }
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate;
}
