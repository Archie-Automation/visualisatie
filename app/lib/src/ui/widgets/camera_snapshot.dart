import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api.dart';
import '../../demo/demo_camera_view.dart';
import '../../demo/demo_session.dart';

/// Live snapshot preview that fetches JPEG bytes manually.
///
/// By owning the HTTP call ourselves we can hold onto the last successful
/// frame and keep showing it while a refresh is in-flight or temporarily
/// fails.  This eliminates the loading-flash / blinking that occurs when
/// using [Image.network] with a cache-buster, because the visible image
/// only ever changes when a *new* successful frame arrives.
enum SnapshotKind { camera, intercom }

class CameraSnapshot extends ConsumerStatefulWidget {
  const CameraSnapshot({
    super.key,
    required this.cameraId,
    required this.aspectRatio,
    this.refresh = const Duration(seconds: 10),
    this.fit = BoxFit.cover,
    this.kind = SnapshotKind.camera,
    this.showLiveBadge = true,
    this.expand = false,
    this.radius = 18,
    this.onIntrinsicAspect,
  });

  final String cameraId;
  final double aspectRatio;
  final Duration refresh;
  final BoxFit fit;
  final SnapshotKind kind;
  final bool showLiveBadge;
  /// Fill the parent instead of locking to [aspectRatio].
  final bool expand;
  /// Eigen afronding. 0 = de ouder knipt, zodat er geen tweede rand in de tegel zit.
  final double radius;
  /// Echte breedte/hoogte van het JPEG, zodra die bekend is.
  final ValueChanged<double>? onIntrinsicAspect;

  @override
  ConsumerState<CameraSnapshot> createState() => _CameraSnapshotState();
}

class _CameraSnapshotState extends ConsumerState<CameraSnapshot> {
  Timer? _timer;
  Uint8List? _frame;       // last good JPEG bytes – null = never loaded yet
  bool _fetching = false;  // guard against overlapping requests
  int _failStreak = 0;     // consecutive failures (used to slow retries)
  int _frameGen = 0;       // unique key so equal-sized JPEGs still swap
  double? _intrinsic;      // decoded frame ratio, so the box hugs the picture

  @override
  void initState() {
    super.initState();
    if (isDemoToken(ref.read(authProvider).token)) return;
    // Kick off the first fetch immediately, then on a timer.
    _scheduleFetch(immediately: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleFetch({bool immediately = false}) {
    _timer?.cancel();
    if (immediately) {
      _fetch();
    }
    // When the camera keeps failing, slow the poll rate to avoid log spam
    // and unnecessary network traffic (max 30 s backoff).
    final delay = _failStreak == 0
        ? widget.refresh
        : Duration(seconds: (widget.refresh.inSeconds * (1 << _failStreak.clamp(0, 3))).clamp(3, 30));
    _timer = Timer(delay, _fetch);
  }

  Future<void> _fetch() async {
    if (_fetching || !mounted) return;
    _fetching = true;

    try {
      final auth = ref.read(authProvider);
      if (auth.token == null) return;

      final segment = widget.kind == SnapshotKind.intercom ? 'intercoms' : 'cameras';
      final url = Uri.parse(
        '$apiBase/api/$segment/${widget.cameraId}/snapshot?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      final res = await http
          .get(url, headers: {'authorization': 'Bearer ${auth.token}'})
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final bytes = res.bodyBytes;
        final intrinsic = _intrinsic ?? await _jpegAspect(bytes);
        if (!mounted) return;
        if (intrinsic != null &&
            (_intrinsic == null || (intrinsic - _intrinsic!).abs() >= 0.02)) {
          _intrinsic = intrinsic;
          widget.onIntrinsicAspect?.call(intrinsic);
        }
        setState(() {
          _frame = bytes;
          _frameGen++;
          _failStreak = 0;
          _intrinsic ??= intrinsic;
        });
      } else {
        // Non-200: keep old frame visible, slow down retries.
        _failStreak = (_failStreak + 1).clamp(0, 4);
      }
    } catch (_) {
      if (mounted) _failStreak = (_failStreak + 1).clamp(0, 4);
    } finally {
      _fetching = false;
      if (mounted) _scheduleFetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isDemoToken(ref.watch(authProvider.select((auth) => auth.token)))) {
      final name = ref.watch(configProvider).maybeWhen(
            data: (cfg) => cfg.deviceById(widget.cameraId)?.name ?? 'Camera',
            orElse: () => 'Camera',
          );
      return DemoCameraView(
        label: name,
        seed: widget.cameraId,
        expand: widget.expand,
        aspectRatio: widget.aspectRatio,
        doorStation: widget.kind == SnapshotKind.intercom,
        radius: widget.radius,
      );
    }
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _frame != null
              ? Image.memory(
                  _frame!,
                  key: ValueKey('frame-$_frameGen'),
                  fit: widget.fit,
                  gaplessPlayback: true,
                )
              : const Center(
                  key: ValueKey('offline'),
                  child: Icon(Icons.videocam_off_outlined,
                      color: Colors.white54, size: 28),
                ),
        ),
        if (widget.showLiveBadge)
          const Positioned(
            top: 10,
            left: 10,
            child: _LiveDot(),
          ),
      ],
    );
    final frame = widget.expand
        ? stack
        : AspectRatio(
            aspectRatio: _intrinsic ?? widget.aspectRatio,
            child: stack,
          );
    if (widget.radius <= 0) return frame;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: frame,
    );
  }
}

/// Width/height of a JPEG without painting it. Null when the bytes are not
/// a decodable image.
Future<double?> _jpegAspect(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (w <= 0 || h <= 0) return null;
    return w / h;
  } catch (_) {
    return null;
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.4, end: 1).animate(_c),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFE44B4B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      );
}
