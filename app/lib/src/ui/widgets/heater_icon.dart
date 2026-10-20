import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Terrasheater: liggende kachel met verticale lamellen op twee pootjes,
/// met warmtestraaltjes erboven. Op het statusicoon golven de straaltjes omhoog.
class HeaterIcon extends StatefulWidget {
  const HeaterIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = false,
    this.status = false,
  });

  final double size;
  final Color color;
  final bool animate;

  /// Header en ruimte-rij: spiralen blijven lichter.
  final bool status;

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
            status: widget.status,
          ),
          size: Size(widget.size, widget.size),
        );

    final glyph = SizedBox(
      width: widget.size,
      height: widget.size,
      child: _ctrl == null
          ? paint(0)
          : AnimatedBuilder(
              animation: _ctrl!,
              builder: (_, __) => paint(_ctrl!.value),
            ),
    );
    return glyph;
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
    required this.status,
  });

  final Color color;
  final double t;
  final bool animate;
  final bool status;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = materialOutlineStroke(s);
    final frameStroke = status ? statusOutlineStroke(s) : stroke;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = frameStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Klein icoon: minder lamellen, anders loopt het dicht. Altijd 3 straaltjes.
    final small = s < 30;
    final bars = small ? 3 : 5;
    const rays = 3;

    // Statusrij deelt de keyline van het lampje (boven 0.084, onder 0.916).
    final top = status ? 0.084 : 0.10;
    final bottom = status ? 0.916 : 0.90;
    final span = bottom - top;
    final bodyTop = top + span * 0.50;
    final bodyBottom = bottom - span * 0.11;
    // Even breed als de split-unit (0.08–0.92), anders oogt de heater kleiner.
    final body = Rect.fromLTRB(
      s * 0.08 + frameStroke / 2,
      s * bodyTop,
      s * 0.92 - frameStroke / 2,
      s * bodyBottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(s * 0.07)),
      line,
    );

    // Lamellen: gelijk verdeeld, los van de rand.
    final padX = s * 0.07 + stroke;
    final padY = s * 0.05 + stroke;
    final innerL = body.left + padX;
    final innerR = body.right - padX;
    for (var i = 0; i < bars; i++) {
      final x = innerL + (innerR - innerL) * i / (bars - 1);
      canvas.drawLine(
        Offset(x, body.top + padY),
        Offset(x, body.bottom - padY),
        line,
      );
    }

    // Pootjes.
    final footY = s * bottom - frameStroke / 2;
    final footInset = s * 0.12;
    final foot = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = frameStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(body.left + footInset, body.bottom),
      Offset(body.left + footInset, footY),
      foot,
    );
    canvas.drawLine(
      Offset(body.right - footInset, body.bottom),
      Offset(body.right - footInset, footY),
      foot,
    );

    // Warmtestraaltjes: golvende lijntjes die omhoog bewegen en vervagen.
    final rayTop = s * top + stroke;
    final rayBottom = body.top - s * 0.06 - stroke;
    final rayH = rayBottom - rayTop;
    if (rayH <= stroke * 2) return;
    final rayPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rayL = innerL + (innerR - innerL) * 0.10;
    final rayR = innerR - (innerR - innerL) * 0.10;
    // Zachte golf: breed genoeg om te lezen, smal genoeg om niet te klonteren.
    final amp = math.min(s * 0.028, rayH * 0.16);
    for (var i = 0; i < rays; i++) {
      final cx = rayL + (rayR - rayL) * i / (rays - 1);
      final phase = animate ? t * math.pi * 2 + i * 1.9 : i * 1.2;
      // Elk straaltje schuift omhoog en komt onderaan vager terug.
      final drift = animate ? ((t + i / rays) % 1.0) : 0.0;
      final alpha = animate ? 0.45 + 0.55 * (1 - (drift * 2 - 1).abs()) : 1.0;
      rayPaint.color = color.withValues(alpha: color.a * alpha);
      final shift = animate ? (drift - 0.5) * rayH * 0.14 : 0.0;
      canvas.drawPath(
        _heatRay(
          cx: cx,
          top: rayTop - shift,
          bottom: rayBottom - shift,
          amp: amp,
          phase: phase,
        ),
        rayPaint,
      );
    }
  }

  /// Eén golvend straaltje: één sinusslag van onder naar boven.
  Path _heatRay({
    required double cx,
    required double top,
    required double bottom,
    required double amp,
    required double phase,
  }) {
    const steps = 16;
    final h = bottom - top;
    final path = Path();
    for (var k = 0; k <= steps; k++) {
      final f = k / steps;
      final y = bottom - h * f;
      final x = cx + math.sin(f * math.pi * 2 + phase) * amp;
      if (k == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate ||
      oldDelegate.status != status;
}
