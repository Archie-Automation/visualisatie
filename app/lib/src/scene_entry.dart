// Friendly scene entries — one per device — that know how to convert
// themselves to the backend's raw `SceneAction` list and back.
//
// This is the bridge between the customer-friendly scene editor (which
// shows a "make this lamp dim to 40%" slider) and the backend, which
// only understands group-address telegrams.

import 'api.dart';
import 'media_api.dart';
import 'models.dart';
import 'fireplace_step_ranges.dart';

const _rgbwSceneChannelOrder = ['r', 'g', 'b', 'w', 'ww', 'cw'];

/// Seconds shown in the scene delay input (empty = direct).
String formatSceneDelayInput(int delayMs) {
  if (delayMs <= 0) return '';
  if (delayMs % 1000 == 0) return '${delayMs ~/ 1000}';
  final s = (delayMs / 1000).toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Parses user-entered seconds; empty/invalid negative → 0, else milliseconds.
int parseSceneDelayInput(String raw) {
  final s = raw.trim().replaceAll(',', '.');
  if (s.isEmpty) return 0;
  final v = double.tryParse(s);
  if (v == null || v < 0) return 0;
  return snapSceneDelayMs((v * 1000).round());
}

/// Fine step (seconds) up to [kSceneDelayHalfStepMaxSec], then whole seconds.
const kSceneDelayHalfStepMaxSec = 3.0;
const kSceneDelayFineStepSec = 0.5;
const kSceneDelayCoarseStepSec = 1.0;

/// Snap to allowed grid: 0.5 s steps up to 3 s, then whole seconds (4, 5, …).
int snapSceneDelayMs(int delayMs) {
  if (delayMs <= 0) return 0;
  final sec = delayMs / 1000.0;
  if (sec <= kSceneDelayHalfStepMaxSec) {
    final halfSteps = (sec * 2).round().clamp(1, 6);
    return halfSteps * 500;
  }
  final whole = (sec / 1.0).round();
  return (whole < 4 ? 4 : whole) * 1000;
}

/// One +/- step from [delayMs]; [direction] is `-1` or `1`.
int adjustSceneDelayMs(int delayMs, int direction) {
  if (direction == 0) return snapSceneDelayMs(delayMs);
  if (delayMs <= 0 && direction < 0) return 0;

  final sec = delayMs / 1000.0;
  double nextSec;
  if (direction > 0) {
    if (delayMs <= 0) {
      nextSec = kSceneDelayFineStepSec;
    } else if (delayMs < kSceneDelayHalfStepMaxSec * 1000) {
      nextSec = sec + kSceneDelayFineStepSec;
    } else if (delayMs == (kSceneDelayHalfStepMaxSec * 1000).round()) {
      nextSec = 4.0;
    } else {
      nextSec = sec + kSceneDelayCoarseStepSec;
    }
  } else {
    if (delayMs > kSceneDelayHalfStepMaxSec * 1000) {
      nextSec = delayMs <= 4000 ? kSceneDelayHalfStepMaxSec : sec - kSceneDelayCoarseStepSec;
    } else if (sec <= kSceneDelayFineStepSec) {
      return 0;
    } else {
      nextSec = sec - kSceneDelayFineStepSec;
    }
  }
  return snapSceneDelayMs((nextSec * 1000).round());
}

/// Add [deltaSeconds] (may be accelerated repeat) and snap to the grid.
int adjustSceneDelayMsByDelta(int delayMs, double deltaSeconds) {
  if (deltaSeconds == 0) return snapSceneDelayMs(delayMs);
  final next = delayMs + (deltaSeconds * 1000).round();
  if (next <= 0) return 0;
  return snapSceneDelayMs(next);
}

List<SceneAction> applyEntryDelay(List<SceneAction> actions, int delayMs) {
  if (delayMs <= 0 || actions.isEmpty) return actions;
  return [actions.first.copyWith(delayMs: delayMs), ...actions.skip(1)];
}

List<SceneMediaAction> applyMediaEntryDelay(
  List<SceneMediaAction> actions,
  int delayMs,
) {
  if (delayMs <= 0 || actions.isEmpty) return actions;
  final first = actions.first;
  return [
    SceneMediaAction(
      deviceId: first.deviceId,
      kind: first.kind,
      action: first.action,
      value: first.value,
      muted: first.muted,
      presetId: first.presetId,
      presetName: first.presetName,
      uri: first.uri,
      delayMs: delayMs,
    ),
    ...actions.skip(1),
  ];
}

String formatSceneDelay(int delayMs) {
  if (delayMs <= 0) return '';
  final value = delayMs % 1000 == 0
      ? '${delayMs ~/ 1000}'
      : (delayMs / 1000).toStringAsFixed(1).replaceAll('.', ',');
  return '$value secondes';
}

String _rgbwWwMode(Device d) {
  final raw = d.raw['rgbwWw'];
  if (raw is Map && raw['mode'] is String) return raw['mode'] as String;
  return 'channels';
}

int _rgbwWwPayloadBytes(Device d) {
  final raw = d.raw['rgbwWw'];
  if (raw is Map && raw['payloadBytes'] is num) {
    return (raw['payloadBytes'] as num).toInt().clamp(1, 14);
  }
  return 14;
}

/// Friendly per-device configuration inside a scene draft.
abstract class SceneEntry {
  Device get device;

  /// Wait time before this device's first command in the scene sequence.
  int get delayMs;

  SceneEntry withDelayMs(int delayMs);

  /// Convert this entry into zero or more low-level scene actions that
  /// the backend can execute.
  List<SceneAction> toActions();

  /// Return a new entry whose settings reflect the current live state
  /// of the device (reading from the bus cache).
  SceneEntry snapshot(BusState bus);

  /// Short human label summarising the configured state, e.g. "60%".
  String summary();
}

/* --------------------------- Concrete types --------------------------- */

class LightSwitchEntry extends SceneEntry {
  @override
  final Device device;
  bool on;
  @override
  final int delayMs;
  LightSwitchEntry({
    required this.device,
    required this.on,
    this.delayMs = 0,
  });

  @override
  LightSwitchEntry withDelayMs(int ms) =>
      LightSwitchEntry(device: device, on: on, delayMs: ms);

  @override
  List<SceneAction> toActions() {
    final ga = device.ga['switch'];
    if (ga == null) return const [];
    return applyEntryDelay(
      [SceneAction(ga: ga, role: SceneRole.switch_, value: on)],
      delayMs,
    );
  }

  @override
  LightSwitchEntry snapshot(BusState bus) {
    final ga = device.ga['switch_status'] ?? device.ga['switch'];
    final v = ga == null ? null : bus.values[ga];
    return LightSwitchEntry(
      device: device,
      on: v == true || v == 1,
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base = on ? 'Aan' : 'Uit';
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class LightDimmerEntry extends SceneEntry {
  @override
  final Device device;
  bool on;
  int percent;
  @override
  final int delayMs;

  LightDimmerEntry({
    required this.device,
    required this.on,
    required this.percent,
    this.delayMs = 0,
  });

  @override
  LightDimmerEntry withDelayMs(int ms) => LightDimmerEntry(
        device: device,
        on: on,
        percent: percent,
        delayMs: ms,
      );

  @override
  List<SceneAction> toActions() {
    final switchGa = device.ga['switch'];
    final dimGa = device.ga['dim_value'];
    final out = <SceneAction>[];
    if (!on) {
      if (switchGa != null) {
        out.add(SceneAction(ga: switchGa, role: SceneRole.switch_, value: false));
      }
      return applyEntryDelay(out, delayMs);
    }
    if (switchGa != null) {
      out.add(SceneAction(ga: switchGa, role: SceneRole.switch_, value: true));
    }
    if (dimGa != null) {
      out.add(SceneAction(
        ga: dimGa,
        role: SceneRole.dimValue,
        value: percent,
        delayMs: switchGa != null ? 150 : null,
      ));
    }
    return applyEntryDelay(out, delayMs);
  }

  @override
  LightDimmerEntry snapshot(BusState bus) {
    final switchGa = device.ga['switch_status'] ?? device.ga['switch'];
    final dimGa = device.ga['dim_status'] ?? device.ga['dim_value'];
    final onV = switchGa == null ? null : bus.values[switchGa];
    final dimV = dimGa == null ? null : bus.values[dimGa];
    final on = onV == true || onV == 1;
    final pct = dimV is num ? dimV.toInt().clamp(0, 100) : (on ? 100 : 0);
    return LightDimmerEntry(
      device: device,
      on: on,
      percent: pct,
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base = on ? '$percent%' : 'Uit';
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class ShadingEntry extends SceneEntry {
  @override
  final Device device;
  int position;
  int? slats;
  @override
  final int delayMs;

  ShadingEntry({
    required this.device,
    required this.position,
    this.slats,
    this.delayMs = 0,
  });

  @override
  ShadingEntry withDelayMs(int ms) => ShadingEntry(
        device: device,
        position: position,
        slats: slats,
        delayMs: ms,
      );

  @override
  List<SceneAction> toActions() {
    final out = <SceneAction>[];
    final posGa = device.ga['position'];
    if (posGa != null) {
      out.add(SceneAction(
          ga: posGa, role: SceneRole.position, value: position));
    }
    final slatGa = device.ga['slat'];
    if (slats != null && slatGa != null) {
      out.add(SceneAction(
        ga: slatGa,
        role: SceneRole.position,
        value: slats!,
        delayMs: 200,
      ));
    }
    return applyEntryDelay(out, delayMs);
  }

  @override
  ShadingEntry snapshot(BusState bus) {
    final posGa = device.ga['position_status'] ?? device.ga['position'];
    final slatGa = device.ga['slat_status'] ?? device.ga['slat'];
    final p = posGa == null ? null : bus.values[posGa];
    final s = slatGa == null ? null : bus.values[slatGa];
    return ShadingEntry(
      device: device,
      position: p is num ? p.toInt().clamp(0, 100) : position,
      slats: slatGa == null
          ? null
          : (s is num ? s.toInt().clamp(0, 100) : (slats ?? 50)),
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base =
        slats != null ? '$position% · lam. $slats%' : '$position%';
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class ClimateEntry extends SceneEntry {
  @override
  final Device device;
  double setpoint;
  @override
  final int delayMs;
  ClimateEntry({
    required this.device,
    required this.setpoint,
    this.delayMs = 0,
  });

  @override
  ClimateEntry withDelayMs(int ms) =>
      ClimateEntry(device: device, setpoint: setpoint, delayMs: ms);

  @override
  List<SceneAction> toActions() {
    final ga = device.ga['setpoint'];
    if (ga == null) return const [];
    return applyEntryDelay(
      [SceneAction(ga: ga, role: SceneRole.setpoint, value: setpoint)],
      delayMs,
    );
  }

  @override
  ClimateEntry snapshot(BusState bus) {
    final ga = device.ga['setpoint_status'] ?? device.ga['setpoint'];
    final v = ga == null ? null : bus.values[ga];
    return ClimateEntry(
      device: device,
      setpoint: v is num ? v.toDouble() : setpoint,
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base = '${setpoint.toStringAsFixed(1)} °C';
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class FireplaceEntry extends SceneEntry {
  @override
  final Device device;
  bool on;
  int flame;
  @override
  final int delayMs;
  FireplaceEntry({
    required this.device,
    required this.on,
    required this.flame,
    this.delayMs = 0,
  });

  @override
  FireplaceEntry withDelayMs(int ms) => FireplaceEntry(
        device: device,
        on: on,
        flame: flame,
        delayMs: ms,
      );

  Map<String, dynamic> get _cfg =>
      (device.raw['fireplace'] as Map).cast<String, dynamic>();

  List<Map<String, dynamic>>? get _stepRanges =>
      parseFireplaceStepRanges(_cfg['flame'] as Map<String, dynamic>?);

  bool get _usesPctStepBands =>
      _stepRanges != null && _stepRanges!.length >= 2;

  int? get steps {
    final f = _cfg['flame'] as Map?;
    if (_usesPctStepBands) return _stepRanges!.length;
    return (f?['steps'] as num?)?.toInt();
  }

  bool get _isDiscrete =>
      _cfg['controlMode'] == 'discrete' && _cfg['discreteLevel'] is Map;

  Map<String, dynamic>? get _discreteLevel =>
      (_cfg['discreteLevel'] as Map?)?.cast<String, dynamic>();

  String? _discretePulseGa(String key) {
    final pulse = _discreteLevel?[key];
    if (pulse is Map) return pulse['ga'] as String?;
    return null;
  }

  int? _discretePulseMs(String key) {
    final pulse = _discreteLevel?[key];
    if (pulse is Map) return (pulse['pulseMs'] as num?)?.toInt();
    return null;
  }

  @override
  List<SceneAction> toActions() {
    final out = <SceneAction>[];
    if (_isDiscrete) {
      final key = on ? 'on' : 'off';
      final ga = _discretePulseGa(key);
      if (ga != null) {
        out.add(SceneAction(
          ga: ga,
          role: SceneRole.pulse,
          value: true,
          pulseMs: _discretePulseMs(key),
        ));
      }
      return applyEntryDelay(out, delayMs);
    }
    final onGa = (_cfg['onOff'] as Map)['ga'] as String?;
    if (onGa != null) {
      out.add(SceneAction(ga: onGa, role: SceneRole.switch_, value: on));
    }
    if (on) {
      final flameGa = (_cfg['flame'] as Map?)?['ga'] as String?;
      if (flameGa != null) {
        final sr = _stepRanges;
        final int busVal;
        final SceneRole role;
        if (sr != null && sr.length >= 2) {
          busVal = writePercentForFlameStep(sr, flame.clamp(1, sr.length));
          role = SceneRole.percent;
        } else if (steps != null) {
          busVal = flame;
          role = SceneRole.byte;
        } else {
          busVal = flame;
          role = SceneRole.percent;
        }
        out.add(SceneAction(
          ga: flameGa,
          role: role,
          value: busVal,
          delayMs: onGa != null ? 200 : null,
        ));
      }
    }
    return applyEntryDelay(out, delayMs);
  }

  @override
  FireplaceEntry snapshot(BusState bus) {
    final onGa = ((_cfg['onOff'] as Map)['statusGa'] as String?) ??
        ((_cfg['onOff'] as Map)['ga'] as String?);
    final flameGa = ((_cfg['flame'] as Map?)?['statusGa'] as String?) ??
        ((_cfg['flame'] as Map?)?['ga'] as String?);
    final onV = onGa == null ? null : bus.values[onGa];
    final flameV = flameGa == null ? null : bus.values[flameGa];
    final sr = _stepRanges;
    var fl = flameV is num ? flameV.toInt() : flame;
    if (sr != null && sr.length >= 2 && flameV is num) {
      fl = busPercentToFlameStep(sr, fl.clamp(0, 100));
    }
    return FireplaceEntry(
      device: device,
      on: onV == true || onV == 1,
      flame: fl,
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    String base;
    if (!on) {
      base = 'Uit';
    } else {
      final sr = _stepRanges;
      if (sr != null && sr.length >= 2) {
        final w = writePercentForFlameStep(sr, flame.clamp(1, sr.length));
        base = 'Stand $flame ($w%)';
      } else if (steps != null) {
        base = 'Stand $flame';
      } else {
        final ld = (_cfg['flame'] as Map?)?['levelDisplay'] as String?;
        if (ld == 'volt_10') {
          base = '${(flame * 0.1).toStringAsFixed(1)} V';
        } else if (ld == 'volt_3') {
          base = '${(flame * 0.03).toStringAsFixed(2)} V';
        } else {
          base = '$flame%';
        }
      }
    }
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class AcEntry extends SceneEntry {
  @override
  final Device device;
  bool on;
  double setpoint;
  int? mode;
  int? fanSpeed;
  @override
  final int delayMs;
  AcEntry({
    required this.device,
    required this.on,
    required this.setpoint,
    this.mode,
    this.fanSpeed,
    this.delayMs = 0,
  });

  @override
  AcEntry withDelayMs(int ms) => AcEntry(
        device: device,
        on: on,
        setpoint: setpoint,
        mode: mode,
        fanSpeed: fanSpeed,
        delayMs: ms,
      );

  Map<String, dynamic> get _cfg =>
      (device.raw['ac'] as Map).cast<String, dynamic>();

  @override
  List<SceneAction> toActions() {
    final out = <SceneAction>[];
    final onGa = (_cfg['onOff'] as Map)['ga'] as String?;
    if (onGa != null) {
      out.add(SceneAction(ga: onGa, role: SceneRole.switch_, value: on));
    }
    if (!on) return applyEntryDelay(out, delayMs);
    final spGa = (_cfg['setpoint'] as Map?)?['ga'] as String?;
    if (spGa != null) {
      out.add(SceneAction(
          ga: spGa, role: SceneRole.setpoint, value: setpoint, delayMs: 150));
    }
    final modeGa = (_cfg['mode'] as Map?)?['ga'] as String?;
    if (mode != null && modeGa != null) {
      out.add(SceneAction(
          ga: modeGa, role: SceneRole.byte, value: mode!, delayMs: 250));
    }
    final fanGa = (_cfg['fanSpeed'] as Map?)?['ga'] as String?;
    if (fanSpeed != null && fanGa != null) {
      out.add(SceneAction(
          ga: fanGa, role: SceneRole.byte, value: fanSpeed!, delayMs: 350));
    }
    return applyEntryDelay(out, delayMs);
  }

  @override
  AcEntry snapshot(BusState bus) {
    String? s(String key, String field) =>
        (_cfg[key] as Map?)?['statusGa'] as String? ??
        (_cfg[key] as Map?)?[field] as String?;
    final onV = bus.values[s('onOff', 'ga')];
    final spV = bus.values[s('setpoint', 'ga')];
    final modeV = bus.values[s('mode', 'ga')];
    final fanV = bus.values[s('fanSpeed', 'ga')];
    return AcEntry(
      device: device,
      on: onV == true || onV == 1,
      setpoint: spV is num ? spV.toDouble() : setpoint,
      mode: modeV is num ? modeV.toInt() : mode,
      fanSpeed: fanV is num ? fanV.toInt() : fanSpeed,
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base = on ? '${setpoint.toStringAsFixed(1)} °C' : 'Uit';
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class FanEntry extends SceneEntry {
  @override
  final Device device;
  bool on;
  int speed;
  bool? oscillate;
  @override
  final int delayMs;

  FanEntry({
    required this.device,
    required this.on,
    required this.speed,
    this.oscillate,
    this.delayMs = 0,
  });

  @override
  FanEntry withDelayMs(int ms) => FanEntry(
        device: device,
        on: on,
        speed: speed,
        oscillate: oscillate,
        delayMs: ms,
      );

  Map<String, dynamic> get _cfg =>
      (device.raw['fan'] as Map).cast<String, dynamic>();
  int? get steps => ((_cfg['speed'] as Map?)?['steps'] as num?)?.toInt();

  @override
  List<SceneAction> toActions() {
    final out = <SceneAction>[];
    final onGa = (_cfg['onOff'] as Map)['ga'] as String?;
    if (onGa != null) {
      out.add(SceneAction(ga: onGa, role: SceneRole.switch_, value: on));
    }
    if (!on) return applyEntryDelay(out, delayMs);
    final spGa = (_cfg['speed'] as Map?)?['ga'] as String?;
    if (spGa != null) {
      out.add(SceneAction(
        ga: spGa,
        role: steps != null ? SceneRole.byte : SceneRole.percent,
        value: speed,
        delayMs: onGa != null ? 150 : null,
      ));
    }
    final osGa = (_cfg['oscillate'] as Map?)?['ga'] as String?;
    if (oscillate != null && osGa != null) {
      out.add(SceneAction(
          ga: osGa, role: SceneRole.switch_, value: oscillate!, delayMs: 250));
    }
    return applyEntryDelay(out, delayMs);
  }

  @override
  FanEntry snapshot(BusState bus) {
    final onGa = (_cfg['onOff'] as Map)['statusGa'] as String? ??
        (_cfg['onOff'] as Map)['ga'] as String?;
    final spGa = (_cfg['speed'] as Map?)?['statusGa'] as String? ??
        (_cfg['speed'] as Map?)?['ga'] as String?;
    final osGa = (_cfg['oscillate'] as Map?)?['statusGa'] as String? ??
        (_cfg['oscillate'] as Map?)?['ga'] as String?;
    final onV = onGa == null ? null : bus.values[onGa];
    final spV = spGa == null ? null : bus.values[spGa];
    final osV = osGa == null ? null : bus.values[osGa];
    return FanEntry(
      device: device,
      on: onV == true || onV == 1,
      speed: spV is num ? spV.toInt() : speed,
      oscillate: osV == null
          ? oscillate
          : (osV == true || osV == 1),
      delayMs: delayMs,
    );
  }

  @override
  String summary() {
    final base = !on ? 'Uit' : (steps != null ? 'Stand $speed' : '$speed%');
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class RgbwWwEntry extends SceneEntry {
  RgbwWwEntry({
    required this.device,
    required this.mode,
    Map<String, int>? channels,
    List<int>? composite,
    this.red = 0,
    this.green = 0,
    this.blue = 0,
    this.delayMs = 0,
  })  : channels = Map<String, int>.from(channels ?? const {}),
        composite = List<int>.from(composite ?? const []);

  @override
  final Device device;
  final String mode;
  final Map<String, int> channels;
  final List<int> composite;
  final int red;
  final int green;
  final int blue;
  @override
  final int delayMs;

  @override
  RgbwWwEntry withDelayMs(int ms) => RgbwWwEntry(
        device: device,
        mode: mode,
        channels: channels,
        composite: composite,
        red: red,
        green: green,
        blue: blue,
        delayMs: ms,
      );

  @override
  List<SceneAction> toActions() {
    final out = <SceneAction>[];
    if (mode == 'channels') {
      for (final k in _rgbwSceneChannelOrder) {
        final ga = device.ga[k];
        if (ga == null) continue;
        final v = channels[k] ?? 0;
        out.add(SceneAction(ga: ga, role: SceneRole.byte, value: v.clamp(0, 255)));
      }
      return applyEntryDelay(out, delayMs);
    }
    if (mode == 'composite') {
      final ga = device.ga['composite'];
      if (ga != null && composite.isNotEmpty) {
        out.add(SceneAction(ga: ga, role: SceneRole.rawBytes, value: composite));
      }
      return applyEntryDelay(out, delayMs);
    }
    if (mode == 'rgb232') {
      final ga = device.ga['rgb232'];
      if (ga != null) {
        out.add(SceneAction(
          ga: ga,
          role: SceneRole.rgb232,
          value: [red.clamp(0, 255), green.clamp(0, 255), blue.clamp(0, 255)],
        ));
      }
      return applyEntryDelay(out, delayMs);
    }
    return out;
  }

  @override
  RgbwWwEntry snapshot(BusState bus) {
    final m = _rgbwWwMode(device);
    if (m == 'channels') {
      final ch = <String, int>{};
      for (final k in _rgbwSceneChannelOrder) {
        final ga = device.ga[k];
        if (ga == null) continue;
        final v = bus.values[ga];
        ch[k] = v is num ? v.toInt().clamp(0, 255) : 0;
      }
      return RgbwWwEntry(device: device, mode: m, channels: ch, delayMs: delayMs);
    }
    if (m == 'composite') {
      final n = _rgbwWwPayloadBytes(device);
      return RgbwWwEntry(
        device: device,
        mode: m,
        composite: List<int>.filled(n, 0),
        delayMs: delayMs,
      );
    }
    final ga = device.ga['rgb232'];
    if (ga != null) {
      final v = bus.values[ga];
      if (v is Map) {
        return RgbwWwEntry(
          device: device,
          mode: m,
          red: (v['red'] as num?)?.toInt() ?? 0,
          green: (v['green'] as num?)?.toInt() ?? 0,
          blue: (v['blue'] as num?)?.toInt() ?? 0,
          delayMs: delayMs,
        );
      }
    }
    return RgbwWwEntry(device: device, mode: m, delayMs: delayMs);
  }

  @override
  String summary() {
    String base;
    if (mode == 'channels') {
      if (channels.isEmpty) {
        base = '—';
      } else {
        base = channels.entries
            .map((e) => '${e.key.toUpperCase()}:${e.value}')
            .take(4)
            .join(' ');
      }
    } else if (mode == 'composite') {
      base = '${composite.length} bytes';
    } else {
      base = 'RGB $red/$green/$blue';
    }
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

class MediaEntry extends SceneEntry {
  MediaEntry({
    required this.device,
    this.transport,
    this.volume,
    this.muted,
    this.presetId,
    this.presetName,
    this.presetUri,
    this.setVolume = false,
    this.delayMs = 0,
  });

  @override
  final Device device;

  /// `play`, `pause`, or `stop`. Ignored when [presetId] is set.
  String? transport;
  int? volume;
  bool? muted;
  String? presetId;
  String? presetName;
  String? presetUri;
  bool setVolume;
  @override
  final int delayMs;

  @override
  MediaEntry withDelayMs(int ms) => copyWith(delayMs: ms);

  MediaEntry copyWith({
    String? transport,
    int? volume,
    bool? muted,
    String? presetId,
    String? presetName,
    String? presetUri,
    bool? setVolume,
    int? delayMs,
    bool clearPreset = false,
    bool clearTransport = false,
    bool clearVolume = false,
    bool clearMuted = false,
  }) =>
      MediaEntry(
        device: device,
        transport: clearTransport ? null : (transport ?? this.transport),
        volume: clearVolume ? null : (volume ?? this.volume),
        muted: clearMuted ? null : (muted ?? this.muted),
        presetId: clearPreset ? null : (presetId ?? this.presetId),
        presetName: clearPreset ? null : (presetName ?? this.presetName),
        presetUri: clearPreset ? null : (presetUri ?? this.presetUri),
        setVolume: setVolume ?? this.setVolume,
        delayMs: delayMs ?? this.delayMs,
      );

  @override
  List<SceneAction> toActions() => const [];

  List<SceneMediaAction> toMediaActions() {
    final out = <SceneMediaAction>[];
    if (setVolume && volume != null) {
      out.add(SceneMediaAction.volume(device.id, volume!.clamp(0, 100)));
    }
    if (muted != null) {
      out.add(SceneMediaAction.mute(device.id, muted!));
    }
    if (presetId != null && presetId!.isNotEmpty) {
      out.add(SceneMediaAction.preset(
        device.id,
        presetId!,
        name: presetName,
        uri: presetUri,
      ));
    } else if (transport != null && transport!.isNotEmpty) {
      out.add(SceneMediaAction.transport(device.id, transport!));
    }
    return applyMediaEntryDelay(out, delayMs);
  }

  @override
  MediaEntry snapshot(BusState bus) => this;

  MediaEntry snapshotMedia(MediaState? state) {
    if (state == null) return this;
    final t = switch (state.transport) {
      MediaTransport.playing || MediaTransport.buffering => 'play',
      MediaTransport.paused => 'pause',
      MediaTransport.stopped => 'stop',
    };
    return copyWith(
      transport: t,
      volume: state.volume,
      setVolume: state.volume != null,
      muted: state.muted,
    );
  }

  @override
  String summary() {
    final parts = <String>[];
    if (presetName != null && presetName!.isNotEmpty) {
      parts.add('Favoriet: $presetName');
    } else if (transport != null) {
      parts.add(switch (transport) {
        'play' => 'Afspelen',
        'pause' => 'Pauzeren',
        'stop' => 'Stoppen',
        _ => transport!,
      });
    }
    if (setVolume && volume != null) parts.add('Vol $volume%');
    if (muted == true) parts.add('Gedempt');
    if (parts.isEmpty) {
      final d = formatSceneDelay(delayMs);
      return d.isEmpty ? 'Geen actie' : 'Na $d';
    }
    final base = parts.join(' · ');
    final d = formatSceneDelay(delayMs);
    return d.isEmpty ? base : '$base · na $d';
  }
}

int entryDelayFromMine(SceneEntry entry, List<SceneAction> mine) {
  final emitted = entry.withDelayMs(0).toActions();
  if (emitted.isEmpty) return 0;
  final first = emitted.first;
  for (final a in mine) {
    if (a.ga == first.ga && a.role == first.role) {
      return a.delayMs ?? 0;
    }
  }
  return mine.isNotEmpty ? (mine.first.delayMs ?? 0) : 0;
}

MediaEntry? parseMediaEntry(Device device, List<SceneMediaAction> actions) {
  if (!device.type.isMedia || actions.isEmpty) return null;
  String? transport;
  int? volume;
  bool? muted;
  String? presetId;
  String? presetName;
  String? presetUri;
  var setVolume = false;
  for (final a in actions) {
    if (a.deviceId != device.id) continue;
    switch (a.kind) {
      case 'transport':
        transport = a.action;
      case 'volume':
        volume = a.value;
        setVolume = true;
      case 'mute':
        muted = a.muted;
      case 'preset':
        presetId = a.presetId;
        presetName = a.presetName;
        presetUri = a.uri;
    }
  }
  return MediaEntry(
    device: device,
    transport: transport,
    volume: volume,
    muted: muted,
    presetId: presetId,
    presetName: presetName,
    presetUri: presetUri,
    setVolume: setVolume,
    delayMs: actions.isNotEmpty ? (actions.first.delayMs ?? 0) : 0,
  );
}

/* ---------------------- Factory / reverse parsing --------------------- */

extension SceneEntryFactory on Device {
  /// Build a default entry (all "off" / neutral values) for this device.
  SceneEntry? defaultSceneEntry() {
    switch (type) {
      case DeviceType.lightSwitch:
        return LightSwitchEntry(device: this, on: true);
      case DeviceType.lightDimmer:
        return LightDimmerEntry(device: this, on: true, percent: 60);
      case DeviceType.shading:
        return ShadingEntry(
          device: this,
          position: 100,
          slats: ga['slat'] != null ? 50 : null,
        );
      case DeviceType.positionActuator:
        return ShadingEntry(
          device: this,
          position: 100,
          slats: ga['slat'] != null ? 50 : null,
        );
      case DeviceType.climate:
        return ClimateEntry(device: this, setpoint: 21.0);
      case DeviceType.fireplace:
        final fp = raw['fireplace'] as Map?;
        final sr = parseFireplaceStepRanges(fp?['flame'] as Map<String, dynamic>?);
        final midStep = sr == null || sr.isEmpty
            ? 60
            : (sr.length <= 2 ? 1 : (sr.length / 2).ceil());
        return FireplaceEntry(device: this, on: true, flame: midStep);
      case DeviceType.ac:
        return AcEntry(device: this, on: true, setpoint: 22.0);
      case DeviceType.fan:
        return FanEntry(device: this, on: true, speed: 50);
      case DeviceType.rgbwWw:
        final mode = _rgbwWwMode(this);
        if (mode == 'channels') {
          final ch = <String, int>{};
          for (final k in _rgbwSceneChannelOrder) {
            if (ga[k] != null) ch[k] = 0;
          }
          return RgbwWwEntry(device: this, mode: mode, channels: ch);
        }
        if (mode == 'composite') {
          final n = _rgbwWwPayloadBytes(this);
          return RgbwWwEntry(
            device: this,
            mode: mode,
            composite: List<int>.filled(n, 0),
          );
        }
        return RgbwWwEntry(device: this, mode: mode);
      case DeviceType.mediaSonos:
      case DeviceType.mediaBluesound:
        return MediaEntry(device: this, transport: 'play', volume: 25, setVolume: true);
      case DeviceType.camera:
      case DeviceType.intercom:
      case DeviceType.universal:
      case DeviceType.wtw:
      case DeviceType.melding:
      case DeviceType.lutronHomeworks:
      case DeviceType.unknown:
        return null;
    }
  }
}

/// Tries to reconstruct a [SceneEntry] from raw [SceneAction]s that
/// reference GAs owned by [device]. Returns null if the device doesn't
/// support scene-editing.
SceneEntry? tryParseEntry(Device device, List<SceneAction> actions) {
  SceneAction? pick(String? ga) {
    if (ga == null) return null;
    for (final a in actions) {
      if (a.ga == ga) return a;
    }
    return null;
  }

  double? asNum(SceneAction? a) {
    final v = a?.value;
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    return null;
  }

  bool? asBool(SceneAction? a) {
    final v = a?.value;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return null;
  }

  switch (device.type) {
    case DeviceType.lightSwitch:
      final sw = pick(device.ga['switch_status'] ?? device.ga['switch']);
      if (sw == null) return null;
      return LightSwitchEntry(device: device, on: asBool(sw) ?? true);
    case DeviceType.lightDimmer:
      final sw = pick(device.ga['switch_status'] ?? device.ga['switch']);
      final dim = pick(device.ga['dim_status'] ?? device.ga['dim_value']);
      if (sw == null && dim == null) return null;
      final on = asBool(sw) ?? false;
      final pct = (asNum(dim) ?? (on ? 100 : 0)).round().clamp(0, 100);
      return LightDimmerEntry(device: device, on: on, percent: pct);
    case DeviceType.shading:
    case DeviceType.positionActuator:
      final pos = pick(device.ga['position']);
      final slat = pick(device.ga['slat']);
      if (pos == null && slat == null) return null;
      return ShadingEntry(
        device: device,
        position: (asNum(pos) ?? 0).round().clamp(0, 100),
        slats: slat == null ? null : (asNum(slat) ?? 0).round().clamp(0, 100),
      );
    case DeviceType.climate:
      final sp = pick(device.ga['setpoint']);
      if (sp == null) return null;
      return ClimateEntry(device: device, setpoint: asNum(sp) ?? 21.0);
    case DeviceType.fireplace:
      final cfg = (device.raw['fireplace'] as Map?)?.cast<String, dynamic>();
      final discrete =
          cfg?['controlMode'] == 'discrete' && cfg?['discreteLevel'] is Map;
      if (discrete) {
        final dl = (cfg!['discreteLevel'] as Map).cast<String, dynamic>();
        String? gaFor(String key) => (dl[key] as Map?)?['ga'] as String?;
        final offGa = gaFor('off');
        final onGa = gaFor('on');
        final offA = offGa == null ? null : pick(offGa);
        final onA = onGa == null ? null : pick(onGa);
        if (offA != null &&
            (offA.role == SceneRole.pulse || offA.role == SceneRole.switch_)) {
          return FireplaceEntry(device: device, on: false, flame: 0);
        }
        if (onA != null &&
            (onA.role == SceneRole.pulse || onA.role == SceneRole.switch_)) {
          return FireplaceEntry(device: device, on: true, flame: 0);
        }
        final legacyOnGa = (cfg['onOff'] as Map?)?['ga'] as String?;
        final legacyA = legacyOnGa == null ? null : pick(legacyOnGa);
        if (legacyA != null && legacyA.role == SceneRole.switch_) {
          return FireplaceEntry(
            device: device,
            on: asBool(legacyA) ?? false,
            flame: 0,
          );
        }
        return null;
      }
      final onA = pick((cfg?['onOff'] as Map?)?['ga'] as String?);
      final flA = pick((cfg?['flame'] as Map?)?['ga'] as String?);
      if (onA == null && flA == null) return null;
      final sr = parseFireplaceStepRanges(cfg?['flame'] as Map<String, dynamic>?);
      var fl = (asNum(flA) ?? 60).round();
      if (sr != null && sr.length >= 2) {
        fl = busPercentToFlameStep(sr, fl.clamp(0, 100));
      }
      return FireplaceEntry(
        device: device,
        on: asBool(onA) ?? true,
        flame: fl,
      );
    case DeviceType.ac:
      final cfg = (device.raw['ac'] as Map?)?.cast<String, dynamic>();
      final onA = pick((cfg?['onOff'] as Map?)?['ga'] as String?);
      final spA = pick((cfg?['setpoint'] as Map?)?['ga'] as String?);
      final mdA = pick((cfg?['mode'] as Map?)?['ga'] as String?);
      final fnA = pick((cfg?['fanSpeed'] as Map?)?['ga'] as String?);
      if (onA == null && spA == null && mdA == null && fnA == null) {
        return null;
      }
      return AcEntry(
        device: device,
        on: asBool(onA) ?? true,
        setpoint: asNum(spA) ?? 22.0,
        mode: mdA == null ? null : asNum(mdA)?.toInt(),
        fanSpeed: fnA == null ? null : asNum(fnA)?.toInt(),
      );
    case DeviceType.fan:
      final cfg = (device.raw['fan'] as Map?)?.cast<String, dynamic>();
      final onA = pick((cfg?['onOff'] as Map?)?['ga'] as String?);
      final spA = pick((cfg?['speed'] as Map?)?['ga'] as String?);
      final osA = pick((cfg?['oscillate'] as Map?)?['ga'] as String?);
      if (onA == null && spA == null && osA == null) return null;
      return FanEntry(
        device: device,
        on: asBool(onA) ?? true,
        speed: (asNum(spA) ?? 50).round(),
        oscillate: osA == null ? null : asBool(osA),
      );
    case DeviceType.rgbwWw:
      final mode = _rgbwWwMode(device);
      SceneAction? pickByte(String? ga_) {
        if (ga_ == null) return null;
        for (final a in actions) {
          if (a.ga == ga_ && a.role == SceneRole.byte) return a;
        }
        return null;
      }

      if (mode == 'channels') {
        final ch = <String, int>{};
        var any = false;
        for (final k in _rgbwSceneChannelOrder) {
          final ga = device.ga[k];
          final a = pickByte(ga);
          if (a != null) {
            any = true;
            final v = a.value;
            ch[k] = v is num ? v.toInt().clamp(0, 255) : 0;
          }
        }
        if (!any) return null;
        return RgbwWwEntry(device: device, mode: mode, channels: ch);
      }
      if (mode == 'composite') {
        final cga = device.ga['composite'];
        if (cga == null) return null;
        for (final a in actions) {
          if (a.ga == cga && a.role == SceneRole.rawBytes) {
            final v = a.value;
            if (v is List) {
              final bytes =
                  v.map((e) => (e as num).toInt().clamp(0, 255)).toList();
              return RgbwWwEntry(device: device, mode: mode, composite: bytes);
            }
          }
        }
        return null;
      }
      final ga232 = device.ga['rgb232'];
      if (ga232 == null) return null;
      for (final a in actions) {
        if (a.ga == ga232 && a.role == SceneRole.rgb232) {
          final v = a.value;
          if (v is List && v.length >= 3) {
            return RgbwWwEntry(
              device: device,
              mode: mode,
              red: (v[0] as num).toInt().clamp(0, 255),
              green: (v[1] as num).toInt().clamp(0, 255),
              blue: (v[2] as num).toInt().clamp(0, 255),
            );
          }
          if (v is Map) {
            return RgbwWwEntry(
              device: device,
              mode: mode,
              red: ((v['red'] as num?) ?? 0).toInt().clamp(0, 255),
              green: ((v['green'] as num?) ?? 0).toInt().clamp(0, 255),
              blue: ((v['blue'] as num?) ?? 0).toInt().clamp(0, 255),
            );
          }
        }
      }
      return null;
    default:
      return null;
  }
}

/// Collects every GA owned by [device] — used to decide which raw
/// scene-actions to consume when parsing existing scenes.
Set<String> deviceGroupAddresses(Device device) {
  final out = <String>{};
  out.addAll(device.ga.values);
  final raw = device.raw;
  void walk(Object? v) {
    if (v is Map) {
      v.forEach((k, val) {
        if (k == 'ga' || k == 'statusGa') {
          if (val is String) out.add(val);
        } else {
          walk(val);
        }
      });
    } else if (v is List) {
      for (final x in v) {
        walk(x);
      }
    }
  }

  walk(raw['fireplace']);
  walk(raw['ac']);
  walk(raw['fan']);
  walk(raw['wtw']);
  walk(raw['melding']);
  return out;
}

/* ------------------------------ Draft --------------------------------- */

/// A work-in-progress scene whose state is friendly (per-device) rather
/// than raw GA-level. Use [SceneDraft.fromScene] to parse an existing
/// scene, edit the entries, then [toScene] to emit the backend payload.
class SceneDraft {
  String name;
  String? icon;
  final List<SceneEntry> entries;
  /// KNX actions that couldn't be matched to any device; preserved verbatim.
  final List<SceneAction> extras;
  /// Media actions that couldn't be matched to any device.
  final List<SceneMediaAction> mediaExtras;

  SceneDraft({
    required this.name,
    required this.entries,
    this.icon,
    this.extras = const [],
    this.mediaExtras = const [],
  });

  static SceneDraft fromScene(Scene s, HouseConfig cfg) {
    final devices = cfg.allDevices.toList();
    final remaining = [...s.actions];
    final entries = <SceneEntry>[];

    for (final d in devices) {
      final gas = deviceGroupAddresses(d);
      final mine = remaining.where((a) => gas.contains(a.ga)).toList();
      if (mine.isEmpty) continue;
      final entry = tryParseEntry(d, mine);
      if (entry == null) continue;
      entries.add(entry.withDelayMs(entryDelayFromMine(entry, mine)));
      remaining.removeWhere((a) => gas.contains(a.ga));
    }

    final mediaByDevice = <String, List<SceneMediaAction>>{};
    for (final a in s.mediaActions) {
      mediaByDevice.putIfAbsent(a.deviceId, () => []).add(a);
    }
    for (final d in devices) {
      if (!d.type.isMedia) continue;
      if (entries.any((e) => e.device.id == d.id)) continue;
      final mine = mediaByDevice.remove(d.id);
      if (mine == null || mine.isEmpty) continue;
      final entry = parseMediaEntry(d, mine);
      if (entry == null) continue;
      entries.add(entry);
    }
    final mediaExtras = mediaByDevice.values.expand((x) => x).toList();

    return SceneDraft(
      name: s.name,
      icon: s.icon,
      entries: entries,
      extras: remaining,
      mediaExtras: mediaExtras,
    );
  }

  Scene toScene(String id) {
    final actions = <SceneAction>[];
    final mediaActions = <SceneMediaAction>[];
    for (final e in entries) {
      actions.addAll(e.toActions());
      if (e is MediaEntry) mediaActions.addAll(e.toMediaActions());
    }
    actions.addAll(extras);
    mediaActions.addAll(mediaExtras);
    return Scene(
      id: id,
      name: name,
      icon: icon,
      actions: actions,
      mediaActions: mediaActions,
    );
  }

  SceneDraft copy() => SceneDraft(
        name: name,
        icon: icon,
        entries: [...entries],
        extras: [...extras],
        mediaExtras: [...mediaExtras],
      );
}
