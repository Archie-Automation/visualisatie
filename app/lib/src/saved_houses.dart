import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lokale lijst van NUC's die deze telefoon al kent.
///
/// Een woning is een server, geen tweede app-build. De lijst komt alleen uit
/// een adres dat de gebruiker zelf invult of uit een koppelcode. Er is geen
/// server die alle huizen van een persoon teruggeeft.
const _kPrefKey = 'saved_houses_v1';

/// UI (login, instellingen) herlaadt de lijst als dit oploopt.
final ValueNotifier<int> savedHousesEpoch = ValueNotifier<int>(0);

class SavedHouse {
  const SavedHouse({
    required this.key,
    required this.name,
    required this.localUrl,
    this.remoteUrl,
    this.serverId,
  });

  final String key;
  final String name;
  final String localUrl;
  final String? remoteUrl;
  final String? serverId;

  String get label {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return houseHostLabel(remoteUrl ?? localUrl);
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'local': localUrl,
        if (remoteUrl != null) 'remote': remoteUrl,
        if (serverId != null) 'serverId': serverId,
      };

  static SavedHouse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final local = (raw['local'] as String?)?.trim() ?? '';
    if (local.isEmpty) return null;
    final serverId = _blankToNull(raw['serverId'] as String?);
    final key = (raw['key'] as String?)?.trim();
    return SavedHouse(
      key: (key == null || key.isEmpty)
          ? houseKey(serverId: serverId, localUrl: local)
          : key,
      name: (raw['name'] as String?)?.trim() ?? '',
      localUrl: local,
      remoteUrl: _blankToNull(raw['remote'] as String?),
      serverId: serverId,
    );
  }
}

class HouseSession {
  const HouseSession({
    required this.token,
    required this.username,
    this.role,
    this.refreshToken,
    this.sessionId,
  });

  final String token;
  final String username;
  final String? role;
  final String? refreshToken;
  final String? sessionId;

  Map<String, dynamic> toApplyBody() => {
        'token': token,
        'user': {
          'username': username,
          if (role != null) 'role': role,
        },
        if (refreshToken != null && refreshToken!.isNotEmpty)
          'refreshToken': refreshToken,
        if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      };

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        if (role != null) 'role': role,
        if (refreshToken != null) 'refresh': refreshToken,
        if (sessionId != null) 'sessionId': sessionId,
      };

  static HouseSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final token = (raw['token'] as String?)?.trim() ?? '';
    if (token.isEmpty) return null;
    return HouseSession(
      token: token,
      username: (raw['username'] as String?) ?? '',
      role: _blankToNull(raw['role'] as String?),
      refreshToken: _blankToNull(raw['refresh'] as String?),
      sessionId: _blankToNull(raw['sessionId'] as String?),
    );
  }
}

String houseKey({String? serverId, required String localUrl}) {
  final sid = serverId?.trim();
  if (sid != null && sid.isNotEmpty) return 'sid:$sid';
  return 'url:$localUrl';
}

String houseHostLabel(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  if (u.hasPort && u.port != 80 && u.port != 443) return '${u.host}:${u.port}';
  return u.host;
}

class _Vault {
  _Vault({
    required this.houses,
    required this.sessions,
    required this.active,
  });

  List<SavedHouse> houses;
  Map<String, HouseSession> sessions;
  String? active;
}

class HouseStore {
  static Future<List<SavedHouse>> list() async {
    final v = await _read();
    final houses = List<SavedHouse>.from(v.houses);
    houses.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return houses;
  }

  static Future<String?> activeKey() async => (await _read()).active;

  static Future<Map<String, String>> sessionUsernames() async {
    final v = await _read();
    return {
      for (final e in v.sessions.entries) e.key: e.value.username,
    };
  }

  static Future<bool> hasSession(String key) async {
    final v = await _read();
    return v.sessions.containsKey(key);
  }

  static Future<HouseSession?> sessionFor(String key) async {
    final v = await _read();
    return v.sessions[key];
  }

