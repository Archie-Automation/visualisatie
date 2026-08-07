import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../camera_api.dart';
import '../../theme.dart';
import 'camera_player.dart';
import 'webrtc_camera_player.dart';

/// Single-camera live view: WebRTC als beschikbaar, anders HLS (geen klantkeuze).
class CameraLivePlayer extends ConsumerStatefulWidget {
  const CameraLivePlayer({
    super.key,
    required this.info,
    this.fit = BoxFit.contain,
  });

  final CameraInfo info;
  final BoxFit fit;

  @override
  ConsumerState<CameraLivePlayer> createState() => _CameraLivePlayerState();
}

class _CameraLivePlayerState extends ConsumerState<CameraLivePlayer> {
  /// When WebRTC fails to deliver video, fall back to HLS instead of snapshots.
  bool _useHlsFallback = false;
  bool _streamReady = false;

  @override
  void initState() {
    super.initState();
    _prewarmStream();
  }

  Future<void> _prewarmStream() async {
    final auth = ref.read(authProvider);
    try {
      await warmCameraStream(
        cameraId: widget.info.id,
        token: auth.token,
      ).timeout(const Duration(seconds: 14));
    } catch (_) {
      /* proceed even if warm-up fails — WebRTC/HLS will retry */
    }
    if (mounted) setState(() => _streamReady = true);
  }

  void _onWebRtcFailed() {
    if (_effectiveHlsUrl.isEmpty || !mounted) return;
    setState(() => _useHlsFallback = true);
  }

  /// Prefer backend-proxied HLS so tablets never need direct go2rtc access.
  String get _effectiveHlsUrl {
    if (widget.info.hlsUrl.contains('/api/cameras/') &&
        widget.info.hlsUrl.contains('/hls.m3u8')) {
      return widget.info.hlsUrl;
    }
    return '$apiBase/api/cameras/${widget.info.id}/hls.m3u8';
  }

  @override
  Widget build(BuildContext context) {
    if (!_streamReady) {
      return AspectRatio(
        aspectRatio: widget.info.aspectRatio,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuxeColors.brass,
            ),
          ),
        ),
      );
    }

    final tryWebRtc =
        widget.info.webrtcUrl.isNotEmpty && !_useHlsFallback;

    if (tryWebRtc) {
      return WebRTCCameraPlayer(
        key: ValueKey('webrtc-${widget.info.id}'),
        signallingPath: 'cameras/${widget.info.id}',
        aspectRatio: widget.info.aspectRatio,
        fit: widget.fit,
        videoOnly: true,
        onFailed: _onWebRtcFailed,
      );
    }

    if (_effectiveHlsUrl.isNotEmpty) {
      return CameraPlayer(
        key: ValueKey('hls-${widget.info.id}'),
        hlsUrl: _effectiveHlsUrl,
        aspectRatio: widget.info.aspectRatio,
        muted: false,
        fit: widget.fit,
        interactive: true,
      );
    }

    return const Center(
      child: Text(
        'Geen live stream beschikbaar',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
