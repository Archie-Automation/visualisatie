import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../../api.dart';
import '../../theme.dart';

/// Full intercom WebRTC session: video + audio down, audio up (talk).
/// The mic transceiver is created up-front but held in a disabled state;
/// the parent toggles [talking] to mute/unmute without renegotiating SDP.
class IntercomPlayer extends ConsumerStatefulWidget {
  const IntercomPlayer({
    super.key,
    required this.intercomId,
    required this.aspectRatio,
    required this.talking,
    this.fit = BoxFit.contain,
  });

  final String intercomId;
  final double aspectRatio;
  final bool talking;
  final BoxFit fit;

  @override
  ConsumerState<IntercomPlayer> createState() => _IntercomPlayerState();
}

class _IntercomPlayerState extends ConsumerState<IntercomPlayer> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _error;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant IntercomPlayer old) {
    super.didUpdateWidget(old);
    if (old.intercomId != widget.intercomId) {
      _restart();
    } else if (old.talking != widget.talking) {
      _applyMicEnabled();
    }
  }

  Future<void> _restart() async {
    await _teardown();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _error = null;
    });
    await _start();
  }

  Future<void> _start() async {
    try {
      await _renderer.initialize();

      // Ask for the mic eagerly – answering a call with permission prompts
      // mid-conversation is a bad UX. We keep the track disabled until the
      // user presses talk.
      final micOk = await Permission.microphone.request();
      if (!micOk.isGranted) {
        throw StateError('microfoontoestemming geweigerd');
      }

      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.cloudflare.com:3478'}
        ],
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;

      pc.onTrack = (e) {
        if (e.track.kind == 'video' && e.streams.isNotEmpty) {
          _renderer.srcObject = e.streams.first;
          if (!mounted) return;
          setState(() => _connected = true);
        }
      };
      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (!mounted) return;
          setState(() => _error = 'verbinding verbroken');
        }
      };

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = widget.talking;
        await pc.addTrack(track, _localStream!);
      }

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      final auth = ref.read(authProvider);
      final resp = await http.post(
        Uri.parse('$apiBase/api/intercoms/${widget.intercomId}/webrtc'),
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
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _applyMicEnabled() {
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = widget.talking;
    }
  }

  Future<void> _teardown() async {
    try {
      _renderer.srcObject = null;
    } catch (_) {}
    try {
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  @override
  void dispose() {
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
            if (_connected)
              RTCVideoView(
                _renderer,
                objectFit: widget.fit == BoxFit.cover
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                mirror: false,
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
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
              )
            else
              Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: LuxeColors.brass),
                ),
              ),
            Positioned(
              top: 10,
              left: 10,
              child: _Badge(talking: widget.talking, connected: _connected),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.talking, required this.connected});
  final bool talking;
  final bool connected;
  @override
  Widget build(BuildContext context) {
    if (!connected) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: talking ? LuxeColors.brass : Color(0xFFE44B4B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            talking ? 'SPREKEN' : 'LIVE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
