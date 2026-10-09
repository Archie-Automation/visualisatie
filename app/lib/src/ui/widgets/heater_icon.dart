import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Hangende terrasheater (plafond): ophanging, paneel, warmte naar beneden.
/// Warmteslierten animeren als [animate].
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

    canvas.drawLine(
      Offset(w * 0.18, h * 0.08),
      Offset(w * 0.82, h * 0.08),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.30, h * 0.08),
      Offset(w * 0.30, h * 0.22),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.70, h * 0.08),
      Offset(w * 0.70, h * 0.22),
      line,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.12, h * 0.22, w * 0.88, h * 0.50),
        Radius.circular(w * 0.08),
      ),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.22, h * 0.40),
      Offset(w * 0.78, h * 0.40),
      line,
    );

    final heat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.7
      ..strokeCap = StrokeCap.round;
    const slots = <(double, double)>[
      (0.30, -1),
      (0.50, 0),
      (0.70, 1),
    ];
    for (var i = 0; i < slots.length; i++) {
      final (xFrac, bendSign) = slots[i];
      var pulse = 1.0;
      if (animate) {
        final phase = t * 2 * math.pi + i * 0.9;
        pulse = 0.35 + 0.65 * ((math.sin(phase) + 1) / 2);
      }
      final len = h * 0.22 * (animate ? (0.5 + 0.5 * pulse) : 1.0);
      heat.color = color.withValues(
        alpha: animate ? pulse.clamp(0.28, 1.0) : 0.8,
      );
      final x = w * xFrac;
      final top = h * 0.54;
      final bend = w * 0.045 * bendSign;
      final path = Path()
        ..moveTo(x, top)
        ..quadraticBezierTo(
          x + bend,
          top + len * 0.55,
          x + bend * 0.2,
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
