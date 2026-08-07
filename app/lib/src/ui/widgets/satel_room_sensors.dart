/// Compact sensor icon strip shown inside a room view.
/// Renders one icon per Satel zone assigned to that room; grey when clear,
/// coloured + slightly enlarged when violated. Tapping the row navigates to
/// the full alarm page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../satel_api.dart';
import '../../theme.dart';
import '../alarm_screen.dart' show satelDeviceConfig;

class SatelRoomSensors extends ConsumerWidget {
  const SatelRoomSensors({super.key, required this.roomId});

  /// Stable app room id; matched against each zone's configured room id.
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(satelStatusProvider);

    final zones = status.zonesForRoomId(roomId);
    if (zones.isEmpty) return const SizedBox.shrink();

    final anyViolated = zones.any((z) => z.violated);

    return GestureDetector(
      onTap: () => context.push('/alarm'),
      child: Container(
        margin: EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: anyViolated
              ? const Color(0xFFD64545).withValues(alpha: 0.06)
              : LuxeColors.surface.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: anyViolated
                ? Color(0xFFD64545).withValues(alpha: 0.22)
                : LuxeColors.line,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              'BEVEILIGING',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
                color: LuxeColors.inkFaint,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: zones.map((z) => _SensorDot(zone: z)).toList(),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: LuxeColors.inkFaint.withValues(alpha: 0.60),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorDot extends StatelessWidget {
  const _SensorDot({super.key, required this.zone});
  final SatelZone zone;

  @override
  Widget build(BuildContext context) {
    final cfg = satelDeviceConfig(zone.deviceType, zone.violated);

    return Tooltip(
      message: '${zone.name}: ${zone.violated ? cfg.alertLabel : "OK"}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: zone.violated ? 34 : 28,
        height: zone.violated ? 34 : 28,
        decoration: BoxDecoration(
          color: cfg.color.withValues(alpha: zone.violated ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cfg.color.withValues(alpha: zone.violated ? 0.40 : 0.18),
            width: zone.violated ? 1.0 : 0.5,
          ),
        ),
        child: Icon(
          cfg.icon,
          size: zone.violated ? 18 : 14,
          color: cfg.color,
        ),
      ),
    );
  }
}
