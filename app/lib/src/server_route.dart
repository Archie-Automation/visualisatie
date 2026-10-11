import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Twee routes naar dezelfde NUC: thuis het LAN-adres, onderweg
/// `https://<klant-id>.archiecloud.nl`. [apiBase] in api.dart geeft de actieve
/// route terug; alle bestaande `$apiBase/...`-calls volgen dus vanzelf.
///
/// Keuze: LAN eerst met een korte timeout (200 ms). Antwoordt die, dan LAN.
/// Zo niet, dan de cloud-URL. `serverId` uit /api/health voorkomt dat een
/// telefoon op andermans wifi op een vreemde NUC uitkomt.
enum RouteKind { local, remote, none }

const String _kRemotePrefKey = 'api_base_remote';
const String _kServerIdPrefKey = 'server_id';
const Duration kLocalProbeTimeout = Duration(milliseconds: 200);
const Duration kRemoteProbeTimeout = Duration(milliseconds: 1500);

String? _remoteBase;
String? _serverId;
RouteKind _active = RouteKind.local;
/// Verandert bij elke wissel; BusController luistert hierop.
final ValueNotifier<int> serverRouteEpoch = ValueNotifier<int>(0);

String? get remoteApiBase => _remoteBase;
String? get knownServerId => _serverId;
RouteKind get activeRoute => _active;

/// Actieve basis-URL of null als het LAN-adres moet gelden.
String? activeRemoteBaseOrNull() =>
    _active == RouteKind.remote ? _remoteBase : null;

Future<void> loadServerRoute() async {
  final sp = await SharedPreferences.getInstance();
  final r = sp.getString(_kRemotePrefKey)?.trim();
  _remoteBase = (r == null || r.isEmpty) ? null : r;
  final s = sp.getString(_kServerIdPrefKey)?.trim();
  _serverId = (s == null || s.isEmpty) ? null : s;
}

String? normalizeRemoteBase(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

Future<void> setRemoteApiBase(String? raw) async {
  final next = raw == null ? null : normalizeRemoteBase(raw);
  _remoteBase = next;
  final sp = await SharedPreferences.getInstance();
  if (next == null) {
    await sp.remove(_kRemotePrefKey);
    if (_active == RouteKind.remote) _switchTo(RouteKind.local);
  } else {
    await sp.setString(_kRemotePrefKey, next);
  }
}

Future<void> setKnownServerId(String? id) async {
  final v = id?.trim();
  _serverId = (v == null || v.isEmpty) ? null : v;
  final sp = await SharedPreferences.getInstance();
  if (_serverId == null) {
    await sp.remove(_kServerIdPrefKey);
  } else {
    await sp.setString(_kServerIdPrefKey, _serverId!);
  }
}

/// Vergeet cloud-URL en server-id (bij wissel van huis / uitloggen op verzoek).
Future<void> clearServerRoute() async {
  await setRemoteApiBase(null);
  await setKnownServerId(null);
}

void _switchTo(RouteKind kind) {
  if (_active == kind) return;
  _active = kind;
  serverRouteEpoch.value++;
  if (kDebugMode) debugPrint('ServerRoute: actief = $kind');
}

class _ProbeResult {
  const _ProbeResult(this.ok, this.serverId, this.remoteUrl);
  final bool ok;
  final String? serverId;
  final String? remoteUrl;
}

Future<_ProbeResult> _ping(String base, Duration timeout) async {
  try {
    final res =
        await http.get(Uri.parse('$base/api/health')).timeout(timeout);
    if (res.statusCode >= 500) return const _ProbeResult(false, null, null);
    String? sid;
    String? remote;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      sid = (body['serverId'] as String?)?.trim();
      remote = (body['remoteUrl'] as String?)?.trim();
    } catch (_) {/* health zonder json: oudere server */}
    return _ProbeResult(true, sid, remote);
  } catch (_) {
    return const _ProbeResult(false, null, null);
  }
}

bool _sameHouse(_ProbeResult r) {
  final known = _serverId;
  final seen = r.serverId;
  if (known == null || seen == null || seen.isEmpty) return true;
  return known == seen;
}

Future<void> _learn(_ProbeResult r) async {
  if (r.serverId != null && r.serverId!.isNotEmpty && _serverId == null) {
    await setKnownServerId(r.serverId);
  }
  // De NUC vertelt zelf zijn cloud-URL; zo hoeft die niet getypt te worden.
  if (_remoteBase == null && r.remoteUrl != null && r.remoteUrl!.isNotEmpty) {
    await setRemoteApiBase(r.remoteUrl);
  }
}

Completer<RouteKind>? _inflight;

/// Bepaal de route. [localBase] is het LAN-adres (apiBase zonder cloud).
/// Parallel: LAN 200 ms, cloud 1,5 s. LAN wint zodra hij antwoordt.
Future<RouteKind> probeServerRoute(String localBase) {
  final running = _inflight;
  if (running != null) return running.future;
  final c = Completer<RouteKind>();
  _inflight = c;
  _doProbe(localBase).then((k) {
    _inflight = null;
    c.complete(k);
  }).catchError((Object e) {
    _inflight = null;
    c.complete(_active);
  });
  return c.future;
}

Future<RouteKind> _doProbe(String localBase) async {
  final remote = _remoteBase;
  final localF = _ping(localBase, kLocalProbeTimeout);
  final remoteF = (remote == null || remote == localBase)
      ? Future<_ProbeResult>.value(const _ProbeResult(false, null, null))
      : _ping(remote, kRemoteProbeTimeout);

  final local = await localF;
  if (local.ok && _sameHouse(local)) {
    await _learn(local);
    _switchTo(RouteKind.local);
    return RouteKind.local;
  }

  final rem = await remoteF;
  if (rem.ok && _sameHouse(rem)) {
    await _learn(rem);
    _switchTo(RouteKind.remote);
    return RouteKind.remote;
  }

  // Beide stil of verkeerd huis: route laten staan, reconnect-logica doet de rest.
  return RouteKind.none;
}

/// Riverpod-spiegel van [serverRouteEpoch]/[activeRoute] voor de UI.
class ServerRouteController extends Notifier<RouteKind> {
  @override
  RouteKind build() {
    void onTick() => state = _active;
    serverRouteEpoch.addListener(onTick);
    ref.onDispose(() => serverRouteEpoch.removeListener(onTick));
    return _active;
  }
}

final serverRouteProvider =
    NotifierProvider<ServerRouteController, RouteKind>(
  ServerRouteController.new,
);
