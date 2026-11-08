import 'package:flutter/material.dart';

import '../theme.dart';
import 'widgets/luxe_form.dart';

enum ScopeIconKind { building, floor }

class ScopeIconChoice {
  const ScopeIconChoice(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const List<ScopeIconChoice> kBuildingScopeIcons = [
  ScopeIconChoice('house', 'Woning', Icons.home_outlined),
  ScopeIconChoice('villa', 'Villa', Icons.villa_outlined),
  ScopeIconChoice('apartment', 'Appartement', Icons.apartment_outlined),
  ScopeIconChoice('guest', 'Gastenverblijf', Icons.holiday_village_outlined),
  ScopeIconChoice('cabin', 'Buitenhuis', Icons.cabin_outlined),
  ScopeIconChoice('pool', 'Zwembad', Icons.pool_outlined),
  ScopeIconChoice('spa', 'Wellness', Icons.hot_tub_outlined),
  ScopeIconChoice('gym', 'Sport', Icons.fitness_center_outlined),
  ScopeIconChoice('garage', 'Garage', Icons.garage_outlined),
  ScopeIconChoice('barn', 'Schuur', Icons.agriculture_outlined),
  ScopeIconChoice('workshop', 'Werkplaats', Icons.handyman_outlined),
  ScopeIconChoice('storage', 'Berging', Icons.warehouse_outlined),
  ScopeIconChoice('office', 'Kantoor', Icons.domain_outlined),
  ScopeIconChoice('garden', 'Tuin', Icons.yard_outlined),
  ScopeIconChoice('greenhouse', 'Kas', Icons.grass_outlined),
  ScopeIconChoice('boat', 'Boothuis', Icons.sailing_outlined),
];

const List<ScopeIconChoice> kFloorScopeIcons = [
  ScopeIconChoice('floor', 'Verdieping', Icons.layers_outlined),
  ScopeIconChoice('basement', 'Kelder', Icons.vertical_align_bottom_outlined),
  ScopeIconChoice('ground', 'Begane grond', Icons.landscape_outlined),
  ScopeIconChoice('upper', 'Boven', Icons.stairs_outlined),
  ScopeIconChoice('attic', 'Zolder', Icons.roofing_outlined),
  ScopeIconChoice('roof', 'Dak', Icons.roofing),
  ScopeIconChoice('terrace', 'Terras', Icons.deck_outlined),
  ScopeIconChoice('garden', 'Tuin', Icons.park_outlined),
  ScopeIconChoice('parking', 'Parkeren', Icons.local_parking_outlined),
  ScopeIconChoice('technical', 'Techniek', Icons.engineering_outlined),
];

List<ScopeIconChoice> scopeIconsFor(ScopeIconKind kind) =>
    kind == ScopeIconKind.building ? kBuildingScopeIcons : kFloorScopeIcons;

IconData scopeBuildingIcon(String? key) =>
    _icon(kBuildingScopeIcons, key, Icons.home_outlined);

IconData scopeFloorIcon(String? key) =>
    _icon(kFloorScopeIcons, key, Icons.layers_outlined);

IconData _icon(List<ScopeIconChoice> list, String? key, IconData fallback) {
  for (final choice in list) {
    if (choice.key == key) return choice.icon;
  }
  return fallback;
}

/// Installateur kiest het icoon. Leeg = het standaardicoon van het soort.
class ScopeIconField extends StatelessWidget {
  const ScopeIconField({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final ScopeIconKind kind;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = scopeIconsFor(kind);
    final known = choices.any((c) => c.key == value);
    final current = known ? value! : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('scope-icon-$kind-$current'),
      initialValue: current,
      isExpanded: true,
      decoration: luxeFilledDecoration(hint: 'Icoon'),
      items: [
        const DropdownMenuItem(value: '', child: Text('Standaard')),
        for (final choice in choices)
          DropdownMenuItem(
            value: choice.key,
            child: Row(
              children: [
                Icon(choice.icon, size: 20, color: LuxeColors.ink),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(choice.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
    );
  }
}
