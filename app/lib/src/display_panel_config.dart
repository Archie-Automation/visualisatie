import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'media_api.dart';
import 'models.dart';

/// Idle/screensaver-instellingen gelden alleen op de native Android-app.
bool get wallTabletDeviceSettingsApply =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Wall-tablet idle / screensaver settings (house.json defaults + local overrides).
class DisplayPanelSettings {
  const DisplayPanelSettings({
    this.enabled = true,
    this.idleHomeMinutes = 1,
    this.screensaverMinutes = 5,
    this.panelRoomId,
    this.panelRoomName,
    this.suppressScreensaverWhenMusicPlaying = true,
    this.temperatureGa,
    this.temperatureRoomId,
    this.temperatureRoomName,
    this.useOutdoorTemperature = false,
  });

  final bool enabled;
  final int idleHomeMinutes;
  /// 0 = screensaver uit.
  final int screensaverMinutes;
  /// Ruimte waar dit wandtablet hangt (muziek-blokkade, optioneel temperatuur).
  final String? panelRoomId;
  final String? panelRoomName;
  /// Geen screensaver zolang er muziek speelt in [panelRoomId].
  final bool suppressScreensaverWhenMusicPlaying;
  final String? temperatureGa;
  final String? temperatureRoomId;
  final String? temperatureRoomName;
  /// Screensaver toont buitentemperatuur via [temperatureGa] i.p.v. een zone.
  final bool useOutdoorTemperature;

  Duration get idleHomeDuration => Duration(minutes: idleHomeMinutes);
  Duration? get screensaverDuration => screensaverMinutes > 0
      ? Duration(minutes: screensaverMinutes)
      : null;

  bool get showTemperature =>
      (temperatureGa != null && temperatureGa!.trim().isNotEmpty) ||
      (temperatureRoomId != null && temperatureRoomId!.trim().isNotEmpty);

  DisplayPanelSettings copyWith({
    bool? enabled,
    int? idleHomeMinutes,
    int? screensaverMinutes,
    String? panelRoomId,
    String? panelRoomName,
    bool? suppressScreensaverWhenMusicPlaying,
    String? temperatureGa,
    String? temperatureRoomId,
    String? temperatureRoomName,
    bool? useOutdoorTemperature,
    bool clearPanelRoom = false,
    bool clearTemperatureGa = false,
    bool clearTemperatureRoom = false,
  }) =>
      DisplayPanelSettings(
        enabled: enabled ?? this.enabled,
        idleHomeMinutes: idleHomeMinutes ?? this.idleHomeMinutes,
        screensaverMinutes: screensaverMinutes ?? this.screensaverMinutes,
        panelRoomId:
            clearPanelRoom ? null : (panelRoomId ?? this.panelRoomId),
        panelRoomName:
            clearPanelRoom ? null : (panelRoomName ?? this.panelRoomName),
        suppressScreensaverWhenMusicPlaying: suppressScreensaverWhenMusicPlaying ??
            this.suppressScreensaverWhenMusicPlaying,
        temperatureGa: clearTemperatureGa
            ? null
            : (temperatureGa ?? this.temperatureGa),
        temperatureRoomId: clearTemperatureRoom
            ? null
            : (temperatureRoomId ?? this.temperatureRoomId),
        temperatureRoomName: clearTemperatureRoom
            ? null
            : (temperatureRoomName ?? this.temperatureRoomName),
        useOutdoorTemperature:
            useOutdoorTemperature ?? this.useOutdoorTemperature,
      );

  static bool _outdoorFromJson(Map<String, dynamic> json) {
    final flag = json['useOutdoorTemperature'] as bool?;
    if (flag != null) return flag;
    return (json['temperatureGa'] as String?)?.trim().isNotEmpty ?? false;
  }

