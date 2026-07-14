import 'package:flutter/material.dart';

import 'models.dart';

/// Curated icon set for universal device groups.
/// Key = stored string in `universal.icon`, value = Flutter IconData.
/// Central icon registry used by the universal device tile, WTW status rows
/// and the installer icon picker. Add entries here to make them available
/// everywhere — the key is the string stored in house.json.
const Map<String, IconData> kUniversalIconMap = {
  // ── Algemeen ──────────────────────────────────────────────────────────────
  'bolt': Icons.bolt,
  'home': Icons.home_outlined,
  'settings': Icons.settings_outlined,
  'grid': Icons.grid_view_rounded,
  'star': Icons.star_outline_rounded,
  'widgets': Icons.widgets_outlined,
  'power': Icons.power_settings_new_outlined,
  'info': Icons.info_outline,
  'check': Icons.check_circle_outline,
  /// Alarm/attentie (geel driehoekje)
  'warning': Icons.warning_amber_outlined,
  /// Storing / fout (rood / oranje uitroepteken)
  'fault': Icons.report_problem_outlined,
  'error': Icons.error_outline,
  'timer': Icons.timer_outlined,
  'schedule': Icons.schedule_outlined,
  'maintenance': Icons.build_outlined,
  'service': Icons.engineering_outlined,
  'remote': Icons.settings_remote_outlined,
  'night': Icons.nightlight_outlined,
  'sun': Icons.wb_sunny_outlined,
  'moon': Icons.dark_mode_outlined,
  'cloud': Icons.cloud_outlined,
  'weather': Icons.thunderstorm_outlined,
  /// Regen
  'rain': Icons.grain,

  // ── Verlichting ───────────────────────────────────────────────────────────
  'lamp': Icons.lightbulb_outlined,
  'lamp_on': Icons.lightbulb,
  'dimmer': Icons.brightness_medium_outlined,
  'rgb': Icons.palette_outlined,
  'spotlight': Icons.highlight_outlined,
  /// Buitenverlichting (schemerlamp / daglicht)
  'outdoor_light': Icons.wb_twilight_outlined,
  'emergency_light': Icons.emergency_outlined,
  'led_strip': Icons.linear_scale_outlined,
  /// Bureaulamp (gloeilamp warm licht)
  'desk_lamp': Icons.wb_incandescent_outlined,

  // ── Klimaat & Ventilatie ──────────────────────────────────────────────────
  'thermostat': Icons.thermostat_outlined,
  'heating': Icons.local_fire_department_outlined,
  'heat_pump': Icons.heat_pump_outlined,
  'cooling': Icons.ac_unit,
  'ventilation': Icons.air_outlined,
  'fan': Icons.air,
  /// Ventilator uit (geblokkeerd)
  'fan_off': Icons.block,
  'humidity': Icons.opacity,
  'co2': Icons.bubble_chart_outlined,
  'air_quality': Icons.masks_outlined,
  'filter': Icons.filter_alt_outlined,
  'filter_full': Icons.filter_alt,
  /// Radiator (horizontale lijnen = vinnen)
  'radiator': Icons.reorder_outlined,
  /// Vloerverwarming (rooster/vloerpatroon)
  'floor_heat': Icons.grid_4x4_outlined,
  /// Open haard (vlammen – gevuld, anders dan heating)
  'fireplace': Icons.local_fire_department,
  'chimney': Icons.fireplace_outlined,
  /// Terrasverwarmer (stralingselement met warmtestralen alleen naar beneden)
  'terras_heater': Icons.wb_incandescent,
  'temperature': Icons.device_thermostat,
  'wind': Icons.wind_power_outlined,
  'pressure': Icons.compress_outlined,
  'dewpoint': Icons.water_drop_outlined,

  // ── Zonwering & Ramen ─────────────────────────────────────────────────────
  'blind': Icons.blinds_outlined,
  'blinds': Icons.blinds_outlined,
  'curtain': Icons.curtains_outlined,
  'roller': Icons.roller_shades_outlined,
  'jalousie': Icons.blinds_closed_outlined,
  /// Ritsscreen / zip-screen (niet `screen` — die is beeldscherm AV)
  'shade_screen': Icons.vertical_shades_outlined,
  'sheers': Icons.curtains,
  'awning': Icons.deck_outlined,
  'window': Icons.window_outlined,
  /// Raam open (pijlen naar buiten = geopend)
  'window_open': Icons.open_in_full,
  /// Raam dicht (pijlen naar binnen = gesloten)
  'window_closed': Icons.close_fullscreen,
  'skylight': Icons.wb_iridescent_outlined,

  // ── Beveiliging & Detectie ────────────────────────────────────────────────
  'security': Icons.security_outlined,
  'alarm': Icons.notifications_active_outlined,
  'alarm_off': Icons.notifications_off_outlined,
  /// Bewegingsmelder
  'motion': Icons.sensors_outlined,
  /// Generieke sensor (gevuld – anders dan motion)
  'sensor': Icons.sensors,
  /// Rookmelder (wazig/rook visueel)
  'smoke': Icons.blur_on,
  /// CO / gasdetector (gasmasker)
  'co': Icons.masks,
  'leak': Icons.water_damage_outlined,
  'fire_alarm': Icons.fire_truck_outlined,
  'doorbell': Icons.doorbell_outlined,
  'camera': Icons.videocam_outlined,
  'camera_off': Icons.videocam_off_outlined,
  'lock': Icons.lock_outline,
  'lock_open': Icons.lock_open_outlined,
  'door': Icons.sensor_door_outlined,
  'door_open': Icons.door_back_door_outlined,
  /// Raamcontact open (pijlen naar buiten)
  'window_open_contact': Icons.open_in_full,
  /// Raamcontact dicht
  'window_closed_contact': Icons.close_fullscreen,
  /// Magneetcontact (stipje in cirkel = contact)
  'contact': Icons.adjust,
  'shield': Icons.shield_outlined,

  // ── Energie & Elektra ─────────────────────────────────────────────────────
  'energy': Icons.electric_bolt_outlined,
  'meter': Icons.speed_outlined,
  'power_meter': Icons.electrical_services_outlined,
  'solar': Icons.solar_power_outlined,
  'battery': Icons.battery_charging_full_outlined,
  'battery_full': Icons.battery_full_outlined,
  'battery_low': Icons.battery_1_bar_outlined,
  'ev_charger': Icons.ev_station_outlined,
  'outlet': Icons.outlet_outlined,
  /// Stekker in stopcontact
  'plug': Icons.power_outlined,
  /// Stekker losgekoppeld
  'unplugged': Icons.power_off,
  'switch_box': Icons.developer_board_outlined,
  'circuit': Icons.cable_outlined,
  'transformer': Icons.transform_outlined,
  'generator': Icons.generating_tokens_outlined,

  // ── Water & Sanitair ──────────────────────────────────────────────────────
  'water': Icons.water_drop_outlined,
  'water_on': Icons.water_drop,
  'valve': Icons.plumbing,
  /// Pomp (water-circulatie – ander icoon dan pressure)
  'pump': Icons.water,
  'tank': Icons.propane_tank_outlined,
  'pool': Icons.pool_outlined,
  'irrigation': Icons.grass_outlined,
  'garden': Icons.yard_outlined,
  'hot_water': Icons.hot_tub_outlined,
  /// Boiler (opslag/cilinder – anders dan hot_water)
  'boiler': Icons.storage_outlined,

  // ── Gebouw & Ruimten ──────────────────────────────────────────────────────
  'room': Icons.meeting_room_outlined,
  'floor': Icons.layers_outlined,
  'elevator': Icons.elevator_outlined,
  /// Lift (gevuld – bijv. meubellift / platformlift)
  'lift': Icons.elevator,
  'stairs': Icons.stairs_outlined,
  'parking': Icons.local_parking_outlined,
  /// Garagedeur gesloten
  'garage': Icons.garage_outlined,
  /// Garagedeur open (gevuld = actief/open)
  'garage_open': Icons.garage,
  'gate': Icons.fence_outlined,
  'office': Icons.business_outlined,
  'kitchen': Icons.kitchen_outlined,
  'bedroom': Icons.king_bed_outlined,
  'bathroom': Icons.bathtub_outlined,
  'spa': Icons.spa_outlined,
  'gym': Icons.fitness_center_outlined,
  'cinema': Icons.movie_outlined,

  // ── Audio & Video ─────────────────────────────────────────────────────────
  'speaker': Icons.speaker_outlined,
  'volume': Icons.volume_up_outlined,
  'mute': Icons.volume_off_outlined,
  'tv': Icons.tv_outlined,
  /// TV-lift (motorische lift die een tv omhoog/omlaag brengt)
  'tv_lift': Icons.connected_tv_outlined,
  'projector': Icons.video_call_outlined,
  'screen': Icons.desktop_windows_outlined,
  'music': Icons.music_note_outlined,
  'mic': Icons.mic_outlined,

  // ── Netwerk & ICT ─────────────────────────────────────────────────────────
  'wifi': Icons.wifi_outlined,
  'wifi_off': Icons.wifi_off_outlined,
  'network': Icons.router_outlined,
  'server': Icons.dns_outlined,
  'bluetooth': Icons.bluetooth_outlined,

  // ── Diversen ──────────────────────────────────────────────────────────────
  'bell': Icons.notifications_outlined,
  'key': Icons.key_outlined,
  'car': Icons.directions_car_outlined,
  'bike': Icons.directions_bike_outlined,
  'person': Icons.person_outline,
  'group': Icons.group_outlined,
  'phone': Icons.phone_outlined,
  'mail': Icons.mail_outline,
  'print': Icons.print_outlined,
  'coffee': Icons.coffee_outlined,
  'restaurant': Icons.restaurant_outlined,
};

