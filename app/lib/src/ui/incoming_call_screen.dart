import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api.dart';
import '../camera_api.dart';
import '../intercom/intercom_controller.dart';
import '../intercom/intercom_sip_types.dart';
import '../theme.dart';

/// Volledig scherm voor inkomende SIP-intercom (en actieve gespreksknoppen).
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.controller});

  final IntercomController controller;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remote.initialize();
    if (mounted) setState(() => _rendererReady = true);
  }

  @override
  void didUpdateWidget(covariant IncomingCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCtrl);
      widget.controller.addListener(_onCtrl);
    }
  }

  void _onCtrl() {
    final s = widget.controller.remoteStream;
    if (_rendererReady && _remote.srcObject != s) {
      _remote.srcObject = s;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _remote.dispose();
    super.dispose();
  }

  Future<void> _openDoor() async {
    final id = widget.controller.boundIntercomId;
    if (id == null) return;
    final auth = ref.read(authProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await releaseIntercomDoor(intercomId: id, token: auth.token);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Deuropen-commando verzonden'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deur: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ring = ref.watch(intercomRingProvider);
    final phase = c.phase;
    if (phase == IntercomSipPhase.idle) return const SizedBox.shrink();

    final remoteName = c.remoteLabel ?? 'Onbekend';
    final canDoor = c.boundIntercomId != null;

    return Material(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              if (ring != null)
                Text(
                  'Ook gemeld op KNX-busmonitor',
                  style: TextStyle(
                    color: LuxeColors.brassGlow.withValues(alpha: 0.85),
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
              SizedBox(height: 12),
              Text(
                phase == IntercomSipPhase.ringing
                    ? 'INKOMENDE SIP-OPROEP'
                    : 'GESPREK',
                style: TextStyle(
                  color: LuxeColors.brassGlow,
                  fontSize: 11,
                  letterSpacing: 2.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Text(
                remoteName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: c.remoteStream != null && _rendererReady
                      ? RTCVideoView(
                          _remote,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Container(
                          alignment: Alignment.center,
                          color: const Color(0xFF1A1A22),
                          child: Icon(
                            phase == IntercomSipPhase.ringing
                                ? Icons.videocam_outlined
                                : Icons.graphic_eq,
                            size: 56,
                            color: Colors.white24,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  if (phase == IntercomSipPhase.ringing) ...[
                    _RoundAction(
                      label: 'Weigeren',
                      icon: Icons.call_end,
                      color: LuxeColors.danger,
                      onTap: () {
                        ref.read(intercomRingProvider.notifier).clear();
                        c.declineCall();
                      },
                    ),
                    _RoundAction(
                      label: 'Opnemen',
                      icon: Icons.call,
                      color: const Color(0xFF2E7D32),
                      onTap: () async {
                        ref.read(intercomRingProvider.notifier).clear();
                        await c.answerCall();
                      },
                    ),
                  ] else ...[
                    _RoundAction(
                      label: c.muted ? 'Unmute' : 'Mute',
                      icon: c.muted ? Icons.mic_off : Icons.mic_none,
                      color: LuxeColors.brass,
                      onTap: c.toggleMute,
                    ),
                    if (canDoor)
                      _RoundAction(
                        label: 'Deur open',
                        icon: Icons.lock_open_outlined,
                        color: LuxeColors.brass,
                        onTap: _openDoor,
                      ),
                    _RoundAction(
                      label: 'Ophangen',
                      icon: Icons.call_end,
                      color: LuxeColors.danger,
                      onTap: () {
                        ref.read(intercomRingProvider.notifier).clear();
                        c.hangup();
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Icon(icon, color: color, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
