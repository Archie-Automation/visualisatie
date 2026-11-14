import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../camera_api.dart';
import '../../server_route.dart';
import '../../demo/demo_camera_view.dart';
import '../../demo/demo_session.dart';
import '../../models.dart';
import 'camera_player.dart';
import 'camera_snapshot.dart';
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

  void _onWebRtcFailed() {
    if (_effectiveHlsUrl.isEmpty || !mounted) return;
    setState(() => _useHlsFallback = true);
  }

  /// Cloudadres of de app-route buitenshuis. Thuis blijft WebRTC.
  bool get _offLan {
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') return false;
      if (RegExp(r'^192\.168\.\d{1,3}\.\d{1,3}$').hasMatch(host)) return false;
      if (RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
        return false;
      }
      final ten = RegExp(r'^10\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(host);
      if (ten != null && ten.group(1) != '80') return false;
      return true;
    }
    return activeRoute == RouteKind.remote;
  }

  /// Altijd via de host waar de app nu op zit. De API kan een LAN-adres
  /// teruggeven; dat haalt een telefoon buitenshuis niet op.
  String get _effectiveHlsUrl =>
      '$apiBase/api/cameras/${widget.info.id}/hls.m3u8';

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

    // Buitenshuis is UDP 8555 dicht. De stream komt dan via de server (HLS),
    // niet via een directe WebRTC-kandidaat die de telefoon niet kan bereiken.
    final tryWebRtc = widget.info.webrtcUrl.isNotEmpty &&
        !_useHlsFallback &&
        !_offLan;

    final Widget live;
    if (tryWebRtc) {
      live = WebRTCCameraPlayer(
        key: ValueKey('webrtc-${widget.info.id}'),
        signallingPath: 'cameras/${widget.info.id}',
        aspectRatio: widget.info.aspectRatio,
        fit: widget.fit,
        expand: true,
        opaqueBackground: false,
        videoOnly: true,
        onFailed: _onWebRtcFailed,
        onIntrinsicAspect: widget.onIntrinsicAspect,
      );
    } else if (_effectiveHlsUrl.isNotEmpty) {
      live = CameraPlayer(
        key: ValueKey('hls-${widget.info.id}'),
        hlsUrl: _effectiveHlsUrl,
        aspectRatio: widget.info.aspectRatio,
        muted: true,
        fit: widget.fit,
        expand: true,
        poster: true,
        onIntrinsicAspect: widget.onIntrinsicAspect,
      );
    } else {
      live = const SizedBox.shrink();
    }

    // Still meteen, live eroverheen zodra WebRTC of HLS een beeld heeft.
    final picture = Stack(
      fit: StackFit.expand,
      children: [
        CameraSnapshot(
          cameraId: widget.info.id,
          aspectRatio: widget.info.aspectRatio,
          fit: widget.fit,
          expand: true,
          showLiveBadge: false,
          radius: 0,
          onIntrinsicAspect: widget.onIntrinsicAspect,
        ),
        live,
      ],
    );
    if (widget.expand) return picture;
    return AspectRatio(
      aspectRatio: widget.info.aspectRatio,
      child: picture,
    );
  }
}
