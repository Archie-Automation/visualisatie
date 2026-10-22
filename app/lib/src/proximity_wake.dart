import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Android proximity sensor: wake screen + notify listeners on near event.
class ProximityWake {
  ProximityWake._();

  static const _events = EventChannel('archie_os/proximity_events');
  static const _methods = MethodChannel('archie_os/proximity');

  static StreamSubscription<dynamic>? _sub;
  static final _nearController = StreamController<void>.broadcast();

  static Stream<void> get onNear => _nearController.stream;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static void start() {
    if (!supported || _sub != null) return;
    _sub = _events.receiveBroadcastStream().listen(
      (_) => _nearController.add(null),
      onError: (_) {},
    );
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> wakeScreen() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('wakeScreen');
    } catch (_) {}
  }

  /// Backlight naar 0. Het scherm blijft aan, zodat een aanraking het wekt.
  static Future<bool> enterStandby() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('enterStandby') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> leaveStandby() async {
    if (!supported) return;
    try {
      await _methods.invokeMethod<void>('leaveStandby');
    } catch (_) {}
  }

  static Future<bool> canDimBrightness() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('canDimBrightness') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Systeemscherm om de helderheid te mogen wijzigen. true als dat mag.
  static Future<bool> requestStandbyBrightness() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('requestStandbyBrightness') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
