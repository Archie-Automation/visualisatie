import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'api.dart';
import 'doorbell_ringer.dart';
import 'inactivity_controller.dart';
import 'proximity_wake.dart';
import 'push_service.dart';

/// Opens the intercom screen on ring (WebSocket). Het native belscherm
/// (CallKit) komt alleen via push als de app dicht was; "Opnemen" daar
/// landt ook hier en opent het intercomscherm.
class CallService {
  CallService._(this._ref);
  WidgetRef _ref;
  GoRouter? _router;
  Timer? _panelRingTimer;
  StreamSubscription<CallEvent?>? _callkitSub;

  static CallService? _instance;
  static CallService? get instance => _instance;

  /// [ref] comes from [ArchieOsApp] (app-lifetime), not a page widget.
  static Future<void> init(WidgetRef ref, GoRouter router) async {
    _instance ??= CallService._(ref);
    _instance!._ref = ref;
    _instance!._router = router;
    if (PushService.supported) {
      await _instance!._attachCallkit();
    }
  }

  Future<void> _attachCallkit() async {
    _callkitSub?.cancel();
    _callkitSub = FlutterCallkitIncoming.onEvent.listen((e) {
      if (e is CallEventActionCallAccept) {
        _openFromCallkit(e.callKitParams);
      } else if (e is CallEventActionCallDecline) {
        FlutterCallkitIncoming.endCall(e.callKitParams.id);
      }
    });
    // App gestart door "Opnemen" terwijl hij dicht was: het event is dan al
    // geweest; de actieve call draagt isAccepted.
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final c in calls) {
        if (c.isAccepted) {
          _openFromCallkit(c);
          break;
        }
      }
    } catch (e) {
      debugPrint('[callkit] activeCalls mislukt: $e');
    }
  }

  void _wakeAndOpenIntercom(String id) {
    if (id.isEmpty) return;
    ProximityWake.wakeScreen();
    _ref.read(inactivityControllerProvider.notifier).registerActivity();
    final target = '/intercom/$id';
    final loc = _router?.state.uri.path;
    if (loc != target) _router?.push(target);
  }

  void _openFromCallkit(CallKitParams p) {
    final id = (p.extra?['intercomId'] as String?) ?? '';
    unawaited(FlutterCallkitIncoming.endAllCalls());
    _wakeAndOpenIntercom(id);
  }

  void dispose() {
    _panelRingTimer?.cancel();
    _panelRingTimer = null;
    _callkitSub?.cancel();
    _callkitSub = null;
    _router = null;
    if (identical(_instance, this)) _instance = null;
  }

  Future<void> showIncoming(IntercomRing ring) async {
    _panelRingTimer?.cancel();
    _wakeAndOpenIntercom(ring.intercomId);
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
    final seconds = _ringSeconds(ring);
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

  /// De belgroep-afringduur. Een lokale kortere stand (bijv. 5 s) wint niet.
  int _ringSeconds(IntercomRing ring) {
    final n = ring.timeoutSec;
    if (n != null && n >= 5 && n <= 180) return n;
    return 30;
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
  // Push (app dicht) aan/uit met de login. Bij een WebSocket die leeft
  // rinkelt de app zelf en wordt het pushbericht genegeerd.
  ref.listen<AuthState>(authProvider, (prev, next) {
    final t = next.token;
    if (t != null && prev?.token == null) {
      unawaited(PushService.start(
        token: t,
        appHandlesRing: () =>
            ref.read(serverLinkProvider) == ServerLink.online,
      ));
    } else if (t == null && prev?.token != null) {
      unawaited(PushService.stop(token: prev?.token));
    }
  }, fireImmediately: true);
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