  static DisplayPanelSettings fromHouseJson(Map<String, dynamic>? json) {
    if (json == null) return const DisplayPanelSettings();
    return DisplayPanelSettings(
      enabled: json['enabled'] as bool? ?? true,
      idleHomeMinutes: (json['idleHomeMinutes'] as num?)?.toInt() ?? 1,
      screensaverMinutes: (json['screensaverMinutes'] as num?)?.toInt() ?? 5,
      panelRoomId: json['panelRoomId'] as String?,
      panelRoomName: json['panelRoomName'] as String?,
      suppressScreensaverWhenMusicPlaying:
          json['suppressScreensaverWhenMusicPlaying'] as bool? ?? true,
      temperatureGa: json['temperatureGa'] as String?,
      temperatureRoomId: json['temperatureRoomId'] as String?,
      temperatureRoomName: json['temperatureRoomName'] as String?,
      useOutdoorTemperature: _outdoorFromJson(json),
    );
  }

  Map<String, dynamic> toPrefsJson() => {
        'enabled': enabled,
        'idleHomeMinutes': idleHomeMinutes,
        'screensaverMinutes': screensaverMinutes,
        if (panelRoomId != null && panelRoomId!.trim().isNotEmpty)
          'panelRoomId': panelRoomId!.trim(),
        if (panelRoomName != null) 'panelRoomName': panelRoomName,
        'suppressScreensaverWhenMusicPlaying':
            suppressScreensaverWhenMusicPlaying,
        'useOutdoorTemperature': useOutdoorTemperature,
        if (temperatureGa != null && temperatureGa!.trim().isNotEmpty)
          'temperatureGa': temperatureGa!.trim(),
        if (temperatureRoomId != null && temperatureRoomId!.trim().isNotEmpty)
          'temperatureRoomId': temperatureRoomId!.trim(),
        if (temperatureRoomName != null) 'temperatureRoomName': temperatureRoomName,
      };

  static DisplayPanelSettings fromPrefsJson(Map<String, dynamic> json) =>
      DisplayPanelSettings(
        enabled: json['enabled'] as bool? ?? true,
        idleHomeMinutes: (json['idleHomeMinutes'] as num?)?.toInt() ?? 1,
        screensaverMinutes: (json['screensaverMinutes'] as num?)?.toInt() ?? 5,
        panelRoomId: json['panelRoomId'] as String?,
        panelRoomName: json['panelRoomName'] as String?,
        suppressScreensaverWhenMusicPlaying:
            json['suppressScreensaverWhenMusicPlaying'] as bool? ?? true,
        temperatureGa: json['temperatureGa'] as String?,
        temperatureRoomId: json['temperatureRoomId'] as String?,
        temperatureRoomName: json['temperatureRoomName'] as String?,
        useOutdoorTemperature: _outdoorFromJson(json),
      );
}

const _prefsKey = 'display_panel_v1';

class DisplayPanelSettingsNotifier extends AsyncNotifier<DisplayPanelSettings> {
  @override
  Future<DisplayPanelSettings> build() async {
    final houseDefaults = ref.watch(configProvider).maybeWhen(
          data: (cfg) => cfg.displayPanelJson,
          orElse: () => null,
        );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final house = DisplayPanelSettings.fromHouseJson(houseDefaults);
    if (raw == null || raw.isEmpty) return house;
    try {
      final local = DisplayPanelSettings.fromPrefsJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      return DisplayPanelSettings(
        enabled: local.enabled,
        idleHomeMinutes: local.idleHomeMinutes,
        screensaverMinutes: local.screensaverMinutes,
        panelRoomId: local.panelRoomId ?? house.panelRoomId,
        panelRoomName: local.panelRoomName ?? house.panelRoomName,
        suppressScreensaverWhenMusicPlaying:
            local.suppressScreensaverWhenMusicPlaying,
        temperatureGa: local.temperatureGa ?? house.temperatureGa,
        temperatureRoomId: local.temperatureRoomId ?? house.temperatureRoomId,
        temperatureRoomName:
            local.temperatureRoomName ?? house.temperatureRoomName,
        useOutdoorTemperature: local.useOutdoorTemperature,
      );
    } catch (_) {
      return house;
    }
  }

  Future<void> save(DisplayPanelSettings settings) async {
    state = AsyncData(settings);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toPrefsJson()));
  }

  Future<void> resetToHouseDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    ref.invalidateSelf();
  }
}

final displayPanelSettingsProvider =
    AsyncNotifierProvider<DisplayPanelSettingsNotifier, DisplayPanelSettings>(
  DisplayPanelSettingsNotifier.new,
);

