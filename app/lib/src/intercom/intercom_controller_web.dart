import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api.dart';
import 'intercom_sip_types.dart';

typedef IntercomRingAlignCallback = void Function(IntercomRing ring);

/// SIP via JsSIP in de browser (sip_ua compileert niet op web).
class IntercomController extends ChangeNotifier {
  IntercomController({this.onAlignKnxRing, this.onAnsweredElsewhere});

  final IntercomRingAlignCallback? onAlignKnxRing;
  final VoidCallback? onAnsweredElsewhere;

  IntercomSipPhase _phase = IntercomSipPhase.idle;
  String? boundIntercomId;
  String? _remoteLabel;
  MediaStream? _remoteStream;
  MediaStream? _localStream;
  bool _muted = false;
  bool _started = false;
  bool registrationInFlight = false;
  bool _localTerminate = false;
  Timer? _elsewhereTimer;

  IntercomSipPhase get phase => _phase;
  String? get remoteLabel => _remoteLabel;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  bool get muted => _muted;
  bool get isStarted => _started;

  Future<void> startFromHouseIntercom({
    required String intercomId,
    required Map<String, dynamic> houseIntercom,
  }) async {
    final sip = houseIntercom['sip'];
    if (sip is! Map) return;
    await startFromVoip({
      'webSocketUrl': sip['webSocketUrl'],
      'uri': sip['uri'],
      'password': sip['password'],
      'authorizationUser': sip['authorizationUser'],
      'displayName': sip['displayName'],
    }, intercomId: intercomId);
  }

  Future<void> startFromVoip(
    Map<String, dynamic> sip, {
    String? intercomId,
  }) async {
    final ws = (sip['webSocketUrl'] as String?)?.trim() ?? '';
    final uri = (sip['uri'] as String?)?.trim() ?? '';
    final password = (sip['password'] as String?) ?? '';
    final displayName = (sip['displayName'] as String?)?.trim() ?? 'Paneel';
    if (ws.isEmpty || uri.isEmpty) return;
    boundIntercomId = intercomId;
    if (!_archieSipAvailable()) {
      debugPrint('IntercomController: JsSIP ontbreekt in index.html');
      return;
    }
    await stop();
    void incoming(JSString label) => _onIncoming(label);
    void confirmed() => _onConfirmed();
    void ended() => _onEnded();
    _archieSipStart(
      ws.toJS,
      uri.toJS,
      password.toJS,
      displayName.toJS,
      incoming.toJS,
      confirmed.toJS,
      ended.toJS,
    );
    _started = true;
  }

  void _onIncoming(JSString label) {
    _phase = IntercomSipPhase.ringing;
    _remoteLabel = label.toDart;
    final id = boundIntercomId ?? 'sip';
    onAlignKnxRing?.call(IntercomRing(
      intercomId: id,
      name: _remoteLabel ?? 'Intercom',
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
    notifyListeners();
  }

  void _onConfirmed() {
    _phase = IntercomSipPhase.inCall;
    notifyListeners();
  }

  void _onEnded() {
    if (_phase == IntercomSipPhase.ringing && !_localTerminate) {
      _phase = IntercomSipPhase.answeredElsewhere;
      onAnsweredElsewhere?.call();
      _elsewhereTimer?.cancel();
      _elsewhereTimer = Timer(const Duration(seconds: 3), () {
        _resetCall();
        notifyListeners();
      });
    } else {
      _resetCall();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (_started) {
      _archieSipStop();
      _started = false;
    }
    _resetCall();
    notifyListeners();
  }

  Future<bool> ensureAvPermissions({required bool video}) async => true;

  Future<void> answerCall() async {
    _archieSipAnswer();
    _phase = IntercomSipPhase.inCall;
    notifyListeners();
  }

  void declineCall() {
    _localTerminate = true;
    _archieSipHangup();
    _resetCall();
    notifyListeners();
  }

  void hangup() {
    _localTerminate = true;
    _archieSipHangup();
    _resetCall();
    notifyListeners();
  }

  void toggleMute() {
    _muted = !_muted;
    _archieSipMute(_muted);
    notifyListeners();
  }

  void _resetCall() {
    _elsewhereTimer?.cancel();
    _elsewhereTimer = null;
    _phase = IntercomSipPhase.idle;
    _remoteLabel = null;
    _remoteStream = null;
    _localStream = null;
    _muted = false;
    _localTerminate = false;
  }

  @override
  void dispose() {
    registrationInFlight = false;
    if (_started) _archieSipStop();
    super.dispose();
  }
}

@JS('ArchieSip')
external JSObject? get _archieSip;

bool _archieSipAvailable() => _archieSip != null;

@JS('ArchieSip.start')
external void _archieSipStart(
  JSString wsUrl,
  JSString uri,
  JSString password,
  JSString displayName,
  JSFunction onIncoming,
  JSFunction onConfirmed,
  JSFunction onEnded,
);

@JS('ArchieSip.stop')
external void _archieSipStop();

@JS('ArchieSip.answer')
external void _archieSipAnswer();

@JS('ArchieSip.hangup')
external void _archieSipHangup();

@JS('ArchieSip.mute')
external void _archieSipMute(bool muted);
