import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _kKey = 'room_order_v1';

/// Per verdieping een geordende lijst van kamer-ID's (door de gebruiker
/// via slepen bepaald). Niet-opgeslagen kamers (nieuw toegevoegd) worden
/// achteraan toegevoegd.
class RoomOrderNotifier extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() {
    Future.microtask(_restore);
    return const {};
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      state = m.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {}
  }

  /// Sla een nieuwe volgorde op voor de opgegeven verdieping.
  Future<void> reorder(String floorId, List<String> roomIds) async {
    state = {...state, floorId: roomIds};
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, jsonEncode(state));
  }
}

final roomOrderProvider =
    NotifierProvider<RoomOrderNotifier, Map<String, List<String>>>(
  RoomOrderNotifier.new,
);

/// Geeft de kamers van [floor] in de door de gebruiker opgeslagen volgorde.
/// Nieuw toegevoegde kamers die nog niet in de opgeslagen volgorde staan
/// worden achteraan toegevoegd.
List<Room> applyRoomOrder(
  Map<String, List<String>> order,
  Floor floor,
) {
  final ids = order[floor.id];
  if (ids == null || ids.isEmpty) return List.of(floor.rooms);
  final byId = {for (final r in floor.rooms) r.id: r};
  final result = <Room>[];
  for (final id in ids) {
    final r = byId[id];
    if (r != null) result.add(r);
  }
  // Voeg eventuele nieuwe kamers toe die nog niet zijn opgeslagen.
  for (final r in floor.rooms) {
    if (!result.contains(r)) result.add(r);
  }
  return result;
}