IconData universalIconData(String? name) =>
    kUniversalIconMap[name] ?? Icons.grid_view_rounded;

/// Icon for a device control button — config key, then label heuristics.
IconData deviceControlOptionIcon({
  String? iconKey,
  String? label,
}) {
  if (iconKey != null && iconKey.isNotEmpty) {
    final mapped = kUniversalIconMap[iconKey];
    if (mapped != null) return mapped;
    final short = switch (iconKey) {
      'auto' => Icons.auto_mode_outlined,
      'snow' => Icons.ac_unit,
      'flame' => Icons.local_fire_department_outlined,
      'fan' => Icons.air,
      'drop' => Icons.water_drop_outlined,
      _ => null,
    };
    if (short != null) return short;
  }
  final l = (label ?? '').trim().toLowerCase();
  if (l.isEmpty) return Icons.tune_outlined;
  if (l.contains('stop')) return Icons.stop_circle_outlined;
  if (l.contains('sluit')) return Icons.arrow_downward_rounded;
  if (l.contains('koel')) return Icons.ac_unit;
  if (l.contains('verwarm') || l.contains('warm')) {
    return Icons.local_fire_department_outlined;
  }
  if (l.contains('ventil') || l.contains('fan')) return Icons.air;
  if (l.contains('auto')) return Icons.auto_mode_outlined;
  if (l.contains('droog') || l.contains('dry')) return Icons.water_drop_outlined;
  if (l.contains('open') || l.contains('omhoog')) return Icons.arrow_upward_rounded;
  if (l.contains('dicht') || l.contains('omlaag')) return Icons.arrow_downward_rounded;
  if (l.contains('oscill')) return Icons.swap_horiz;
  if (l.contains('omgekeerd') || l.contains('reverse')) return Icons.loop;
  if (l.startsWith('stand')) return Icons.speed_outlined;
  // Alleen los 'uit' — niet 'sluiten' (bevat ook "uit").
  if (l == 'uit' || (l.contains('uit') && !l.contains('sluit'))) {
    return Icons.power_off_outlined;
  }
  if (l == 'aan' || l.contains(' aan')) return Icons.power_settings_new_outlined;
  return Icons.tune_outlined;
}

