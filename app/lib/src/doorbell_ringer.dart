import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native ding-dong. Volume, tone and ring length are per device (this panel).
class DoorbellRinger {
  DoorbellRinger._();

  static const _channel = MethodChannel('archie_os/doorbell');
  static const defaultVolume = 0.8;
  static const defaultToneId = 'chime';
  static const defaultRingSeconds = 20;

  static const tones = <({String id, String label})>[
    (id: 'chime', label: 'Ding-dong'),
    (id: 'short', label: 'Kort'),
    (id: 'soft', label: 'Zacht'),
    (id: 'double', label: 'Dubbel'),
  ];

  static const ringSecondsChoices = <int>[
    5,
    8,
    10,
    12,
    15,
    20,
    25,
    30,
    45,
    60,
  ];

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool isKnownTone(String id) => tones.any((t) => t.id == id);

  static Future<void> start({double? volume, String? toneId}) async {
    if (!supported) return;
    final v = (volume ?? defaultVolume).clamp(0.0, 1.0);
    if (v <= 0) return;
    final tone = (toneId != null && isKnownTone(toneId))
        ? toneId
        : defaultToneId;
    try {
      await _channel.invokeMethod<void>('start', {
        'volume': v,
        'tone': tone,
      });
    } catch (e) {
      debugPrint('[doorbell] start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('[doorbell] stop failed: $e');
    }
  }
}

const _volumePrefsKey = 'doorbell_panel_volume';
const _tonePrefsKey = 'doorbell_panel_tone';
const _ringSecondsPrefsKey = 'doorbell_panel_ring_seconds';

class DoorbellVolumeNotifier extends AsyncNotifier<double> {
  @override
  Future<double> build() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_volumePrefsKey) ?? DoorbellRinger.defaultVolume)
        .clamp(0.0, 1.0);
  }

  Future<void> set(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    state = AsyncData(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumePrefsKey, v);
  }
}

final doorbellVolumeProvider =
    AsyncNotifierProvider<DoorbellVolumeNotifier, double>(
  DoorbellVolumeNotifier.new,
);

double doorbellVolumeValue(AsyncValue<double> async) => async.maybeWhen(
      data: (v) => v.clamp(0.0, 1.0),
      orElse: () => DoorbellRinger.defaultVolume,
    );

class DoorbellToneNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tonePrefsKey);
    if (raw != null && DoorbellRinger.isKnownTone(raw)) return raw;
    return DoorbellRinger.defaultToneId;
  }

  Future<void> set(String toneId) async {
    final id = DoorbellRinger.isKnownTone(toneId)
        ? toneId
        : DoorbellRinger.defaultToneId;
    state = AsyncData(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tonePrefsKey, id);
  }
}

final doorbellToneProvider =
    AsyncNotifierProvider<DoorbellToneNotifier, String>(
  DoorbellToneNotifier.new,
);

String doorbellToneValue(AsyncValue<String> async) => async.maybeWhen(
      data: (v) => DoorbellRinger.isKnownTone(v) ? v : DoorbellRinger.defaultToneId,
      orElse: () => DoorbellRinger.defaultToneId,
    );

class DoorbellRingSecondsNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt(_ringSecondsPrefsKey) ??
        DoorbellRinger.defaultRingSeconds;
    return _clampRingSeconds(n);
  }

  Future<void> set(int seconds) async {
    final n = _clampRingSeconds(seconds);
    state = AsyncData(n);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ringSecondsPrefsKey, n);
  }
}

final doorbellRingSecondsProvider =
    AsyncNotifierProvider<DoorbellRingSecondsNotifier, int>(
  DoorbellRingSecondsNotifier.new,
);

int doorbellRingSecondsValue(AsyncValue<int> async) => async.maybeWhen(
      data: _clampRingSeconds,
      orElse: () => DoorbellRinger.defaultRingSeconds,
    );

int _clampRingSeconds(int n) {
  final choices = DoorbellRinger.ringSecondsChoices;
  if (choices.contains(n)) return n;
  return choices.reduce(
    (a, b) => (a - n).abs() <= (b - n).abs() ? a : b,
  );
}
