import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native ding-dong. Volume is per device (this panel), not per account.
class DoorbellRinger {
  DoorbellRinger._();

  static const _channel = MethodChannel('archie_os/doorbell');
  static const defaultVolume = 0.8;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start({double? volume}) async {
    if (!supported) return;
    final v = (volume ?? defaultVolume).clamp(0.0, 1.0);
    if (v <= 0) return;
    try {
      await _channel.invokeMethod<void>('start', {'volume': v});
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
