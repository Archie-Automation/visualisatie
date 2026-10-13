import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campfire_icon.dart';

/// Sentinel — render via [iconWidgetForData] / [universalIconGlyph], niet [Icon].
const IconData heaterIconData = IconData(0xF001);

/// Terrasheater: liggende rechthoek met twee horizontale spiralen.
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

    // Liggende rechthoek, zelfde lijngewicht als de schouw.
    final frame = Rect.fromCenter(
      center: Offset(s / 2, s / 2),
      width: s * 0.88,
      height: s * 0.56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(s * 0.06)),
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

    final padY = stroke * 0.5 + s * 0.09;
    final inner = Rect.fromLTRB(
      frame.left + s * 0.07,
      frame.top + padY,
      frame.right - s * 0.07,
      frame.bottom - padY,
    );
    const rows = 2;
    const intervals = 4;
    final gap = stroke * 1.55;
    final rowH = (inner.height - gap) / rows;
    final pitch = inner.width / intervals;
    for (var row = 0; row < rows; row++) {
      final top = inner.top + row * (rowH + gap);
      canvas.drawPath(
        _heatingCoil(
          left: inner.left,
          right: inner.right,
          top: top,
          bottom: top + rowH,
          pitch: pitch,
        ),
        coilPaint,
      );
    }
  }

  /// Horizontale spiraal: aaneengesloten halve cirkels, boven en onder om de beurt.
  Path _heatingCoil({
    required double left,
    required double right,
    required double top,
    required double bottom,
    required double pitch,
  }) {
    final band = bottom - top;
    final waves = (pitch <= 0 ? 4 : (right - left) / pitch).round().clamp(3, 5);
    final step = (right - left) / waves;
    final r = math.min(step / 2, band / 2);
    final cy = (top + bottom) / 2;
    final path = Path()..moveTo(left, cy);
    for (var i = 0; i < waves; i++) {
      final x = left + i * step;
      path.arcTo(
        Rect.fromCircle(center: Offset(x + step / 2, cy), radius: r),
        math.pi,
        i.isEven ? math.pi : -math.pi,
        false,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HeaterIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.t != t ||
      oldDelegate.animate != animate;
}
