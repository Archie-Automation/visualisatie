/// Piept tijdens in- en uitloop en opent de alarmpagina bij inloop of alarm.
/// Geen eigen scherm: dezelfde route als Systemen → Alarm.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../inactivity_controller.dart';
import '../../knx_alarm.dart';
import '../../proximity_wake.dart';
import '../../satel_api.dart';
import 'alarm_delay_sound.dart';

class SatelEntryDelayLayer extends ConsumerStatefulWidget {
  const SatelEntryDelayLayer({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SatelEntryDelayLayer> createState() =>
      _SatelEntryDelayLayerState();
}

class _SatelEntryDelayLayerState extends ConsumerState<SatelEntryDelayLayer> {
  Timer? _fastTimer;
  String? _lastKey;
  DateTime? _trackedDeadline;
  DateTime? _panelDeadline;

  static const _fastTail = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    alarmDelayPrepare();
  }

  @override
  void dispose() {
    _fastTimer?.cancel();
    alarmDelayStop();
    super.dispose();
  }

  void _openAlarmPage() {
    final router = GoRouter.maybeOf(context);
    if (router == null || !mounted) return;
    final uri = router.state.uri;
    if (uri.path == '/alarm' ||
        uri.path == '/splash' ||
        uri.path == '/login' ||
        uri.path == '/wachtwoord') {
      return;
    }
    final from = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    router.push(
      Uri(
        path: '/alarm',
        queryParameters: {'from': from.isEmpty ? '/' : from},
      ).toString(),
    );
    HapticFeedback.mediumImpact();
    ProximityWake.wakeScreen();
    ref.read(inactivityControllerProvider.notifier).hideScreensaver();
    ref.read(inactivityControllerProvider.notifier).registerActivity();
  }

  void _sync() {
    final satel = ref.read(satelStatusProvider);
    final knx = ref.read(knxAlarmStatusProvider);
    final knxOn = knx.enabled;
    final knxEntry = knxOn && knx.phase == 'entry';
    final knxExit = knxOn && knx.phase == 'exit';
    final knxAlarm = knxOn && knx.phase == 'alarm';
    final worst = knxOn ? SatelPartitionState.disarmed : satel.worstState;
    final key = knxOn ? 'knx:${knx.phase}' : 'satel:${worst.name}';
    if (key != _lastKey) {
      final prev = _lastKey;
      _lastKey = key;
      if (knxEntry || knxAlarm || worst == SatelPartitionState.entryDelay) {
        _openAlarmPage();
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
      } else if (prev != null && _turnedOff(prev, key)) {
        alarmDelayDouble();
      } else if (prev != null && _armedAfterExit(prev, key)) {
        alarmDelayArmed();
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

  bool _turnedOff(String prev, String key) {
    if (key == 'knx:off' && prev.startsWith('knx:') && prev != 'knx:off') {
      return true;
    }
    return key == 'satel:disarmed' &&
        prev.startsWith('satel:') &&
        prev != 'satel:disarmed';
  }

  bool _armedAfterExit(String prev, String key) {
    return (prev == 'knx:exit' && key == 'knx:armed') ||
        (prev == 'satel:exitDelay' && key == 'satel:armed');
  }

  void _syncExitCountdown(SatelStatus status) {
    if (status.worstState != SatelPartitionState.exitDelay) return;
    if (status.exitDeadline != null) {
      if (status.exitDeadline != _trackedDeadline) {
        _armFast(status.exitDeadline);
      }
      return;
    }
    if (status.exitFinal && _panelDeadline == null) {
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
    return widget.child;
  }
}
