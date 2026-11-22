import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../knx_alarm.dart';
import '../knx_alarm_api.dart';
import '../theme.dart';
import 'widgets/alarm_delay_sound.dart';

/// KNX-alarm: code, aanwezig/afwezig, sensoren, overbruggen, sirene.
class KnxAlarmBody extends ConsumerStatefulWidget {
  const KnxAlarmBody({super.key});

  @override
  ConsumerState<KnxAlarmBody> createState() => _KnxAlarmBodyState();
}

class _KnxAlarmBodyState extends ConsumerState<KnxAlarmBody> {
  String _pin = '';
  bool _busy = false;
  String? _feedback;
  Timer? _tick;
  Timer? _beep;

  static const _minPin = 4;
  static const _maxPin = 8;

  @override
  void initState() {
    super.initState();
    alarmDelayPrepare();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _syncBeep();
    });
    Future<void>(() async {
      final raw = await fetchKnxAlarm(ref.read(authProvider).token);
      if (!mounted || raw == null) return;
      ref.read(knxAlarmStatusProvider.notifier).apply(raw);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep?.cancel();
    alarmDelayStop();
    super.dispose();
  }

  void _syncBeep() {
    final phase = ref.read(knxAlarmStatusProvider).phase;
    if (phase != 'entry' && phase != 'exit') {
      _beep?.cancel();
      _beep = null;
      alarmDelayStop();
      return;
    }
    _beep ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final status = ref.read(knxAlarmStatusProvider);
      if (status.phase != 'entry' && status.phase != 'exit') return;
      final left = _secondsLeft(status.deadlineMs);
      if (status.phase == 'entry' && left != null && left <= 3) {
        alarmDelayFast();
      } else {
        alarmDelaySlow();
      }
    });
  }

  int? _secondsLeft(int? deadlineMs) {
    if (deadlineMs == null) return null;
    final left = ((deadlineMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    return left < 0 ? 0 : left;
  }

  Future<void> _run(
    Future<({bool ok, String? message, Map<String, dynamic>? status})> call,
  ) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    final result = await call;
    if (!mounted) return;
    if (result.status != null) {
      ref.read(knxAlarmStatusProvider.notifier).apply(result.status!);
    }
    setState(() {
      _busy = false;
      _pin = '';
      _feedback = result.ok ? null : result.message;
    });
    if (result.ok) HapticFeedback.lightImpact();
    _syncBeep();
  }

  Future<void> _arm(String mode) async {
    if (_pin.length < _minPin || _busy) return;
    await _run(knxAlarmArm(mode, _pin, ref.read(authProvider).token));
  }

  Future<void> _disarm() async {
    if (_pin.length < _minPin || _busy) return;
    await _run(knxAlarmDisarm(_pin, ref.read(authProvider).token));
  }

  Future<void> _bypass(KnxAlarmSensorState sensor) async {
    if (_busy) return;
    final status = ref.read(knxAlarmStatusProvider);
    if (status.phase != 'off' && _pin.length < _minPin) {
      setState(() => _feedback = 'Code nodig om te overbruggen terwijl het alarm aan staat.');
      return;
    }
    await _run(knxAlarmBypass(
      id: sensor.id,
      bypass: !sensor.bypassed,
      pin: _pin,
      token: ref.read(authProvider).token,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(knxAlarmStatusProvider);
    final left = _secondsLeft(status.deadlineMs);
    final title = switch (status.phase) {
      'exit' => 'Uitloop ${left ?? 0}s',
      'entry' => 'Inloop ${left ?? 0}s',
      'alarm' => status.siren ? 'Alarm — sirene aan' : 'Alarm',
      'armed' => status.mode == 'aanwezig' ? 'Aanwezig ingeschakeld' : 'Afwezig ingeschakeld',
      _ => status.pinSet ? 'Alarm uit' : 'Nog geen code ingesteld',
    };
    final armed = status.phase != 'off';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (_feedback != null) ...[
          const SizedBox(height: 8),
          Text(
            _feedback!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _pin.isEmpty ? 'Code' : '•' * _pin.length,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _Pad(
          onDigit: (d) {
            if (_pin.length >= _maxPin) return;
            setState(() {
              _pin += d;
              _feedback = null;
            });
          },
          onBack: () {
            if (_pin.isEmpty) return;
            setState(() => _pin = _pin.substring(0, _pin.length - 1));
          },
        ),
        const SizedBox(height: 12),
        if (!armed) ...[
          _Action(
            label: 'Aanwezig',
            busy: _busy,
            onTap: _pin.length >= _minPin ? () => _arm('aanwezig') : null,
          ),
          const SizedBox(height: 8),
          _Action(
            label: 'Afwezig',
            busy: _busy,
            onTap: _pin.length >= _minPin ? () => _arm('afwezig') : null,
          ),
        ] else
          _Action(
            label: 'Uitschakelen',
            busy: _busy,
            onTap: _pin.length >= _minPin ? _disarm : null,
          ),
        const SizedBox(height: 18),
        Text('Sensoren', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final sensor in status.sensors)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(sensor.name.isEmpty ? sensor.ga : sensor.name),
            subtitle: Text(_sensorLine(sensor, status.mode)),
            trailing: TextButton(
              onPressed: _busy ? null : () => _bypass(sensor),
              child: Text(sensor.bypassed ? 'Herstel' : 'Overbrug'),
            ),
          ),
      ],
    );
  }

  String _sensorLine(KnxAlarmSensorState sensor, String? mode) {
    final bits = <String>[
      if (sensor.aanwezig) 'aanwezig',
      if (sensor.afwezig) 'afwezig',
      if (sensor.inloop) 'inloop',
      if (sensor.open) 'open' else 'dicht',
      if (sensor.bypassed) 'overbrugd',
    ];
    if (mode != null) {
      final counts = mode == 'aanwezig' ? sensor.aanwezig : sensor.afwezig;
      if (!counts) bits.add('niet in deze modus');
    }
    return bits.join(' · ');
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: LuxeColors.ink,
          foregroundColor: LuxeColors.onInk,
          minimumSize: const Size.fromHeight(48),
        ),
        child: Text(label),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.onDigit, required this.onBack});

  final void Function(String digit) onDigit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: [
        for (final key in keys)
          if (key.isEmpty)
            const SizedBox.shrink()
          else
            TextButton(
              onPressed: () => key == '⌫' ? onBack() : onDigit(key),
              child: Text(key, style: const TextStyle(fontSize: 22)),
            ),
      ],
    );
  }
}
