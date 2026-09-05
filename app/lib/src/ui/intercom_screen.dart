import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../camera_api.dart';
import '../intercom/intercom_controller.dart';
import '../intercom/intercom_sip_providers.dart';
import '../intercom/intercom_sip_types.dart';
import '../models.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/camera_snapshot.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/intercom_player.dart';
import 'widgets/live_video_stage.dart';
import 'widgets/luxe_backdrop.dart';
import 'widgets/webrtc_camera_player.dart';

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
  bool _warmScheduled = false;
  bool _closing = false;
  bool _inConversation = false;
  bool _previewFailed = false;
  bool _previewLive = false;

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

  void _ensureWarm() {
    if (_warmScheduled) return;
    _warmScheduled = true;
    final token = ref.read(authProvider).token;
    unawaited(
      warmIntercomStream(intercomId: widget.intercomId, token: token)
          .then((_) {}, onError: (_) {}),
    );
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
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureSipUaFromConfig();
                _ensureWarm();
              });
            }
            final phone = context.isPhone;
            final showRelease = i.canRelease &&
                intercomHasReleaseTarget(
                    ref.watch(configProvider).value?.deviceById(i.id));
            final hPad = phone ? 12.0 : 16.0;
            final stagePad = EdgeInsets.fromLTRB(hPad, 4, hPad, 8);
            return SafeArea(
              child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: stagePad,
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.75,
                        heightFactor: 0.75,
                        child: LiveVideoStage(
                      heroTag: 'intercom-${i.id}',
                      child: waiting
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                if (!_previewLive)
                                  CameraSnapshot(
                                    cameraId: i.id,
                                    aspectRatio: i.aspectRatio,
                                    kind: SnapshotKind.intercom,
                                    fit: BoxFit.cover,
                                    expand: true,
                                    showLiveBadge: false,
                                  ),
                                if (!_previewFailed)
                                  WebRTCCameraPlayer(
                                    signallingPath: 'intercoms/${i.id}',
                                    aspectRatio: i.aspectRatio,
                                    fit: BoxFit.cover,
                                    expand: true,
                                    videoOnly: true,
                                    opaqueBackground: false,
                                    connectTimeout:
                                        const Duration(seconds: 8),
                                    maxAttempts: 2,
                                    onConnected: () {
                                      if (mounted) {
                                        setState(() => _previewLive = true);
                                      }
                                    },
                                    onFailed: () {
                                      if (mounted) {
                                        setState(() => _previewFailed = true);
                                      }
                                    },
                                  ),
                              ],
                            )
                          : IntercomPlayer(
                              intercomId: i.id,
                              aspectRatio: i.aspectRatio,
                              talking: true,
                              fit: BoxFit.cover,
                              expand: true,
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
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 28),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.75,
                      child: SizedBox(
                        width: double.infinity,
                        child: LuxeRimBox(
                          radius: 28,
                          rimWidth: 1.25,
                          fillColor: LuxeColors.surface.withValues(
                            alpha: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? 0.28
                                : 0.18,
                          ),
                          rimColor: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? LuxeColors.line
                              : LuxeBorders.solid(
                                  LuxeColors.ink.withValues(alpha: 0.22),
                                ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _ActionButton(
                                icon: Icons.call_end_rounded,
                                label: 'OPHANGEN',
                                color: _kCallHangup,
                                shake: ringing,
                                onTap: () => _cancel(sip),
                              ),
                              if (waiting)
                                _ActionButton(
                                  icon: Icons.call_rounded,
                                  label: 'OPNEMEN',
                                  color: _kCallAnswer,
                                  shake: ringing,
                                  onTap: () => _answer(sip),
                                ),
                              if (showRelease)
                                _ActionButton(
                                  icon: Icons.lock_open_rounded,
                                  label: 'DEUR OPEN',
                                  color: _kCallDoor,
                                  loading: _releasing,
                                  onTap: () => _release(i),
                                ),
                            ],
                          ),
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
    duration: const Duration(milliseconds: 1600),
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
        // One short ring, pause, one short ring, then a longer rest.
        double envelope = 0;
        if (t < 0.14) {
          envelope = math.sin((t / 0.14) * math.pi);
        } else if (t >= 0.28 && t < 0.42) {
          envelope = math.sin(((t - 0.28) / 0.14) * math.pi);
        }
        return Transform.rotate(
          angle: envelope * 0.09,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Same fills in light and dark — palette danger/brass wash out in dark mode.
const _kCallHangup = Color(0xFFB83A3A);
const _kCallAnswer = Color(0xFF3E6B4F);
const _kCallDoor = Color(0xFFA67C3D);
const _kCallOnFill = Color(0xFFF7F4EC);

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
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.34),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kCallOnFill,
                  ),
                ),
              )
            : Icon(icon, color: _kCallOnFill, size: 30),
      ),
    );
    return Column(
      children: [
        _AlarmShake(enabled: shake && !loading, child: circle),
        const SizedBox(height: 12),
        Text(label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

/// True when house.json has a real unlock target (KNX / HTTP / DoorBird).
bool intercomHasReleaseTarget(Device? device) {
  if (device == null) return false;
  final ic = device.raw['intercom'];
  if (ic is! Map) return false;
  final mode = '${ic['releaseMode'] ?? ''}'.trim();
  final ga = ic['release'] is Map
      ? '${(ic['release'] as Map)['ga'] ?? ''}'.trim()
      : '';
  final url = ic['httpRelease'] is Map
      ? '${(ic['httpRelease'] as Map)['url'] ?? ''}'.trim()
      : '';
  final db = ic['doorbird'] is Map ? ic['doorbird'] as Map : null;
  final doorbirdOk = db != null &&
      '${db['host'] ?? ''}'.trim().isNotEmpty &&
      '${db['username'] ?? ''}'.trim().isNotEmpty &&
      '${db['password'] ?? ''}'.isNotEmpty;
  if (mode == 'http') return url.isNotEmpty;
  if (mode == 'doorbird') return doorbirdOk;
  if (mode == 'knx') return ga.isNotEmpty;
  return url.isNotEmpty || ga.isNotEmpty || doorbirdOk;
}
