import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';

import '../api.dart';
import 'intercom_sip_types.dart';

typedef IntercomRingAlignCallback = void Function(IntercomRing ring);

/// SIP User-Agent voor inkomende intercom-oproepen (iOS / Android / desktop).
class IntercomController extends ChangeNotifier implements SipUaHelperListener {
  IntercomController({this.onAlignKnxRing});

  final IntercomRingAlignCallback? onAlignKnxRing;

  final SIPUAHelper _helper = SIPUAHelper();
  bool _listenerAttached = false;
  bool _started = false;

  Call? _activeCall;
  IntercomSipPhase _phase = IntercomSipPhase.idle;
  String? _remoteLabel;
  MediaStream? _remoteStream;
  MediaStream? _localStream;
  bool _muted = false;
  String? boundIntercomId;
  bool _ringAlignSentForThisCall = false;

  IntercomSipPhase get phase => _phase;
  String? get remoteLabel => _remoteLabel;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  bool get muted => _muted;

  /// Registratie starten vanuit `house.json` → `intercom.sip` (WebSocket + URI + auth).
  Future<void> startFromHouseIntercom({
    required String intercomId,
    required Map<String, dynamic> houseIntercom,
  }) async {
    final sip = houseIntercom['sip'];
    if (sip is! Map) return;
    final m = sip.map((k, v) => MapEntry(k.toString(), v));
    final ws = (m['webSocketUrl'] as String?)?.trim();
    final uri = (m['uri'] as String?)?.trim();
    final password = (m['password'] as String?) ?? '';
    final authUser = (m['authorizationUser'] as String?)?.trim();
    final displayName = (m['displayName'] as String?)?.trim();
    if (ws == null || ws.isEmpty || uri == null || uri.isEmpty) return;

    boundIntercomId = intercomId;

    final settings = UaSettings()
      ..transportType = TransportType.WS
      ..webSocketUrl = ws
      ..uri = uri
      ..password = password
      ..authorizationUser =
          (authUser != null && authUser.isNotEmpty) ? authUser : null
      ..displayName =
          (displayName != null && displayName.isNotEmpty) ? displayName : 'Intercom'
      ..userAgent = 'LuxeKNX-Intercom'
      ..register = true;

    await start(settings);
  }

  Future<void> start(UaSettings settings) async {
    if (!_listenerAttached) {
      _helper.addSipUaHelperListener(this);
      _listenerAttached = true;
    }
    await _helper.start(settings);
    _helper.register();
    _started = true;
  }

  Future<void> stop() async {
    _activeCall?.hangup();
    _resetCall();
    if (_started) {
      try {
        if (_helper.registered) {
          await _helper.unregister(true);
        }
      } catch (_) {}
      _helper.stop();
      _started = false;
    }
    if (_listenerAttached) {
      _helper.removeSipUaHelperListener(this);
      _listenerAttached = false;
    }
    notifyListeners();
  }

  Future<bool> ensureAvPermissions({required bool video}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<void> answerCall() async {
    final call = _activeCall;
    if (call == null) return;
    final remoteVideo = call.remote_has_video;
    final ok = await ensureAvPermissions(video: remoteVideo);
    if (!ok) return;

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': remoteVideo
          ? <String, dynamic>{
              'mandatory': <String, dynamic>{
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '24',
              },
              'facingMode': 'user',
              'optional': <dynamic>[],
            }
          : false,
    };
    if (!remoteVideo) {
      mediaConstraints['video'] = false;
    }

    final mediaStream =
        await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = mediaStream;
    call.answer(_helper.buildCallOptions(!remoteVideo), mediaStream: mediaStream);
    _phase = IntercomSipPhase.inCall;
    notifyListeners();
  }

  void declineCall() {
    _activeCall?.hangup({'status_code': 603});
    _resetCall();
    notifyListeners();
  }

  void hangup() {
    _activeCall?.hangup({'status_code': 603});
    _resetCall();
    notifyListeners();
  }

  void toggleMute() {
    final call = _activeCall;
    if (call == null) return;
    if (_muted) {
      call.unmute(true, false);
    } else {
      call.mute(true, false);
    }
    _muted = !_muted;
    notifyListeners();
  }

  void _resetCall() {
    _activeCall = null;
    _phase = IntercomSipPhase.idle;
    _remoteLabel = null;
    _remoteStream = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _muted = false;
    _ringAlignSentForThisCall = false;
  }

  void _maybeAlignRing(Call call) {
    if (_ringAlignSentForThisCall) return;
    if (call.direction != Direction.incoming) return;
    final id = boundIntercomId ?? 'sip-intercom';
    final name = (call.remote_display_name?.trim().isNotEmpty == true)
        ? call.remote_display_name!.trim()
        : (call.remote_identity?.trim().isNotEmpty == true)
            ? call.remote_identity!.trim()
            : 'Intercom';
    onAlignKnxRing?.call(IntercomRing(
      intercomId: id,
      name: name,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
    _ringAlignSentForThisCall = true;
  }

  @override
  void callStateChanged(Call call, CallState state) {
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _activeCall = call;
        _phase = IntercomSipPhase.ringing;
        _remoteLabel = (call.remote_display_name?.trim().isNotEmpty == true)
            ? call.remote_display_name
            : call.remote_identity;
        _maybeAlignRing(call);
        break;
      case CallStateEnum.STREAM:
        if (state.stream != null) {
          if (state.originator == Originator.remote) {
            _remoteStream = state.stream;
          } else if (state.originator == Originator.local) {
            _localStream = state.stream;
          }
        }
        _phase = IntercomSipPhase.inCall;
        break;
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        _activeCall = call;
        _phase = IntercomSipPhase.inCall;
        break;
      case CallStateEnum.MUTED:
        if (state.audio == true) _muted = true;
        break;
      case CallStateEnum.UNMUTED:
        if (state.audio == true) _muted = false;
        break;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _resetCall();
        break;
      default:
        break;
    }
    notifyListeners();
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void dispose() {
    _activeCall?.hangup();
    _resetCall();
    if (_listenerAttached) {
      _helper.removeSipUaHelperListener(this);
      _listenerAttached = false;
    }
    if (_started) {
      _helper.stop();
      _started = false;
    }
    super.dispose();
  }
}
