import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../ui/widgets/function_screen_header.dart';
import '../ui/widgets/luxe_backdrop.dart';
import 'installer_api.dart';

/// Apparaattype dat een LEAP-zone in het huis wordt.
enum LutronImportKind { switchLoad, dimmer, color, white, shade, jalousie }

const lutronImportKindLabels = <LutronImportKind, String>{
  LutronImportKind.switchLoad: 'Schakelaar',
  LutronImportKind.dimmer: 'Dimmer',
  LutronImportKind.color: 'Kleur',
  LutronImportKind.white: 'Tunable white',
  LutronImportKind.shade: 'Gordijn',
  LutronImportKind.jalousie: 'Jaloezie',
};

/// Bekende QSX-`ControlType`s. Onbekend blijft uit tot de installateur een type kiest.
LutronImportKind? suggestLutronImportKind(String controlType) {
  switch (controlType.trim().toLowerCase()) {
    case 'switched':
    case 'switch':
      return LutronImportKind.switchLoad;
    case 'dimmed':
    case 'dimmer':
      return LutronImportKind.dimmer;
    case 'spectrumtune':
    case 'colortune':
      return LutronImportKind.color;
    case 'whitetune':
      return LutronImportKind.white;
    case 'shade':
      return LutronImportKind.shade;
    case 'shadewithtilt':
    case 'tilt':
      return LutronImportKind.jalousie;
    default:
      return null;
  }
}

class LutronZoneImportItem {
  const LutronZoneImportItem({
    required this.id,
    required this.name,
    required this.area,
    required this.kind,
  });

  final int id;
  final String name;
  final String area;
  final LutronImportKind kind;
}

class LutronZoneImportTarget {
  const LutronZoneImportTarget.room(this.floorIndex, this.roomIndex)
      : perArea = false;

  const LutronZoneImportTarget.perArea(this.floorIndex)
      : perArea = true,
        roomIndex = -1;

  final bool perArea;
  final int floorIndex;
  final int roomIndex;
}

Set<int> lutronZoneIdsInHouse(Map<String, dynamic> house) {
  final ids = <int>{};
  void take(dynamic device) {
    if (device is! Map) return;
    if (device['control'] != 'lutron') return;
    final v = device['lutronIntegrationId'];
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null && n >= 1) ids.add(n);
  }

  final floors = house['floors'];
  if (floors is List) {
    for (final floor in floors) {
      if (floor is! Map) continue;
      final rooms = floor['rooms'];
      if (rooms is! List) continue;
      for (final room in rooms) {
        if (room is! Map) continue;
        final devices = room['devices'];
        if (devices is! List) continue;
        for (final device in devices) {
          take(device);
        }
      }
    }
  }
  final global = house['devices'];
  if (global is List) {
    for (final device in global) {
      take(device);
    }
  }
  return ids;
}

/// Zet gekozen zones in het huis. Een zone-id dat er al in zit wordt overgeslagen.
int applyLutronZoneImport({
  required Map<String, dynamic> house,
  required List<LutronZoneImportItem> items,
  required LutronZoneImportTarget target,
  String Function()? newId,
}) {
  final floors = house['floors'];
  if (floors is! List ||
      target.floorIndex < 0 ||
      target.floorIndex >= floors.length) {
    return 0;
  }
  final floor = floors[target.floorIndex];
  if (floor is! Map) return 0;

  final used = lutronZoneIdsInHouse(house);
  final rooms = _mapList(floor, 'rooms');
  var added = 0;

  Map<String, dynamic>? fixedRoom;
  if (!target.perArea) {
    if (target.roomIndex < 0 || target.roomIndex >= rooms.length) return 0;
    fixedRoom = rooms[target.roomIndex];
  }

  final roomsByName = <String, Map<String, dynamic>>{
    for (final room in rooms) _roomKey('${room['name'] ?? ''}'): room,
  };

  for (final item in items) {
    if (item.id < 1 || used.contains(item.id)) continue;
    final Map<String, dynamic> room;
    if (fixedRoom != null) {
      room = fixedRoom;
    } else {
      final area = item.area.trim().isEmpty ? 'Lutron' : item.area.trim();
      final key = _roomKey(area);
      final existing = roomsByName[key];
      if (existing != null) {
        room = existing;
      } else {
        room = {
          'id': 'rm-${(newId ?? _uuid)()}',
          'name': area,
          'devices': <Map<String, dynamic>>[],
        };
        rooms.add(room);
        roomsByName[key] = room;
      }
    }
    _mapList(room, 'devices').add(_deviceMap(item, newId ?? _uuid));
    used.add(item.id);
    added++;
  }
  return added;
}

