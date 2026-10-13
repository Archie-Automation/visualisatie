import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData campfireIconData = IconData(0xF002);

/// Lijngewicht van de Material-outlined iconen (zonwering, camera, intercom,
/// ventilatie): 2 px op een icoon van 24 px, en verder lineair met de maat.
double materialOutlineStroke(double size) => size * 2 / 24;

/// Status-omlijning van heater en haard: een fractie onder die Material-pen.
double statusOutlineStroke(double size) => materialOutlineStroke(size) * 0.85;

/// Eén schouwlijn in het gewicht van de andere statusiconen.
/// De vlam is het outline-vlammetje en flikkert alleen op de statusbadge.
class CampfireIcon extends StatefulWidget {
  const CampfireIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = true,
    this.status = false,
  });

  final double size;
  final Color color;

  /// Statusbadge flikkert. Op een bedieningsknop blijft de vlam stil.
  final bool animate;

  /// Header en ruimte-rij: boven- en onderkant op de lamp-keyline.
  final bool status;

  @override
  State<CampfireIcon> createState() => _CampfireIconState();
}

class _CampfireIconState extends State<CampfireIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CampfireIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) return;
    if (widget.animate) {
      _start();
    } else {
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  void _start() {
    if (!widget.animate || _ctrl != null) return;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _mark(double scale) {
    final flame = widget.size * 0.58;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _SchouwPainter(
            color: widget.color,
            status: widget.status,
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.68),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Icon(
              Icons.local_fire_department_outlined,
              size: flame,
              color: widget.color,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ctrl == null
          ? _mark(1)
          : AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) {
                final t = ctrl.value * 2 * math.pi;
                final flicker =
                    (math.sin(t * 1.7) + math.sin(t * 2.3) + 2) / 4;
                return _mark(0.90 + 0.10 * flicker);
              },
            ),
    );
  }
}

/// Mantel en poten, zonder vloer. Dun balkje op de staanders, boven de vlam.
class _SchouwPainter extends CustomPainter {
  _SchouwPainter({required this.color, required this.status});

  final Color color;

  /// Statusrij deelt de verticale keyline van het lampje (y 0.084–0.916).
  final bool status;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final weight =
        status ? statusOutlineStroke(w) : materialOutlineStroke(w);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Tegel houdt de compacte schouw. Statusrij: zelfde vorm, opgerekt tot
    // de lijn van het lampje (boven 0.084, onder 0.916, halve pen eraf).
    final top = status ? 0.126 : 0.14;
    final lip = status ? 0.302 : 0.30;
    final foot = status ? 0.874 : 0.82;
    final path = Path()
      ..moveTo(w * 0.08, h * foot)
      ..lineTo(w * 0.20, h * foot)
      ..lineTo(w * 0.20, h * lip)
      ..lineTo(w * 0.08, h * lip)
      ..lineTo(w * 0.08, h * top)
      ..lineTo(w * 0.92, h * top)
      ..lineTo(w * 0.92, h * lip)
      ..lineTo(w * 0.80, h * lip)
      ..lineTo(w * 0.80, h * foot)
      ..lineTo(w * 0.92, h * foot);
    canvas.drawPath(path, line);

    // Zelfde pen als de schouw, anders oogt het balkje als een andere serie.
    final beam = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.butt;
    // Zelfde hoogte als het hoekje onder de schouwplaat.
    final beamY = h * lip;
    canvas.drawLine(
      Offset(w * 0.20, beamY),
      Offset(w * 0.80, beamY),
      beam,
    );
  }

  @override
  bool shouldRepaint(covariant _SchouwPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.status != status;
}
