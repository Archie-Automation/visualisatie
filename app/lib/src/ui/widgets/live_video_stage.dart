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

/// One stable frame for snapshot and live. The first real ratio (cache, else
/// the first measurement) is kept; later reports do not resize the picture.
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
  /// Null until a real ratio is committed. The fallback box stays invisible
  /// so the first thing on screen is already the final size.
  double? _locked;

  @override
  void initState() {
    super.initState();
    _locked = _cached();
  }

  @override
  void didUpdateWidget(covariant LiveVideoHuggingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _locked = _cached();
    }
  }

  double? _cached() {
    final id = widget.identity;
    if (id == null) return null;
    return cachedCameraFrameAspect(id);
  }

  void _onIntrinsic(double aspect) {
    if (!_plausibleFrameAspect(aspect)) return;
    if (_locked != null) return;
    final id = widget.identity;
    if (id != null) rememberCameraFrameAspect(id, aspect);
    setState(() => _locked = aspect);
  }

  @override
  Widget build(BuildContext context) {
    final known = _locked != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: known ? 1 : 0,
          child: LiveVideoFittedStage(
            aspectRatio: _locked ?? widget.fallbackAspect,
            heroTag: widget.heroTag,
            factor: widget.factor,
            child: widget.builder(_onIntrinsic),
          ),
        ),
        if (!known)
          Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: LuxeColors.brass,
              ),
            ),
          ),
      ],
    );
  }
}
