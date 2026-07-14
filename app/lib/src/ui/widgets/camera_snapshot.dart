import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api.dart';

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
    this.refresh = const Duration(milliseconds: 1500),
    this.fit = BoxFit.cover,
    this.kind = SnapshotKind.camera,
    this.showLiveBadge = true,
  });

  final String cameraId;
  final double aspectRatio;
  final Duration refresh;
  final BoxFit fit;
  final SnapshotKind kind;
  final bool showLiveBadge;

  @override
  ConsumerState<CameraSnapshot> createState() => _CameraSnapshotState();
}

class _CameraSnapshotState extends ConsumerState<CameraSnapshot> {
  Timer? _timer;
  Uint8List? _frame;       // last good JPEG bytes – null = never loaded yet
  bool _fetching = false;  // guard against overlapping requests
  int _failStreak = 0;     // consecutive failures (used to slow retries)

  @override
  void initState() {
    super.initState();
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
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        setState(() {
          _frame = res.bodyBytes;
          _failStreak = 0;
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _frame != null
                  ? Image.memory(
                      _frame!,
                      key: ValueKey('frame-${_frame!.length}'),
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
        ),
      ),
    );
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
