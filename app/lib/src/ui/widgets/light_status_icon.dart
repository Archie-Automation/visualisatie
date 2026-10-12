import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Statuslamp: het outline-lampje, heel licht op en neer.
/// De beweging is de gloed — geen opacity-puls.
class LightStatusIcon extends StatefulWidget {
  const LightStatusIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  State<LightStatusIcon> createState() => _LightStatusIconState();
}

class _LightStatusIconState extends State<LightStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final dy =
              math.sin(_ctrl.value * 2 * math.pi) * widget.size * 0.045;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              size: widget.size,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}
