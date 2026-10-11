import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// ICE-servers voor WebRTC (camera + intercom), geleverd door de NUC via
/// `GET /api/media/ice`. Thuis blijft de host-candidate winnen; buitenshuis
/// komt daar een TURN op de Archie-VPS bij met tijdelijke credentials.
///
/// Zonder bereikbare backend of zonder TURN valt dit terug op publieke STUN,
/// precies wat de spelers vóór deze module hardcoded hadden.
const List<Map<String, dynamic>> _fallbackIceServers = [
  {'urls': 'stun:stun.cloudflare.com:3478'},
];

List<Map<String, dynamic>>? _cached;
DateTime? _cachedUntil;
String? _cachedBase;

/// Haal ICE-servers op; cache tot de helft van de TURN-geldigheid (max 10 min).
Future<List<Map<String, dynamic>>> fetchIceServers({
  required String? token,
}) async {
  final base = apiBase;
  final now = DateTime.now();
  final c = _cached;
  if (c != null &&
      _cachedBase == base &&
      _cachedUntil != null &&
      now.isBefore(_cachedUntil!)) {
    return c;
  }
  if (token == null) return _fallbackIceServers;
  try {
    final res = await http.get(
      Uri.parse('$base/api/media/ice'),
      headers: {'authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) return c ?? _fallbackIceServers;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['iceServers'] as List?) ?? const [];
    final servers = <Map<String, dynamic>>[
      for (final s in raw)
        if (s is Map) Map<String, dynamic>.from(s),
    ];
    if (servers.isEmpty) return _fallbackIceServers;
    final ttl = (body['ttl'] as num?)?.toInt() ?? 0;
    final keepSeconds = ttl > 0 ? (ttl ~/ 2).clamp(30, 600) : 600;
    _cached = servers;
    _cachedBase = base;
    _cachedUntil = now.add(Duration(seconds: keepSeconds));
    return servers;
  } catch (_) {
    return c ?? _fallbackIceServers;
  }
}

/// Na een routewissel (LAN <-> cloud) zijn credentials/hosts mogelijk anders.
void invalidateIceServers() {
  _cached = null;
  _cachedUntil = null;
  _cachedBase = null;
}
