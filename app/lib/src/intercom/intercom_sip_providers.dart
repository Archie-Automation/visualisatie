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
    onAnsweredElsewhere: () {
      ref.read(intercomRingProvider.notifier).markAnsweredElsewhere();
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

bool _starting = false;

Future<void> _startRegistration({
  required IntercomController controller,
  required String token,
  required HouseConfig cfg,
}) async {
  if (_starting) return;
    if (controller.isStarted) return;
    if (controller.phase != IntercomSipPhase.idle) return;
  _starting = true;
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
    _starting = false;
  }
}

/// Legt het SIP-incoming scherm over de hele app (onder MaterialApp.router).
class SipIncomingCallLayer extends ConsumerWidget {
  const SipIncomingCallLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sip = ref.watch(intercomSipControllerProvider);
    return ListenableBuilder(
      listenable: sip,
      builder: (context, _) {
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
      },
    );
  }
}
