import 'package:flutter/material.dart';

import '../models.dart';
import '../roles.dart';
import '../theme.dart';

class AclNavRoom {
  const AclNavRoom({required this.id, required this.name});
  final String id;
  final String name;
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

List<AclNavFloor> aclFloorsFromConfig(HouseConfig cfg) {
  return [
    for (final f in cfg.floors)
      AclNavFloor(
        id: f.id,
        name: f.name,
        rooms: [for (final r in f.rooms) AclNavRoom(id: r.id, name: r.name)],
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

/// Mutates [user]['access'] for a regular user (not staff).
class UserAccessEditor extends StatelessWidget {
  const UserAccessEditor({
    super.key,
    required this.user,
    required this.floors,
    required this.onChanged,
  });

  final Map<String, dynamic> user;
  final List<AclNavFloor> floors;
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
      'editScenes': true,
    };
    user['access'] = m;
    return m;
  }

  Map<String, dynamic> _roomFunctions(Map<String, dynamic> access) {
    final rf = access['roomFunctions'];
    if (rf is Map<String, dynamic>) return rf;
    if (rf is Map) {
      final m = Map<String, dynamic>.from(rf);
      access['roomFunctions'] = m;
      return m;
    }
    final m = <String, dynamic>{};
    access['roomFunctions'] = m;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final access = _access();
    final allFloors = _isAll(access['floors']);
    final allRooms = _isAll(access['rooms']);
    final allFunctions = _isAll(access['functions']);
    final editScenes = access['editScenes'] != false;
    final floorIds = _ids(access['floors']).toSet();
    final roomIds = _ids(access['rooms']).toSet();
    final functionIds = _ids(access['functions']).toSet();
    final roomFn = _roomFunctions(access);

    final visibleFloors = allFloors
        ? floors
        : floors.where((f) => floorIds.contains(f.id)).toList();
    final visibleRooms = [
      for (final f in visibleFloors)
        for (final r in f.rooms)
          if (allRooms || roomIds.contains(r.id)) r,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Scenes en tijdschema\'s mogen wijzigen'),
          value: editScenes,
          onChanged: (v) {
            access['editScenes'] = v;
            onChanged();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alle verdiepingen'),
          value: allFloors,
          onChanged: (v) {
            access['floors'] = v ? '*' : <String>[];
            onChanged();
          },
        ),
        if (!allFloors)
          ...floors.map(
            (f) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(f.name),
              value: floorIds.contains(f.id),
              onChanged: (v) {
                if (v == true) {
                  floorIds.add(f.id);
                } else {
                  floorIds.remove(f.id);
                }
                access['floors'] = floorIds.toList();
                onChanged();
              },
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alle kamers'),
          subtitle: const Text('Binnen de gekozen verdiepingen'),
          value: allRooms,
          onChanged: (v) {
            access['rooms'] = v ? '*' : <String>[];
            onChanged();
          },
        ),
        if (!allRooms)
          ...[
            for (final f in visibleFloors) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  f.name,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
              ),
              for (final r in f.rooms)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(r.name),
                  value: roomIds.contains(r.id),
                  onChanged: (v) {
                    if (v == true) {
                      roomIds.add(r.id);
                    } else {
                      roomIds.remove(r.id);
                    }
                    access['rooms'] = roomIds.toList();
                    onChanged();
                  },
                ),
            ],
          ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alle functies'),
          subtitle: const Text('Verlichting, klimaat, camera\'s, …'),
          value: allFunctions,
          onChanged: (v) {
            access['functions'] = v ? '*' : <String>[];
            if (v) access.remove('roomFunctions');
            onChanged();
          },
        ),
        if (!allFunctions) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final fn in kHouseFunctionDefs)
                FilterChip(
                  label: Text(fn.label),
                  selected: functionIds.contains(fn.slug),
                  onSelected: (sel) {
                    if (sel) {
                      functionIds.add(fn.slug);
                    } else {
                      functionIds.remove(fn.slug);
                    }
                    access['functions'] = functionIds.toList();
                    onChanged();
                  },
                ),
            ],
          ),
          if (visibleRooms.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Functies per kamer',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Standaard volgt de kamer de huisbrede functies. '
              'Kies “hele kamer” of een subset om af te wijken.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LuxeColors.inkSoft,
                  ),
            ),
            for (final r in visibleRooms)
              _RoomFunctionTile(
                room: r,
                value: roomFn[r.id],
                onChanged: (v) {
                  if (v == null) {
                    roomFn.remove(r.id);
                  } else {
                    roomFn[r.id] = v;
                  }
                  if (roomFn.isEmpty) {
                    access.remove('roomFunctions');
                  } else {
                    access['roomFunctions'] = roomFn;
                  }
                  onChanged();
                },
              ),
          ],
        ],
      ],
    );
  }
}

String _functionLabel(String slug) {
  for (final f in kHouseFunctionDefs) {
    if (f.slug == slug) return f.label;
  }
  return slug;
}

class _RoomFunctionTile extends StatelessWidget {
  const _RoomFunctionTile({
    required this.room,
    required this.value,
    required this.onChanged,
  });

  final AclNavRoom room;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final whole = value == '*';
    final custom = value is List;
    final selected = custom
        ? (value as List).map((e) => e.toString()).toSet()
        : <String>{};

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(room.name),
      subtitle: Text(
        whole
            ? 'Hele kamer'
            : custom
                ? selected.isEmpty
                    ? 'Geen functies'
                    : selected.map(_functionLabel).join(', ')
                : 'Standaard (huisbreed)',
      ),
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Standaard (huisbreed)'),
          value: 'inherit',
          groupValue: whole
              ? 'whole'
              : custom
                  ? 'custom'
                  : 'inherit',
          onChanged: (_) => onChanged(null),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Hele kamer'),
          value: 'whole',
          groupValue: whole
              ? 'whole'
              : custom
                  ? 'custom'
                  : 'inherit',
          onChanged: (_) => onChanged('*'),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Alleen deze functies'),
          value: 'custom',
          groupValue: whole
              ? 'whole'
              : custom
                  ? 'custom'
                  : 'inherit',
          onChanged: (_) => onChanged(<String>[]),
        ),
        if (custom)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fn in kHouseFunctionDefs)
                  FilterChip(
                    label: Text(fn.label),
                    selected: selected.contains(fn.slug),
                    onSelected: (sel) {
                      final next = {...selected};
                      if (sel) {
                        next.add(fn.slug);
                      } else {
                        next.remove(fn.slug);
                      }
                      onChanged(next.toList());
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
