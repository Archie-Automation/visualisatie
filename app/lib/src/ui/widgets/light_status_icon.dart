import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Statuslamp: de omtrek blijft stil. Alleen de vulling gloeit,
/// met een lichte schaalbeweging, zodat het lijkt alsof de lamp brandt.
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
          final glow = (math.sin(_ctrl.value * 2 * math.pi) + 1) / 2;
          final alpha = 0.12 + 0.36 * glow;
          final scale = 0.86 + 0.14 * glow;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.lightbulb_rounded,
                  size: widget.size * 0.70,
                  color: widget.color.withValues(alpha: alpha),
                ),
              ),
              Icon(
                Icons.lightbulb_outline_rounded,
                size: widget.size,
                color: widget.color,
              ),
            ],
          );
        },
      ),
    );
  }
}
