import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../api.dart';
import '../../display_panel_config.dart';
import '../../idle_reset.dart';
import '../../inactivity_controller.dart';
import '../../kiosk_system_ui.dart';
import '../../media_api.dart';
import '../../proximity_wake.dart';
import '../../satel_api.dart';
import '../../theme.dart';
import '../responsive.dart';
import 'honeycomb_pattern.dart';

bool get _displayPanelActive => !kIsWeb && Platform.isAndroid;

/// Screensaver canvas (burn-in: vast zwart vlak, content faded/shifted).
const Color _screensaverCanvas = Color(0xFF0A0A09);
const Color _screensaverTime = Color.fromRGBO(255, 255, 255, 0.85);

const double _ssFadeMax = 1.0;
const double _ssFadeMin = 0.1;
const double _ssFadeSeconds = 1.8;
/// Fade-out start within each minute (second 58).
const double _ssFadeOutAt = 58.0;
/// Korte hold na :00 vóór fade-in.
const double _ssHoldPastMidnight = 0.2;

/// Opacity curve per wall-clock second (ease-in-out), tegen inbranden.
double screensaverBurnInOpacity(DateTime now) {
  final t = now.second + now.millisecond / 1000.0;
  final fadeOutEnd = _ssFadeOutAt + _ssFadeSeconds; // 59.8

  if (t >= _ssFadeOutAt && t < fadeOutEnd) {
    final p = Curves.easeInOut.transform((t - _ssFadeOutAt) / _ssFadeSeconds);
    return _ssFadeMax + (_ssFadeMin - _ssFadeMax) * p;
  }
  // Hold rond minuutwissel (eind van minuut + kort na :00).
  if (t >= fadeOutEnd || t < _ssHoldPastMidnight) {
    return _ssFadeMin;
  }
  final fadeInEnd = _ssHoldPastMidnight + _ssFadeSeconds;
  if (t < fadeInEnd) {
    final p = Curves.easeInOut
        .transform((t - _ssHoldPastMidnight) / _ssFadeSeconds);
    return _ssFadeMin + (_ssFadeMax - _ssFadeMin) * p;
  }
  return _ssFadeMax;
}

