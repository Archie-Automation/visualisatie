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
}
