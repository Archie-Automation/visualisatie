import 'dart:async';
import 'dart:io' show Platform;

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
import '../../media_api.dart';
import '../../proximity_wake.dart';
import '../../satel_api.dart';
import '../../theme.dart';
import '../responsive.dart';

bool get _displayPanelActive => !kIsWeb && Platform.isAndroid;

/// Fullscreen luxe klok (+ optionele temperatuur) na langdurige inactiviteit.
class ScreensaverOverlay extends ConsumerStatefulWidget {
  const ScreensaverOverlay({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  ConsumerState<ScreensaverOverlay> createState() => _ScreensaverOverlayState();
}

class _ScreensaverOverlayState extends ConsumerState<ScreensaverOverlay> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

    final clockSize = context.isPhone ? 112.0 : 168.0;
    final timeStr = DateFormat('HH:mm').format(_now);

    return Material(
      color: LuxeColors.surfaceDark,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        onPanDown: (_) => widget.onDismiss(),
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
                      LuxeColors.brass.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
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
                      letterSpacing: 6,
                      height: 1,
                      color: const Color(0xFFF8F4EC),
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: const [
                        Shadow(
                          color: Color(0x33B08A4E),
                          blurRadius: 48,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                  if (temp != null) ...[
                    SizedBox(height: context.isPhone ? 28 : 40),
                    Text(
                      '${temp.toStringAsFixed(1)}°',
                      style: GoogleFonts.lexendDeca(
                        fontSize: context.isPhone ? 40 : 52,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1,
                        color: LuxeColors.brassGlow.withValues(alpha: 0.92),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
