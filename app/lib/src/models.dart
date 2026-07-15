// Mirrors the backend house.json tree.

import 'package:flutter/material.dart';

enum DeviceType {
  lightSwitch,
  lightDimmer,
  rgbwWw,
  shading,
  positionActuator,
  climate,
  mediaSonos,
  mediaBluesound,
  camera,
  intercom,
  fireplace,
  ac,
  fan,
  universal,
  wtw,
  melding,
  lutronHomeworks,
  unknown;

  static DeviceType fromJson(String s) => switch (s) {
        'light_switch' => lightSwitch,
        'light_dimmer' => lightDimmer,
        'rgbw_ww' => rgbwWw,
        'shading' => shading,
        'position_actuator' => positionActuator,
        'climate' => climate,
        'media_sonos' => mediaSonos,
        'media_bluesound' => mediaBluesound,
        'camera' => camera,
        'intercom' => intercom,
        'fireplace' => fireplace,
        'ac' => ac,
        'fan' => fan,
        'universal' => universal,
        'wtw' => wtw,
        'melding' => melding,
        'lutron_homeworks' => lutronHomeworks,
        _ => unknown,
      };

  bool get isMedia =>
      this == DeviceType.mediaSonos || this == DeviceType.mediaBluesound;
}

/// Shading variants; controls icon, labels and UI behaviour.
enum ShadingSubtype {
  blind,
  roller,
  curtain,
  jalousie,
  screen,
  sheers,
  awning;

  static ShadingSubtype fromJson(String? s) => switch (s) {
        'roller' => roller,
        'curtain' => curtain,
        'jalousie' => jalousie,
        'screen' => screen,
        'sheers' => sheers,
        'awning' => awning,
        _ => blind,
      };

  /// Value stored in house.json `subtype`.
  String get configValue => name;

  String get label => switch (this) {
        blind => 'Rolluik',
        roller => 'Rolgordijn',
        curtain => 'Gordijn',
        jalousie => 'Jaloezie',
        screen => 'Screen',
        sheers => 'Sheers / vitrage',
        awning => 'Markies',
      };

  IconData get tileIcon => switch (this) {
        blind => Icons.door_sliding_outlined,
        roller => Icons.roller_shades_outlined,
        curtain => Icons.curtains_outlined,
        jalousie => Icons.blinds_closed_outlined,
        screen => Icons.texture_outlined,
        sheers => Icons.curtains,
        awning => Icons.wb_sunny_outlined,
      };

  /// Open/dicht-knoppen (horizontaal) i.p.v. omhoog/omlaag.
  bool get usesHorizontalOpenClose =>
      this == curtain || this == sheers;

  /// Horizontale positie-slider in popup.
  bool get usesHorizontalPositionSlider => usesHorizontalOpenClose;

  /// 3-state status-icoon i.p.v. percentage in tegelkop.
  bool get showsPositionStateIcon =>
      this == curtain ||
      this == jalousie ||
      this == sheers ||
      this == screen ||
      this == roller ||
      this == awning;

  /// Stijl van het custom status-icoon (open / half / dicht).
  ShadingPositionIconStyle get positionIconStyle => switch (this) {
        curtain => ShadingPositionIconStyle.curtain,
        sheers => ShadingPositionIconStyle.sheers,
        jalousie => ShadingPositionIconStyle.blinds,
        blind => ShadingPositionIconStyle.shutter,
        roller => ShadingPositionIconStyle.roller,
        screen => ShadingPositionIconStyle.screen,
        awning => ShadingPositionIconStyle.awning,
      };
}

enum ShadingPositionIconStyle {
  curtain,
  sheers,
  blinds,
  roller,
  awning,
  shutter,
  screen,
}

/// A single "are you sure?" prompt parsed from config. The value in config
/// can be a boolean, a plain string (shorthand for the message), or an
/// object `{ title, message, pin }`.
///
/// When [pin] is a 4-digit string the dialog switches to PIN-entry mode:
/// the user must type the correct code before the action is executed.
class ConfirmPrompt {
  final String? title;
  final String? message;
  /// Optional 4-digit PIN. When set the dialog shows digit inputs instead
  /// of a simple "Doorgaan / Annuleren" button pair.
  final String? pin;

  const ConfirmPrompt({this.title, this.message, this.pin});

