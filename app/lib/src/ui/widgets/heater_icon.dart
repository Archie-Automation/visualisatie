import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Hangende terrasheater: paneel met golvende gloeispiralen en warmte naar beneden.
/// Spiralen en warmtestrepen bewegen als [animate].
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

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.10, h * 0.06, w * 0.90, h * 0.58),
        Radius.circular(w * 0.1),
      ),
      line,
    );

    final coil = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const rows = <double>[0.18, 0.32, 0.46];
    for (var i = 0; i < rows.length; i++) {
      final phase = animate ? t * 2 * math.pi + i * 0.9 : i * 0.6;
      var pulse = 0.9;
      if (animate) {
        pulse = 0.45 + 0.55 * ((math.sin(phase) + 1) / 2);
      }
      coil.color = color.withValues(alpha: pulse.clamp(0.4, 1.0));
      _glowCoil(
        canvas,
        coil,
        y: h * rows[i],
        left: w * 0.22,
        right: w * 0.78,
        amp: h * 0.04,
        phase: phase,
      );
    }

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
      final len = h * 0.2 * (animate ? (0.5 + 0.5 * pulse) : 1.0);
      heat.color = color.withValues(
        alpha: animate ? pulse.clamp(0.28, 1.0) : 0.8,
      );
      final x = w * xFrac;
      final top = h * 0.66;
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

  void _glowCoil(
    Canvas canvas,
    Paint paint, {
    required double y,
    required double left,
    required double right,
    required double amp,
    required double phase,
  }) {
    const steps = 18;
    final path = Path();
    for (var s = 0; s <= steps; s++) {
      final u = s / steps;
      final x = left + (right - left) * u;
      final yy = y + math.sin(u * math.pi * 5 + phase) * amp;
      if (s == 0) {
        path.moveTo(x, yy);
      } else {
        path.lineTo(x, yy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate;
}
