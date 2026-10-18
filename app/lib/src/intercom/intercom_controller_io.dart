import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';

import '../api.dart';
import 'intercom_sip_types.dart';
import 'panel_speech_audio.dart';

typedef IntercomRingAlignCallback = void Function(IntercomRing ring);

/// SIP User-Agent voor inkomende intercom-oproepen (iOS / Android / desktop).
class IntercomController extends ChangeNotifier implements SipUaHelperListener {
  IntercomController({
    this.onAlignKnxRing,
    this.onAnsweredElsewhere,
    this.resolveIntercomId,
  });

  final IntercomRingAlignCallback? onAlignKnxRing;
  final VoidCallback? onAnsweredElsewhere;

  /// SIP-nummer van de beller → intercom-id uit house.json (null = onbekend).
  final String? Function(String callerExt)? resolveIntercomId;

  final SIPUAHelper _helper = SIPUAHelper();
  bool _listenerAttached = false;
  bool _started = false;
  bool registrationInFlight = false;

  Call? _activeCall;
  IntercomSipPhase _phase = IntercomSipPhase.idle;
  String? _remoteLabel;
  MediaStream? _remoteStream;
  MediaStream? _localStream;
  bool _muted = false;
  String? boundIntercomId;
  bool _ringAlignSentForThisCall = false;
  bool _localTerminate = false;
  bool _outgoing = false;
  String? dialError;
  Timer? _elsewhereTimer;

  IntercomSipPhase get phase => _phase;
  String? get remoteLabel => _remoteLabel;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  bool get muted => _muted;
  bool get isStarted => _started;

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
      ..userAgent = 'ArchieOS-Intercom'
      ..dtmfMode = DtmfMode.RFC2833
      ..register = true;