/// Extract a compact numeric label ("1", "25", "255") when possible.
String? deviceControlNumericLabel(String label) {
  final t = label.trim();
  final stand = RegExp(r'^stand\s*(\d+)$', caseSensitive: false).firstMatch(t);
  if (stand != null) return stand.group(1);
  if (RegExp(r'^\d{1,3}%?$').hasMatch(t)) return t.replaceAll('%', '');
  return null;
}

/// Vaste volgorde op het dashboard: verlichting → klimaat → zonwering → audio → lutron → openhaard.
enum RoomControlCategory {
  lighting,
  climate,
  shading,
  position,
  audio,
  lutron,
  fireplace;

  static RoomControlCategory? tryParseSlug(String slug) {
    for (final v in RoomControlCategory.values) {
      if (v.name == slug) return v;
    }
    return null;
  }

  String get labelUpper => switch (this) {
        RoomControlCategory.lighting => 'VERLICHTING',
        RoomControlCategory.climate => 'KLIMAAT',
        RoomControlCategory.shading => 'ZONWERING',
        RoomControlCategory.position => 'POSITIE',
        RoomControlCategory.audio => 'AUDIO',
        RoomControlCategory.lutron => 'LUTRON',
        RoomControlCategory.fireplace => 'OPENHAARD',
      };

