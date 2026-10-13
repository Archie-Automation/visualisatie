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

    // Iets hoger dan voorheen, anders vult de dikkere spiraal zichzelf.
    // Statusrij: dezelfde boven- en onderkant als het lampje. Tegel blijft lager.
    final frame = Rect.fromCenter(
      center: Offset(s / 2, s / 2),
      width: s * 0.88,
      height: s * (status ? 0.748 : 0.66),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(s * 0.08)),
      line,
    );

    // Op de statusrij piekt de spiraal lager, anders vult het vak zich.
    final wave = (math.sin(t * math.pi * 2) + 1) / 2;
    final pulse = status
        ? (animate ? 0.38 + 0.32 * wave : 0.55)
        : (animate ? 0.42 + 0.58 * wave : 1.0);
    final coilPaint = Paint()
      ..color = color.withValues(alpha: color.a * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final padY = stroke * 0.55 + s * 0.045;
    final inner = Rect.fromLTRB(
      frame.left + s * 0.055,
      frame.top + padY,
      frame.right - s * 0.055,
      frame.bottom - padY,
    );
    const rows = 2;
    const intervals = 4;
    final gap = stroke * 1.15;
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
      oldDelegate.animate != animate ||
      oldDelegate.status != status;
}
