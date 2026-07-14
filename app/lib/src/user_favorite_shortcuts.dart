import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'room_control_category.dart';

/// Eén gebruikers-favoriet: hele kamer of één functiegroep (categorie) in die kamer.
class FavoriteShortcut {
  const FavoriteShortcut({
    required this.floorId,
    required this.roomId,
    this.categorySlug,
  });

  final String floorId;
  final String roomId;
  /// `null` of leeg = hele kamer; anders enum-naam, bv. `lighting`.
  final String? categorySlug;

  bool get isRoomOnly =>
      categorySlug == null || categorySlug!.trim().isEmpty;

  bool matches(String f, String r, String? cat) =>
      floorId == f &&
      roomId == r &&
      (categorySlug ?? '') == (cat ?? '');

  Map<String, dynamic> toJson() => {
        'floorId': floorId,
        'roomId': roomId,
        if (!isRoomOnly) 'categorySlug': categorySlug,
      };

  factory FavoriteShortcut.fromJson(Map<String, dynamic> j) =>
      FavoriteShortcut(
        floorId: j['floorId'] as String,
        roomId: j['roomId'] as String,
        categorySlug: j['categorySlug'] as String?,
      );
}

String _storageKey(HouseConfig cfg, String username) {
  final id =
      cfg.projectId.trim().isNotEmpty ? cfg.projectId.trim() : cfg.projectName;
  return 'user_fav_shortcuts_v1_${id}_$username';
}

List<FavoriteShortcut> _pruneToConfig(
  HouseConfig cfg,
  List<FavoriteShortcut> list,
) {
  final out = <FavoriteShortcut>[];
  for (final s in list) {
    Floor? floor;
    for (final f in cfg.floors) {
      if (f.id == s.floorId) {
        floor = f;
        break;
      }
    }
    if (floor == null) continue;
    Room? room;
    for (final r in floor.rooms) {
      if (r.id == s.roomId) {
        room = r;
        break;
      }
    }
    if (room == null) continue;
    if (!s.isRoomOnly) {
      if (RoomControlCategory.tryParseSlug(s.categorySlug!) == null) {
        continue;
      }
    }
    out.add(s);
  }
  return out;
}

Future<void> _persist(
  HouseConfig cfg,
  String username,
  List<FavoriteShortcut> list,
) async {
  final sp = await SharedPreferences.getInstance();
  final key = _storageKey(cfg, username);
  if (list.isEmpty) {
    await sp.remove(key);
  } else {
    await sp.setString(
      key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}

Future<List<FavoriteShortcut>> _readList(HouseConfig cfg, String username) async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(_storageKey(cfg, username));
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => FavoriteShortcut.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Favorieten die de gebruiker zelf kiest (lokaal op dit toestel, per project + login).
final userFavoriteShortcutsProvider =
    FutureProvider<List<FavoriteShortcut>>((ref) async {
  final auth = ref.watch(authProvider);
  final cfg = ref.watch(configProvider).value;
  final uname = auth.username;
  if (!auth.isAuthed || uname == null || cfg == null) return [];

  final list = await _readList(cfg, uname);
  final pruned = _pruneToConfig(cfg, list);
  if (pruned.length != list.length) {
    await _persist(cfg, uname, pruned);
  }
  return pruned;
});

Future<void> toggleUserFavoriteRoom(
  WidgetRef ref,
  HouseConfig cfg,
  String floorId,
  String roomId,
) async {
  final auth = ref.read(authProvider);
  final uname = auth.username;
  if (uname == null) return;

  final current = _pruneToConfig(
    cfg,
    await _readList(cfg, uname),
  );
  final idx = current.indexWhere(
    (e) => e.floorId == floorId && e.roomId == roomId && e.isRoomOnly,
  );
  if (idx >= 0) {
    current.removeAt(idx);
  } else {
    current.add(FavoriteShortcut(floorId: floorId, roomId: roomId));
  }
  await _persist(cfg, uname, current);
  ref.invalidate(userFavoriteShortcutsProvider);
}

Future<void> toggleUserFavoriteCategory(
  WidgetRef ref,
  HouseConfig cfg,
  String floorId,
  String roomId,
  String categorySlug,
) async {
  final auth = ref.read(authProvider);
  final uname = auth.username;
  if (uname == null) return;

  final current = _pruneToConfig(
    cfg,
    await _readList(cfg, uname),
  );
  final idx = current.indexWhere(
    (e) =>
        e.floorId == floorId &&
        e.roomId == roomId &&
        (e.categorySlug ?? '') == categorySlug,
  );
  if (idx >= 0) {
    current.removeAt(idx);
  } else {
    current.add(FavoriteShortcut(
      floorId: floorId,
      roomId: roomId,
      categorySlug: categorySlug,
    ));
  }
  await _persist(cfg, uname, current);
  ref.invalidate(userFavoriteShortcutsProvider);
}

// ── Per-device user favourites ───────────────────────────────────────────────
// Stored as a Map<deviceId, bool>:
//   true  = user explicitly added (even if config says false)
//   false = user explicitly removed (even if config says favorite: true)
//   absent = fall back to device.favorite from house.json

String _deviceFavKey(HouseConfig cfg, String username) {
  final id =
      cfg.projectId.trim().isNotEmpty ? cfg.projectId.trim() : cfg.projectName;
  return 'user_fav_devices_v2_${id}_$username';
}

Future<Map<String, bool>> _readDevFavOverrides(
    HouseConfig cfg, String username) async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(_deviceFavKey(cfg, username));
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v == true));
  } catch (_) {
    return {};
  }
}

