import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets/glass_card.dart';

/// A luxe card representing a room. Shows aggregated status:
///   "2 / 4 lampen · 19.5 °C · intercom"
class RoomCard extends ConsumerWidget {
  const RoomCard({
    super.key,
    required this.floor,
    required this.room,
    required this.onTap,
  });

  final Floor floor;
  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(busProvider);
    final summary = _summarise(room, bus);

    return GlassCard(
      heroTag: 'room-${room.id}',
      onTap: onTap,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 30),
      shadows: summary.anyOn ? LuxeShadows.brassGlow : LuxeShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: summary.anyOn
                      ? LuxeColors.brass.withValues(alpha: 0.12)
                      : LuxeColors.surfaceDim.withValues(alpha: 0.7),
                  border: Border.all(
                    color: summary.anyOn
                        ? LuxeColors.brass.withValues(alpha: 0.35)
                        : LuxeColors.line,
                  ),
                ),
                child: Icon(
                  _iconFor(room.icon),
                  size: 20,
                  color: summary.anyOn ? LuxeColors.brass : LuxeColors.ink,
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: summary.anyOn
                      ? LuxeColors.ink
                      : LuxeColors.surface.withValues(alpha: 0.6),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_outward,
                  size: 16,
                  color: summary.anyOn ? Colors.white : LuxeColors.inkSoft,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            floor.name.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            summary.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _Summary {
  final String text;
  final bool anyOn;
  const _Summary(this.text, this.anyOn);
}

_Summary _summarise(Room r, BusState bus) {
  var lightsOn = 0;
  var lights = 0;
  var cams = 0;
  var intercoms = 0;
  double? temp;
  for (final d in r.devices) {
    if (d.type == DeviceType.lightSwitch ||
        d.type == DeviceType.lightDimmer ||
        d.type == DeviceType.rgbwWw) {
      lights++;
      final ga = d.ga['switch_status'] ?? d.ga['switch'];
      if (ga != null) {
        final v = bus.values[ga];
        if (v == true || v == 1) lightsOn++;
      }
    } else if (d.type == DeviceType.climate) {
      final ga = d.ga['actual_temp'];
      if (ga != null) {
        final v = bus.values[ga];
        if (v is num) temp = v.toDouble();
      }
    } else if (d.type == DeviceType.camera) {
      cams++;
    } else if (d.type == DeviceType.intercom) {
      intercoms++;
    }
  }
  final parts = <String>[];
  if (lights > 0) parts.add('$lightsOn / $lights lampen');
  if (temp != null) parts.add('${temp.toStringAsFixed(1)} °C');
  if (intercoms > 0) parts.add('intercom');
  if (cams > 0) parts.add('$cams camera${cams > 1 ? "'s" : ""}');
  if (parts.isEmpty) parts.add('${r.devices.length} apparaten');
  return _Summary(parts.join('  ·  '), lightsOn > 0);
}

IconData _iconFor(String? name) => switch (name) {
      'sofa' => Icons.chair_outlined,
      'kitchen' => Icons.kitchen_outlined,
      'bed' => Icons.bed_outlined,
      'door' => Icons.door_front_door_outlined,
      'home' => Icons.home_outlined,
      'stairs' => Icons.stairs_outlined,
      _ => Icons.square_outlined,
    };