    await start(settings);
  }

  Future<void> startFromVoip(
    Map<String, dynamic> sip, {
    String? intercomId,
  }) async {
    final ws = (sip['webSocketUrl'] as String?)?.trim();
    final uri = (sip['uri'] as String?)?.trim();
    final password = (sip['password'] as String?) ?? '';
    final authUser = (sip['authorizationUser'] as String?)?.trim();
    final displayName = (sip['displayName'] as String?)?.trim();
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
          (displayName != null && displayName.isNotEmpty) ? displayName : 'Paneel'
      ..userAgent = 'ArchieOS-Intercom'
      ..dtmfMode = DtmfMode.RFC2833
      ..register = true;
    await start(settings);
  }

  Future<void> start(UaSettings settings) async {
    // WSS van de NUC draait op een zelfondertekend certificaat; zonder dit
    // weigert Android de TLS-handshake en registreert het toestel nooit.
    settings.webSocketSettings.allowBadCertificate = true;
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

  void clearDialError() {
    dialError = null;
  }

  /// Bel de deur zelf, zonder dat er aangebeld is. `null` = gestart.
  Future<String?> placeCall(String target) async {
    final uri = target.trim();
    if (uri.isEmpty) return 'Geen nummer voor deze intercom.';
    if (_phase == IntercomSipPhase.inCall || _phase == IntercomSipPhase.ringing) {
      return 'Er is al een gesprek.';
    }
    if (!_started || !_helper.registered) {
      return 'Dit scherm is niet aangemeld op de belcentrale.';
    }
    final ok = await ensureAvPermissions(video: false);
    if (!ok) return 'Microfoon geweigerd.';
    try {
      await configurePanelSpeechAudio();
      final mediaStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _localStream = mediaStream;
      _outgoing = true;
      _localTerminate = false;
      final started = await _helper.call(
        uri,
        voiceOnly: true,
        mediaStream: mediaStream,
      );
      if (!started) {
        _outgoing = false;
        _localStream?.getTracks().forEach((t) => t.stop());
        _localStream = null;
        return 'Opnemen mislukt. De belcentrale nam niet op.';
      }
      _phase = IntercomSipPhase.ringing;
      notifyListeners();
      return null;
    } catch (e) {
      _outgoing = false;
      debugPrint('[SIP] zelf bellen mislukt: $e');
      return 'Opnemen mislukt.';
    }
  }

  Future<void> answerCall() async {
    final call = _activeCall;
    if (call == null) {
      debugPrint('[SIP] opnemen: geen actieve oproep');
      return;
    }
    // Beeld komt via go2rtc; SIP draagt alleen het gesprek.
    final ok = await ensureAvPermissions(video: false);
    if (!ok) {
      debugPrint('[SIP] opnemen: microfoontoestemming geweigerd');
      return;
    }

    final mediaConstraints = <String, dynamic>{'audio': true, 'video': false};

    try {
      await configurePanelSpeechAudio();
      final mediaStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = mediaStream;
      call.answer(_helper.buildCallOptions(true), mediaStream: mediaStream);
      debugPrint('[SIP] opgenomen');
    } catch (e) {
      debugPrint('[SIP] opnemen mislukt: $e');
      return;
    }
    _phase = IntercomSipPhase.inCall;
    notifyListeners();
  }

  void declineCall() {
    _localTerminate = true;
    _elsewhereTimer?.cancel();
    _activeCall?.hangup({'status_code': 603});
    _resetCall();
    notifyListeners();
  }

  void hangup() {
    _localTerminate = true;
    _elsewhereTimer?.cancel();
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

  bool sendDtmf(String digit) {
    final call = _activeCall;
    final tone = digit.trim();
    if (call == null || _phase != IntercomSipPhase.inCall || tone.isEmpty) {
      debugPrint('[SIP] DTMF overgeslagen fase=$_phase');
      return false;
    }
    try {
      call.sendDTMF(tone);
      debugPrint('[SIP] DTMF $tone');
      return true;
    } catch (e) {
      debugPrint('[SIP] DTMF mislukt: $e');
      return false;
    }
  }

  void _resetCall() {
    _elsewhereTimer?.cancel();
    _elsewhereTimer = null;
    _activeCall = null;
    _phase = IntercomSipPhase.idle;
    _remoteLabel = null;
    _remoteStream = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _muted = false;
    _ringAlignSentForThisCall = false;
    _localTerminate = false;
    _outgoing = false;
  }

  void _onRemoteCancelWhileRinging() {
    _activeCall = null;
    _phase = IntercomSipPhase.answeredElsewhere;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _remoteStream = null;
    onAnsweredElsewhere?.call();
    _elsewhereTimer?.cancel();
    _elsewhereTimer = Timer(const Duration(seconds: 3), () {
      _resetCall();
      notifyListeners();
    });
  }

  void _maybeAlignRing(Call call) {
    if (_ringAlignSentForThisCall) return;
    if (call.direction != Direction.incoming) return;
    final caller = call.remote_identity?.trim() ?? '';
    final id = boundIntercomId ?? resolveIntercomId?.call(caller);
    // Onbekende beller: de server stuurt zelf de belmelding met het juiste id.
    // Een verzonnen id opent anders een intercomscherm dat 404 geeft.
    if (id == null) {
      debugPrint('[SIP] oproep van $caller zonder bekende intercom');
      return;
    }
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
    debugPrint('[SIP] oproep ${state.state.name}'
        '${state.cause != null ? ' (${state.cause?.cause} ${state.cause?.status_code})' : ''}');
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.PROGRESS:
        // PROGRESS is 180/183, geen antwoord. Anders slaat OPNEMEN SIP over.
        _activeCall = call;
        if (_phase != IntercomSipPhase.inCall) {
          _phase = IntercomSipPhase.ringing;
        }
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
        _activeCall = call;
        break;
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
        final outgoing = _outgoing;
        final ringing = _phase == IntercomSipPhase.ringing;
        final local = _localTerminate;
        _outgoing = false;
        if (outgoing && !local) {
          final code = state.cause?.status_code;
          dialError = (code == 404 || code == 480 || code == 603 || code == 604)
              ? 'De intercom nam niet op. Zet op de DoorBird aan dat een inkomend gesprek wordt opgenomen.'
              : 'Bellen mislukt.';
        }
        if (!outgoing && ringing && !local) {
          _onRemoteCancelWhileRinging();
        } else {
          _resetCall();
        }
        break;
      default:
        break;
    }
    notifyListeners();
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    debugPrint('[SIP] registratie ${state.state?.name}'
        '${state.cause != null ? ' (${state.cause?.cause} ${state.cause?.status_code})' : ''}');
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    debugPrint('[SIP] transport ${state.state.name}'
        '${state.cause != null ? ' (${state.cause?.cause})' : ''}');
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void dispose() {
    registrationInFlight = false;
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
