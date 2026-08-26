import 'package:flutter/material.dart';

import '../models.dart';
import '../roles.dart';
import '../theme.dart';
import 'widgets/luxe_form.dart';

class AclNavDevice {
  const AclNavDevice({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final String type;

  factory AclNavDevice.fromDevice(Device d) => AclNavDevice(
        id: d.id,
        name: d.name,
        type: (d.raw['type'] as String?) ?? 'universal',
      );

  factory AclNavDevice.fromMap(Map<String, dynamic> m) => AclNavDevice(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? (m['id'] as String?) ?? '',
        type: (m['type'] as String?) ?? 'universal',
      );
}

class AclNavRoom {
  const AclNavRoom({
    required this.id,
    required this.name,
    this.devices = const [],
  });
  final String id;
  final String name;
  final List<AclNavDevice> devices;
}

class AclNavFloor {
  const AclNavFloor({
    required this.id,
    required this.name,
    required this.rooms,
  });
  final String id;
  final String name;
  final List<AclNavRoom> rooms;
}

class AclNavScene {
  const AclNavScene({required this.id, required this.name});
  final String id;
  final String name;
}

class AclHouseExtras {
  const AclHouseExtras({
    this.cameras = const [],
    this.intercoms = const [],
    this.globalDevices = const [],
    this.scenes = const [],
    this.hasAlarm = false,
  });

  final List<AclNavDevice> cameras;
  final List<AclNavDevice> intercoms;
  final List<AclNavDevice> globalDevices;
  final List<AclNavScene> scenes;
  final bool hasAlarm;

  bool get isEmpty =>
      cameras.isEmpty &&
      intercoms.isEmpty &&
      globalDevices.isEmpty &&
      !hasAlarm;

  factory AclHouseExtras.fromConfig(HouseConfig cfg) => AclHouseExtras(
        cameras: [for (final d in cfg.cameras) AclNavDevice.fromDevice(d)],
        intercoms: [for (final d in cfg.intercoms) AclNavDevice.fromDevice(d)],
        globalDevices: [
          for (final d in cfg.globalDevices) AclNavDevice.fromDevice(d)
        ],
        scenes: [
          for (final s in cfg.scenes) AclNavScene(id: s.id, name: s.name),
        ],
        hasAlarm: cfg.satelEnabled,
      );

  factory AclHouseExtras.fromHouseMap(Map<String, dynamic> house) {
    List<AclNavDevice> list(String key) {
      final raw = house[key];
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map)
            AclNavDevice.fromMap(Map<String, dynamic>.from(e)),
      ].where((d) => d.id.isNotEmpty).toList();
    }

    final sceneRaw = house['scenes'];
    final scenes = <AclNavScene>[
      if (sceneRaw is List)
        for (final e in sceneRaw)
          if (e is Map)
            AclNavScene(
              id: (e['id'] as String?) ?? '',
              name: (e['name'] as String?) ?? (e['id'] as String?) ?? '',
            ),
    ].where((s) => s.id.isNotEmpty).toList();

    final satel = house['satel'];
    final satelOn = satel is Map && satel['enabled'] == true;
    return AclHouseExtras(
      cameras: list('cameras'),
      intercoms: list('intercoms'),
      globalDevices: list('devices'),
      scenes: scenes,
      hasAlarm: satelOn,
    );
  }
}

List<AclNavFloor> aclFloorsFromConfig(HouseConfig cfg) {
  return [
    for (final f in cfg.floors)
      AclNavFloor(
        id: f.id,
        name: f.name,
        rooms: [
          for (final r in f.rooms)
            AclNavRoom(
              id: r.id,
              name: r.name,
              devices: [for (final d in r.devices) AclNavDevice.fromDevice(d)],
            ),
        ],
      ),
  ];
}

