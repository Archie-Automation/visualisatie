import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../api.dart';
import '../../theme.dart';

/// A lean, luxe HLS player. Autoplays, chases the live edge on stall,
/// muted by default for inline previews. Tap-to-unmute when [interactive].
class CameraPlayer extends ConsumerStatefulWidget {
  const CameraPlayer({
    super.key,
    required this.hlsUrl,
    required this.aspectRatio,
    this.muted = true,
    this.fit = BoxFit.cover,
    this.interactive = false,
    this.showLiveBadge = true,
  });

  final String hlsUrl;
  final double aspectRatio;
  final bool muted;
  final BoxFit fit;
  final bool interactive;
  final bool showLiveBadge;

  @override
  ConsumerState<CameraPlayer> createState() => _CameraPlayerState();
}

class _CameraPlayerState extends ConsumerState<CameraPlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  String? _err;
  late bool _muted;
  Timer? _liveChase;
  Duration _lastPosition = Duration.zero;
  int _stallTicks = 0;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    _init();
  }

  Map<String, String> _authHeaders() {
    final token = ref.read(authProvider).token;
    if (token == null) return const {};
    return {'authorization': 'Bearer $token'};
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.hlsUrl),
        httpHeaders: _authHeaders(),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: false,
          mixWithOthers: true,
        ),
      );
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(_muted ? 0 : 1);
      await c.play();
      if (!mounted) return;
      setState(() {
        _ctrl = c;
        _ready = true;
      });
      _startLiveChase(c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  void _startLiveChase(VideoPlayerController c) {
    _liveChase?.cancel();
    _liveChase = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _ctrl != c || !c.value.isInitialized) return;
      final pos = c.value.position;
      final dur = c.value.duration;

      // Detect stall: position unchanged while supposedly playing.
      if (c.value.isPlaying && pos == _lastPosition) {
        _stallTicks++;
      } else {
        _stallTicks = 0;
      }
      _lastPosition = pos;

      if (dur.inMilliseconds <= 0) return;

      final lag = dur - pos;
      if (lag > const Duration(seconds: 6) || _stallTicks >= 2) {
        final target = dur - const Duration(seconds: 2);
        if (target > Duration.zero) {
          await c.seekTo(target);
          _stallTicks = 0;
          if (!c.value.isPlaying) await c.play();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant CameraPlayer old) {
    super.didUpdateWidget(old);
    if (old.hlsUrl != widget.hlsUrl) {
      _liveChase?.cancel();
      _ctrl?.dispose();
      _ctrl = null;
      _ready = false;
      _err = null;
      _stallTicks = 0;
      _lastPosition = Duration.zero;
      _init();
    }
  }

  @override
  void dispose() {
    _liveChase?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    if (_ctrl == null) return;
    setState(() => _muted = !_muted);
    _ctrl!.setVolume(_muted ? 0 : 1);
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
            if (_ready && _ctrl != null)
              FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _ctrl!.value.size.width == 0
                      ? 1920
                      : _ctrl!.value.size.width,
                  height: _ctrl!.value.size.height == 0
                      ? 1080
                      : _ctrl!.value.size.height,
                  child: VideoPlayer(_ctrl!),
                ),
              )
            else if (_err != null)
              const Center(
                child: Icon(Icons.videocam_off_outlined,
                    color: Colors.white54, size: 32),
              )
            else
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LuxeColors.brass,
                  ),
                ),
              ),
            if (widget.showLiveBadge && _ready)
              const Positioned(
                top: 10,
                left: 10,
                child: _LiveBadge(),
              ),
            if (widget.interactive)
              Positioned(
                bottom: 10,
                right: 10,
                child: _MuteButton(muted: _muted, onTap: _toggleMute),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(),
            SizedBox(width: 6),
            Text('LIVE',
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

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
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
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.4, end: 1).animate(_c),
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFE44B4B),
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onTap});
  final bool muted;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 18,
          ),
        ),
      );
}
