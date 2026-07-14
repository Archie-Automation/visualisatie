import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../camera_api.dart';
import '../models.dart';
import '../ui/incoming_call_screen.dart';
import 'intercom_controller.dart';
import 'intercom_sip_types.dart';

final intercomSipControllerProvider =
    Provider<IntercomController>((ref) {
  final c = IntercomController(
    onAlignKnxRing: (ring) {
      ref.read(intercomRingProvider.notifier).push(ring);
    },
  );
  ref.onDispose(c.dispose);
  return c;
});

/// Kijkt bij elke config-update of er SIP-intercoms zijn en start dan
/// automatisch SIP-registratie. Wordt bewaakt via `ref.watch` in `app.dart`.
///
/// Op web is SIP niet beschikbaar (stub) — geen actie.
final sipStartupProvider = Provider<void>((ref) {
  if (kIsWeb) return;

  final auth = ref.watch(authProvider);
  if (!auth.isAuthed || auth.token == null) return;

  final configAsync = ref.watch(configProvider);
  configAsync.whenData((cfg) {
    // `Device.raw` bevat het volledige JSON-object; intercom-kind zit in raw['intercom']['kind'].
    final sipIntercoms = cfg.intercoms.where((ic) {
      final ic2 = ic.raw['intercom'];
      if (ic2 is! Map) return false;
      return ic2['kind'] == 'sip';
    }).toList();
    if (sipIntercoms.isEmpty) return;

    final controller = ref.read(intercomSipControllerProvider);
    if (controller.phase != IntercomSipPhase.idle) return;

    // Start SIP voor het eerste SIP-intercom (uitbreidbaar naar meerdere).
    final first = sipIntercoms.first;
    _startSipRegistration(
      controller: controller,
      intercomId: first.id,
      token: auth.token!,
    );
  });
});

Future<void> _startSipRegistration({
  required IntercomController controller,
  required String intercomId,
  required String token,
}) async {
  try {
    final sipConfig = await fetchIntercomSipConfig(
      intercomId: intercomId,
      token: token,
    );
    if (sipConfig == null) return;
    await controller.startFromHouseIntercom(
      intercomId: intercomId,
      houseIntercom: {'sip': sipConfig},
    );
    debugPrint('[SIP startup] geregistreerd voor $intercomId');
  } catch (e) {
    debugPrint('[SIP startup] registratie mislukt voor $intercomId: $e');
  }
}

/// Legt het SIP-incoming scherm over de hele app (onder MaterialApp.router).
class SipIncomingCallLayer extends ConsumerWidget {
  const SipIncomingCallLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sip = ref.watch(intercomSipControllerProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (sip.phase != IntercomSipPhase.idle)
          Positioned.fill(
            child: IncomingCallScreen(controller: sip),
          ),
      ],
    );
  }
}
