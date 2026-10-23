import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../media_api.dart';
import '../models.dart';
import '../satel_api.dart';
import '../wtw_logic.dart';
import 'demo_house.dart';

/// Beweging van zonwering in de demo. Geannuleerd bij uitloggen.
final _moves = <String, Timer>{};

void demoDisposeMotion() {
  for (final timer in _moves.values) {
    timer.cancel();
  }
  _moves.clear();
}

void registerDemoHooks() {
  demoSessionHook = (ref, {required active}) {
    demoDisposeMotion();
    if (!active) {
      ref.read(mediaStateProvider.notifier).snapshot(const []);
      ref.read(wtwLogicProvider.notifier).snapshot(const []);
      DemoAlarm.instance.reset();
      return;
    }
    _seedMedia(ref);
    DemoAlarm.instance.reset();
  };
  demoCommandHook = (ref, command, readBus, writeBus) {
    _onCommand(ref, command, readBus, writeBus);
  };
  demoDisposeHook = demoDisposeMotion;
}

Future<void> runDemoScene(Ref ref, String sceneId) async {
  final cfg = ref.read(configProvider).value;
  if (cfg == null) {
    throw StateError('Demowoning is nog niet geladen');
  }
  final scene = _sceneById(cfg, sceneId);
  if (scene == null) {
    throw StateError('Scene niet gevonden');
  }

  final actions = [...scene.actions]
    ..sort((a, b) => (a.delayMs ?? 0).compareTo(b.delayMs ?? 0));
  var waited = 0;
  for (final action in actions) {
    final delay = action.delayMs ?? 0;
    if (delay > waited) {
      await Future<void>.delayed(Duration(milliseconds: delay - waited));
      waited = delay;
    }
    ref.read(busProvider.notifier).reflectAll({action.ga: action.value});
  }

  for (final media in scene.mediaActions) {
    final delay = media.delayMs ?? 0;
    if (delay > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
    _applyMedia(ref, {
      'deviceId': media.deviceId,
      'kind': 'media.${media.kind}',
      if (media.action != null) 'action': media.action,
      if (media.value != null) 'value': media.value,
      if (media.muted != null) 'muted': media.muted,
      if (media.presetId != null) 'presetId': media.presetId,
    });
  }

  if (sceneId == 'scn-weg') {
    DemoAlarm.instance.tryArm(skipPin: true);
  } else if (sceneId == 'scn-welkom') {
    DemoAlarm.instance.tryDisarm(skipPin: true);
  }
}

Scene? _sceneById(HouseConfig cfg, String id) {
  for (final scene in cfg.scenes) {
    if (scene.id == id) return scene;
  }
  for (final floor in cfg.floors) {
    for (final room in floor.rooms) {
      for (final scene in room.scenes) {
        if (scene.id == id) return scene;
      }
    }
  }
  return null;
}

void _onCommand(
  Ref ref,
  Map<String, dynamic> command,
  DemoBusRead readBus,
  DemoBusWrite writeBus,
) {
  final kind = command['kind'];
  if (kind == 'shading.move') {
    _startMove(ref, command, readBus, writeBus);
    return;
  }
  if (kind == 'shading.position') {
    final id = command['deviceId'] as String?;
    if (id != null) _moves.remove(id)?.cancel();
    return;
  }
  if (kind is String && kind.startsWith('media.')) {
    _applyMedia(ref, command);
    return;
  }
  if (kind == 'wtw.press' && command['buttonId'] != 'boost') {
    ref.read(wtwLogicProvider.notifier).snapshot(const []);
  }
}

void _startMove(
  Ref ref,
  Map<String, dynamic> command,
  DemoBusRead readBus,
  DemoBusWrite writeBus,
) {
  final id = command['deviceId'] as String?;
  if (id == null) return;
  _moves.remove(id)?.cancel();
  final cfg = ref.read(configProvider).value ?? demoHouse.config;
  final device = cfg.deviceById(id);
  final ga = device?.ga['position'];
  final moving = device?.ga['moving'];
  if (device == null || ga == null) return;
  if (command['direction'] == 'stop') {
    writeBus({
      if (moving != null) moving: false,
    });
    return;
  }
  final opening = command['direction'] == 'up';

  // Eerste stap meteen, daarna om de 180 ms tot open of dicht.
  final done = _stepShade(readBus, writeBus, ga, moving, opening);
  if (done) return;

  _moves[id] = Timer.periodic(const Duration(milliseconds: 180), (timer) {
    if (_stepShade(readBus, writeBus, ga, moving, opening)) {
      timer.cancel();
      _moves.remove(id);
    }
  });
}

/// Eén stap van 10%. `true` als de eindstand bereikt is.
bool _stepShade(
  DemoBusRead readBus,
  DemoBusWrite writeBus,
  String ga,
  String? moving,
  bool opening,
) {
  final current = readBus()[ga];
  final parsed = current is num
      ? current.round()
      : int.tryParse('$current') ?? 0;
  var pct = opening ? parsed - 10 : parsed + 10;
  final atEnd = pct <= 0 || pct >= 100;
  pct = pct.clamp(0, 100);
  writeBus({
    ga: pct,
    if (moving != null && atEnd) moving: false,
    if (moving != null && !atEnd) moving: true,
  });
  return atEnd;
}

const _presets = <MediaPreset>[
  MediaPreset(id: 'npo2', name: 'NPO Radio 2'),
  MediaPreset(id: 'jazz', name: 'Jazz FM'),
  MediaPreset(id: 'focus', name: 'Focus'),
];

const _tracks = <String, (String, String)>{
  'npo2': ('Ochtendshow', 'NPO Radio 2'),
  'jazz': ('Blue in Green', 'Miles Davis'),
  'focus': ('Weightless', 'Marconi Union'),
};

void _seedMedia(Ref ref) {
  final house = demoHouse;
  final states = <MediaState>[
    for (final id in house.mediaIds)
      _player(
        id,
        playing: id == house.livingMediaId,
        volume: id == house.livingMediaId ? 22 : 16,
      ),
  ];
  ref.read(mediaStateProvider.notifier).snapshot(states);
}

MediaState _player(
  String id, {
  required bool playing,
  String preset = 'npo2',
  int volume = 18,
}) {
  final track = _tracks[preset] ?? _tracks['npo2']!;
  return MediaState(
    deviceId: id,
    brand: MediaBrand.sonos,
    online: true,
    transport: playing ? MediaTransport.playing : MediaTransport.stopped,
    title: playing ? track.$1 : null,
    artist: playing ? track.$2 : null,
    source: playing ? track.$2 : null,
    volume: volume,
    muted: false,
    presets: _presets,
    currentUri: preset,
  );
}

void _applyMedia(Ref ref, Map<String, dynamic> command) {
  final id = command['deviceId'] as String?;
  if (id == null || id.isEmpty) return;
  final store = ref.read(mediaStateProvider.notifier);
  final current = store.get(id) ?? _player(id, playing: false);
  store.update(_nextMedia(current, command));
}

MediaState _nextMedia(MediaState current, Map<String, dynamic> command) {
  switch (command['kind']) {
    case 'media.transport':
      final action = command['action'];
      if (action == 'play') {
        return _withPreset(current, current.currentUri ?? 'npo2', playing: true);
      }
      if (action == 'pause') {
        return _copy(current, transport: MediaTransport.paused);
      }
      if (action == 'stop') {
        return _copy(current, transport: MediaTransport.stopped, clearMeta: true);
      }
      if (action == 'next' || action == 'previous') {
        return _withPreset(
          current,
          _stepPreset(current.currentUri, action == 'next' ? 1 : -1),
          playing: true,
        );
      }
      return current;
    case 'media.volume':
      final value = (command['value'] as num?)?.round().clamp(0, 100) ?? 0;
      return _copy(current, volume: value);
    case 'media.mute':
      return _copy(current, muted: command['muted'] == true);
    case 'media.preset':
      final preset = (command['presetId'] as String?)?.trim();
      return _withPreset(
        current,
        preset == null || preset.isEmpty ? 'npo2' : preset,
        playing: true,
      );
    default:
      return current;
  }
}

String _stepPreset(String? current, int delta) {
  final index = _presets.indexWhere((preset) => preset.id == current);
  final base = index < 0 ? 0 : index;
  final count = _presets.length;
  return _presets[(base + delta + count) % count].id;
}

MediaState _withPreset(MediaState current, String preset, {required bool playing}) {
  final track = _tracks[preset] ?? _tracks['npo2']!;
  return _copy(
    current,
    transport: playing ? MediaTransport.playing : current.transport,
    title: track.$1,
    artist: track.$2,
    source: track.$2,
    currentUri: preset,
  );
}

MediaState _copy(
  MediaState current, {
  MediaTransport? transport,
  int? volume,
  bool? muted,
  String? title,
  String? artist,
  String? source,
  String? currentUri,
  bool clearMeta = false,
}) {
  return MediaState(
    deviceId: current.deviceId,
    brand: current.brand,
    online: true,
    transport: transport ?? current.transport,
    title: clearMeta ? null : (title ?? current.title),
    artist: clearMeta ? null : (artist ?? current.artist),
    source: clearMeta ? null : (source ?? current.source),
    volume: volume ?? current.volume,
    muted: muted ?? current.muted,
    presets: current.presets.isEmpty ? _presets : current.presets,
    currentUri: currentUri ?? current.currentUri,
  );
}