Future<int?> openLutronZoneImportPage({
  required BuildContext context,
  required List<LutronZoneInfo> zones,
  required Map<String, dynamic> house,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (context) => _LutronZoneImportPage(zones: zones, house: house),
    ),
  );
}

const _uuidGen = Uuid();

String _uuid() => _uuidGen.v4();

String _roomKey(String name) => name.trim().toLowerCase();

/// Altijd een nieuwe `List<Map<String, dynamic>>`. Een lijst uit JSON of een
/// map-literal liegt soms bij `is List<Map<String, dynamic>>` en weigert daarna
/// een gewoon map-object.
List<Map<String, dynamic>> _mapList(Object parent, String key) {
  final map = parent as Map;
  final raw = map[key];
  final list = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) list.add(Map<String, dynamic>.from(item));
    }
  }
  map[key] = list;
  return list;
}

Map<String, dynamic> _deviceMap(
  LutronZoneImportItem item,
  String Function() newId,
) {
  final name = item.name.trim().isEmpty ? 'Zone ${item.id}' : item.name.trim();
  final device = <String, dynamic>{
    'id': 'dev-${newId()}',
    'name': name,
    'control': 'lutron',
    'lutronIntegrationId': item.id,
  };
  switch (item.kind) {
    case LutronImportKind.switchLoad:
      device['type'] = 'light_switch';
    case LutronImportKind.dimmer:
      device['type'] = 'light_dimmer';
    case LutronImportKind.color:
      device['type'] = 'rgbw_ww';
      device['rgbwWw'] = {
        'mode': 'channels',
        'kelvinMin': 2700,
        'kelvinMax': 6500,
      };
    case LutronImportKind.white:
      device['type'] = 'rgbw_ww';
      device['rgbwWw'] = {
        'mode': 'tunable_white',
        'kelvinMin': 2700,
        'kelvinMax': 6500,
      };
    case LutronImportKind.shade:
      device['type'] = 'shading';
      device['subtype'] = 'blind';
    case LutronImportKind.jalousie:
      device['type'] = 'shading';
      device['subtype'] = 'jalousie';
      device['lutronSlatIntegrationId'] = item.id;
  }
  return device;
}

class _FloorOption {
  const _FloorOption(this.index, this.label);
  final int index;
  final String label;
}

class _RowState {
  _RowState({required this.zone, required this.used})
      : kind = suggestLutronImportKind(zone.controlType),
        deviceName = TextEditingController(text: zone.name.trim()),
        selected = !used && suggestLutronImportKind(zone.controlType) != null;

  final LutronZoneInfo zone;
  final bool used;
  final LutronImportKind? kind;
  final TextEditingController deviceName;
  bool selected;

  String get typeLabel =>
      kind == null ? zone.controlType.trim() : lutronImportKindLabels[kind]!;
}

class _ImportGroup {
  _ImportGroup(String roomName) : room = TextEditingController(text: roomName);

  final TextEditingController room;
  final List<_RowState> rows = [];
}

class _LutronZoneImportPage extends StatefulWidget {
  const _LutronZoneImportPage({required this.zones, required this.house});

  final List<LutronZoneInfo> zones;
  final Map<String, dynamic> house;

  @override
  State<_LutronZoneImportPage> createState() => _LutronZoneImportPageState();
}

class _LutronZoneImportPageState extends State<_LutronZoneImportPage> {
  late final List<_ImportGroup> _groups;
  late final List<_FloorOption> _floors;
  late int _floorIndex;

  @override
  void initState() {
    super.initState();
    final used = lutronZoneIdsInHouse(widget.house);
    final byRoom = <String, _ImportGroup>{};
    for (final zone in widget.zones) {
      if (zone.id < 1) continue;
      final roomName = zone.area.trim().isEmpty ? 'Lutron' : zone.area.trim();
      final group = byRoom.putIfAbsent(roomName, () => _ImportGroup(roomName));
      group.rows.add(_RowState(zone: zone, used: used.contains(zone.id)));
    }
    _groups = byRoom.values.toList();
    _floors = _readFloors(widget.house);
    _floorIndex = _floors.isEmpty ? -1 : _floors.first.index;
  }

