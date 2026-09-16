import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'doorbell_ringer.dart';
import 'proximity_wake.dart';

/// Opens the intercom screen on ring. No native CallKit UI.
class CallService {
  CallService._(this._ref);
  WidgetRef _ref;
  GoRouter? _router;
  Timer? _panelRingTimer;

  static CallService? _instance;
  static CallService? get instance => _instance;

  /// [ref] comes from [ArchieOsApp] (app-lifetime), not a page widget.
  static Future<void> init(WidgetRef ref, GoRouter router) async {
    _instance ??= CallService._(ref);
    _instance!._ref = ref;
    _instance!._router = router;
  }

  void dispose() {
    _panelRingTimer?.cancel();
    _panelRingTimer = null;
    _router = null;
    if (identical(_instance, this)) _instance = null;
  }

  Future<void> showIncoming(IntercomRing ring) async {
    ProximityWake.wakeScreen();
    _panelRingTimer?.cancel();
    final silent =
        _ref.read(configProvider).value?.me?.doorbellSilent == true;
    if (silent) {
      debugPrint('[doorbell] skipped — account muted');
    } else {
      final volume = doorbellVolumeValue(_ref.read(doorbellVolumeProvider));
      if (volume <= 0) {
        debugPrint('[doorbell] skipped — panel volume 0');
      } else {
        final tone = doorbellToneValue(_ref.read(doorbellToneProvider));
        await DoorbellRinger.start(volume: volume, toneId: tone);
      }
    }
    final target = '/intercom/${ring.intercomId}';
    final loc = _router?.state.uri.path;
    if (loc != target) {
      _router?.push(target);
    }
    final seconds =
        doorbellRingSecondsValue(_ref.read(doorbellRingSecondsProvider));
    _panelRingTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_onPanelRingTimedOut(ring));
    });
  }

  Future<void> _onPanelRingTimedOut(IntercomRing ring) async {
    final cur = _ref.read(intercomRingProvider);
    if (cur == null ||
        cur.intercomId != ring.intercomId ||
        cur.answeredElsewhere) {
      return;
    }
    await DoorbellRinger.stop();
    final loc = _router?.state.uri.path;
    if (loc == '/intercom/${ring.intercomId}') {
      _router?.pop();
    }
  }

  Future<void> end(String intercomId) async {
    _panelRingTimer?.cancel();
    _panelRingTimer = null;
    await DoorbellRinger.stop();
  }

  Future<void> endAll() async {
    _panelRingTimer?.cancel();
    _panelRingTimer = null;
    await DoorbellRinger.stop();
  }
}

final callServiceListenerProvider = Provider<void>((ref) {
  ref.watch(doorbellVolumeProvider);
  ref.watch(doorbellToneProvider);
  ref.watch(doorbellRingSecondsProvider);
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
