import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Terrasheater: afgerond vierkant met de ronde verwarmingsspiraal.
/// Op het statusicoon dooft de spiraal en komt terug, zonder helemaal te verdwijnen.
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
        duration: const Duration(milliseconds: 2800),
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
          duration: const Duration(milliseconds: 2800),
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
    final s = size.shortestSide;
    // Zelfde lijngewicht als de andere statusiconen, iets dikker op grote maten
    // zodat de bocht open blijft.
    final stroke = (s * 0.055).clamp(1.05, 1.7);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final inset = stroke / 2 + s * 0.04;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(inset, inset, s - inset, s - inset),
        Radius.circular(s * 0.18),
      ),
      line,
    );

    // Vloert op ~0.42: de spiraal dooft, maar blijft zichtbaar.
    final pulse = animate
        ? 0.42 + 0.58 * ((math.sin(t * math.pi * 2) + 1) / 2)
        : 1.0;
    final coilPaint = Paint()
      ..color = color.withValues(alpha: color.a * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pad = s * 0.16;
    final inner = Rect.fromLTRB(pad, pad, s - pad, s - pad);
    const columns = 3;
    const intervals = 4;
    final gap = stroke * 1.7;
    final colW = (inner.width - gap * (columns - 1)) / columns;
    final pitch = inner.height / intervals;
    for (var c = 0; c < columns; c++) {
      final left = inner.left + c * (colW + gap);
      canvas.drawPath(
        _heatingCoil(
          left: left,
          right: left + colW,
          top: inner.top,
          bottom: inner.bottom,
          pitch: pitch,
        ),
        coilPaint,
      );
    }
  }

  /// Verticale spiraal met ronde U-bochten, dezelfde vorm als het voorbeeld.
  Path _heatingCoil({
    required double left,
    required double right,
    required double top,
    required double bottom,
    required double pitch,
  }) {
    final r = math.min(right - left, pitch) / 2;
    final extra = math.max(0.0, (right - left) - r * 2);
    final xL = left + extra / 2 + r;
    final xR = right - extra / 2 - r;
    final path = Path();
    final cap = math.max(0.0, xR - xL) * 0.45;
    path.moveTo(xL + cap, top);

    final intervals = ((bottom - top) / pitch).round();
    for (var i = 0; i < intervals; i++) {
      final y = top + i * pitch;
      final y2 = y + pitch;
      final midY = (y + y2) / 2;
      if (i.isEven) {
        path.lineTo(xR, y);
        path.arcTo(
          Rect.fromCircle(center: Offset(xR, midY), radius: r),
          -math.pi / 2,
          math.pi,
          false,
        );
      } else {
        path.lineTo(xL, y);
        path.arcTo(
          Rect.fromCircle(center: Offset(xL, midY), radius: r),
          -math.pi / 2,
          -math.pi,
          false,
        );
      }
    }
    path.lineTo(xR - cap, top + intervals * pitch);
    return path;
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate;
}
