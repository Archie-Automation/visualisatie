import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'doorbell_ringer.dart';
import 'proximity_wake.dart';

/// Opens the intercom screen on ring. No native CallKit UI.
class CallService {
  CallService._(this._ref);
  final WidgetRef _ref;
  GoRouter? _router;

  static CallService? _instance;
  static CallService? get instance => _instance;

  static Future<void> init(WidgetRef ref, GoRouter router) async {
    _instance ??= CallService._(ref);
    _instance!._router = router;
  }

  Future<void> showIncoming(IntercomRing ring) async {
    ProximityWake.wakeScreen();
    final silent =
        _ref.read(configProvider).value?.me?.doorbellSilent == true;
    if (silent) {
      debugPrint('[doorbell] skipped — account muted');
    } else {
      final volume = doorbellVolumeValue(_ref.read(doorbellVolumeProvider));
      if (volume <= 0) {
        debugPrint('[doorbell] skipped — panel volume 0');
      } else {
        await DoorbellRinger.start(volume: volume);
      }
    }
    final target = '/intercom/${ring.intercomId}';
    final loc = _router?.state.uri.path;
    if (loc != target) {
      _router?.push(target);
    }
  }

  Future<void> end(String intercomId) async {
    await DoorbellRinger.stop();
  }

  Future<void> endAll() async {
    await DoorbellRinger.stop();
  }
}

final callServiceListenerProvider = Provider<void>((ref) {
  ref.watch(doorbellVolumeProvider);
  ref.listen<IntercomRing?>(intercomRingProvider, (prev, next) {
    final svc = CallService.instance;
    if (svc == null) return;
    if (next != null &&
        !next.answeredElsewhere &&
        (prev == null || prev.ts != next.ts || prev.answeredElsewhere)) {
      svc.showIncoming(next);
    }
    if (next != null && next.answeredElsewhere) {
      svc.end(next.intercomId);
    }
    if (next == null && prev != null) {
      svc.end(prev.intercomId);
    }
  });
});