List<AclNavFloor> aclFloorsFromHouseMaps(List<Map<String, dynamic>> floors) {
  return [
    for (final f in floors)
      if ((f['id'] as String?)?.isNotEmpty == true)
        AclNavFloor(
          id: f['id'] as String,
          name: (f['name'] as String?) ?? f['id'] as String,
          rooms: [
            for (final raw in (f['rooms'] as List?) ?? const [])
              if (raw is Map && (raw['id'] as String?)?.isNotEmpty == true)
                AclNavRoom(
                  id: raw['id'] as String,
                  name: (raw['name'] as String?) ?? raw['id'] as String,
                  devices: [
                    for (final d in (raw['devices'] as List?) ?? const [])
                      if (d is Map && (d['id'] as String?)?.isNotEmpty == true)
                        AclNavDevice.fromMap(Map<String, dynamic>.from(d)),
                  ],
                ),
          ],
        ),
  ];
}

bool _isAll(dynamic v) => v == null || v == '*';

List<String> _ids(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

bool _allows(dynamic list, String id) {
  if (_isAll(list)) return true;
  return _ids(list).contains(id);
}

bool? _tri(Iterable<String> ids, Set<String> granted) {
  final list = ids.toList();
  if (list.isEmpty) return true;
  final n = list.where(granted.contains).length;
  if (n == 0) return false;
  if (n == list.length) return true;
  return null;
}

Map<String, List<AclNavDevice>> _groupByFunction(List<AclNavDevice> devices) {
  final grouped = <String, List<AclNavDevice>>{};
  for (final d in devices) {
    grouped.putIfAbsent(functionSlugForDeviceType(d.type), () => []).add(d);
  }
  final ordered = <String, List<AclNavDevice>>{};
  for (final fn in kHouseFunctionDefs) {
    final items = grouped.remove(fn.slug);
    if (items != null && items.isNotEmpty) ordered[fn.slug] = items;
  }
  ordered.addAll(grouped);
  return ordered;
}

/// Mutates [user]['access'] for a regular user (not staff).
class UserAccessEditor extends StatelessWidget {
  const UserAccessEditor({
    super.key,
    required this.user,
    required this.floors,
    required this.onChanged,
    this.extras = const AclHouseExtras(),
  });

  final Map<String, dynamic> user;
  final List<AclNavFloor> floors;
  final AclHouseExtras extras;
  final VoidCallback onChanged;

  Map<String, dynamic> _access() {
    final a = user['access'];
    if (a is Map<String, dynamic>) return a;
    if (a is Map) {
      final m = Map<String, dynamic>.from(a);
      user['access'] = m;
      return m;
    }
    final m = <String, dynamic>{
      'floors': '*',
      'rooms': '*',
      'functions': '*',
      'devices': '*',
      'scenes': '*',
      'editScenes': true,
    };
    user['access'] = m;
    return m;
  }

  Iterable<AclNavDevice> _allDevices() sync* {
    for (final f in floors) {
      for (final r in f.rooms) {
        yield* r.devices;
      }
    }
    yield* extras.cameras;
    yield* extras.intercoms;
    yield* extras.globalDevices;
  }

  Set<String> _allIds() => {for (final d in _allDevices()) d.id};

  bool _deviceVisible(AclNavDevice d, {String? floorId, String? roomId}) {
    final access = _access();
    if (!_allows(access['devices'], d.id)) return false;
    if (floorId != null &&
        floorId.isNotEmpty &&
        !_allows(access['floors'], floorId)) {
      return false;
    }
    if (roomId != null &&
        roomId.isNotEmpty &&
        !_allows(access['rooms'], roomId)) {
      return false;
    }
    final slug = functionSlugForDeviceType(d.type);
    final rf = access['roomFunctions'];
    if (roomId != null && rf is Map && rf.containsKey(roomId)) {
      return _allows(rf[roomId], slug);
    }
    return _allows(access['functions'], slug);
  }

  Set<String> _granted() {
    final granted = <String>{};
    for (final f in floors) {
      for (final r in f.rooms) {
        for (final d in r.devices) {
          if (_deviceVisible(d, floorId: f.id, roomId: r.id)) {
            granted.add(d.id);
          }
        }
      }
    }
    for (final d in extras.cameras) {
      if (_deviceVisible(d)) granted.add(d.id);
    }
    for (final d in extras.intercoms) {
      if (_deviceVisible(d)) granted.add(d.id);
    }
    for (final d in extras.globalDevices) {
      if (_deviceVisible(d)) granted.add(d.id);
    }
    return granted;
  }

  bool _alarmGranted() {
    if (!extras.hasAlarm) return true;
    return _allows(_access()['functions'], 'alarm');
  }

  Set<String> _scenesGranted() => {
        for (final s in extras.scenes)
          if (_allows(_access()['scenes'], s.id)) s.id,
      };

  void _setScenes(Set<String> scenes) => _commit(_granted(), scenes: scenes);

  void _commit(Set<String> granted, {bool? alarm, Set<String>? scenes}) {
    final access = _access();
    final all = _allIds();
    final alarmOn = extras.hasAlarm ? (alarm ?? _alarmGranted()) : true;
    final allDevicesOn = all.every(granted.contains);
    final scenesOn = scenes ?? _scenesGranted();
    final allScenesOn = extras.scenes.isEmpty ||
        extras.scenes.every((s) => scenesOn.contains(s.id));

    access['scenes'] = extras.scenes.isEmpty || allScenesOn
        ? '*'
        : scenesOn.toList();

    if (allDevicesOn && alarmOn) {
      access['devices'] = '*';
      access['floors'] = '*';
      access['rooms'] = '*';
      access['functions'] = '*';
      access.remove('roomFunctions');
      onChanged();
      return;
    }

    access['devices'] = granted.toList();

    final floorIds = <String>[
      for (final f in floors)
        if (f.rooms.any((r) => r.devices.any((d) => granted.contains(d.id))))
          f.id,
    ];
    access['floors'] =
        floorIds.length == floors.length && floors.isNotEmpty ? '*' : floorIds;

    final allRooms = [for (final f in floors) ...f.rooms];
    final roomIds = <String>[
      for (final r in allRooms)
        if (r.devices.any((d) => granted.contains(d.id))) r.id,
    ];
    access['rooms'] =
        roomIds.length == allRooms.length && allRooms.isNotEmpty ? '*' : roomIds;

    final fns = <String>{};
    for (final d in _allDevices()) {
      if (granted.contains(d.id)) {
        fns.add(functionSlugForDeviceType(d.type));
      }
    }
    if (alarmOn) fns.add('alarm');
    access['functions'] = fns.toList();

    final rf = <String, dynamic>{};
    for (final r in allRooms) {
      if (r.devices.isEmpty) continue;
      final kept = r.devices.where((d) => granted.contains(d.id)).toList();
      if (kept.isEmpty) continue;
      if (kept.length == r.devices.length) {
        rf[r.id] = '*';
      } else {
        rf[r.id] = {
          for (final d in kept) functionSlugForDeviceType(d.type),
        }.toList();
      }
    }
    if (rf.isEmpty) {
      access.remove('roomFunctions');
    } else {
      access['roomFunctions'] = rf;
    }
    onChanged();
  }

  void _setIds(Iterable<String> ids, bool on) {
    final next = _granted();
    if (on) {
      next.addAll(ids);
    } else {
      next.removeAll(ids);
    }
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final access = _access();
    final editScenes = access['editScenes'] != false;
    final granted = _granted();
    final allIds = _allIds();
    final allTri = _tri(allIds, granted);
    final alarmOn = _alarmGranted();
    final scenesGranted = _scenesGranted();
    final allScenesOn = extras.scenes.isEmpty ||
        extras.scenes.every((s) => scenesGranted.contains(s.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Scenes en tijdschema\'s mogen wijzigen',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              LuxeOnOffSwitch(
                value: editScenes,
                onChanged: (v) {
                  access['editScenes'] = v;
                  onChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Zichtbaar in de app', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Vink uit wat deze gebruiker niet mag zien. '
          'Hele verdieping, kamer, functie, apparaat of een scene op de hoofdpagina. '
          'Voor gasten, housekeeping of kinderen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: LuxeColors.inkSoft,
              ),
        ),
        const SizedBox(height: 8),
        _AclNode(
          title: 'Alles',
          value: () {
            final allOn = allTri == true && alarmOn && allScenesOn;
            final allOff = allTri == false &&
                (!extras.hasAlarm || !alarmOn) &&
                (extras.scenes.isEmpty || scenesGranted.isEmpty);
            if (allOn) return true;
            if (allOff) return false;
            return null;
          }(),
          onChanged: (on) {
            final allSceneIds = {for (final s in extras.scenes) s.id};
            if (on) {
              _commit({...allIds}, alarm: true, scenes: allSceneIds);
            } else {
              _commit({}, alarm: false, scenes: {});
            }
          },
          initiallyExpanded: true,
          children: [
            for (final f in floors)
              if (f.rooms.any((r) => r.devices.isNotEmpty))
                _AclNode(
                  title: f.name,
                  value: _tri(
                    [for (final r in f.rooms) for (final d in r.devices) d.id],
                    granted,
                  ),
                  onChanged: (on) => _setIds(
                    [for (final r in f.rooms) for (final d in r.devices) d.id],
                    on,
                  ),
                  children: [
                    for (final r in f.rooms)
                      if (r.devices.isNotEmpty)
                        _AclNode(
                          title: r.name,
                          value: _tri(r.devices.map((d) => d.id), granted),
                          onChanged: (on) =>
                              _setIds(r.devices.map((d) => d.id), on),
                          children: [
                            for (final e in _groupByFunction(r.devices).entries)
                              _functionBranch(e.key, e.value, granted),
                          ],
                        ),
                  ],
                ),
            if (extras.scenes.isNotEmpty)
              _AclNode(
                title: 'Scenes',
                value: _tri(extras.scenes.map((s) => s.id), scenesGranted),
                onChanged: (on) => _setScenes(
                  on ? {for (final s in extras.scenes) s.id} : {},
                ),
                children: [
                  for (final s in extras.scenes)
                    _AclLeaf(
                      title: s.name,
                      value: scenesGranted.contains(s.id),
                      onChanged: (v) {
                        final next = {...scenesGranted};
                        if (v) {
                          next.add(s.id);
                        } else {
                          next.remove(s.id);
                        }
                        _setScenes(next);
                      },
                    ),
                ],
              ),
            if (!extras.isEmpty)
              _AclNode(
                title: 'Huis',
                value: _tri([
                  ...extras.cameras.map((d) => d.id),
                  ...extras.intercoms.map((d) => d.id),
                  ...extras.globalDevices.map((d) => d.id),
                  if (extras.hasAlarm) '__alarm__',
                ], {
                  ...granted,
                  if (alarmOn) '__alarm__',
                }),
                onChanged: (on) {
                  final ids = [
                    ...extras.cameras.map((d) => d.id),
                    ...extras.intercoms.map((d) => d.id),
                    ...extras.globalDevices.map((d) => d.id),
                  ];
                  final next = _granted();
                  if (on) {
                    next.addAll(ids);
                  } else {
                    next.removeAll(ids);
                  }
                  _commit(next, alarm: on);
                },
                children: [
                  if (extras.cameras.isNotEmpty)
                    _functionBranch('cameras', extras.cameras, granted),
                  if (extras.intercoms.isNotEmpty)
                    _functionBranch('intercom', extras.intercoms, granted),
                  for (final e in _groupByFunction(extras.globalDevices).entries)
                    _functionBranch(e.key, e.value, granted),
                  if (extras.hasAlarm)
                    _AclLeaf(
                      title: 'Alarm',
                      value: alarmOn,
                      onChanged: (v) => _commit(_granted(), alarm: v),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _functionBranch(
    String slug,
    List<AclNavDevice> devices,
    Set<String> granted,
  ) {
    return _AclNode(
      title: houseFunctionLabel(slug),
      value: _tri(devices.map((d) => d.id), granted),
      onChanged: (on) => _setIds(devices.map((d) => d.id), on),
      children: [
        for (final d in devices)
          _AclLeaf(
            title: d.name,
            value: granted.contains(d.id),
            onChanged: (v) => _setIds([d.id], v),
          ),
      ],
    );
  }
}

class _AclNode extends StatelessWidget {
  const _AclNode({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return _AclLeaf(
        title: title,
        value: value ?? false,
        onChanged: onChanged,
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 16),
        title: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                tristate: true,
                value: value,
                onChanged: (_) => onChanged(value != true),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _AclLeaf extends StatelessWidget {
  const _AclLeaf({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
