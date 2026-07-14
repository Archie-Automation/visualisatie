import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api.dart';
import 'intercom_sip_types.dart';

typedef IntercomRingAlignCallback = void Function(IntercomRing ring);

/// Geen SIP op Flutter Web (sip_ua compileert daar niet); zelfde API, alles no-op.
class IntercomController extends ChangeNotifier {
  IntercomController({this.onAlignKnxRing});

  final IntercomRingAlignCallback? onAlignKnxRing;

  IntercomSipPhase _phase = IntercomSipPhase.idle;
  String? boundIntercomId;

  IntercomSipPhase get phase => _phase;
  String? get remoteLabel => null;
  MediaStream? get remoteStream => null;
  MediaStream? get localStream => null;
  bool get muted => false;

  Future<void> startFromHouseIntercom({
    required String intercomId,
    required Map<String, dynamic> houseIntercom,
  }) async {
    debugPrint('IntercomController: SIP-intercom niet beschikbaar op web.');
  }

  Future<void> stop() async {}

  Future<bool> ensureAvPermissions({required bool video}) async => false;

  Future<void> answerCall() async {}

  void declineCall() {}

  void hangup() {}

  void toggleMute() {}

  @override
  void dispose() {
    super.dispose();
  }
}
