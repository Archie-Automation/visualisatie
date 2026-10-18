import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../camera_api.dart';
import '../models.dart';
import 'intercom_controller.dart';
import 'intercom_sip_types.dart';

final intercomSipControllerProvider =
    Provider<IntercomController>((ref) {
  final c = IntercomController(
    onAlignKnxRing: (ring) {
      final cur = ref.read(intercomRingProvider);
      final timeout = ring.timeoutSec ??
          (cur != null && cur.intercomId == ring.intercomId
              ? cur.timeoutSec
              : null);
      ref.read(intercomRingProvider.notifier).push(
            IntercomRing(
              intercomId: ring.intercomId,
              name: ring.name,
              ts: ring.ts,
              timeoutSec: timeout,
            ),
          );
    },
    onAnsweredElsewhere: () {
      ref.read(intercomRingProvider.notifier).markAnsweredElsewhere();
    },
    resolveIntercomId: (callerExt) {
      if (callerExt.isEmpty) return null;
      final cfg = ref.read(configProvider).value;
      if (cfg == null) return null;
      for (final ic in cfg.intercoms) {
        final raw = ic.raw['intercom'];
        if (raw is Map && '${raw['sipExt'] ?? ''}'.trim() == callerExt) {
          return ic.id;
        }
      }
      return null;
    },
  );
  ref.onDispose(c.dispose);
  return c;
});

/// Registreert de app als binnen-toestel op de eigen PBX.
/// Fallback: legacy `kind: sip` intercom (externe PBX).
final sipStartupProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed || auth.token == null) return;

  final configAsync = ref.watch(configProvider);
  configAsync.whenData((cfg) {
    final controller = ref.read(intercomSipControllerProvider);
    _startRegistration(
      controller: controller,
      token: auth.token!,
      cfg: cfg,
    );
  });
});

Future<void> _startRegistration({
  required IntercomController controller,
  required String token,
  required HouseConfig cfg,
}) async {
  if (kIsWeb) return;
  if (controller.registrationInFlight) return;
  if (controller.isStarted) return;
  if (controller.phase != IntercomSipPhase.idle) return;
  controller.registrationInFlight = true;
  try {
    final me = await fetchVoipMe(token: token);
    if (me != null && me['enabled'] == true && me['sip'] is Map) {
      await controller.startFromVoip(
        Map<String, dynamic>.from(me['sip'] as Map),
      );
      debugPrint('[SIP] geregistreerd op eigen PBX');
      return;
    }

    final sipIntercoms = cfg.intercoms.where((ic) {
      final ic2 = ic.raw['intercom'];
      if (ic2 is! Map) return false;
      return ic2['kind'] == 'sip';
    }).toList();
    if (sipIntercoms.isEmpty) return;
    final first = sipIntercoms.first;
    final sipConfig = await fetchIntercomSipConfig(
      intercomId: first.id,
      token: token,
    );
    if (sipConfig == null) return;
    await controller.startFromHouseIntercom(
      intercomId: first.id,
      houseIntercom: {'sip': sipConfig},
    );
    debugPrint('[SIP] legacy-registratie voor ${first.id}');
  } catch (e) {
    debugPrint('[SIP] registratie mislukt: $e');
  } finally {
    controller.registrationInFlight = false;
  }
}
