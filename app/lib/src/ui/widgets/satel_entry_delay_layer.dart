/// Full-screen PIN overlay that fires automatically when the Satel partition
/// enters "Entry_Delay" (inlooptijd). The user must enter their code to disarm
/// before the delay runs out. The overlay dismisses itself as soon as the
/// state returns to "Disarmed".
///
/// Usage (wrap the navigator child in app.dart):
///   builder: (context, child) => SatelEntryDelayLayer(child: child!),
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../knx_alarm.dart';
import '../../knx_alarm_api.dart';
import '../../satel_api.dart';
import 'alarm_delay_sound.dart';
import 'alarm_keypad.dart';

class SatelEntryDelayLayer extends ConsumerStatefulWidget {
  const SatelEntryDelayLayer({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SatelEntryDelayLayer> createState() =>
      _SatelEntryDelayLayerState();
}

class _SatelEntryDelayLayerState extends ConsumerState<SatelEntryDelayLayer>
    with TickerProviderStateMixin {
  bool _overlayVisible = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  Timer? _fastTimer;
  String? _lastKey;
  DateTime? _trackedDeadline;
  DateTime? _panelDeadline;

  static const _fastTail = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    alarmDelayPrepare();
  }

  @override
  void dispose() {
    _fastTimer?.cancel();
    alarmDelayStop();
    _animCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    final satel = ref.read(satelStatusProvider);
    final knx = ref.read(knxAlarmStatusProvider);
    final knxOn = knx.enabled;
    final knxEntry = knxOn && knx.phase == 'entry';
    final knxExit = knxOn && knx.phase == 'exit';
    final worst = knxOn ? SatelPartitionState.disarmed : satel.worstState;
    final key = knxOn ? 'knx:${knx.phase}' : 'satel:${worst.name}';
    if (key != _lastKey) {
      _lastKey = key;
      final shouldShow = knxEntry || worst == SatelPartitionState.entryDelay;
      if (shouldShow && !_overlayVisible) {
        setState(() => _overlayVisible = true);
        _animCtrl.forward();
        HapticFeedback.heavyImpact();
      } else if (!shouldShow && _overlayVisible) {
        _animCtrl.reverse().then((_) {
          if (mounted) setState(() => _overlayVisible = false);
        });
      }

      _fastTimer?.cancel();
      _fastTimer = null;
      _trackedDeadline = null;
      _panelDeadline = null;
      alarmDelayStop();

      if (knxEntry) {
        alarmDelaySlow();
        _armFast(_deadline(knx.deadlineMs));
      } else if (knxExit) {
        alarmDelaySlow();
        _armFast(_deadline(knx.deadlineMs));
      } else if (worst == SatelPartitionState.entryDelay) {
        alarmDelaySlow();
      } else if (worst == SatelPartitionState.exitDelay) {
        alarmDelaySlow();
        _armFast(satel.exitDeadline);
      }
    }

    if (!knxOn && worst == SatelPartitionState.exitDelay) {
      _syncExitCountdown(satel);
    } else if (knxEntry || knxExit) {
      final deadline = _deadline(knx.deadlineMs);
      if (deadline != _trackedDeadline) _armFast(deadline);
    }
  }

  DateTime? _deadline(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  void _syncExitCountdown(SatelStatus status) {
    if (status.worstState != SatelPartitionState.exitDelay) return;
    if (status.exitDeadline != null) {
      if (status.exitDeadline != _trackedDeadline) {
        _armFast(status.exitDeadline);
      }
      return;
    }
    if (status.exitFinal && _panelDeadline == null) {
      // The panel only reports "under 10 seconds", and that poll is a few
      // seconds late. Count from here so the fast beeps sit in the last ~3s.
      _panelDeadline = DateTime.now().add(const Duration(seconds: 8));
      _armFast(_panelDeadline);
    }
  }

  void _armFast(DateTime? deadline) {
    _fastTimer?.cancel();
    _fastTimer = null;
    _trackedDeadline = deadline;
    if (deadline == null) return;
    final wait = deadline.difference(DateTime.now()) - _fastTail;
    if (wait <= Duration.zero) {
      alarmDelayFast();
      return;
    }
    _fastTimer = Timer(wait, alarmDelayFast);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SatelStatus>(satelStatusProvider, (_, __) => _sync());
    ref.listen<KnxAlarmStatus>(knxAlarmStatusProvider, (_, __) => _sync());

    final status = ref.watch(satelStatusProvider);

    return Stack(
      children: [
        widget.child,
        if (_overlayVisible)
          FadeTransition(
            opacity: _fadeAnim,
            child: _EntryDelayOverlay(
              status: status,
              // The overlay itself cannot be popped — it auto-dismisses on disarm.
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay contents
// ---------------------------------------------------------------------------

class _EntryDelayOverlay extends ConsumerStatefulWidget {
  const _EntryDelayOverlay({required this.status});
  final SatelStatus status;

  @override
  ConsumerState<_EntryDelayOverlay> createState() =>
      _EntryDelayOverlayState();
}

class _EntryDelayOverlayState extends ConsumerState<_EntryDelayOverlay>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _error;
  String _pin = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _disarm() async {
    setState(() { _busy = true; _error = null; });
    final token  = ref.read(authProvider).token;
    final status = ref.read(satelStatusProvider);
    final target = status.partitions
        .where((p) => p.isEntryDelay)
        .map((p) => p.number)
        .firstOrNull ?? 1;
    final result = await satelDisarm(target, token: token);
    if (!mounted) return;
    setState(() { _busy = false; });
    if (!result.ok) {
      setState(() => _error = result.error ?? 'Uitschakelen mislukt.');
      HapticFeedback.heavyImpact();
    }
    // On success the status provider flips to Disarmed and the layer
    // auto-dismisses this overlay.
  }

  Future<void> _disarmKnx() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await knxAlarmDisarm(_pin, ref.read(authProvider).token);
    if (!mounted) return;
    final status = result.status;
    if (status != null) {
      ref.read(knxAlarmStatusProvider.notifier).apply(status);
    }
    setState(() {
      _busy = false;
      if (result.ok) _pin = '';
      _error = result.ok ? null : (result.message ?? 'Uitschakelen mislukt.');
    });
    if (!result.ok) HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(satelStatusProvider);
    final knx = ref.watch(knxAlarmStatusProvider);
    final knxEntry = knx.enabled && knx.phase == 'entry';
    final names = knxEntry
        ? [
            for (final sensor in knx.sensors)
              if (sensor.open && !sensor.bypassed)
                sensor.name.isEmpty ? sensor.ga : sensor.name,
          ]
        : status.allZones.where((z) => z.violated).map((z) => z.name).toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xE8181820),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Pulsing warning icon ─────────────────────────────
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFFD64545).withValues(alpha: 0.15),
                      const Color(0xFFD64545).withValues(alpha: 0.30),
                      _pulse.value,
                    ),
                    border: Border.all(
                      color: Color.lerp(
                        const Color(0xFFD64545).withValues(alpha: 0.40),
                        const Color(0xFFD64545).withValues(alpha: 0.80),
                        _pulse.value,
                      )!,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD64545),
                    size: 40,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'INLOOPTIJD',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.0,
                  color: Color(0xFFD64545),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Druk op Uitschakelen om het\nalarm te stoppen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),

              // Violated zones hint
              if (names.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: names.take(4).map((name) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD64545).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFD64545).withValues(alpha: 0.30),
                            width: 0.5),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFD64545),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 28),

              if (knxEntry)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AlarmPinSection(
                      pin: _pin,
                      busy: _busy,
                      feedback: _error,
                      canConfirm: _pin.length >= 4,
                      arming: false,
                      onDigit: (d) {
                        if (_pin.length >= 8) return;
                        setState(() {
                          _pin += d;
                          _error = null;
                        });
                      },
                      onBackspace: () {
                        if (_pin.isEmpty) return;
                        setState(() => _pin = _pin.substring(0, _pin.length - 1));
                      },
                      onConfirm: _disarmKnx,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.20),
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(
                        color: Color(0xFF4CAF50),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                    onPressed: _busy ? null : _disarm,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF4CAF50),
                            ),
                          )
                        : const Icon(Icons.lock_open_outlined, size: 22),
                    label: const Text(
                      'Uitschakelen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ),
                  ),
                ),

              if (_error != null && !knxEntry) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFD64545),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