  /// Standaard waarschuwing bij openhaard aanzetten (zonder custom config).
  static const fireplaceOn = ConfirmPrompt(
    title: 'Weet u zeker dat u de haard aan wilt zetten?',
    message: 'Let op: volg bij het gebruik van de haard altijd de '
        'veiligheids- en bedieningsvoorschriften van de fabrikant.',
  );

  static ConfirmPrompt? fromJson(Object? v) {
    if (v == null) return null;
    if (v is bool) return v ? const ConfirmPrompt() : null;
    if (v is String) return ConfirmPrompt(message: v);
    if (v is Map) {
      return ConfirmPrompt(
        title: v['title'] as String?,
        message: v['message'] as String?,
        pin: v['pin'] as String?,
      );
    }
    return null;
  }
}

class DeviceConfirm {
  final ConfirmPrompt? on;
  final ConfirmPrompt? off;
  final Map<String, ConfirmPrompt> actions;

  const DeviceConfirm({
    this.on,
    this.off,
    this.actions = const {},
  });

  static DeviceConfirm? fromJson(Object? v) {
    if (v is! Map) return null;
    final actionsRaw = (v['actions'] as Map?) ?? const {};
    final actions = <String, ConfirmPrompt>{};
    actionsRaw.forEach((k, val) {
      final p = ConfirmPrompt.fromJson(val);
      if (p != null) actions[k as String] = p;
    });
    return DeviceConfirm(
      on: ConfirmPrompt.fromJson(v['on']),
      off: ConfirmPrompt.fromJson(v['off']),
      actions: actions,
    );
  }
}

