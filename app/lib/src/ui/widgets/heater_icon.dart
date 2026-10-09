import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Hangende heater: plafondbeugel, rooster, hittestraaltjes.
/// Alleen de stralen bewegen als [animate].
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
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.34, h * 0.02, w * 0.66, h * 0.09),
        Radius.circular(w * 0.025),
      ),
      fill,
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.44, h * 0.08, w * 0.56, h * 0.17),
      fill,
    );

    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(w * 0.06, h * 0.16, w * 0.94, h * 0.56),
          Radius.circular(w * 0.08),
        ),
      );
    const slotYs = <double>[0.23, 0.335, 0.44];
    final slotH = h * 0.048;
    for (final y in slotYs) {
      body.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(w * 0.16, h * y, w * 0.84, h * y + slotH),
          Radius.circular(slotH / 2),
        ),
      );
    }
    canvas.drawPath(body, fill);

    final heat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.055).clamp(1.15, 2.0)
      ..strokeCap = StrokeCap.round;
    const xs = <double>[0.28, 0.50, 0.72];
    final top = h * 0.64;
    final bottom = h * 0.96;
    for (var i = 0; i < xs.length; i++) {
      final phase = animate ? t * math.pi * 2 + i * 1.15 : i * 1.4;
      heat.color = color.withValues(
        alpha: animate
            ? (0.4 + 0.6 * ((math.sin(phase * 0.7) + 1) / 2)).clamp(0.35, 1.0)
            : 1,
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
