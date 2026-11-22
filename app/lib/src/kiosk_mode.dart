import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_panel_config.dart';

const _channel = MethodChannel('archie_os/kiosk');

/// Kiosk staat alleen op de native Android-app. Web heeft geen schakelaar.
class KioskModeController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> reload() async {
    state = await _read();
  }

  Future<void> setEnabled(bool on) async {
    final previous = state;
    state = on;
    try {
      state = await _write(on);
    } catch (_) {
      state = previous;
    }
  }
}

final kioskModeProvider =
    NotifierProvider<KioskModeController, bool>(KioskModeController.new);

Future<bool> _read() async {
  if (!wallTabletDeviceSettingsApply) return false;
  final raw = await _channel.invokeMethod<Object?>('status');
  return _enabled(raw);
}

Future<bool> _write(bool on) async {
  if (!wallTabletDeviceSettingsApply) return false;
  final raw = await _channel.invokeMethod<Object?>(on ? 'enable' : 'disable');
  return _enabled(raw);
}

bool _enabled(Object? raw) {
  if (raw is Map && raw['enabled'] == true) return true;
  return false;
}