Future<void> _persistDevFavOverrides(
    HouseConfig cfg, String username, Map<String, bool> overrides) async {
  final sp = await SharedPreferences.getInstance();
  final key = _deviceFavKey(cfg, username);
  if (overrides.isEmpty) {
    await sp.remove(key);
  } else {
    await sp.setString(key, jsonEncode(overrides));
  }
}

/// Override-map voor apparaat-favorieten.
/// Gebruik [effectiveDeviceFav] om het werkelijke favouriet-status te bepalen.
final userFavoriteDevicesProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  final auth = ref.watch(authProvider);
  final cfg = ref.watch(configProvider).value;
  final uname = auth.username;
  if (!auth.isAuthed || uname == null || cfg == null) return {};
  return _readDevFavOverrides(cfg, uname);
});

/// Bepaal of een apparaat als favoriet getoond moet worden.
/// Respecteert zowel de config-waarde als de gebruiker-override.
bool effectiveDeviceFav(
  AsyncValue<Map<String, bool>> overridesAsync,
  Device device,
) =>
    overridesAsync.maybeWhen(
      data: (overrides) {
        if (overrides.containsKey(device.id)) return overrides[device.id]!;
        return device.favorite; // config default
      },
      orElse: () => device.favorite,
    );

/// Schakel het apparaat als favoriet in of uit.
/// [currentlyFav]: de huidige zichtbare staat in de app.
Future<void> toggleUserFavoriteDevice(
  WidgetRef ref,
  HouseConfig cfg,
  String deviceId,
  bool currentlyFav,
) async {
  final auth = ref.read(authProvider);
  final uname = auth.username;
  if (uname == null) return;

  final overrides = await _readDevFavOverrides(cfg, uname);
  if (currentlyFav) {
    // Verwijder: sla expliciet false op
    overrides[deviceId] = false;
  } else {
    // Voeg toe: sla expliciet true op
    overrides[deviceId] = true;
  }
  await _persistDevFavOverrides(cfg, uname, overrides);
  ref.invalidate(userFavoriteDevicesProvider);
}

bool userHasRoomFavorite(
  AsyncValue<List<FavoriteShortcut>> async,
  String floorId,
  String roomId,
) =>
    async.maybeWhen(
      data: (l) =>
          l.any((e) => e.floorId == floorId && e.roomId == roomId && e.isRoomOnly),
      orElse: () => false,
    );

bool userHasCategoryFavorite(
  AsyncValue<List<FavoriteShortcut>> async,
  String floorId,
  String roomId,
  String categorySlug,
) =>
    async.maybeWhen(
      data: (l) => l.any(
        (e) =>
            e.floorId == floorId &&
            e.roomId == roomId &&
            (e.categorySlug ?? '') == categorySlug,
      ),
      orElse: () => false,
    );
