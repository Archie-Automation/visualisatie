import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared live-frame size on tablet/desktop. Camera and intercom stay in sync.
const kLiveVideoStageFactor = 0.75;

/// Full-bleed camera/intercom stage: fills the parent, clips to a rounded
/// frame, shadow outside the clip so the picture can run edge-to-edge.
class LiveVideoStage extends StatelessWidget {
  const LiveVideoStage({
    super.key,
    required this.child,
    this.heroTag,
    this.radius = 22,
  });

  final Widget child;
  final String? heroTag;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final stage = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: LuxeShadows.darkLift,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(color: Colors.black, child: child),
      ),
    );
    final tag = heroTag;
    if (tag == null) return stage;
    return Hero(tag: tag, child: stage);
  }
}
