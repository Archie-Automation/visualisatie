import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inactivity_controller.dart';
import '../../knx_alarm.dart';
import '../../proximity_wake.dart';
import '../../theme.dart';

/// Sabotage geeft een melding op de tablet. De sirene blijft uit tot het alarm aan staat.
class KnxSabotageNotice extends ConsumerStatefulWidget {
  const KnxSabotageNotice({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KnxSabotageNotice> createState() => _KnxSabotageNoticeState();
}

class _KnxSabotageNoticeState extends ConsumerState<KnxSabotageNotice> {
  var _seen = false;
  var _message = '';
  Set<String> _open = {};

  void _sync() {
    final open = ref
        .read(knxAlarmStatusProvider)
        .sensors
        .where((s) => s.kind == 'sabotage' && s.open && !s.bypassed)
        .toList();
    final ids = open.map((s) => s.id).toSet();
    if (!_seen) {
      _seen = true;
      _open = ids;
      return;
    }
    final fresh = ids.difference(_open);
    _open = ids;
    if (fresh.isEmpty || !mounted) return;
    final names = open
        .where((s) => fresh.contains(s.id))
        .map((s) => s.name.trim().isEmpty ? s.ga : s.name.trim())
        .join(', ');
    setState(() => _message = names);
    HapticFeedback.heavyImpact();
    ProximityWake.wakeScreen();
    ref.read(inactivityControllerProvider.notifier).hideScreensaver();
    ref.read(inactivityControllerProvider.notifier).registerActivity();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(knxAlarmStatusProvider, (_, __) => _sync());
    return Stack(
      children: [
        widget.child,
        if (_message.isNotEmpty)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xE8181820),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Material(
                      color: LuxeColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MELDING',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.4,
                                color: Color(0xFFD64545),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sabotage',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: LuxeColors.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: LuxeColors.inkSoft,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: () => setState(() => _message = ''),
                                child: const Text('Sluiten'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
