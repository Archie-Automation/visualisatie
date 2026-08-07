import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Balk stil; warmtestreepjes animeren (als [animate]).
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
    final stroke = (w * 0.085).clamp(1.6, 2.6);

    // Horizontale balk — stil.
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.14, h * 0.22, w * 0.86, h * 0.38),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final rayTop = h * 0.42;
    final rayBottomFull = h * 0.9;
    final amplitude = w * 0.055;
    final centers = [w * 0.28, w * 0.5, w * 0.72];

    for (var i = 0; i < centers.length; i++) {
      double pulse = 1.0;
      if (animate) {
        final phase = t * 2 * math.pi + i * 0.9;
        pulse = 0.35 + 0.65 * ((math.sin(phase) + 1) / 2);
      }
      final length = animate ? (0.55 + 0.45 * pulse) : 1.0;
      final rayBottom = rayTop + (rayBottomFull - rayTop) * length;
      _drawDownWave(
        canvas,
        cx: centers[i],
        top: rayTop,
        bottom: rayBottom,
        amplitude: amplitude,
        paint: Paint()
          ..color = color.withValues(
            alpha: animate ? pulse.clamp(0.25, 1.0) : 1.0,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.92
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawDownWave(
    Canvas canvas, {
    required double cx,
    required double top,
    required double bottom,
    required double amplitude,
    required Paint paint,
  }) {
    final path = Path()..moveTo(cx, top);
    const steps = 8;
    final dy = (bottom - top) / steps;
    for (var i = 1; i <= steps; i++) {
      final y = top + dy * i;
      final phase = i / steps * math.pi;
      final x = cx + math.sin(phase * 2.4 + cx) * amplitude;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate;
}