  /// Bewaar of werk bij. Zelfde [serverId] valt samen, ook als de sleutel
  /// eerst alleen het LAN-adres was. Een lege [name] overschrijft een
  /// bestaande naam niet.
  static Future<SavedHouse> upsert({
    required String localUrl,
    String? remoteUrl,
    String? serverId,
    String name = '',
  }) async {
    final local = localUrl.trim();
    if (local.isEmpty) {
      throw ArgumentError('localUrl');
    }
    final v = await _read();
    final sid = _blankToNull(serverId);
    final remote = _blankToNull(remoteUrl);
    final key = houseKey(serverId: sid, localUrl: local);

    SavedHouse? match;
    for (final h in v.houses) {
      if (sid != null && h.serverId == sid) {
        match = h;
        break;
      }
      // Zelfde adres, nog zonder server-id: dat is dit huis, nu herkend.
      if (h.localUrl == local && (h.serverId == null || h.serverId == sid)) {
        match = h;
        break;
      }
      if (h.key == key) {
        match = h;
        break;
      }
    }

    final resolvedName = name.trim().isNotEmpty
        ? name.trim()
        : (match != null && match.name.trim().isNotEmpty
            ? match.name
            : houseHostLabel(remote ?? local));

    final next = SavedHouse(
      key: key,
      name: resolvedName,
      localUrl: local,
      remoteUrl: remote ?? match?.remoteUrl,
      serverId: sid ?? match?.serverId,
    );

    if (match != null && match.key != next.key) {
      final moved = v.sessions.remove(match.key);
      if (moved != null) v.sessions[next.key] = moved;
      if (v.active == match.key) v.active = next.key;
      v.houses.removeWhere((h) => h.key == match!.key);
    } else {
      v.houses.removeWhere((h) => h.key == next.key);
    }
    v.houses.add(next);
    v.active ??= next.key;
    await _write(v);
    return next;
  }

  static Future<void> saveSession(String key, HouseSession session) async {
    final v = await _read();
    v.sessions[key] = session;
    await _write(v);
  }

  static Future<void> dropSession(String key) async {
    final v = await _read();
    if (v.sessions.remove(key) == null) return;
    await _write(v);
  }

  static Future<void> setActive(String? key) async {
    final v = await _read();
    if (v.active == key) return;
    v.active = key;
    await _write(v);
  }

  static Future<void> remove(String key) async {
    final v = await _read();
    v.houses.removeWhere((h) => h.key == key);
    v.sessions.remove(key);
    if (v.active == key) v.active = null;
    await _write(v);
  }

  static Future<_Vault> _read() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kPrefKey);
    if (raw == null || raw.isEmpty) {
      return _Vault(houses: [], sessions: {}, active: null);
    }
    try {
      final map = jsonDecode(raw);
      if (map is! Map) {
        return _Vault(houses: [], sessions: {}, active: null);
      }
      final houses = <SavedHouse>[];
      final list = map['houses'];
      if (list is List) {
        for (final item in list) {
          final h = SavedHouse.fromJson(item);
          if (h != null) houses.add(h);
        }
      }
      final sessions = <String, HouseSession>{};
      final sess = map['sessions'];
      if (sess is Map) {
        for (final e in sess.entries) {
          final parsed = HouseSession.fromJson(e.value);
          if (parsed != null) sessions['${e.key}'] = parsed;
        }
      }
      return _Vault(
        houses: houses,
        sessions: sessions,
        active: _blankToNull(map['active'] as String?),
      );
    } catch (_) {
      return _Vault(houses: [], sessions: {}, active: null);
    }
  }

  static Future<void> _write(_Vault v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kPrefKey,
      jsonEncode({
        'active': v.active,
        'houses': [for (final h in v.houses) h.toJson()],
        'sessions': {
          for (final e in v.sessions.entries) e.key: e.value.toJson(),
        },
      }),
    );
    savedHousesEpoch.value++;
  }
}

String? _blankToNull(String? v) {
  final t = v?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}
