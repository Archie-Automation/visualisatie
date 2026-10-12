import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData campfireIconData = IconData(0xF002);

/// Outline-vlam in een schouw. Lijndikte gelijk aan de andere statusiconen.
/// Alleen de vlam flikkert; de schouw blijft stil.
class CampfireIcon extends StatefulWidget {
  const CampfireIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = true,
  });

  final double size;
  final Color color;

  /// Statusbadge flikkert. Op een bedieningsknop blijft de vlam stil.
  final bool animate;

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
    // Zelfde verhouding als de outlined Material-vlam (2px op een 24-grid),
    // zodat schouw en vlam één lijndikte hebben.
    final flame = widget.size * 0.70;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _SchouwPainter(color: widget.color, stroke: flame * 2 / 24),
        ),
        Align(
          alignment: const Alignment(0, 0.42),
          child: Transform.scale(
            scale: scale,
            alignment: const Alignment(0, 0.72),
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

class _SchouwPainter extends CustomPainter {
  _SchouwPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final weight = stroke.clamp(1.15, 2.2);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final yShelf = h * 0.13;
    final yLip = h * 0.27;
    final yHearth = h * 0.86;
    final xOutL = w * 0.07;
    final xOutR = w * 0.93;
    final xInL = w * 0.26;
    final xInR = w * 0.74;

    final mantel = Path()
      ..moveTo(xOutL, yLip)
      ..lineTo(xOutL, yShelf)
      ..lineTo(xOutR, yShelf)
      ..lineTo(xOutR, yLip);
    canvas.drawPath(mantel, line);

    final jamb = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(xInL, yLip),
      Offset(xInL, yHearth - weight / 2),
      jamb,
    );
    canvas.drawLine(
      Offset(xInR, yLip),
      Offset(xInR, yHearth - weight / 2),
      jamb,
    );
    canvas.drawLine(Offset(xOutL, yHearth), Offset(xOutR, yHearth), line);
  }

  @override
  bool shouldRepaint(covariant _SchouwPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.stroke != stroke;
}
