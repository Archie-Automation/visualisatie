import 'dart:math';

import 'package:flutter/material.dart';

/// Vier balken, dezelfde tekening als het audiostatusicoon.
class EqualizerIcon extends StatefulWidget {
  const EqualizerIcon({
    super.key,
    required this.size,
    required this.color,
    this.animate = true,
  });

  final double size;
  final Color color;
  final bool animate;

  @override
  State<EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<EqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(EqualizerIcon old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = (widget.size * 0.06).clamp(1.15, 1.7);
    final maxH = widget.size * 0.72;
    final bottomInset = widget.size * 0.08;
    final gap = widget.size * 0.07;
    final color = widget.color;

    Widget bars(List<double> levels) => SizedBox(
          width: barW * 4 + gap * 3,
          height: widget.size,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < levels.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  _bar(barW, maxH * levels[i], color),
                ],
              ],
            ),
          ),
        );

    if (!widget.animate) {
      const levels = [0.45, 1.0, 0.62, 0.82];
      return bars(levels);
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * pi;
        final levels = List<double>.generate(4, (i) {
          return (0.35 + 0.65 * ((sin(t + i * 1.45) + 1) / 2)).clamp(0.15, 1.0);
        });
        return bars(levels);
      },
    );
  }

  Widget _bar(double w, double h, Color color) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
}
