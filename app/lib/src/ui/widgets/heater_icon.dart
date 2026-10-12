import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Hangende heater: plafondbeugel, gloeispiraal, hittestraaltjes.
/// De spiraal gloeit en de stralen bewegen als [animate].
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
  if (icon == campfireIconData) {
    return CampfireIcon(size: size, color: color, animate: false);
  }
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
    final stroke = (w * 0.05).clamp(1.05, 1.45);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.40, h * 0.08, w * 0.60, h * 0.125),
        Radius.circular(w * 0.02),
      ),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.5, h * 0.125),
      Offset(w * 0.5, h * 0.20),
      line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.18, h * 0.20, w * 0.82, h * 0.52),
        Radius.circular(w * 0.08),
      ),
      line,
    );
    final coilGlow = animate
        ? (0.35 + 0.65 * ((math.sin(t * math.pi * 2) + 1) / 2))
        : 1.0;
    final coil = Paint()
      ..color = color.withValues(alpha: coilGlow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final coilPath = Path();
    const turns = 4;
    final coilLeft = w * 0.30;
    final coilRight = w * 0.70;
    final coilTop = h * 0.28;
    final coilBot = h * 0.44;
    for (var i = 0; i <= turns; i++) {
      final x = coilLeft + (coilRight - coilLeft) * (i / turns);
      final y = i.isEven ? coilBot : coilTop;
      if (i == 0) {
        coilPath.moveTo(x, y);
      } else {
        coilPath.lineTo(x, y);
      }
    }
    canvas.drawPath(coilPath, coil);

    final heat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const xs = <double>[0.28, 0.50, 0.72];
    final top = h * 0.64;
    final bottom = h * 0.96;
    for (var i = 0; i < xs.length; i++) {
      final phase = animate ? t * math.pi * 2 + i * 1.15 : i * 1.4;
      heat.color = color.withValues(
        alpha: animate
            ? (0.4 + 0.6 * ((math.sin(phase * 0.7) + 1) / 2)).clamp(0.35, 1.0)
            : 0.72,
      );
      _heatRay(
        canvas,
        heat,
        x: w * xs[i],
        top: top,
        bottom: bottom,
        amp: w * 0.038,
        phase: phase,
      );
    }
  }

  void _heatRay(
    Canvas canvas,
    Paint paint, {
    required double x,
    required double top,
    required double bottom,
    required double amp,
    required double phase,
  }) {
    const steps = 14;
    final path = Path();
    for (var s = 0; s <= steps; s++) {
      final u = s / steps;
      final y = top + (bottom - top) * u;
      final xx = x + math.sin(u * math.pi * 2 + phase) * amp;
      if (s == 0) {
        path.moveTo(xx, y);
      } else {
        path.lineTo(xx, y);
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
