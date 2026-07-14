import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api.dart';
import '../../theme.dart';

/// Sits above the whole app. When an `intercom.ring` event comes in over
/// the bus WebSocket, slides in from the top, loops a haptic heartbeat and
/// offers a one-tap "Opnemen" action that deep-links to the intercom
/// screen. Native CallKit / ConnectionService is driven in parallel by
/// [CallService]; this banner covers the in-app foreground case where a
/// full-screen native call UI would be overkill.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<IncomingCallOverlay> createState() =>
      _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  Timer? _hapticTimer;
  int? _lastHandledTs;

  @override
  void dispose() {
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _startHaptics() {
    _hapticTimer?.cancel();
    HapticFeedback.heavyImpact();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.heavyImpact();
      // Subtle audible click for the cases where CallKit isn't wired
      // (e.g. Flutter desktop dev builds).
      SystemSound.play(SystemSoundType.alert);
    });
  }

  void _stopHaptics() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final ring = ref.watch(intercomRingProvider);

    if (ring != null && ring.ts != _lastHandledTs) {
      _lastHandledTs = ring.ts;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startHaptics());
    } else if (ring == null && _hapticTimer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stopHaptics());
    }

    return Stack(
      children: [
        widget.child,
        AnimatedSlide(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          offset: ring == null ? const Offset(0, -1.2) : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: ring == null ? 0 : 1,
            child: ring == null ? const SizedBox.shrink() : _Banner(ring: ring),
          ),
        ),
      ],
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.ring});
  final IntercomRing ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 18, 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF23232A), Color(0xFF14141A)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: LuxeColors.brass.withValues(alpha: 0.25),
              ),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 42,
                    offset: Offset(0, 18)),
                BoxShadow(
                    color: Color(0x33B08A4E),
                    blurRadius: 60,
                    spreadRadius: -10,
                    offset: Offset(0, 20)),
              ],
            ),
            child: Row(
              children: [
                const _RingIcon(),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('INKOMENDE OPROEP',
                          style: TextStyle(
                            color: LuxeColors.brassGlow,
                            fontSize: 10,
                            letterSpacing: 2.8,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 6),
                      Text(ring.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ),
                _round(
                  icon: Icons.call_end,
                  color: LuxeColors.danger,
                  onTap: () =>
                      ref.read(intercomRingProvider.notifier).clear(),
                ),
                const SizedBox(width: 12),
                _round(
                  icon: Icons.call,
                  color: LuxeColors.brass,
                  onTap: () {
                    ref.read(intercomRingProvider.notifier).clear();
                    context.push('/intercom/${ring.intercomId}');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _round({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}

class _RingIcon extends StatefulWidget {
  const _RingIcon();
  @override
  State<_RingIcon> createState() => _RingIconState();
}

class _RingIconState extends State<_RingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.rotate(
          angle: (_c.value - 0.5) * 0.3,
          child: const Icon(Icons.notifications_active,
              color: LuxeColors.brass, size: 28),
        ),
      );
}