/// Fullscreen luxe klok (+ optionele temperatuur) na langdurige inactiviteit.
class ScreensaverOverlay extends ConsumerStatefulWidget {
  const ScreensaverOverlay({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  ConsumerState<ScreensaverOverlay> createState() => _ScreensaverOverlayState();
}

class _ScreensaverOverlayState extends ConsumerState<ScreensaverOverlay> {
  static final _rng = math.Random();

  Timer? _tick;
  DateTime _now = DateTime.now();
  Offset _pixelShift = Offset.zero;
  double _tiltRad = 0;
  /// Epoch-minute id waarvoor de shift al is gezet (tijdens diepe fade).
  int? _shiftForMinuteId;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final opacity = screensaverBurnInOpacity(now);
      _maybeApplyHiddenShift(now, opacity);
      setState(() => _now = now);
    });
  }

  /// Shift/tilt alleen terwijl opacity ~10% is — beweging is niet zichtbaar.
  void _maybeApplyHiddenShift(DateTime now, double opacity) {
    if (opacity > _ssFadeMin + 0.02) return;
    final minuteId = now.millisecondsSinceEpoch ~/ 60000;
    if (_shiftForMinuteId == minuteId) return;
    _shiftForMinuteId = minuteId;
    _pixelShift = Offset(
      (_rng.nextDouble() * 16) - 8,
      (_rng.nextDouble() * 16) - 8,
    );
    // ±0.35° — te klein om op te vallen, wel pixel-rotatie.
    _tiltRad = ((_rng.nextDouble() * 0.7) - 0.35) * (math.pi / 180);
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (isAndroidKioskTarget) {
      applyAndroidKioskSystemUi();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(displayPanelSettingsProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const DisplayPanelSettings(),
        );
    final cfg = ref.watch(configProvider).maybeWhen(
          data: (c) => c,
          orElse: () => null,
        );
    final bus = ref.watch(busProvider);
    final temp = settings.showTemperature
        ? resolveDisplayTemperature(cfg: cfg, bus: bus, settings: settings)
        : null;
    final hvac = settings.showTemperature && !settings.useOutdoorTemperature
        ? resolveDisplayHvacStatus(cfg: cfg, bus: bus, settings: settings)
        : null;

    final clockSize = context.isPhone ? 112.0 : 168.0;
    final timeStr = DateFormat('HH:mm').format(_now);
    final opacity = screensaverBurnInOpacity(_now);
    const heatColor = Color(0xFFE07A3F);
    const coolColor = Color(0xFF5BA7E0);

    return Material(
      color: _screensaverCanvas,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        onPanDown: (_) => widget.onDismiss(),
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: _pixelShift,
            child: Transform.rotate(
              angle: _tiltRad,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.35),
                          radius: 1.1,
                          colors: [
                            LuxeColors.brass.withValues(alpha: 0.10),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const HoneycombPattern(
                    color: Colors.white,
                    opacity: 0.03,
                    hexSize: 64,
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: GoogleFonts.lexendDeca(
                            fontSize: clockSize,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -1.4,
                            height: 1,
                            color: _screensaverTime,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        if (temp != null) ...[
                          SizedBox(height: context.isPhone ? 28 : 40),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                '${temp.toStringAsFixed(1)}°',
                                style: GoogleFonts.inter(
                                  fontSize: context.isPhone ? 40 : 52,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 0.5,
                                  color: LuxeColors.brassGlow,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (settings.useOutdoorTemperature) ...[
                                SizedBox(width: context.isPhone ? 12 : 16),
                                _OutdoorTempIcon(
                                  size: context.isPhone ? 34 : 44,
                                  color: LuxeColors.brassGlow,
                                ),
                              ] else if (hvac != null) ...[
                                SizedBox(width: context.isPhone ? 12 : 16),
                                Icon(
                                  hvac.isHeating
                                      ? Icons.local_fire_department_outlined
                                      : Icons.ac_unit_outlined,
                                  size: context.isPhone ? 34 : 44,
                                  color: hvac.demandActive
                                      ? (hvac.isHeating
                                          ? heatColor
                                          : coolColor)
                                      : _screensaverTime.withValues(
                                          alpha: 0.35,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thermometer met klein huis — buitentemperatuur op de screensaver.
class _OutdoorTempIcon extends StatelessWidget {
  const _OutdoorTempIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 6,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.thermostat_outlined, size: size, color: color),
          Positioned(
            right: -2,
            bottom: -1,
            child: Icon(
              Icons.home_outlined,
              size: size * 0.42,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detecteert inactiviteit, keert terug naar home en toont screensaver.
class InactivityLayer extends ConsumerStatefulWidget {
  const InactivityLayer({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<InactivityLayer> createState() => _InactivityLayerState();
}

class _InactivityLayerState extends ConsumerState<InactivityLayer> {
  Timer? _tickTimer;
  StreamSubscription<void>? _proximitySub;
  SatelPartitionState? _lastAlarmState;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (_displayPanelActive) {
      ProximityWake.start();
      _proximitySub = ProximityWake.onNear.listen((_) => _onProximityNear());
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _proximitySub?.cancel();
    if (_displayPanelActive) ProximityWake.stop();
    super.dispose();
  }

  void _wakePanel() {
    if (!_displayPanelActive) return;
    ProximityWake.wakeScreen();
    ref.read(inactivityControllerProvider.notifier).registerActivity();
  }

  void _onProximityNear() => _wakePanel();

  void _onEntryDelayStarted() => _wakePanel();

  bool _isPaused() {
    if (ref.read(intercomRingProvider) != null) return true;
    final satel = ref.read(satelStatusProvider);
    if (satel.worstState == SatelPartitionState.entryDelay) return true;
    final loc = widget.router.state.matchedLocation;
    if (loc.startsWith('/intercom/')) return true;
    return false;
  }

  void _onTick() {
    if (!mounted || !_displayPanelActive) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthed || !auth.restoreComplete) return;

    final settings = ref.read(displayPanelSettingsProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const DisplayPanelSettings(),
        );
    if (!settings.enabled) {
      ref.read(inactivityControllerProvider.notifier).hideScreensaver();
      return;
    }
    if (_isPaused()) return;

    final ctrl = ref.read(inactivityControllerProvider.notifier);
    final state = ref.read(inactivityControllerProvider);
    final idle = DateTime.now().difference(state.lastActivity);
    final loc = widget.router.state.matchedLocation;
    final onHome = loc == '/';
    final onAuthFlow = loc == '/splash' || loc == '/login';

    final cfg = ref.read(configProvider).maybeWhen(
          data: (c) => c,
          orElse: () => null,
        );
    final mediaStates = ref.read(mediaStateProvider);
    final musicBlocksIdle = shouldSuppressIdleForMusic(
      settings: settings,
      cfg: cfg,
      mediaStates: mediaStates,
      matchedLocation: loc,
    );

    if (musicBlocksIdle) {
      ctrl.hideScreensaver();
    }

    final ssDuration = settings.screensaverDuration;
    if (ssDuration != null && idle >= ssDuration && !musicBlocksIdle) {
      ctrl.showScreensaver();
      return;
    }

    if (!onAuthFlow &&
        idle >= settings.idleHomeDuration &&
        !state.homeReturnedThisIdle &&
        !musicBlocksIdle) {
      ctrl.markHomeReturned();
      ctrl.hideScreensaver();
      if (!onHome) widget.router.go('/');
      ref.read(idleResetSignalProvider.notifier).trigger();
    }
  }

  void _onUserActivity() {
    ref.read(inactivityControllerProvider.notifier).registerActivity();
  }

  @override
  Widget build(BuildContext context) {
    if (!_displayPanelActive) return widget.child;

    // Alarm-inloop: scherm ontwaken + screensaver weg.
    ref.listen<SatelPartitionState>(
      satelStatusProvider.select((s) => s.worstState),
      (prev, next) {
        final was = prev ?? _lastAlarmState;
        _lastAlarmState = next;
        if (next == SatelPartitionState.entryDelay &&
            was != SatelPartitionState.entryDelay) {
          _onEntryDelayStarted();
        }
      },
    );

    final screensaver =
        ref.watch(inactivityControllerProvider).screensaverVisible;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerSignal: (_) => _onUserActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (screensaver)
            Positioned.fill(
              child: ScreensaverOverlay(onDismiss: _onUserActivity),
            ),
        ],
      ),
    );
  }
}
