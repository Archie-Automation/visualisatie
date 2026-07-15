import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'media_api.dart';
import 'models.dart';

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
      );

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

bool shouldSuppressIdleForMusic({
  required DisplayPanelSettings settings,
  required HouseConfig? cfg,
  required Map<String, MediaState> mediaStates,
}) {
  if (!settings.suppressScreensaverWhenMusicPlaying) return false;
  return isMusicPlayingInRoom(
    cfg: cfg,
    mediaStates: mediaStates,
    roomId: settings.panelRoomId,
  );
}
