import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData campfireIconData = IconData(0xF002);

/// Eén schouwlijn in het gewicht van de andere statusiconen.
/// De vlam is het outline-vlammetje en flikkert alleen op de statusbadge.
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
    final flame = widget.size * 0.58;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _SchouwPainter(color: widget.color)),
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
  _SchouwPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final weight = (w * 0.065).clamp(1.2, 1.85);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(w * 0.08, h * 0.82)
      ..lineTo(w * 0.20, h * 0.82)
      ..lineTo(w * 0.20, h * 0.30)
      ..lineTo(w * 0.08, h * 0.30)
      ..lineTo(w * 0.08, h * 0.14)
      ..lineTo(w * 0.92, h * 0.14)
      ..lineTo(w * 0.92, h * 0.30)
      ..lineTo(w * 0.80, h * 0.30)
      ..lineTo(w * 0.80, h * 0.82)
      ..lineTo(w * 0.92, h * 0.82);
    canvas.drawPath(path, line);

    // Dun recht balkje op de twee staanders, boven de vlam.
    final beam = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (weight * 0.55).clamp(0.7, 1.05)
      ..strokeCap = StrokeCap.butt;
    final beamY = h * 0.36;
    canvas.drawLine(
      Offset(w * 0.20, beamY),
      Offset(w * 0.80, beamY),
      beam,
    );
  }

  @override
  bool shouldRepaint(covariant _SchouwPainter oldDelegate) =>
      oldDelegate.color != color;
}