Room? roomById(HouseConfig cfg, String roomId) {
  for (final f in cfg.floors) {
    for (final r in f.rooms) {
      if (r.id == roomId) return r;
    }
  }
  return null;
}

/// Live ruimte-/GA-temperatuur voor het screensaver-paneel.
double? resolveDisplayTemperature({
  required HouseConfig? cfg,
  required BusState bus,
  required DisplayPanelSettings settings,
}) {
  if (settings.useOutdoorTemperature) {
    final ga = settings.temperatureGa?.trim();
    if (ga == null || ga.isEmpty) return null;
    final v = bus.values[ga];
    if (v is num) return v.toDouble();
    return null;
  }
  final ga = settings.temperatureGa?.trim();
  if (ga != null && ga.isNotEmpty) {
    final v = bus.values[ga];
    if (v is num) return v.toDouble();
    return null;
  }
  final roomId = settings.temperatureRoomId?.trim();
  if (roomId == null || roomId.isEmpty || cfg == null) return null;
  final room = roomById(cfg, roomId);
  if (room == null) return null;
  for (final d in room.devices) {
    if (d.type == DeviceType.climate) {
      final tga = d.ga['actual_temp'];
      if (tga != null) {
        final v = bus.values[tga];
        if (v is num) return v.toDouble();
      }
    } else if (d.type == DeviceType.ac) {
      final ac = d.raw['ac'] as Map<String, dynamic>?;
      final tga = (ac?['actualTemp'] as Map?)?['ga'] as String?;
      if (tga != null) {
        final v = bus.values[tga];
        if (v is num) return v.toDouble();
      }
    }
  }
  return null;
}

/// HVAC-modus + vraag voor screensaver (zelfde bron als temperatuur).
class DisplayHvacStatus {
  const DisplayHvacStatus({
    required this.isHeating,
    required this.demandActive,
  });

  final bool isHeating;
  final bool demandActive;
}

bool _demandActive(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value > 0;
  return false;
}

bool _isHeatingRaw(dynamic hvacRaw, {required bool defaultHeat}) {
  if (hvacRaw == null) return defaultHeat;
  if (hvacRaw is bool) return hvacRaw;
  if (hvacRaw is num) return hvacRaw != 0;
  if (hvacRaw is String) {
    final s = hvacRaw.trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'heat') return true;
    if (s == '0' || s == 'false' || s == 'cool') return false;
  }
  return defaultHeat;
}

Device? _climateOrAcForDisplay({
  required HouseConfig? cfg,
  required DisplayPanelSettings settings,
}) {
  if (cfg == null) return null;

  final tempGa = settings.temperatureGa?.trim();
  if (tempGa != null && tempGa.isNotEmpty) {
    for (final f in cfg.floors) {
      for (final r in f.rooms) {
        for (final d in r.devices) {
          if (d.type == DeviceType.climate && d.ga['actual_temp'] == tempGa) {
            return d;
          }
          if (d.type == DeviceType.ac) {
            final ac = d.raw['ac'] as Map<String, dynamic>?;
            final tga = (ac?['actualTemp'] as Map?)?['ga'] as String?;
            if (tga == tempGa) return d;
          }
        }
      }
    }
  }

  final roomId = (settings.temperatureRoomId ?? settings.panelRoomId)?.trim();
  if (roomId == null || roomId.isEmpty) return null;
  final room = roomById(cfg, roomId);
  if (room == null) return null;
  for (final d in room.devices) {
    if (d.type == DeviceType.climate || d.type == DeviceType.ac) return d;
  }
  return null;
}

