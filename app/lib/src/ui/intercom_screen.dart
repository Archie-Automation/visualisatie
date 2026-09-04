import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../camera_api.dart';
import '../intercom/intercom_controller.dart';
import '../intercom/intercom_sip_providers.dart';
import '../intercom/intercom_sip_types.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'widgets/camera_snapshot.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/intercom_player.dart';
import 'widgets/luxe_backdrop.dart';

class IntercomScreen extends ConsumerStatefulWidget {
  const IntercomScreen({super.key, required this.intercomId});
  final String intercomId;

  @override
  ConsumerState<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends ConsumerState<IntercomScreen> {
  bool _releasing = false;
  String? _releaseFeedback;
  bool _sipUaStarted = false;
  bool _sipDiscoveryScheduled = false;
  bool _closing = false;
  bool _inConversation = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  bool _isRinging({
    required IntercomRing? ring,
    required IntercomSipPhase sipPhase,
  }) {
    if (ring != null &&
        ring.intercomId == widget.intercomId &&
        !ring.answeredElsewhere) {
      return true;
    }
    return sipPhase == IntercomSipPhase.ringing;
  }

  Future<void> _answer(IntercomController sip) async {
    if (_inConversation) return;
    setState(() => _inConversation = true);
    if (sip.phase == IntercomSipPhase.ringing) {
      await sip.answerCall();
    }
    ref.read(intercomRingProvider.notifier).clear();
  }

  void _cancel(IntercomController sip) {
    if (_closing) return;
    _closing = true;
    if (sip.phase == IntercomSipPhase.ringing) {
      sip.declineCall();
    } else if (sip.phase == IntercomSipPhase.inCall) {
      sip.hangup();
    }
    ref.read(intercomRingProvider.notifier).clear();
    if (mounted) appBack(context);
  }

  void _ensureSipUaFromConfig() {
    if (_sipUaStarted) return;
    final cfg = ref.read(configProvider).value;
    if (cfg == null) return;
    final device = cfg.deviceById(widget.intercomId);
    if (device == null) return;
    final ic = device.raw['intercom'];
    if (ic is! Map) return;
    final kind = ic['kind'] as String?;
    if (kind != 'sip') return;
    _sipUaStarted = true;
    ref.read(intercomSipControllerProvider).startFromHouseIntercom(
          intercomId: widget.intercomId,
          houseIntercom: Map<String, dynamic>.from(ic),
        );
  }

  Future<void> _release(IntercomInfo i) async {
    if (_releasing) return;

    // Surface an "are you sure?" prompt if the config requests one.
    final cfg = ref.read(configProvider).value;
    final device = cfg?.deviceById(i.id);
    final prompt = device?.confirm?.actions['release'];
    final ok = await maybeConfirm(context, prompt);
    if (!ok) return;

    setState(() {
      _releasing = true;
      _releaseFeedback = null;
    });
    try {
      final auth = ref.read(authProvider);
      await releaseIntercomDoor(intercomId: i.id, token: auth.token);
      if (!mounted) return;
      setState(() => _releaseFeedback = 'Deur geopend');
    } catch (e) {
      if (!mounted) return;
      setState(() => _releaseFeedback = 'Fout: $e');
    } finally {
      if (mounted) {
        setState(() => _releasing = false);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _releaseFeedback = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(intercomInfoProvider(widget.intercomId));
    final ring = ref.watch(intercomRingProvider);
    final sip = ref.watch(intercomSipControllerProvider);

    return ListenableBuilder(
      listenable: sip,
      builder: (context, _) {
        final waiting = !_inConversation;
        final ringing =
            waiting && _isRinging(ring: ring, sipPhase: sip.phase);
        if (!_closing &&
            ring != null &&
            ring.answeredElsewhere &&
            ring.intercomId == widget.intercomId) {
          _closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) appBack(context);
          });
        }

        return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: info.maybeWhen(
          data: (i) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('INTERCOM',
                  style: TextStyle(
                    color: LuxeColors.brass,
                    fontSize: 10,
                    letterSpacing: 2.6,
                    fontWeight: FontWeight.w600,
                  )),
              Text(i.name,
                  style: TextStyle(
                    color: LuxeColors.ink,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                    fontSize: 18,
                  )),
            ],
          ),
          orElse: () => SizedBox.shrink(),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Sluiten',
          onPressed: () => _cancel(sip),
        ),
      ),
      body: LuxeBackdrop(
        child: info.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: LuxeColors.brass),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Kan intercom niet laden:\n$e',
                  style: TextStyle(color: LuxeColors.inkSoft),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (i) {
            if (!_sipDiscoveryScheduled) {
              _sipDiscoveryScheduled = true;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _ensureSipUaFromConfig());
            }
            return SafeArea(
              child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Hero(
                      tag: 'intercom-${i.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: LuxeShadows.darkLift,
                          ),
                          child: waiting
                              ? CameraSnapshot(
                                  cameraId: i.id,
                                  aspectRatio: i.aspectRatio,
                                  kind: SnapshotKind.intercom,
                                  fit: BoxFit.cover,
                                )
                              : IntercomPlayer(
                                  intercomId: i.id,
                                  aspectRatio: i.aspectRatio,
                                  talking: true,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_releaseFeedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: LuxeColors.brass.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(_releaseFeedback!,
                          style: TextStyle(
                            color: LuxeColors.brassGlow,
                            letterSpacing: 2,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(28, 18, 28, 28),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 24),
                        decoration: BoxDecoration(
                          color: LuxeColors.surface.withValues(alpha: 0.80),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: LuxeColors.line,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ActionButton(
                              icon: Icons.call_end,
                              label: 'OPHANGEN',
                              color: LuxeColors.danger,
                              shake: ringing,
                              onTap: () => _cancel(sip),
                            ),
                            if (waiting)
                              _ActionButton(
                                icon: Icons.call,
                                label: 'OPNEMEN',
                                color: const Color(0xFF2E7D32),
                                shake: ringing,
                                onTap: () => _answer(sip),
                              )
                            else
                              const SizedBox(width: 72),
                            if (i.canRelease)
                              _ActionButton(
                                icon: Icons.lock_open_outlined,
                                label: 'DEUR OPEN',
                                color: LuxeColors.brass,
                                loading: _releasing,
                                onTap: () => _release(i),
                              )
                            else
                              const SizedBox(width: 72),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            );
          },
        ),
      ),
    );
      },
    );
  }
}

class _AlarmShake extends StatefulWidget {
  const _AlarmShake({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<_AlarmShake> createState() => _AlarmShakeState();
}

class _AlarmShakeState extends State<_AlarmShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _AlarmShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.enabled && _c.isAnimating) {
      _c.stop();
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // Burst like a mechanical alarm: ring-ring, then a beat of rest.
        final ringing = t < 0.55;
        final local = ringing ? t / 0.55 : 0.0;
        final wiggle = ringing ? math.sin(local * math.pi * 10) : 0.0;
        final decay = ringing ? (1.0 - local * 0.35) : 0.0;
        return Transform.rotate(
          angle: wiggle * 0.38 * decay,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
    this.shake = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;
  final bool shake;

  @override
  Widget build(BuildContext context) {
    final circle = GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(
              color: color.withValues(alpha: 0.55), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: -4,
            ),
          ],
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: LuxeColors.ink),
                ),
              )
            : Icon(icon, color: color, size: 28),
      ),
    );
    return Column(
      children: [
        _AlarmShake(enabled: shake && !loading, child: circle),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 10,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