  String get labelTitle => switch (this) {
        RoomControlCategory.lighting => 'Verlichting',
        RoomControlCategory.climate => 'Klimaat',
        RoomControlCategory.shading => 'Zonwering',
        RoomControlCategory.position => 'Positie-aansturing',
        RoomControlCategory.audio => 'Audio',
        RoomControlCategory.lutron => 'Lutron',
        RoomControlCategory.fireplace => 'Openhaard',
      };

  IconData get icon => switch (this) {
        RoomControlCategory.lighting => Icons.lightbulb_outline_rounded,
        RoomControlCategory.climate => Icons.thermostat_rounded,
        RoomControlCategory.shading => Icons.blinds_rounded,
        RoomControlCategory.position => Icons.vertical_split_outlined,
        RoomControlCategory.audio => Icons.speaker_group_outlined,
        RoomControlCategory.lutron => Icons.home_work_outlined,
        RoomControlCategory.fireplace => Icons.local_fire_department_outlined,
      };

  bool matchesDevice(Device d) {
    switch (this) {
      case RoomControlCategory.lighting:
        return d.type == DeviceType.lightSwitch ||
            d.type == DeviceType.lightDimmer ||
            d.type == DeviceType.rgbwWw;
      case RoomControlCategory.climate:
        return d.type == DeviceType.climate ||
            d.type == DeviceType.ac ||
            d.type == DeviceType.fan ||
            d.type == DeviceType.wtw;
      case RoomControlCategory.shading:
        return d.type == DeviceType.shading;
      case RoomControlCategory.position:
        return d.type == DeviceType.positionActuator;
      case RoomControlCategory.audio:
        return d.type == DeviceType.mediaSonos ||
            d.type == DeviceType.mediaBluesound;
      case RoomControlCategory.lutron:
        return d.type == DeviceType.lutronHomeworks;
      case RoomControlCategory.fireplace:
        return d.type == DeviceType.fireplace;
    }
  }
}

/// A display segment in the room UI – either a fixed [RoomControlCategory]
/// or a per-device universal panel (custom name + icon, single device).
class RoomSegment {
  const RoomSegment._({
    required this.slug,
    required this.labelUpper,
    required this.icon,
    required this.devices,
    this.category,
  });

  /// Fixed category segment (Verlichting, Klimaat, …).
  factory RoomSegment.fromCategory(
    RoomControlCategory cat,
    List<Device> devices,
  ) =>
      RoomSegment._(
        slug: cat.name,
        labelUpper: cat.labelUpper,
        icon: cat.icon,
        devices: devices,
        category: cat,
      );

  /// One universal device = one segment with custom name + icon.
  factory RoomSegment.fromUniversal(Device device) {
    final cfg = device.raw['universal'] as Map<String, dynamic>?;
    final iconName = cfg?['icon'] as String?;
    return RoomSegment._(
      slug: 'universal__${device.id}',
      labelUpper: device.name.toUpperCase(),
      icon: universalIconData(iconName),
      devices: [device],
    );
  }

  /// One melding device = one segment with alert icon.
  factory RoomSegment.fromMelding(Device device) => RoomSegment._(
        slug: 'melding__${device.id}',
        labelUpper: device.name.toUpperCase(),
        icon: Icons.notifications_outlined,
        devices: [device],
      );

  /// Non-null for fixed categories; null for universal device segments.
  final RoomControlCategory? category;
  final String slug;
  final String labelUpper;
  final IconData icon;
  final List<Device> devices;

  bool get isUniversal => category == null && slug.startsWith('universal');
  bool get isMelding => category == null && slug.startsWith('melding');
}

/// Returns all segments for a room in display order:
/// fixed categories (non-empty) followed by one entry per universal device.
List<RoomSegment> roomControlSegments(List<Device> devices) {
  final out = <RoomSegment>[];

  // Fixed categories in order.
  for (final c in RoomControlCategory.values) {
    final list = devices.where(c.matchesDevice).toList();
    if (list.isNotEmpty) out.add(RoomSegment.fromCategory(c, list));
  }

  // Each universal / melding device gets its own segment.
  for (final d in devices) {
    if (d.type == DeviceType.universal) {
      out.add(RoomSegment.fromUniversal(d));
    } else if (d.type == DeviceType.melding) {
      out.add(RoomSegment.fromMelding(d));
    }
  }

  return out;
}
