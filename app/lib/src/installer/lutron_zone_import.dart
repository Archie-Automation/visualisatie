import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

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

Future<int?> showLutronZoneImportDialog({
  required BuildContext context,
  required List<LutronZoneInfo> zones,
  required Map<String, dynamic> house,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _LutronZoneImportDialog(zones: zones, house: house),
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

class _RoomOption {
  const _RoomOption(this.floorIndex, this.roomIndex, this.label);
  final int floorIndex;
  final int roomIndex;
  final String label;
}

class _RowState {
  _RowState({required this.zone, required this.used})
      : kind = suggestLutronImportKind(zone.controlType) ?? LutronImportKind.dimmer,
        known = suggestLutronImportKind(zone.controlType) != null,
        selected = !used && suggestLutronImportKind(zone.controlType) != null;

  final LutronZoneInfo zone;
  final bool used;
  final bool known;
  LutronImportKind kind;
  bool selected;
}

class _LutronZoneImportDialog extends StatefulWidget {
  const _LutronZoneImportDialog({required this.zones, required this.house});

  final List<LutronZoneInfo> zones;
  final Map<String, dynamic> house;

  @override
  State<_LutronZoneImportDialog> createState() => _LutronZoneImportDialogState();
}

class _LutronZoneImportDialogState extends State<_LutronZoneImportDialog> {
  late final List<_RowState> _rows;
  late final List<_FloorOption> _floors;
  late final List<_RoomOption> _rooms;
  late bool _perArea;
  late int _floorIndex;
  int _roomChoice = 0;

  @override
  void initState() {
    super.initState();
    final used = lutronZoneIdsInHouse(widget.house);
    _rows = [
      for (final zone in widget.zones)
        if (zone.id >= 1) _RowState(zone: zone, used: used.contains(zone.id)),
    ];
    _floors = _readFloors(widget.house);
    _rooms = _readRooms(widget.house, _floors);
    _perArea = _rows.any((row) => row.zone.area.trim().isNotEmpty) || _rooms.isEmpty;
    _floorIndex = _floors.isEmpty ? -1 : _floors.first.index;
    if (_rooms.isEmpty) _perArea = _floors.isNotEmpty;
  }

  bool get _canApply {
    if (_selected.isEmpty) return false;
    if (_perArea) return _floorIndex >= 0;
    return _roomChoice >= 0 && _roomChoice < _rooms.length;
  }

  List<_RowState> get _selected =>
      _rows.where((row) => row.selected && !row.used).toList();

  void _setKnown(bool selected) {
    setState(() {
      for (final row in _rows) {
        if (!row.used && row.known) row.selected = selected;
      }
    });
  }

  void _apply() {
    if (!_canApply) return;
    final target = _perArea
        ? LutronZoneImportTarget.perArea(_floorIndex)
        : LutronZoneImportTarget.room(
            _rooms[_roomChoice].floorIndex,
            _rooms[_roomChoice].roomIndex,
          );
    final added = applyLutronZoneImport(
      house: widget.house,
      target: target,
      items: [
        for (final row in _selected)
          LutronZoneImportItem(
            id: row.zone.id,
            name: row.zone.name,
            area: row.zone.area,
            kind: row.kind,
          ),
      ],
    );
    Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_RowState>>{};
    for (final row in _rows) {
      final area = row.zone.area.trim().isEmpty ? 'Zonder gebied' : row.zone.area.trim();
      groups.putIfAbsent(area, () => []).add(row);
    }
    final knownOn = _rows.where((row) => row.known && !row.used && row.selected).length;
    final known = _rows.where((row) => row.known && !row.used).length;

    return AlertDialog(
      title: const Text('Zones in het huis zetten'),
      content: SizedBox(
        width: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alleen aangevinkte zones worden apparaten. Een zone die al in het huis zit blijft staan.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_floors.isEmpty)
              const Text('Maak eerst een verdieping. De import maakt geen gebouw of verdieping.')
            else ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _perArea,
                onChanged: (v) => setState(() => _perArea = v ?? false),
                title: const Text('Nieuwe kamer per Lutron-gebied'),
                subtitle: const Text(
                  'Op de gekozen verdieping. Een kamer met dezelfde naam wordt hergebruikt.',
                ),
              ),
              if (_perArea)
                DropdownButtonFormField<int>(
                  initialValue: _floorIndex,
                  decoration: const InputDecoration(
                    labelText: 'Verdieping',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final floor in _floors)
                      DropdownMenuItem(value: floor.index, child: Text(floor.label)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _floorIndex = v);
                  },
                )
              else if (_rooms.isEmpty)
                const Text('Geen kamer. Zet nieuwe kamer per gebied aan, of maak eerst een kamer.')
              else
                DropdownButtonFormField<int>(
                  initialValue: _roomChoice,
                  decoration: const InputDecoration(
                    labelText: 'Kamer',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var i = 0; i < _rooms.length; i++)
                      DropdownMenuItem(value: i, child: Text(_rooms[i].label)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _roomChoice = v);
                  },
                ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: known == 0
                    ? null
                    : () => _setKnown(knownOn != known),
                child: Text(knownOn == known && known > 0
                    ? 'Bekende uitzetten'
                    : 'Bekende aanvinken'),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (final row in entry.value) _rowTile(row),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: _canApply ? _apply : null,
          child: Text('${_selected.length} toevoegen'),
        ),
      ],
    );
  }

  Widget _rowTile(_RowState row) {
    final type = row.zone.controlType.trim();
    final subtitle = row.used
        ? 'Staat al in het huis'
        : (row.known
            ? (type.isEmpty ? lutronImportKindLabels[row.kind]! : type)
            : (type.isEmpty
                ? 'Onbekend type. Kies een apparaat en vink aan.'
                : 'Onbekend type $type. Kies een apparaat en vink aan.'));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: row.selected,
          onChanged: row.used
              ? null
              : (v) => setState(() => row.selected = v ?? false),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.zone.name.trim().isEmpty ? 'Zone ${row.zone.id}' : row.zone.name),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<LutronImportKind>(
            initialValue: row.kind,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final kind in LutronImportKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(lutronImportKindLabels[kind]!),
                ),
            ],
            onChanged: row.used
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => row.kind = v);
                  },
          ),
        ),
      ],
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

List<_RoomOption> _readRooms(Map<String, dynamic> house, List<_FloorOption> floors) {
  final raw = house['floors'];
  if (raw is! List) return const [];
  final out = <_RoomOption>[];
  for (final floor in floors) {
    final floorMap = raw[floor.index];
    if (floorMap is! Map) continue;
    final rooms = floorMap['rooms'];
    if (rooms is! List) continue;
    for (var ri = 0; ri < rooms.length; ri++) {
      final room = rooms[ri];
      if (room is! Map) continue;
      final name = '${room['name'] ?? ''}'.trim();
      out.add(_RoomOption(
        floor.index,
        ri,
        '$floor.label · ${name.isEmpty ? 'Kamer' : name}',
      ));
    }
  }
  return out;
}
