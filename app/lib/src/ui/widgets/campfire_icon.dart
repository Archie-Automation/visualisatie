import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData campfireIconData = IconData(0xF002);

/// Lijngewicht van de Material-outlined iconen (zonwering, camera, intercom,
/// ventilatie): 2 px op een icoon van 24 px, en verder lineair met de maat.
double materialOutlineStroke(double size) => size * 2 / 24;

/// Status-omlijning van heater en haard: een fractie onder die Material-pen.
double statusOutlineStroke(double size) => materialOutlineStroke(size) * 0.85;

/// Outline-vlam met twee gekruiste stronken eronder, in het gewicht van de
/// andere statusiconen. De vlam flikkert alleen op de statusbadge.
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
    // Statusrij: iets hoger zodat vlam en hout binnen de lamp-keyline vallen.
    final flame = widget.size * (widget.status ? 0.80 : 0.84);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _CampfireLogsPainter(
            color: widget.color,
            status: widget.status,
          ),
        ),
        Align(
          alignment: Alignment(0, widget.status ? -0.42 : -0.50),
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

/// Twee gekruiste stronken onder de vlam, zelfde pen als de andere iconen.
class _CampfireLogsPainter extends CustomPainter {
  _CampfireLogsPainter({required this.color, required this.status});

  final Color color;

  /// Statusrij deelt de verticale keyline van het lampje (y 0.084–0.916).
  final bool status;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final weight =
        status ? statusOutlineStroke(w) : materialOutlineStroke(w);
    final logs = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round;

    // Onderkant op de lamp-keyline (halve pen eraf), kruis net onder de vlam.
    final top = status ? 0.76 : 0.80;
    final bottom = status ? 0.88 : 0.93;
    canvas.drawLine(
      Offset(w * 0.22, h * top),
      Offset(w * 0.78, h * bottom),
      logs,
    );
    canvas.drawLine(
      Offset(w * 0.22, h * bottom),
      Offset(w * 0.78, h * top),
      logs,
    );
  }

  @override
  bool shouldRepaint(covariant _CampfireLogsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.status != status;
}