class Device {
  final String id;
  final String name;
  final DeviceType type;
  final bool favorite;
  final Map<String, String> ga;
  final Map<String, dynamic> raw;
  final DeviceConfirm? confirm;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.favorite,
    required this.ga,
    required this.raw,
    this.confirm,
  });

  /// Shading subtype (defaults to `blind`). Only meaningful for `shading`.
  ShadingSubtype get shadingSubtype =>
      ShadingSubtype.fromJson(raw['subtype'] as String?);

  /// Whether the UI should prefer a continuous slider over stepped buttons.
  /// Defaults to `true` for shading, `true` for fireplace/fan, otherwise
  /// whatever the config says.
  bool get preferSlider {
    final v = raw['slider'];
    if (v is bool) return v;
    return type == DeviceType.shading ||
        type == DeviceType.positionActuator ||
        type == DeviceType.fireplace ||
        type == DeviceType.fan;
  }

  /// Zelfde KNX-object als zonwering (up/down, positie %, lamellen).
  bool get usesPositionControl =>
      type == DeviceType.shading || type == DeviceType.positionActuator;

  /// `knx` (standaard) of `lutron` — direct Homeworks #OUTPUT i.p.v. KNX-GA.
  String get busControl {
    final s = (raw['control'] as String?)?.trim();
    if (s == null || s.isEmpty) return 'knx';
    return s;
  }

  bool get isLutronBusControl => busControl == 'lutron';

  Map<String, dynamic>? get lutronOutputMap {
    final o = raw['lutronOutput'];
    if (o is Map<String, dynamic>) return o;
    if (o is Map) return Map<String, dynamic>.from(o);
    return null;
  }

  bool get isLutronShade => type == DeviceType.shading && isLutronBusControl;

  int? get lutronIntegrationId {
    final v = raw['lutronIntegrationId'] ?? lutronOutputMap?['integrationId'];
    if (v is num) return v.toInt();
    return null;
  }

  factory Device.fromJson(Map<String, dynamic> j) {
    final gaMap = (j['ga'] as Map?) ?? const {};
    return Device(
      id: j['id'] as String,
      name: j['name'] as String,
      type: DeviceType.fromJson(j['type'] as String),
      favorite: (j['favorite'] as bool?) ?? false,
      ga: gaMap.map((k, v) => MapEntry(k as String, v as String)),
      raw: Map<String, dynamic>.from(j),
      confirm: DeviceConfirm.fromJson(j['confirm']),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Scenes                                                               */
/* --------------------------------------------------------------------- */

/// A UI-friendly role enum, mapped 1:1 with the backend's scene roles.
enum SceneRole {
  switch_,
  dimValue,
  setpoint,
  position,
  sceneNumber,
  bit,
  byte,
  percent,
  temperature,
  rawBytes,
  rgb232,
  pulse;

  static SceneRole fromJson(String s) => switch (s) {
        'switch' => SceneRole.switch_,
        'dim_value' => SceneRole.dimValue,
        'setpoint' => SceneRole.setpoint,
        'position' => SceneRole.position,
        'scene_number' => SceneRole.sceneNumber,
        'bit' => SceneRole.bit,
        'byte' => SceneRole.byte,
        'percent' => SceneRole.percent,
        'temperature' => SceneRole.temperature,
        'raw_bytes' => SceneRole.rawBytes,
        'rgb232' => SceneRole.rgb232,
        'pulse' => SceneRole.pulse,
        _ => SceneRole.bit,
      };

  String toJson() => switch (this) {
        SceneRole.switch_ => 'switch',
        SceneRole.dimValue => 'dim_value',
        SceneRole.setpoint => 'setpoint',
        SceneRole.position => 'position',
        SceneRole.sceneNumber => 'scene_number',
        SceneRole.bit => 'bit',
        SceneRole.byte => 'byte',
        SceneRole.percent => 'percent',
        SceneRole.temperature => 'temperature',
        SceneRole.rawBytes => 'raw_bytes',
        SceneRole.rgb232 => 'rgb232',
        SceneRole.pulse => 'pulse',
      };

  /// Whether the role's value is a boolean rather than a number.
  bool get isBoolean => this == SceneRole.switch_ || this == SceneRole.bit;

  String get humanName => switch (this) {
        SceneRole.switch_ => 'Schakelen (bit)',
        SceneRole.dimValue => 'Dimmen (0–100%)',
        SceneRole.setpoint => 'Setpoint (°C)',
        SceneRole.position => 'Zonwering (0–100%)',
        SceneRole.sceneNumber => 'Scene nummer',
        SceneRole.bit => 'Bit (ruw)',
        SceneRole.byte => 'Byte (0–255)',
        SceneRole.percent => 'Percentage (0–100)',
        SceneRole.temperature => 'Temperatuur (°C)',
        SceneRole.rawBytes => 'Ruwe bytes (1–14)',
        SceneRole.rgb232 => 'RGB DPT 232',
        SceneRole.pulse => 'Puls (DPT1)',
      };
}

class SceneAction {
  final String ga;
  final SceneRole role;
  final Object value; // bool or num
  final int? delayMs;
  final int? pulseMs;

  const SceneAction({
    required this.ga,
    required this.role,
    required this.value,
    this.delayMs,
    this.pulseMs,
  });

  factory SceneAction.fromJson(Map<String, dynamic> j) => SceneAction(
        ga: j['ga'] as String,
        role: SceneRole.fromJson(j['role'] as String),
        value: j['value'] as Object,
        delayMs: (j['delayMs'] as num?)?.toInt(),
        pulseMs: (j['pulseMs'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'ga': ga,
        'role': role.toJson(),
        'value': value,
        if (delayMs != null) 'delayMs': delayMs,
        if (pulseMs != null) 'pulseMs': pulseMs,
      };

  SceneAction copyWith({
    String? ga,
    SceneRole? role,
    Object? value,
    int? delayMs,
    int? pulseMs,
  }) =>
      SceneAction(
        ga: ga ?? this.ga,
        role: role ?? this.role,
        value: value ?? this.value,
        delayMs: delayMs ?? this.delayMs,
        pulseMs: pulseMs ?? this.pulseMs,
      );
}

class SceneMediaAction {
  final String deviceId;
  final String kind;
  final String? action;
  final int? value;
  final bool? muted;
  final String? presetId;
  final String? presetName;
  final String? uri;
  final int? delayMs;

  const SceneMediaAction({
    required this.deviceId,
    required this.kind,
    this.action,
    this.value,
    this.muted,
    this.presetId,
    this.presetName,
    this.uri,
    this.delayMs,
  });

  factory SceneMediaAction.transport(
    String deviceId,
    String action, {
    int? delayMs,
  }) =>
      SceneMediaAction(
        deviceId: deviceId,
        kind: 'transport',
        action: action,
        delayMs: delayMs,
      );

  factory SceneMediaAction.volume(
    String deviceId,
    int value, {
    int? delayMs,
  }) =>
      SceneMediaAction(
        deviceId: deviceId,
        kind: 'volume',
        value: value.clamp(0, 100),
        delayMs: delayMs,
      );

  factory SceneMediaAction.mute(
    String deviceId,
    bool muted, {
    int? delayMs,
  }) =>
      SceneMediaAction(
        deviceId: deviceId,
        kind: 'mute',
        muted: muted,
        delayMs: delayMs,
      );

  factory SceneMediaAction.preset(
    String deviceId,
    String presetId, {
    String? name,
    String? uri,
    int? delayMs,
  }) =>
      SceneMediaAction(
        deviceId: deviceId,
        kind: 'preset',
        presetId: presetId,
        presetName: name,
        uri: uri,
        delayMs: delayMs,
      );

  factory SceneMediaAction.fromJson(Map<String, dynamic> j) => SceneMediaAction(
        deviceId: j['deviceId'] as String,
        kind: j['kind'] as String,
        action: j['action'] as String?,
        value: (j['value'] as num?)?.toInt(),
        muted: j['muted'] as bool?,
        presetId: j['presetId'] as String?,
        presetName: j['presetName'] as String?,
        uri: j['uri'] as String?,
        delayMs: (j['delayMs'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'kind': kind,
        if (action != null) 'action': action,
        if (value != null) 'value': value,
        if (muted != null) 'muted': muted,
        if (presetId != null) 'presetId': presetId,
        if (presetName != null) 'presetName': presetName,
        if (uri != null) 'uri': uri,
        if (delayMs != null) 'delayMs': delayMs,
      };
}

class Scene {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final List<SceneAction> actions;
  final List<SceneMediaAction> mediaActions;

  const Scene({
    required this.id,
    required this.name,
    required this.actions,
    this.icon,
    this.color,
    this.mediaActions = const [],
  });

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        color: j['color'] as String?,
        actions: ((j['actions'] as List?) ?? const [])
            .map((a) => SceneAction.fromJson(a as Map<String, dynamic>))
            .toList(),
        mediaActions: ((j['mediaActions'] as List?) ?? const [])
            .map((a) => SceneMediaAction.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        'actions': actions.map((a) => a.toJson()).toList(),
        if (mediaActions.isNotEmpty)
          'mediaActions': mediaActions.map((a) => a.toJson()).toList(),
      };

  Scene copyWith({
    String? name,
    String? icon,
    String? color,
    List<SceneAction>? actions,
    List<SceneMediaAction>? mediaActions,
  }) =>
      Scene(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        actions: actions ?? this.actions,
        mediaActions: mediaActions ?? this.mediaActions,
      );
}

/* --------------------------------------------------------------------- */
/*  Rooms / floors / config                                              */
/* --------------------------------------------------------------------- */

class Room {
  final String id;
  final String name;
  final String? icon;
  final String? cover;
  final List<Device> devices;
  final List<Scene> scenes;

  const Room({
    required this.id,
    required this.name,
    required this.devices,
    required this.scenes,
    this.icon,
    this.cover,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        cover: j['cover'] as String?,
        devices: ((j['devices'] as List?) ?? const [])
            .map((d) => Device.fromJson(d as Map<String, dynamic>))
            .toList(),
        scenes: ((j['scenes'] as List?) ?? const [])
            .map((s) => Scene.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class Floor {
  final String id;
  final String name;
  final int order;
  final String? icon;
  final List<Room> rooms;

  const Floor({
    required this.id,
    required this.name,
    required this.order,
    required this.rooms,
    this.icon,
  });

  factory Floor.fromJson(Map<String, dynamic> j) => Floor(
        id: j['id'] as String,
        name: j['name'] as String,
        order: (j['order'] as int?) ?? 0,
        icon: j['icon'] as String?,
        rooms: ((j['rooms'] as List?) ?? const [])
            .map((r) => Room.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

class CurrentUser {
  final String id;
  final String username;
  final String? displayName;
  final String role;
  final bool canEditScenes;

  const CurrentUser({
    required this.id,
    required this.username,
    required this.role,
    required this.canEditScenes,
    this.displayName,
  });

  bool get isAdmin => role == 'admin';

  factory CurrentUser.fromJson(Map<String, dynamic> j) {
    final access = (j['access'] as Map?) ?? const {};
    // Default "true" unless the backend explicitly opted out. Admins always.
    final editRaw = access['editScenes'];
    final canEdit =
        j['role'] == 'admin' || (editRaw == null ? true : editRaw == true);
    return CurrentUser(
      id: j['id'] as String,
      username: j['username'] as String,
      role: j['role'] as String,
      displayName: j['displayName'] as String?,
      canEditScenes: canEdit,
    );
  }
}

class HouseConfig {
  final String projectId;
  final String projectName;
  final List<Floor> floors;
  /// KNX/Lutron devices NOT placed in any room. Visible in Systemen and
  /// favourites, but not in the room navigator.
  final List<Device> globalDevices;
  final List<Device> cameras;
  final List<Device> intercoms;
  final List<Scene> scenes;
  final CurrentUser? me;
  /// Wandtablet idle / screensaver defaults uit house.json (`displayPanel`).
  final Map<String, dynamic>? displayPanelJson;

  const HouseConfig({
    required this.projectId,
    required this.projectName,
    required this.floors,
    this.globalDevices = const [],
    required this.cameras,
    required this.intercoms,
    required this.scenes,
    this.me,
    this.displayPanelJson,
  });

  factory HouseConfig.fromJson(Map<String, dynamic> j) {
    final users = (j['users'] as List?) ?? const [];
    final me = users.isNotEmpty
        ? CurrentUser.fromJson(users.first as Map<String, dynamic>)
        : null;
    final project = (j['project'] as Map?) ?? const {};
    return HouseConfig(
      projectId: (project['id'] as String?) ?? '',
      projectName: (project['name'] as String?) ?? '',
      floors: ((j['floors'] as List?) ?? const [])
          .map((f) => Floor.fromJson(f as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      globalDevices: ((j['devices'] as List?) ?? const [])
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList(),
      cameras: ((j['cameras'] as List?) ?? const [])
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList(),
      intercoms: ((j['intercoms'] as List?) ?? const [])
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList(),
      scenes: ((j['scenes'] as List?) ?? const [])
          .map((s) => Scene.fromJson(s as Map<String, dynamic>))
          .toList(),
      me: me,
      displayPanelJson: j['displayPanel'] as Map<String, dynamic>?,
    );
  }

  /// All room-bound + global automation devices (no cameras/intercoms).
  Iterable<Device> get allDevices sync* {
    for (final f in floors) {
      for (final r in f.rooms) {
        yield* r.devices;
      }
    }
    yield* globalDevices;
  }

  Device? deviceById(String id) {
    for (final d in intercoms) {
      if (d.id == id) return d;
    }
    for (final d in cameras) {
      if (d.id == id) return d;
    }
    for (final d in allDevices) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Returns the [Room] that contains [deviceId], or `null` for global /
  /// camera / intercom devices.
  Room? roomForDevice(String deviceId) {
    for (final f in floors) {
      for (final r in f.rooms) {
        for (final d in r.devices) {
          if (d.id == deviceId) return r;
        }
      }
    }
    return null;
  }

  /// Returns the [Floor] that contains [deviceId] (via its room), or `null`.
  Floor? floorForDevice(String deviceId) {
    for (final f in floors) {
      for (final r in f.rooms) {
        for (final d in r.devices) {
          if (d.id == deviceId) return f;
        }
      }
    }
    return null;
  }

  /// Human-readable placement, e.g. "Begane grond · Woonkamer", or "Diverse".
  String? locationLabelForDevice(String deviceId) {
    final room = roomForDevice(deviceId);
    if (room != null) {
      final floor = floorForDevice(deviceId);
      if (floor != null) return '${floor.name} · ${room.name}';
      return room.name;
    }
    if (globalDevices.any((d) => d.id == deviceId)) return 'Diverse';
    return null;
  }
}

/* --------------------------------------------------------------------- */
/*  Schedules                                                            */
/* --------------------------------------------------------------------- */

/// Seven booleans, Monday-first (ISO). `days[0]` = Monday … `days[6]` =
/// Sunday. Using a positional list (rather than a bitmask) keeps JSON
/// round-trips trivially readable.
typedef WeekdayMask = List<bool>;

/// Fallback Monday-to-Sunday mask (all true) — convenient default when
/// the user hasn't picked anything yet.
const WeekdayMask kAllDays = [true, true, true, true, true, true, true];

/// Guard used to bound astro triggers (e.g. "at sunset, but not before
/// 18:00" or "at sunrise, but not after sunrise+60min").
sealed class ScheduleGuard {
  const ScheduleGuard();

  Map<String, dynamic> toJson();

  static ScheduleGuard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    if (kind == 'time') return TimeGuard(time: raw['time'] as String);
    if (kind == 'astro') {
      return AstroGuard(
        event: AstroEvent.fromJson(raw['event'] as String),
        offsetMin: (raw['offsetMin'] as num?)?.toInt() ?? 0,
      );
    }
    return null;
  }
}

class TimeGuard extends ScheduleGuard {
  final String time; // "HH:MM"
  const TimeGuard({required this.time});
  @override
  Map<String, dynamic> toJson() => {'kind': 'time', 'time': time};
}

class AstroGuard extends ScheduleGuard {
  final AstroEvent event;
  final int offsetMin;
  const AstroGuard({required this.event, this.offsetMin = 0});
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'astro',
        'event': event.toJson(),
        if (offsetMin != 0) 'offsetMin': offsetMin,
      };
}

enum AstroEvent {
  sunrise,
  sunset;

  String toJson() => name;
  static AstroEvent fromJson(String s) =>
      s == 'sunrise' ? AstroEvent.sunrise : AstroEvent.sunset;
  String get label => this == AstroEvent.sunrise ? 'Zonsopkomst' : 'Zonsondergang';
}

sealed class ScheduleTrigger {
  const ScheduleTrigger();

  WeekdayMask get days;
  Map<String, dynamic> toJson();

  static ScheduleTrigger fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String;
    final days =
        (((j['days'] as List?) ?? kAllDays).map((e) => e == true).toList());
    while (days.length < 7) {
      days.add(false);
    }
    if (kind == 'time') {
      return TimeTrigger(
        time: j['time'] as String,
        days: days,
      );
    }
    return AstroTrigger(
      event: AstroEvent.fromJson(j['event'] as String),
      offsetMin: (j['offsetMin'] as num?)?.toInt() ?? 0,
      days: days,
      notBefore: ScheduleGuard.fromJson(j['notBefore']),
      notAfter: ScheduleGuard.fromJson(j['notAfter']),
    );
  }
}

class TimeTrigger extends ScheduleTrigger {
  final String time; // "HH:MM"
  @override
  final WeekdayMask days;
  const TimeTrigger({required this.time, required this.days});

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'time',
        'time': time,
        'days': days,
      };
}

class AstroTrigger extends ScheduleTrigger {
  final AstroEvent event;
  final int offsetMin;
  @override
  final WeekdayMask days;
  final ScheduleGuard? notBefore;
  final ScheduleGuard? notAfter;
  const AstroTrigger({
    required this.event,
    required this.days,
    this.offsetMin = 0,
    this.notBefore,
    this.notAfter,
  });

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'astro',
        'event': event.toJson(),
        if (offsetMin != 0) 'offsetMin': offsetMin,
        'days': days,
        if (notBefore != null) 'notBefore': notBefore!.toJson(),
        if (notAfter != null) 'notAfter': notAfter!.toJson(),
      };
}

sealed class ScheduleAction {
  const ScheduleAction();
  Map<String, dynamic> toJson();

  static ScheduleAction fromJson(Map<String, dynamic> j) {
    if (j['kind'] == 'scene') {
      return ScheduleSceneAction(sceneId: j['sceneId'] as String);
    }
    final acts = ((j['actions'] as List?) ?? const [])
        .map((a) => SceneAction.fromJson(a as Map<String, dynamic>))
        .toList();
    return ScheduleActionsAction(actions: acts);
  }
}

class ScheduleSceneAction extends ScheduleAction {
  final String sceneId;
  const ScheduleSceneAction({required this.sceneId});
  @override
  Map<String, dynamic> toJson() => {'kind': 'scene', 'sceneId': sceneId};
}

class ScheduleActionsAction extends ScheduleAction {
  final List<SceneAction> actions;
  const ScheduleActionsAction({required this.actions});
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'actions',
        'actions': actions.map((a) => a.toJson()).toList(),
      };
}

class Schedule {
  final String id;
  final String name;
  final bool enabled;
  final ScheduleTrigger trigger;
  final ScheduleAction action;
  final DateTime? lastRun;

  const Schedule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.trigger,
    required this.action,
    this.lastRun,
  });

  Schedule copyWith({
    String? name,
    bool? enabled,
    ScheduleTrigger? trigger,
    ScheduleAction? action,
  }) =>
      Schedule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        trigger: trigger ?? this.trigger,
        action: action ?? this.action,
        lastRun: lastRun,
      );

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        id: j['id'] as String,
        name: j['name'] as String,
        enabled: j['enabled'] == true,
        trigger: ScheduleTrigger.fromJson(
            (j['trigger'] as Map).cast<String, dynamic>()),
        action: ScheduleAction.fromJson(
            (j['action'] as Map).cast<String, dynamic>()),
        lastRun: j['lastRun'] is String
            ? DateTime.tryParse(j['lastRun'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'trigger': trigger.toJson(),
        'action': action.toJson(),
        if (lastRun != null) 'lastRun': lastRun!.toIso8601String(),
      };
}
