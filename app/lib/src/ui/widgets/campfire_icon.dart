import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sentinel — render via [iconWidgetForData], niet [Icon].
const IconData campfireIconData = IconData(0xF002);

/// Oude flikkerende vlam, met een licht kruis van twee stronken eronder.
class CampfireIcon extends StatefulWidget {
  const CampfireIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = true,
    this.filledLogs = false,
  });

  final double size;
  final Color color;

  /// Statusbadge flikkert. Op een bedieningsknop blijft de vlam stil.
  final bool animate;

  /// Kamerstatus: stronken voller ingekleurd, nog wel met de witte nerf.
  final bool filledLogs;

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
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _CampfireLogsPainter(
            color: widget.color,
            filled: widget.filledLogs,
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.48),
          child: Transform.scale(
            scale: scale,
            child: Icon(
              Icons.local_fire_department_rounded,
              size: widget.size * 0.86,
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
                final scale = 0.82 +
                    0.18 * ((math.sin(t * 1.7) + math.sin(t * 2.3) + 2) / 4);
                return _mark(scale);
              },
            ),
    );
  }
}

class _CampfireLogsPainter extends CustomPainter {
  _CampfireLogsPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final logWidth = filled
        ? (w * 0.115).clamp(2.2, 3.6)
        : (w * 0.082).clamp(1.45, 2.15);
    final logs = Paint()
      ..color = filled ? color : color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = logWidth
      ..strokeCap = StrokeCap.round;
    final grain = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = filled
          ? (logWidth * 0.16).clamp(0.45, 0.7)
          : (logWidth * 0.28).clamp(0.55, 0.85)
      ..strokeCap = StrokeCap.round;

    void log(Offset a, Offset b) {
      canvas.drawLine(a, b, logs);
      canvas.drawLine(a, b, grain);
    }

    log(Offset(w * 0.16, h * 0.76), Offset(w * 0.84, h * 0.92));
    log(Offset(w * 0.16, h * 0.92), Offset(w * 0.84, h * 0.76));
  }

  @override
  bool shouldRepaint(covariant _CampfireLogsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}
