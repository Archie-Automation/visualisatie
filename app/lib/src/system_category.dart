import 'package:flutter/material.dart';

import 'models.dart';
import 'room_control_category.dart';

/// House-wide system tile (dashboard SYSTEMEN strip).
class HouseSystem {
  const HouseSystem({
    required this.slug,
    required this.name,
    required this.icon,
    required this.types,
  });

  final String slug;
  final String name;
  final IconData icon;
  final List<DeviceType> types;

  /// Route for this system chip. Camera's and Alarm use dedicated screens.
  String? get routePath {
    if (slug == 'cameras') return '/cameras';
    if (slug == 'alarm') return '/alarm';
    return '/system/$slug';
  }
}

/// Path opened from a Systemen chip. A single intercom skips the tile list
/// and goes straight to the same screen as an incoming doorbell.
String houseSystemOpenPath(HouseSystem system, List<Device> devices) {
  if (system.slug == 'intercom' && devices.length == 1) {
    return '/intercom/${devices.first.id}';
  }
  return system.routePath ?? '/system/${system.slug}';
}

const kHouseSystems = <HouseSystem>[
  HouseSystem(
    slug: 'verlichting',
    name: 'Verlichting',
    icon: Icons.lightbulb_outline,
    types: [
      DeviceType.lightSwitch,
      DeviceType.lightDimmer,
      DeviceType.rgbwWw,
      DeviceType.lutronHomeworks,
    ],
  ),
  HouseSystem(
    slug: 'klimaat',
    name: 'Klimaat',
    icon: Icons.thermostat_outlined,
    types: [DeviceType.climate, DeviceType.ac],
  ),
  HouseSystem(
    slug: 'zonwering',
    name: 'Zonwering',
    icon: Icons.blinds_outlined,
    types: [DeviceType.shading, DeviceType.positionActuator],
  ),
  HouseSystem(
    slug: 'ventilatie',
    name: 'Ventilatie',
    icon: Icons.air_outlined,
    types: [DeviceType.fan, DeviceType.wtw],
  ),
  HouseSystem(
    slug: 'openhaard',
    name: 'Openhaard',
    icon: Icons.local_fire_department_outlined,
    types: [DeviceType.fireplace],
  ),
  HouseSystem(
    slug: 'cameras',
    name: 'Camera\'s',
    icon: Icons.videocam_outlined,
    types: [DeviceType.camera],
  ),
  HouseSystem(
    slug: 'intercom',
    name: 'Intercom',
    icon: Icons.doorbell_outlined,
    types: [DeviceType.intercom],
  ),
  HouseSystem(
    slug: 'audio',
    name: 'Audio',
    icon: Icons.music_note_outlined,
    types: [DeviceType.mediaSonos, DeviceType.mediaBluesound],
  ),
  HouseSystem(
    slug: 'meldingen',
    name: 'Meldingen',
    icon: Icons.notifications_outlined,
    types: [DeviceType.melding],
  ),
];

const kFavorietenSlug = 'favorieten';
const kGrafiekenSlug = 'grafieken';

HouseSystem? houseSystemBySlug(String slug, [HouseConfig? cfg]) {
  for (final s in kHouseSystems) {
    if (s.slug == slug) return s;
  }
  if (cfg != null) {
    for (final s in cfg.customHouseSystems) {
      if (s.id == slug) return customHouseSystemAsTile(s);
    }
  }
  return null;
}

HouseSystem? houseSystemByName(String name, [HouseConfig? cfg]) {
  for (final s in allHouseSystems(cfg)) {
    if (s.name == name) return s;
  }
  return null;
}

HouseSystem customHouseSystemAsTile(CustomHouseSystem s) => HouseSystem(
      slug: s.id,
      name: s.name,
      icon: universalIconData(s.icon),
      types: const [],
    );

List<HouseSystem> allHouseSystems([HouseConfig? cfg]) {
  if (cfg == null || cfg.customHouseSystems.isEmpty) return kHouseSystems;
  return [
    ...kHouseSystems,
    for (final s in cfg.customHouseSystems) customHouseSystemAsTile(s),
  ];
}

/// Default tile from device type. Universeel heeft geen tegel tot je er een kiest.
String? defaultSystemSlugForType(DeviceType type) {
  for (final s in kHouseSystems) {
    if (s.types.contains(type)) return s.slug;
  }
  return null;
}

/// Explicit `systemId` wins; otherwise the type default (not Diverse).
String? systemSlugForDevice(Device d, [HouseConfig? cfg]) {
  final assigned = (d.raw['systemId'] as String?)?.trim();
  if (assigned != null && assigned.isNotEmpty) {
    if (houseSystemBySlug(assigned, cfg) != null) return assigned;
  }
  return defaultSystemSlugForType(d.type);
}

/// Devices belonging to a house-wide system (includes cameras from [cfg.camerasOverview]).
List<Device> devicesForHouseSystem(HouseConfig cfg, HouseSystem system) {
  final devices = [
    for (final d in cfg.allDevices)
      if (systemSlugForDevice(d, cfg) == system.slug) d,
  ];
  for (final custom in cfg.customHouseSystems) {
    if (custom.id != system.slug) continue;
    final byId = <String, Device>{};
    for (final d in [
      ...cfg.allDevices,
      ...cfg.cameras,
      ...cfg.intercoms,
      ...cfg.camerasOverview,
    ]) {
      byId[d.id] = d;
    }
    _addUniqueDevices(devices, [
      for (final id in custom.deviceIds)
        if (byId[id] != null) byId[id]!,
    ]);
    break;
  }
  if (system.slug == 'cameras') {
    _addUniqueDevices(devices, cfg.camerasOverview);
  }
  if (system.slug == 'intercom') {
    _addUniqueDevices(devices, cfg.intercoms);
  }
  return devices;
}

void _addUniqueDevices(List<Device> into, Iterable<Device> extra) {
  final seen = {for (final d in into) d.id};
  for (final d in extra) {
    if (seen.add(d.id)) into.add(d);
  }
}
