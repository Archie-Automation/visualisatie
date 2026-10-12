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
    return CustomPaint(
      painter: _SchouwPainter(
        color: widget.color,
        flameScale: scale,
      ),
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
  _SchouwPainter({required this.color, required this.flameScale});

  final Color color;
  final double flameScale;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Zelfde gewicht als de split-unit.
    final weight = (w * 0.065).clamp(1.2, 1.85);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final radius = Radius.circular(w * 0.045);

    final mantel = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.04, h * 0.04, w * 0.96, h * 0.20),
      radius,
    );
    final hearth = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.04, h * 0.80, w * 0.96, h * 0.96),
      radius,
    );
    final opening = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.30, h * 0.30, w * 0.70, h * 0.72),
      Radius.circular(w * 0.03),
    );

    canvas.drawRRect(mantel, line);
    canvas.drawRRect(hearth, line);
    canvas.drawRRect(opening, line);

    final side = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.butt;
    final sideTop = mantel.bottom + weight * 0.35;
    final sideBot = hearth.top - weight * 0.35;
    canvas.drawLine(Offset(w * 0.14, sideTop), Offset(w * 0.14, sideBot), side);
    canvas.drawLine(Offset(w * 0.86, sideTop), Offset(w * 0.86, sideBot), side);

    final box = opening.outerRect.deflate(weight + w * 0.025);
    final flame = Rect.fromCenter(
      center: box.center,
      width: box.width * 0.62,
      height: box.height * 0.78,
    );
    _flame(canvas, line, flame);
  }

  void _flame(Canvas canvas, Paint paint, Rect rect) {
    final cx = rect.center.dx;
    final top = rect.top;
    final bot = rect.bottom;
    final hw = rect.width / 2;
    final hh = rect.height;

    canvas.save();
    canvas.translate(cx, bot);
    canvas.scale(flameScale.clamp(0.75, 1.0));
    canvas.translate(-cx, -bot);

    final outer = Path()
      ..moveTo(cx, top)
      ..cubicTo(
        cx + hw * 0.35,
        top + hh * 0.38,
        cx + hw * 1.05,
        top + hh * 0.55,
        cx + hw * 0.55,
        bot - hh * 0.02,
      )
      ..quadraticBezierTo(cx, bot + hh * 0.04, cx - hw * 0.55, bot - hh * 0.02)
      ..cubicTo(
        cx - hw * 1.05,
        top + hh * 0.55,
        cx - hw * 0.35,
        top + hh * 0.38,
        cx,
        top,
      );
    canvas.drawPath(outer, paint);

    final innerTop = top + hh * 0.42;
    final innerBot = bot - hh * 0.08;
    final ih = innerBot - innerTop;
    final iw = hw * 0.38;
    if (ih > paint.strokeWidth * 2.4 && iw > paint.strokeWidth) {
      final inner = Path()
        ..moveTo(cx, innerTop)
        ..cubicTo(
          cx + iw * 0.9,
          innerTop + ih * 0.45,
          cx + iw * 0.7,
          innerBot,
          cx,
          innerBot,
        )
        ..cubicTo(
          cx - iw * 0.7,
          innerBot,
          cx - iw * 0.9,
          innerTop + ih * 0.45,
          cx,
          innerTop,
        );
      canvas.drawPath(inner, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SchouwPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.flameScale != flameScale;
}
