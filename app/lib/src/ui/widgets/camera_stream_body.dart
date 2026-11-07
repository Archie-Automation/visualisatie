import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../camera_api.dart';
import '../../demo/demo_camera_view.dart';
import '../../demo/demo_session.dart';
import '../../models.dart';
import '../../theme.dart';
import 'camera_player.dart';
import 'webrtc_camera_player.dart';

/// Single-camera live view: WebRTC als beschikbaar, anders HLS (geen klantkeuze).
class CameraLivePlayer extends ConsumerStatefulWidget {
  const CameraLivePlayer({
    super.key,
    required this.info,
    this.fit = BoxFit.contain,
    this.expand = false,
    this.onIntrinsicAspect,
  });

  final CameraInfo info;
  final BoxFit fit;
  /// Fill the parent instead of locking to [CameraInfo.aspectRatio].
  final bool expand;
  /// Real frame width/height once the stream has a picture.
  final ValueChanged<double>? onIntrinsicAspect;

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
    if (mounted) setState(() => _streamReady = true);
    if (isDemoToken(ref.read(authProvider).token)) return;
    final auth = ref.read(authProvider);
    // Niet op dit verzoek wachten: de recorder levert het eerste beeld
    // pas na een keyframe, en dat hield het scherm seconden leeg.
    warmCameraStream(cameraId: widget.info.id, token: auth.token).catchError(
      (_) => false,
    );
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
    if (isDemoToken(ref.watch(authProvider.select((auth) => auth.token)))) {
      final doorStation = ref.watch(configProvider).maybeWhen(
            data: (cfg) =>
                cfg.deviceById(widget.info.id)?.type == DeviceType.intercom,
            orElse: () => false,
          );
      return DemoCameraView(
        label: widget.info.name,
        seed: widget.info.id,
        expand: widget.expand,
        aspectRatio: widget.info.aspectRatio,
        doorStation: doorStation,
      );
    }
    if (!_streamReady) {
      final spinner = Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LuxeColors.brass,
          ),
        ),
      );
      if (widget.expand) return spinner;
      return AspectRatio(
        aspectRatio: widget.info.aspectRatio,
        child: spinner,
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
        expand: widget.expand,
        videoOnly: true,
        onFailed: _onWebRtcFailed,
        onIntrinsicAspect: widget.onIntrinsicAspect,
      );
    }

    if (_effectiveHlsUrl.isNotEmpty) {
      return CameraPlayer(
        key: ValueKey('hls-${widget.info.id}'),
        hlsUrl: _effectiveHlsUrl,
        aspectRatio: widget.info.aspectRatio,
        muted: false,
        fit: widget.fit,
        expand: widget.expand,
        interactive: true,
        onIntrinsicAspect: widget.onIntrinsicAspect,
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
