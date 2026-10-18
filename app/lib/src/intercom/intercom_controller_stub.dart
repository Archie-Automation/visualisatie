import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api.dart';
import 'intercom_sip_types.dart';

typedef IntercomRingAlignCallback = void Function(IntercomRing ring);

/// Geen SIP op Flutter Web (sip_ua compileert daar niet); zelfde API, alles no-op.
class IntercomController extends ChangeNotifier {
  IntercomController({
    this.onAlignKnxRing,
    this.onAnsweredElsewhere,
    this.resolveIntercomId,
  });

  final IntercomRingAlignCallback? onAlignKnxRing;
  final VoidCallback? onAnsweredElsewhere;
  final String? Function(String callerExt)? resolveIntercomId;

  IntercomSipPhase _phase = IntercomSipPhase.idle;
  String? boundIntercomId;
  bool registrationInFlight = false;

  IntercomSipPhase get phase => _phase;
  String? get remoteLabel => null;
  MediaStream? get remoteStream => null;
  MediaStream? get localStream => null;
  bool get muted => false;
  bool get isStarted => false;
  String? get dialError => null;
  void clearDialError() {}

  Future<void> startFromHouseIntercom({
    required String intercomId,
    required Map<String, dynamic> houseIntercom,
  }) async {
    debugPrint('IntercomController: SIP-intercom niet beschikbaar op web.');
  }

  Future<void> startFromVoip(
    Map<String, dynamic> sip, {
    String? intercomId,
  }) async {
    debugPrint('IntercomController: SIP-intercom niet beschikbaar op web.');
  }

  Future<void> stop() async {}

  Future<bool> ensureAvPermissions({required bool video}) async => false;

  Future<String?> placeCall(String target) async {
    if (target.trim().isEmpty) return 'Geen nummer voor deze intercom.';
    return 'Praten en luisteren kan hier niet.';
  }

  Future<void> answerCall() async {}

  void declineCall() {}

  void hangup() {}

  void toggleMute() {}

  bool sendDtmf(String digit) => false;

  @override
  void dispose() {
    registrationInFlight = false;
    super.dispose();
  }
}
