import 'package:flutter/services.dart';

const _channel = MethodChannel('archie_os/alarm_delay');

Future<void> alarmDelayPrepare() async {}

Future<void> alarmDelaySlow() => _play('slow');

Future<void> alarmDelayFast() => _play('fast');

void alarmDelayStop() {
  _playStop();
}

Future<void> _play(String which) async {
  try {
    await _channel.invokeMethod<void>('play', {'which': which});
  } catch (_) {}
}

void _playStop() {
  _channel.invokeMethod<void>('stop').then((_) {}, onError: (_) {});
}
