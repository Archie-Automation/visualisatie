import 'package:flutter/services.dart';

const _channel = MethodChannel('archie_os/alarm_delay');

Future<void> alarmDelayPrepare() async {}

Future<void> alarmDelaySlow() => _play('slow', loop: true);

Future<void> alarmDelayFast() => _play('fast', loop: true);

Future<void> alarmDelayDouble() => _play('double', loop: false);

Future<void> alarmDelayArmed() => _play('armed', loop: false);

void alarmDelayStop() {
  _playStop();
}

Future<void> _play(String which, {required bool loop}) async {
  try {
    await _channel.invokeMethod<void>('play', {'which': which, 'loop': loop});
  } catch (_) {}
}

void _playStop() {
  _channel.invokeMethod<void>('stop').then((_) {}, onError: (_) {});
}
