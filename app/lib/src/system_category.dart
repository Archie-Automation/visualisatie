import 'package:flutter/material.dart';

import 'models.dart';

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
    types: [DeviceType.shading],
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
  HouseSystem(
    slug: 'diverse',
    name: 'Diverse',
    icon: Icons.tune_outlined,
    types: [DeviceType.universal, DeviceType.positionActuator],
  ),
];

const kFavorietenSlug = 'favorieten';

HouseSystem? houseSystemBySlug(String slug) {
  for (final s in kHouseSystems) {
    if (s.slug == slug) return s;
  }
  return null;
}

HouseSystem? houseSystemByName(String name) {
  for (final s in kHouseSystems) {
    if (s.name == name) return s;
  }
  return null;
}

/// Devices belonging to a house-wide system (includes cameras from [cfg.cameras]).
List<Device> devicesForHouseSystem(HouseConfig cfg, HouseSystem system) {
  final devices =
      cfg.allDevices.where((d) => system.types.contains(d.type)).toList();
  if (system.types.contains(DeviceType.camera)) {
    devices.addAll(cfg.cameras);
  }
  return devices;
}
