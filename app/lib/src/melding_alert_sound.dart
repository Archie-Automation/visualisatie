import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'melding_active.dart';
import 'models.dart';
import '_melding_alert_beep_stub.dart'
    if (dart.library.html) '_melding_alert_beep_web.dart';

/// Stable key so mute survives label edits but resets when the item clears.
String meldingItemSoundKey(String deviceId, Map<String, dynamic> item) {
  final id = (item['id'] as String?)?.trim() ?? '';
  if (id.isNotEmpty) return '$deviceId::$id';
  return '$deviceId::${item['ga'] ?? ''}';
}

List<Map<String, dynamic>> meldingItemsOf(Device device) {
  final cfg = device.raw['melding'] as Map<String, dynamic>? ?? {};
  return (cfg['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
}

Set<String> collectActiveUrgentMeldingKeys(
  HouseConfig? cfg,
  Map<String, dynamic> busValues,
) {
  if (cfg == null) return {};
  final keys = <String>{};
  for (final d in cfg.allDevices) {
    if (d.type != DeviceType.melding) continue;
    for (final item in meldingItemsOf(d)) {
      if ((item['urgency'] as String? ?? '') != 'urgent') continue;
      final ga = item['ga'] as String? ?? '';
      if (!meldingItemIsActive(item, busValues[ga])) continue;
      keys.add(meldingItemSoundKey(d.id, item));
    }
  }
  return keys;
}

/// Native / web looping alarm for urgent meldingen.
class MeldingAlertSound {
  MeldingAlertSound._();

  static const _channel = MethodChannel('archie_os/melding_alert');
  static Timer? _timer;
  static var _androidPlaying = false;
  static var _generation = 0;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start() async {
    final token = ++_generation;
    if (_android) {
      _timer?.cancel();
      _timer = null;
      try {
        await _channel.invokeMethod<void>('start');
        if (token != _generation) {
          await _channel.invokeMethod<void>('stop');
          return;
        }
        _androidPlaying = true;
      } catch (e) {
        debugPrint('[melding-alert] start failed: $e');
        if (token == _generation) _startTicking();
      }
      return;
    }
    if (token == _generation) _startTicking();
  }

  static void _startTicking() {
    _timer?.cancel();
    playMeldingAlertBeep();
    _timer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => playMeldingAlertBeep(),
    );
  }

  static Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (!_androidPlaying) return;
    _androidPlaying = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('[melding-alert] stop failed: $e');
    }
  }
}

class MeldingAlertSilence extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void silence(String key) {
    if (state.contains(key)) return;
    state = {...state, key};
  }

  void unsilence(String key) {
    if (!state.contains(key)) return;
    state = {...state}..remove(key);
  }

  void toggle(String key) {
    if (state.contains(key)) {
      unsilence(key);
    } else {
      silence(key);
    }
  }

  /// Drop mute once the incident is gone so the next one rings again.
  void retainOnly(Set<String> active) {
    if (state.isEmpty) return;
    final next = state.intersection(active);
    if (next.length == state.length) return;
    state = next;
  }
}

final meldingAlertSilenceProvider =
    NotifierProvider<MeldingAlertSilence, Set<String>>(
  MeldingAlertSilence.new,
);
