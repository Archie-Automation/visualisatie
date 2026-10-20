import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../camera_api.dart';
import '../inactivity_controller.dart';
import '../installer/intercom_sip_config.dart';
import '../intercom/intercom_controller.dart';
import '../intercom/intercom_release_ui.dart';
import '../intercom/intercom_sip_providers.dart';
import '../intercom/intercom_sip_types.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/camera_snapshot.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/gate_icon.dart';
import 'widgets/intercom_capture_overlay.dart';
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
  bool _opened = false;
  Timer? _openedTimer;
  bool _sipUaStarted = false;
  bool _sipDiscoveryScheduled = false;
  bool _closing = false;
  bool _inConversation = false;
  bool _previewFailed = false;
  bool _previewLive = false;
  bool _lineFetched = false;
  bool _claimed = false;
  String? _notice;
  bool _callWasLive = false;
  Timer? _homeTimer;
  bool _homeQueued = false;

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

  void _snack(String message) {
    setState(() => _notice = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _ensureLine() {
    if (_lineFetched) return;
    _lineFetched = true;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    unawaited(
      fetchIntercomLine(intercomId: widget.intercomId, token: token).then((s) {
        if (s == null) return;
        ref.read(intercomLineProvider.notifier).setLine(widget.intercomId, s);
      }),
    );
  }

  Future<void> _releaseClaim() async {
    if (!_claimed) return;
    _claimed = false;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    await releaseIntercomLine(intercomId: widget.intercomId, token: token);
  }

  Future<void> _answer(IntercomController sip) async {
    if (_inConversation || sip.phase == IntercomSipPhase.inCall) return;
    if (sip.phase == IntercomSipPhase.ringing) {
      setState(() => _inConversation = true);
      debugPrint('[SIP] UI opnemen fase=${sip.phase.name}');
      await sip.answerCall();
      ref.read(intercomRingProvider.notifier).clear();
      return;
    }
    if (kIsWeb) {
      _snack(
        'Praten en luisteren kan in de browser niet. Het paneel belt wel mee.',
      );
      return;
    }
    final token = ref.read(authProvider).token;
    if (token == null) return;
    // Arm vóór het verzoek: de DoorBird kan al bellen voordat het antwoord
    // van de server binnen is.
    sip.armMonitorAnswer();
    final claim = await claimIntercomLine(
      intercomId: widget.intercomId,
      token: token,
    );
    if (!mounted) {
      sip.disarmMonitorAnswer();
      return;
    }
    final callback = claim.mode == 'callback';
    if (!claim.ok ||
        (!callback && (claim.target == null || claim.target!.isEmpty))) {
      sip.disarmMonitorAnswer();
      final line = claim.state;
      if (line != null && line.isNotEmpty) {
        ref.read(intercomLineProvider.notifier).setLine(widget.intercomId, line);
      }
      _snack(claim.error ?? 'Er is al een gesprek.');
      return;
    }
    setState(() {
      _inConversation = true;
      _notice = null;
    });
    _claimed = true;
    if (callback) return;
    sip.disarmMonitorAnswer();
    final err = await sip.placeCall(claim.target!);
    if (!mounted) return;
    if (err != null) {
      await _releaseClaim();
      setState(() => _inConversation = false);
      _snack(err);
    }
  }

  bool _callStillLive() {
    if (_inConversation) return true;
    final sip = ref.read(intercomSipControllerProvider);
    final ring = ref.read(intercomRingProvider);
    return sip.phase == IntercomSipPhase.ringing ||
        sip.phase == IntercomSipPhase.inCall ||
        (ring != null &&
            ring.intercomId == widget.intercomId &&
            !ring.answeredElsewhere);
  }

  void _goHomeNow() {
    if (_closing) return;
    _closing = true;
    _homeTimer?.cancel();
    _homeTimer = null;
    if (!mounted) return;
    context.go('/');
  }

  /// Na ophangen het beeld nog even laten staan, dan pas het beginscherm.
  void _scheduleHome() {
    if (_homeTimer != null || _closing) return;
    ref.read(inactivityControllerProvider.notifier).registerActivity();
    _homeTimer = Timer(const Duration(seconds: 5), () {
      _homeTimer = null;
      if (!mounted || _closing) return;
      if (_callStillLive()) return;
      unawaited(_releaseClaim());
      final ringNow = ref.read(intercomRingProvider);
      if (ringNow != null && ringNow.intercomId == widget.intercomId) {
        ref.read(intercomRingProvider.notifier).clear();
      }
      _goHomeNow();
    });
  }

  void _queueHome() {
    if (_homeQueued || _homeTimer != null || _closing) return;
    _homeQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeQueued = false;
      if (!mounted || _closing || _homeTimer != null) return;
      if (_callStillLive()) return;
      _scheduleHome();
    });
  }

  void _cancel(IntercomController sip) {
    if (_homeTimer != null) {
      _goHomeNow();
      return;
    }
    if (_closing) return;
    final live = _callWasLive ||
        _inConversation ||
        sip.phase == IntercomSipPhase.inCall ||
        sip.phase == IntercomSipPhase.ringing;
    sip.disarmMonitorAnswer();
    unawaited(_releaseClaim());
    if (sip.phase == IntercomSipPhase.ringing) {
      sip.declineCall();
    } else if (sip.phase == IntercomSipPhase.inCall) {
      sip.hangup();
    }
    ref.read(intercomRingProvider.notifier).clear();
    if (!live) {
      _closing = true;
      if (mounted) appBack(context);
      return;
    }
    _scheduleHome();
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

  @override
  void dispose() {
    _openedTimer?.cancel();
    _homeTimer?.cancel();
    super.dispose();
  }

  void _flashOpened() {
    _openedTimer?.cancel();
    setState(() => _opened = true);
    _openedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _opened = false);
    });
  }

  Future<void> _release(IntercomInfo i, IntercomController sip) async {
    if (_releasing) return;

    // Surface an "are you sure?" prompt if the config requests one.
    final cfg = ref.read(configProvider).value;
    final device = cfg?.deviceById(i.id);
    final prompt = device?.confirm?.actions['release'];
    final ok = await maybeConfirm(context, prompt);
    if (!ok) return;

    setState(() => _releasing = true);
    try {
      final raw = device?.raw['intercom'];
      final digit = raw is Map
          ? ((raw['dtmfDigit'] as String?)?.trim().isNotEmpty == true
              ? (raw['dtmfDigit'] as String).trim()
              : defaultDtmfDigit)
          : defaultDtmfDigit;
      final viaSip = sip.sendDtmf(digit);
      try {
        final auth = ref.read(authProvider);
        await releaseIntercomDoor(intercomId: i.id, token: auth.token);
      } catch (e) {
        if (!viaSip) rethrow;
      }
      if (!mounted) return;
      _flashOpened();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Openen mislukt: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _releasing = false);
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
        final inTalk = sip.phase == IntercomSipPhase.inCall ||
            (_inConversation && sip.phase == IntercomSipPhase.ringing);
        final waiting = !inTalk;
        final ringing =
            waiting && _isRinging(ring: ring, sipPhase: sip.phase);
        final line = ref.watch(intercomLineProvider)[widget.intercomId];
        final taken = waiting &&
            !_inConversation &&
            !_claimed &&
            sip.phase != IntercomSipPhase.ringing &&
            (line == 'busy' || line == 'dialing');
        final failed = sip.dialError;
        if (failed != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || sip.dialError != failed) return;
            sip.clearDialError();
            setState(() {
              _inConversation = false;
              _notice = failed;
            });
            unawaited(_releaseClaim());
          });
        }
        final dialing = _inConversation &&
            sip.phase != IntercomSipPhase.inCall;
        final sipLive = sip.phase == IntercomSipPhase.ringing ||
            sip.phase == IntercomSipPhase.inCall;
        final ringLive = ring != null &&
            ring.intercomId == widget.intercomId &&
            !ring.answeredElsewhere;
        final placing = _inConversation &&
            !sipLive &&
            !_callWasLive &&
            _notice == null &&
            sip.dialError == null;
        if (sipLive || ringLive) _callWasLive = true;
        final sessionOver = _callWasLive ||
            (ring != null &&
                ring.intercomId == widget.intercomId &&
                ring.answeredElsewhere);
        final otherDoor = ring != null &&
            ring.intercomId != widget.intercomId &&
            !ring.answeredElsewhere;
        if (!_closing &&
            sessionOver &&
            !sipLive &&
            !ringLive &&
            !placing &&
            !otherDoor) {
          _queueHome();
        }

        final title = info.maybeWhen(
          data: (i) => i.name,
          orElse: () => 'Intercom',
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: LuxeBackdrop(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FunctionScreenHeader(
                  onBack: () => _cancel(sip),
                  title: title,
                  subtitle: 'Intercom',
                ),
                Expanded(
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
                _ensureLine();
              });
            }
            final phone = context.isPhone;
            final icRaw = ref.read(configProvider).value?.deviceById(i.id)?.raw['intercom'];
            final intercomRaw = icRaw is Map
                ? Map<String, dynamic>.from(icRaw)
                : null;
            final showRelease = intercomShowsDoorButton(
              canRelease: i.canRelease,
              sipInCall: sip.phase == IntercomSipPhase.inCall,
              intercomRaw: intercomRaw,
            );
            // SIP-gesprek (bellen of opgenomen): geluid via Asterisk,
            // go2rtc alleen beeld. Anders claimt de UI "spreken" zonder mic.
            final sipLive = sip.phase == IntercomSipPhase.ringing ||
                sip.phase == IntercomSipPhase.inCall;
            final releaseIsGate =
                !_opened && intercomReleaseIsGate(intercomRaw);
            final releaseIcon = _opened
                ? Icons.check_rounded
                : Icons.door_front_door_outlined;
            final releaseLabel = intercomReleaseActionLabel(intercomRaw);
            final hPad = phone ? 12.0 : 16.0;
            final stagePad = EdgeInsets.fromLTRB(hPad, 4, hPad, 8);
            return IntercomCaptureScope(
              intercomId: i.id,
              builder: (context, cap) => Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: stagePad,
                    child: LiveVideoFittedStage(
                      aspectRatio: i.aspectRatio,
                      factor: _kIntercomStageFactor,
                      heroTag: 'intercom-${i.id}',
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (waiting || sipLive) ...[
                            if (!_previewLive)
                              CameraSnapshot(
                                cameraId: i.id,
                                aspectRatio: i.aspectRatio,
                                kind: SnapshotKind.intercom,
                                fit: BoxFit.contain,
                                expand: true,
                                showLiveBadge: false,
                              ),
                            if (!_previewFailed)
                              WebRTCCameraPlayer(
                                signallingPath: 'intercoms/${i.id}',
                                aspectRatio: i.aspectRatio,
                                fit: BoxFit.contain,
                                expand: true,
                                videoOnly: true,
                                opaqueBackground: false,
                                connectTimeout: const Duration(seconds: 8),
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
                          ] else
                            IntercomPlayer(
                              intercomId: i.id,
                              aspectRatio: i.aspectRatio,
                              talking: true,
                              fit: BoxFit.contain,
                              expand: true,
                            ),
                          cap.flash,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 28),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: _kIntercomStageFactor,
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
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final callCount = 1 +
                                  (waiting ? 1 : 0) +
                                  (showRelease ? 1 : 0);
                              final count = phone ? callCount : callCount + 2;
                              final diameter =
                                  ((constraints.maxWidth / count) - 8)
                                      .clamp(48.0, 72.0);
                              final photos = [
                                _ActionButton(
                                  icon: Icons.photo_camera_outlined,
                                  label: 'FOTO',
                                  color: _kCallPhoto,
                                  diameter: diameter,
                                  loading: cap.busy,
                                  onTap: cap.takePhoto,
                                ),
                                _ActionButton(
                                  icon: Icons.photo_library_outlined,
                                  label: "FOTO'S",
                                  color: _kCallPhoto,
                                  diameter: diameter,
                                  onTap: cap.openPhotos,
                                ),
                              ];
                              final calls = <Widget>[
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.call_end_rounded,
                                    label: 'OPHANGEN',
                                    color: _kCallHangup,
                                    diameter: diameter,
                                    shake: ringing,
                                    onTap: () => _cancel(sip),
                                  ),
                                ),
                                if (waiting)
                                  Expanded(
                                    child: _ActionButton(
                                      icon: taken
                                          ? Icons.phone_locked_outlined
                                          : Icons.call_rounded,
                                      label: taken ? 'BEZET' : 'OPNEMEN',
                                      color: taken
                                          ? _kCallPhoto
                                          : _kCallAnswer,
                                      diameter: diameter,
                                      shake: ringing && !taken,
                                      onTap: taken
                                          ? () => _snack(
                                                'Er is al een gesprek op deze intercom.',
                                              )
                                          : () => _answer(sip),
                                    ),
                                  ),
                                if (!phone)
                                  for (final photo in photos)
                                    Expanded(child: photo),
                                if (showRelease)
                                  Expanded(
                                    child: _ActionButton(
                                      icon: releaseIcon,
                                      mark: releaseIsGate
                                          ? (size, color) => GateIcon(
                                                size: size,
                                                color: color,
                                              )
                                          : null,
                                      label: releaseLabel,
                                      color: _kCallDoor,
                                      diameter: diameter,
                                      loading: _releasing,
                                      onTap: () => _release(i, sip),
                                    ),
                                  ),
                              ];
                              return Column(
                                children: [
                                  if (_notice != null || dialing)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        _notice ?? 'Bezig met bellen…',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: LuxeColors.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  Row(children: calls),
                                  if (phone) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (final photo in photos) ...[
                                          photo,
                                          if (photo != photos.last)
                                            const SizedBox(width: 28),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            },
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
              ],
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
    duration: const Duration(milliseconds: 1400),
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
        // One left-right wobble, then rest until the cycle repeats.
        var x = 0.0;
        if (t < 0.32) {
          final u = t / 0.32;
          x = -math.sin(u * 2 * math.pi);
        }
        return Transform.translate(
          offset: Offset(x * 4.5, 0),
          child: Transform.rotate(
            angle: x * 0.08,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Ruimer dan het camerabeeld op de camera-pagina. De verhouding blijft
/// die van de stream; alleen de maximale tegel groeit.
const _kIntercomStageFactor = 0.9;

/// Same fills in light and dark — palette danger/brass wash out in dark mode.
const _kCallHangup = Color(0xFFB83A3A);
const _kCallAnswer = Color(0xFF3E6B4F);
const _kCallDoor = Color(0xFFA67C3D);
const _kCallPhoto = Color(0xFF3E4550);
const _kCallOnFill = Color(0xFFF7F4EC);

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.mark,
    this.diameter = 72,
    this.loading = false,
    this.shake = false,
  });
  final IconData icon;
  final Widget Function(double size, Color color)? mark;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double diameter;
  final bool loading;
  final bool shake;

  @override
  Widget build(BuildContext context) {
    final circle = GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: diameter,
        height: diameter,
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
            : (mark != null
                ? Center(child: mark!(diameter * 0.42, _kCallOnFill))
                : Icon(icon, color: _kCallOnFill, size: diameter * 0.42)),
      ),
    );
    return Column(
      children: [
        _AlarmShake(enabled: shake && !loading, child: circle),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: LuxeColors.inkSoft,
                fontSize: 10,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}