DisplayHvacStatus? resolveDisplayHvacStatus({
  required HouseConfig? cfg,
  required BusState bus,
  required DisplayPanelSettings settings,
}) {
  if (settings.useOutdoorTemperature) return null;
  final d = _climateOrAcForDisplay(cfg: cfg, settings: settings);
  if (d == null) return null;

  if (d.type == DeviceType.climate) {
    final climateCfg = d.raw['climate'] as Map<String, dynamic>?;
    final canHeat = climateCfg?['canHeat'] != false;
    final canCool = climateCfg?['canCool'] == true;
    if (!canHeat && !canCool) return null;

    final hvacStatusGa = d.ga['hvac_mode_status'] ?? d.ga['hvac_mode'];
    final hvacRaw = hvacStatusGa != null ? bus.values[hvacStatusGa] : null;
    final isHeating = _isHeatingRaw(hvacRaw, defaultHeat: canHeat);

    final heatDemandGa = d.ga['heat_demand'];
    final coolDemandGa = d.ga['cool_demand'];
    final demandGa = isHeating ? heatDemandGa : coolDemandGa;
    final demandActive =
        demandGa != null ? _demandActive(bus.values[demandGa]) : false;
    return DisplayHvacStatus(isHeating: isHeating, demandActive: demandActive);
  }

  if (d.type == DeviceType.ac) {
    final ac = d.raw['ac'] as Map<String, dynamic>?;
    if (ac == null) return null;
    final onOff = ac['onOff'] as Map<String, dynamic>?;
    final onStatusGa =
        onOff?['statusGa'] as String? ?? onOff?['ga'] as String?;
    final onVal = onStatusGa == null ? null : bus.values[onStatusGa];
    final on = onVal == true || onVal == 1;
    if (!on) return null;

    final mode = ac['mode'] as Map<String, dynamic>?;
    final modeStatusGa =
        mode?['statusGa'] as String? ?? mode?['ga'] as String?;
    final modeRaw = modeStatusGa == null ? null : bus.values[modeStatusGa];
    final activeMode = modeRaw is num ? modeRaw.toInt() : null;
    final options = (mode?['options'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    int? heatVal;
    int? coolVal;
    for (final o in options) {
      final icon = (o['icon'] as String?)?.toLowerCase() ?? '';
      final label = (o['label'] as String?)?.toLowerCase() ?? '';
      final v = (o['value'] as num?)?.toInt();
      if (v == null) continue;
      if (icon.contains('fire') ||
          icon.contains('heat') ||
          label.contains('verwarm') ||
          label.contains('heat')) {
        heatVal ??= v;
      }
      if (icon.contains('snow') ||
          icon.contains('cool') ||
          icon.contains('ac') ||
          label.contains('koel') ||
          label.contains('cool')) {
        coolVal ??= v;
      }
    }
    if (activeMode == null) return null;
    final isHeating = heatVal != null && activeMode == heatVal;
    final isCooling = coolVal != null && activeMode == coolVal;
    if (!isHeating && !isCooling) return null;
    return DisplayHvacStatus(
      isHeating: isHeating,
      demandActive: true,
    );
  }

  return null;
}

/// Of Sonos/Bluesound in de gekoppelde ruimte actief speelt.
bool isMusicPlayingInRoom({
  required HouseConfig? cfg,
  required Map<String, MediaState> mediaStates,
  required String? roomId,
}) {
  if (cfg == null || roomId == null || roomId.trim().isEmpty) return false;
  final room = roomById(cfg, roomId.trim());
  if (room == null) return false;
  for (final d in room.devices) {
    if (!d.type.isMedia) continue;
    final ms = mediaStates[d.id];
    if (ms != null && ms.transport.isActive) return true;
  }
  return false;
}

/// Screensaver blokkeren alleen als de fullscreen media-speler open is voor
/// een Sonos/Bluesound in de paneel-ruimte én die speelt.
bool shouldSuppressIdleForMusic({
  required DisplayPanelSettings settings,
  required HouseConfig? cfg,
  required Map<String, MediaState> mediaStates,
  required String matchedLocation,
}) {
  if (!settings.suppressScreensaverWhenMusicPlaying) return false;
  if (cfg == null) return false;
  final roomId = settings.panelRoomId?.trim();
  if (roomId == null || roomId.isEmpty) return false;

  final mediaMatch = RegExp(r'^/media/([^/]+)/?$').firstMatch(matchedLocation);
  if (mediaMatch == null) return false;
  final deviceId = mediaMatch.group(1)!;

  final room = roomById(cfg, roomId);
  if (room == null) return false;
  Device? device;
  for (final d in room.devices) {
    if (d.id == deviceId) {
      device = d;
      break;
    }
  }
  if (device == null || !device.type.isMedia) return false;

  final ms = mediaStates[deviceId];
  return ms != null && ms.transport.isActive;
}
