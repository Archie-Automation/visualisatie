import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';

/// Native call UI bridge. On iOS this drives CallKit (full-screen call
/// overlay, lock-screen controls, native ringtone). On Android it drives
/// ConnectionService through flutter_callkit_incoming's notification.
///
/// Flow:
///   intercom.ring (WebSocket)
///     → push to intercomRingProvider
///     → [CallService] shows native incoming call
///     → user taps Accept  → router navigates to /intercom/:id
///     → user taps Decline → we clear the ring state
class CallService {
  CallService._(this._ref);
  final WidgetRef _ref;
  final Map<String, String> _activeCalls = {}; // intercomId → callId
  StreamSubscription? _eventSub;
  GoRouter? _router;

  static CallService? _instance;
  static CallService? get instance => _instance;

  static Future<void> init(WidgetRef ref, GoRouter router) async {
    _instance ??= CallService._(ref);
    _instance!._router = router;
    // Native call UIs don't exist on the web / desktop builds – don't
    // try to subscribe to a platform channel that isn't there.
    if (kIsWeb) return;
    await _instance!._bindEvents();
  }

  /// Reverse-lookup: callId → intercomId
  String? _intercomForCall(String callId) {
    for (final entry in _activeCalls.entries) {
      if (entry.value == callId) return entry.key;
    }
    return null;
  }

  Future<void> _bindEvents() async {
    await _eventSub?.cancel();
    try {
      _eventSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? e) async {
        if (e == null) return;
        switch (e) {
          case CallEventActionCallAccept(callKitParams: final params):
            final id = params.id;
            final intercomId = _intercomForCall(id);
            if (intercomId == null) return;
            _ref.read(intercomRingProvider.notifier).clear();
            _activeCalls.remove(intercomId);
            _router?.push('/intercom/$intercomId');
          case CallEventActionCallDecline(callKitParams: final params):
            final id = params.id;
            final intercomId = _intercomForCall(id);
            _ref.read(intercomRingProvider.notifier).clear();
            if (intercomId != null) _activeCalls.remove(intercomId);
          case CallEventActionCallEnded(callKitParams: final params):
            final id = params.id;
            final intercomId = _intercomForCall(id);
            _ref.read(intercomRingProvider.notifier).clear();
            if (intercomId != null) _activeCalls.remove(intercomId);
          case CallEventActionCallTimeout(id: final id):
            final intercomId = _intercomForCall(id);
            _ref.read(intercomRingProvider.notifier).clear();
            if (intercomId != null) _activeCalls.remove(intercomId);
          default:
            break;
        }
      });
    } catch (err) {
      debugPrint('CallKit event binding skipped: $err');
    }
  }

  Future<void> showIncoming(IntercomRing ring) async {
    // Native call UIs aren't available on desktop / web builds; no-op.
    if (kIsWeb) return;
    try {
      final callId = const Uuid().v4();
      _activeCalls[ring.intercomId] = callId;
      final params = CallKitParams(
        id: callId,
        nameCaller: ring.name,
        appName: 'Archie OS',
        avatar: '',
        handle: 'Intercom',
        type: 1, // 0 = audio, 1 = video
        duration: 45000,
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Gemist',
        ),
        extra: <String, dynamic>{'intercomId': ring.intercomId, 'ts': ring.ts},
        headers: <String, dynamic>{'platform': 'archie-os'},
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1A1A1A',
          actionColor: '#B08D57', // LuxeColors.brass
          incomingCallNotificationChannelName: 'Intercom',
          missedCallNotificationChannelName: 'Gemiste oproepen',
          textAccept: 'Opnemen',
          textDecline: 'Weigeren',
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (err) {
      debugPrint('CallKit showIncoming failed: $err');
    }
  }

  Future<void> endAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
    _activeCalls.clear();
  }

  Future<void> end(String intercomId) async {
    final id = _activeCalls.remove(intercomId);
    if (id == null) return;
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }
}

/// Riverpod glue. Watches the ring provider and drives CallKit off it.
final callServiceListenerProvider = Provider<void>((ref) {
  ref.listen<IntercomRing?>(intercomRingProvider, (prev, next) {
    final svc = CallService.instance;
    if (svc == null) return;
    if (next != null && (prev?.ts != next.ts)) {
      svc.showIncoming(next);
    }
    if (next == null && prev != null) {
      svc.end(prev.intercomId);
    }
  });
});