  @override
  void dispose() {
    for (final group in _groups) {
      group.room.dispose();
      for (final row in group.rows) {
        row.deviceName.dispose();
      }
    }
    super.dispose();
  }

  bool get _canApply => _selected.isNotEmpty && _floorIndex >= 0;

  List<_RowState> get _selected => [
        for (final group in _groups)
          for (final row in group.rows)
            if (row.selected && !row.used && row.kind != null) row,
      ];

  void _setKnown(bool selected) {
    setState(() {
      for (final group in _groups) {
        for (final row in group.rows) {
          if (!row.used && row.kind != null) row.selected = selected;
        }
      }
    });
  }

  void _apply() {
    if (!_canApply) return;
    final added = applyLutronZoneImport(
      house: widget.house,
      target: LutronZoneImportTarget.perArea(_floorIndex),
      items: [
        for (final group in _groups)
          for (final row in group.rows)
            if (row.selected && !row.used && row.kind != null)
              LutronZoneImportItem(
                id: row.zone.id,
                name: row.deviceName.text.trim().isEmpty
                    ? row.zone.name
                    : row.deviceName.text.trim(),
                area: group.room.text.trim().isEmpty ? 'Lutron' : group.room.text.trim(),
                kind: row.kind!,
              ),
      ],
    );
    Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final knownOn = _selected.length;
    final known = [
      for (final group in _groups)
        for (final row in group.rows)
          if (!row.used && row.kind != null) row,
    ].length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FunctionScreenHeader(
              onBack: () => Navigator.pop(context),
              title: 'Zones in het huis zetten',
              subtitle: 'Lutron',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_floors.isEmpty)
                    const Text('Maak eerst een verdieping.')
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _floorIndex,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Verdieping',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final floor in _floors)
                          DropdownMenuItem(
                            value: floor.index,
                            child: Text(floor.label),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _floorIndex = v);
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: known == 0 ? null : () => _setKnown(knownOn != known),
                      child: Text(
                        knownOn == known && known > 0 ? 'Uitzetten' : 'Aanvinken',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                children: [
                  for (final group in _groups) ...[
                    TextField(
                      controller: group.room,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Ruimte',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final row in group.rows) _rowTile(row),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: _canApply ? _apply : null,
                child: Text('${_selected.length} toevoegen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_RowState row) {
    final editable = !row.used && row.kind != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Checkbox(
            value: row.selected && editable,
            onChanged: editable
                ? (v) => setState(() => row.selected = v ?? false)
                : null,
          ),
          Expanded(
            child: editable
                ? TextField(
                    controller: row.deviceName,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: row.used ? 'Staat al in het huis' : 'Apparaat',
                    ),
                  )
                : Text(
                    row.used
                        ? '${row.zone.name} · staat al in het huis'
                        : (row.deviceName.text.trim().isEmpty
                            ? 'Zone ${row.zone.id}'
                            : row.deviceName.text.trim()),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: Text(
              row.typeLabel.isEmpty ? 'Onbekend' : row.typeLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

List<_FloorOption> _readFloors(Map<String, dynamic> house) {
  final buildings = <String, String>{};
  final rawBuildings = house['buildings'];
  if (rawBuildings is List) {
    for (final building in rawBuildings) {
      if (building is! Map) continue;
      final id = '${building['id'] ?? ''}'.trim();
      final name = '${building['name'] ?? ''}'.trim();
      if (id.isNotEmpty && name.isNotEmpty) buildings[id] = name;
    }
  }
  final floors = house['floors'];
  if (floors is! List) return const [];
  final out = <_FloorOption>[];
  for (var i = 0; i < floors.length; i++) {
    final floor = floors[i];
    if (floor is! Map) continue;
    final name = '${floor['name'] ?? ''}'.trim();
    final label = name.isEmpty ? 'Verdieping' : name;
    final building = buildings['${floor['buildingId'] ?? ''}'.trim()];
    out.add(_FloorOption(i, building == null ? label : '$building · $label'));
  }
  return out;
}
