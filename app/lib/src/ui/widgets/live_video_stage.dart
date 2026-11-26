import 'package:flutter/material.dart';

import '../../theme.dart';

/// How much of the parent the camera frame may use.
/// 1 sizes the picture to the largest box that still fits, with no inset.
const kLiveVideoStageFactor = 1.0;

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
        child: child,
      ),
    );
    final tag = heroTag;
    if (tag == null) return stage;
    return Hero(tag: tag, child: stage);
  }
}

/// Rounded live frame: at most [factor] of the parent, sized to [aspectRatio]
/// so the picture is fully visible and not stretched or cropped.
///
/// Pass the stream's real ratio once it is known. A configured 16:9 box
/// around a different stream is what leaves the black bars.
class LiveVideoFittedStage extends StatelessWidget {
  const LiveVideoFittedStage({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.heroTag,
    this.factor = kLiveVideoStageFactor,
  });

  final double aspectRatio;
  final Widget child;
  final String? heroTag;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth * factor;
        final maxH = constraints.maxHeight * factor;
        final ar = aspectRatio > 0.1 ? aspectRatio : 16 / 9;
        var width = maxW;
        var height = width / ar;
        if (height > maxH) {
          height = maxH;
          width = height * ar;
        }
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: LiveVideoStage(heroTag: heroTag, child: child),
          ),
        );
      },
    );
  }
}

/// Last committed frame ratio per camera. Reopening starts at this size
/// instead of the configured 16:9 and then growing when live starts.
final Map<Object, double> _cameraFrameAspect = {};

double? cachedCameraFrameAspect(Object id) => _cameraFrameAspect[id];

void rememberCameraFrameAspect(Object id, double aspect) {
  _cameraFrameAspect[id] = aspect;
}

void clearCameraFrameAspectCache() => _cameraFrameAspect.clear();

bool _plausibleFrameAspect(double aspect) =>
    aspect.isFinite && aspect >= 0.2 && aspect <= 5;

/// One fixed frame for snapshot and live. The size is decided before anything
/// loads (last measured ratio of this camera, else [fallbackAspect]) and never
/// changes while the view is open. Measurements only feed the next opening.
class LiveVideoHuggingStage extends StatefulWidget {
  const LiveVideoHuggingStage({
    super.key,
    required this.fallbackAspect,
    required this.builder,
    this.identity,
    this.heroTag,
    this.factor = kLiveVideoStageFactor,
  });

  final double fallbackAspect;
  final Widget Function(ValueChanged<double> onIntrinsicAspect) builder;
  final Object? identity;
  final String? heroTag;
  final double factor;

  @override
  State<LiveVideoHuggingStage> createState() => _LiveVideoHuggingStageState();
}

class _LiveVideoHuggingStageState extends State<LiveVideoHuggingStage> {
  late double _aspect;

  @override
  void initState() {
    super.initState();
    _aspect = _initialAspect();
  }

  @override
  void didUpdateWidget(covariant LiveVideoHuggingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _aspect = _initialAspect();
    }
  }

  double _initialAspect() {
    final id = widget.identity;
    final cached = id == null ? null : cachedCameraFrameAspect(id);
    return cached ?? widget.fallbackAspect;
  }

  void _onIntrinsic(double aspect) {
    if (!_plausibleFrameAspect(aspect)) return;
    final id = widget.identity;
    if (id != null) rememberCameraFrameAspect(id, aspect);
  }

  @override
  Widget build(BuildContext context) {
    return LiveVideoFittedStage(
      aspectRatio: _aspect,
      heroTag: widget.heroTag,
      factor: widget.factor,
      child: ColoredBox(
        color: Colors.black,
        child: widget.builder(_onIntrinsic),
      ),
    );
  }
}
