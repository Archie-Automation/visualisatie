import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../api.dart';
import '../../theme.dart';

/// View-only WebRTC player for surveillance cameras.
class WebRTCCameraPlayer extends ConsumerStatefulWidget {
  const WebRTCCameraPlayer({
    super.key,
    required this.signallingPath,
    required this.aspectRatio,
    this.fit = BoxFit.cover,
    this.showLiveBadge = true,
    this.muted = true,
    this.videoOnly = false,
    this.onFailed,
  });

  final String signallingPath;
  final double aspectRatio;
  final BoxFit fit;
  final bool showLiveBadge;
  final bool muted;
  final bool videoOnly;
  final VoidCallback? onFailed;

  @override
  ConsumerState<WebRTCCameraPlayer> createState() =>
      _WebRTCCameraPlayerState();
}

class _WebRTCCameraPlayerState extends ConsumerState<WebRTCCameraPlayer> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _error;
  bool _connected = false;
  Timer? _connectTimeout;
  Timer? _iceWatchdog;
  bool _failedNotified = false;
  int _attempt = 0;
  bool _rendererReady = false;

  static const _maxAttempts = 5;
  static const _connectTimeoutDuration = Duration(seconds: 25);
  static const _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant WebRTCCameraPlayer old) {
    super.didUpdateWidget(old);
    if (old.signallingPath != widget.signallingPath) {
      _attempt = 0;
      _restart();
    }
  }

  Future<void> _restart() async {
    _connectTimeout?.cancel();
    _iceWatchdog?.cancel();
    await _teardown();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _error = null;
      _failedNotified = false;
    });
    await _start();
  }

  void _notifyFailed(String message) {
    if (_attempt + 1 < _maxAttempts) {
      _attempt++;
      Future<void>.delayed(_retryDelay, () {
        if (mounted) _restart();
      });
      return;
    }
    if (_failedNotified) return;
    _failedNotified = true;
    _connectTimeout?.cancel();
    _iceWatchdog?.cancel();
    if (!mounted) return;
    setState(() => _error = message);
    widget.onFailed?.call();
  }

  void _armConnectTimeout() {
    _connectTimeout?.cancel();
    _connectTimeout = Timer(_connectTimeoutDuration, () {
      if (!mounted || _connected) return;
      _notifyFailed('live stream timeout');
    });
  }

  void _armIceWatchdog(RTCPeerConnection pc) {
    _iceWatchdog?.cancel();
    _iceWatchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || pc != _pc) return;
      final ice = pc.iceConnectionState;
      if (ice == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _notifyFailed('WebRTC ICE mislukt');
      } else if (_connected &&
          (ice == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              ice ==
                  RTCIceConnectionState.RTCIceConnectionStateClosed)) {
        _notifyFailed('verbinding verbroken');
      }
    });
  }

  Future<void> _start() async {
    _armConnectTimeout();
    try {
      if (!_rendererReady) {
        await _renderer.initialize();
        _rendererReady = true;
      }
      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.cloudflare.com:3478'},
        ],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      });
      _pc = pc;
      _armIceWatchdog(pc);

      pc.onTrack = (e) {
        if (e.track.kind == 'video' && e.streams.isNotEmpty) {
          _renderer.srcObject = e.streams.first;
          if (!mounted) return;
          _connectTimeout?.cancel();
          setState(() => _connected = true);
        }
      };
      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          if (_connected) {
            _notifyFailed('verbinding verbroken');
          } else {
            _notifyFailed('verbinding mislukt');
          }
        }
      };

      if (!widget.videoOnly) {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init:
              RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      final auth = ref.read(authProvider);
      final resp = await http.post(
        Uri.parse('$apiBase/api/${widget.signallingPath}/webrtc'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${auth.token}',
        },
        body: jsonEncode({'type': 'offer', 'sdp': offer.sdp}),
      );
      if (resp.statusCode != 200) {
        throw StateError('signalling http ${resp.statusCode}: ${resp.body}');
      }
      final answer = jsonDecode(resp.body) as Map<String, dynamic>;
      await pc.setRemoteDescription(
        RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
      );
    } catch (e) {
      _notifyFailed('$e');
    }
  }

  Future<void> _teardown() async {
    _connectTimeout?.cancel();
    _iceWatchdog?.cancel();
    try {
      _renderer.srcObject = null;
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  @override
  void dispose() {
    _connectTimeout?.cancel();
    _iceWatchdog?.cancel();
    _teardown();
    _renderer.dispose();
    super.dispose();
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
            AnimatedOpacity(
              opacity: _connected ? 1.0 : 0.0,
              duration: Duration(milliseconds: 300),
              child: RTCVideoView(
                _renderer,
                objectFit: widget.fit == BoxFit.cover
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                mirror: false,
              ),
            ),
            if (!_connected && _error == null)
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
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined,
                          color: Colors.white54, size: 32),
                      const SizedBox(height: 8),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            if (widget.showLiveBadge && _connected)
              const Positioned(
                top: 10,
                left: 10,
                child: _LiveBadge(),
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
            _PulseDot(color: Color(0xFFE44B4B)),
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
  const _PulseDot({required this.color});
  final Color color;
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
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}
