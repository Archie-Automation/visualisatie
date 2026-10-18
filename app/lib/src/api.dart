import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'media_api.dart';
import 'server_route.dart';
import 'hvac_switch_lock.dart';
import 'fireplace_virtual.dart';
import 'wtw_logic.dart';
import 'models.dart';
import 'roles.dart';

/// Returns the API base URL.
/// In release builds on web the app is served by the backend itself, so we
/// can derive the origin from the page URL — this makes the built PWA work
/// from any IP without a --dart-define.
/// In debug mode (flutter run) the Flutter dev server runs on a different port
/// than the backend, so we fall back to the compile-time env var / localhost.
/// On native, a SharedPreferences override (login/splash) wins over the build default.
String? _apiBaseOverride;

const String _kApiBasePrefKey = 'api_base';

String get _compileTimeApiBase => const String.fromEnvironment(
      'API_BASE',
      defaultValue: 'http://localhost:4000');

/// Normalise user input: trim, add http:// if missing, strip trailing slash.
String normalizeApiBase(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return _compileTimeApiBase;
  if (!s.contains('://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// LAN-adres van de NUC (zonder cloud-route). Zie [apiBase] voor de actieve.
String get localApiBase {
  if (kIsWeb && kReleaseMode) {
    final origin = Uri.base.origin;
    return origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  }
  final o = _apiBaseOverride;
  if (o != null && o.isNotEmpty) return o;
  return _compileTimeApiBase;
}

/// Actieve basis-URL: LAN thuis, `https://<klant>.archiecloud.nl` onderweg.
/// De web-build praat altijd met zijn eigen origin; daar is geen wissel.
String get apiBase {
  if (kIsWeb && kReleaseMode) return localApiBase;
  return activeRemoteBaseOrNull() ?? localApiBase;
}

/// Load persisted server URL into memory. Call once at app start (native).
Future<void> loadApiBaseOverride() async {
  if (kIsWeb && kReleaseMode) return;
  final sp = await SharedPreferences.getInstance();
  final v = sp.getString(_kApiBasePrefKey)?.trim();
  if (v != null && v.isNotEmpty) {
    _apiBaseOverride = normalizeApiBase(v);
  }
  await loadServerRoute();
}

/// Kies LAN of cloud (max ~1,5 s, meestal <200 ms). Veilig om vaak aan te roepen.
Future<RouteKind> chooseServerRoute() {
  if (kIsWeb && kReleaseMode) return Future.value(RouteKind.local);
  return probeServerRoute(localApiBase);
}

/// Persist and apply a new server URL. Clears auth if the host changed.
Future<void> setApiBase(String raw, {AuthController? auth}) async {
  final next = normalizeApiBase(raw);
  final prev = localApiBase;
  _apiBaseOverride = next;
  final sp = await SharedPreferences.getInstance();
  await sp.setString(_kApiBasePrefKey, next);
  if (next != prev) {
    // Ander huis: cloud-URL en server-id horen bij de oude NUC.
    await clearServerRoute();
    if (auth != null) await auth.logout();
  }
}

/// JWT payload `role` (SharedPreferences / API may omit it on web).
String? _parseJwtRole(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (payload.length % 4) {
      case 2:
        payload += '==';
        break;
      case 3:
        payload += '=';
        break;
    }
    final bytes = base64.decode(payload);
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final r = map['role'];
    if (r is String) return r;
    if (r != null) return '$r';
    return null;
  } catch (_) {
    return null;
  }
}

/// ------------------------------- Auth ---------------------------------

class AuthState {
  final String? token;
  final String? username;
  final String? role;
  /// False until [AuthController.build] finishes (SharedPreferences on web).
  final bool restoreComplete;
  const AuthState({
    this.token,
    this.username,
    this.role,
    this.restoreComplete = false,
  });

  bool get isAuthed => token != null;

  String? get effectiveRole {
    final stored = role?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final t = token;
    if (t == null) return null;
    return _parseJwtRole(t);
  }

  bool get isInstaller => isInstallerRole(effectiveRole);

  bool get isSuperUser => isSuperUserRole(effectiveRole);

  bool get isStaff => isStaffRole(effectiveRole);

  /// Technical configuration (KNX house editor). Legacy name for [isInstaller].
  bool get isAdmin => isInstaller;
}

/// Scene/schedule editing: installer and superuser always; other users follow ACL on `me`.
bool canEditScenesInApp(AuthState auth, HouseConfig cfg) =>
    auth.isStaff || (cfg.me?.canEditScenes ?? false);

/// KNX-scene inlezen/store: alleen installer/superuser (Instellingen).
bool canLearnKnxScenesInApp(AuthState auth) => auth.isStaff;

class KnxSceneHeard {
  const KnxSceneHeard({
    required this.roomId,
    required this.ga,
    required this.number,
    required this.trusted,
    this.timeout = false,
    this.memberIds = const [],
    this.reason,
    this.existingId,
    this.existingName,
    this.learnedMembers = const [],
    this.src,
    this.switchName,
    this.buttonName,
    this.sceneName,
  });
  final String roomId;
  final String ga;
  final int number;
  final bool trusted;
  final bool timeout;
  final List<String> memberIds;
  final String? reason;
  final String? existingId;
  final String? existingName;
  final List<Map<String, dynamic>> learnedMembers;
  final String? src;
  final String? switchName;
  final String? buttonName;
  final String? sceneName;
}

class KnxSceneHeardController extends Notifier<KnxSceneHeard?> {
  @override
  KnxSceneHeard? build() => null;

  void setHeard(KnxSceneHeard v) => state = v;
  void clear() => state = null;
}

final knxSceneHeardProvider =
    NotifierProvider<KnxSceneHeardController, KnxSceneHeard?>(
  KnxSceneHeardController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState(restoreComplete: false);
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    var t = sp.getString('token');
    var u = sp.getString('username');
    var r = sp.getString('role')?.trim();
    if (r != null && r.isEmpty) r = null;
    if (t != null && r == null) {
      r = _parseJwtRole(t);
      if (r != null) await sp.setString('role', r);
    }
    // Re-read after any await: login may have completed during restore and
    // written prefs; do not overwrite that session with a stale null snapshot.
    t = sp.getString('token');
    u = sp.getString('username');
    r = sp.getString('role')?.trim();
    if (r != null && r.isEmpty) r = null;
    state = AuthState(
      token: t,
      username: u,
      role: r,
      restoreComplete: true,
    );
    if (kDebugMode && t != null) {
      debugPrint(
        'Auth restore: user=$u role=$r isAdmin=${state.isAdmin}',
      );
    }
    if (t != null) {
      _scheduleRefreshCheck();
      unawaited(ensureFresh());
    }
  }

  Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$apiBase/api/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'device': deviceLabel(),
      }),
    );
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await applySession(body);
    return true;
  }

  /// Sessie uit een login- of koppel-antwoord overnemen:
  /// `{ token, user: {username, role}, refreshToken? }`.
  Future<void> applySession(Map<String, dynamic> body) async {
    final token = body['token'] as String;
    final user = (body['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final storedUsername = (user['username'] as String?) ?? '';
    var roleStr = (user['role'] as String?)?.trim();
    if (roleStr == null || roleStr.isEmpty) {
      roleStr = _parseJwtRole(token);
    }
    final refresh = (body['refreshToken'] as String?)?.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await sp.setString('username', storedUsername);
    if (roleStr != null && roleStr.isNotEmpty) {
      await sp.setString('role', roleStr);
    } else {
      await sp.remove('role');
    }
    if (refresh != null && refresh.isNotEmpty) {
      await sp.setString(_kRefreshPrefKey, refresh);
    }
    final sid = (body['sessionId'] as String?)?.trim();
    if (sid != null && sid.isNotEmpty) {
      await sp.setString(kSessionIdPrefKey, sid);
    }
    state = AuthState(
      token: token,
      username: storedUsername,
      role: roleStr,
      restoreComplete: true,
    );
    _scheduleRefreshCheck();
  }

  static const _kRefreshPrefKey = 'refresh_token';
  Timer? _refreshTimer;
  bool _refreshing = false;

  /// Nieuw access-token halen op het refresh-token. False = sessie echt weg.
  Future<bool> tryRefresh() async {
    if (_refreshing) return state.isAuthed;
    _refreshing = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final rt = sp.getString(_kRefreshPrefKey);
      if (rt == null || rt.isEmpty) return false;
      final res = await http
          .post(
            Uri.parse('$apiBase/api/auth/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401) {
        await sp.remove(_kRefreshPrefKey);
        return false;
      }
      if (res.statusCode != 200) return state.isAuthed; // netwerk: later nog eens
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await applySession({...body, 'refreshToken': rt});
      return true;
    } catch (_) {
      return state.isAuthed;
    } finally {
      _refreshing = false;
    }
  }

  /// Verloopt het token binnen twee uur (of is het al verlopen)? Dan stil vernieuwen.
  Future<void> ensureFresh() async {
    final t = state.token;
    if (t == null) return;
    final exp = _parseJwtExp(t);
    if (exp == null) return; // oud token zonder exp: niets doen
    final soon = DateTime.now().add(const Duration(hours: 2));
    if (exp.isAfter(soon)) return;
    await tryRefresh();
  }

  void _scheduleRefreshCheck() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      ensureFresh();
    });
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    final sp = await SharedPreferences.getInstance();
    final rt = sp.getString(_kRefreshPrefKey);
    await sp.remove('token');
    await sp.remove('username');
    await sp.remove('role');
    await sp.remove(_kRefreshPrefKey);
    await sp.remove(kSessionIdPrefKey);
    state = const AuthState(restoreComplete: true);
    if (rt != null && rt.isNotEmpty) {
      // Best effort: apparaat intrekken op de server.
      unawaited(http
          .post(
            Uri.parse('$apiBase/api/auth/logout'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(const Duration(seconds: 4))
          .catchError((_) => http.Response('', 0)));
    }
  }
}

/// Pref-sleutel van de server-sessie-id van dit apparaat (zie `/api/auth/sessions`).
const kSessionIdPrefKey = 'session_id';

/// Sessie-id van dit apparaat op de server, of null (oude login zonder refresh).
Future<String?> storedSessionId() async {
  final sp = await SharedPreferences.getInstance();
  final v = sp.getString(kSessionIdPrefKey);
  return (v == null || v.isEmpty) ? null : v;
}

/// Korte apparaatomschrijving voor de sessielijst op de server.
String deviceLabel() {
  if (kIsWeb) return 'browser';
  return defaultTargetPlatform.name;
}

DateTime? _parseJwtExp(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final map = jsonDecode(payload) as Map<String, dynamic>;
    final exp = map['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
  } catch (_) {
    return null;
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// ------------------------------- Config -------------------------------

final configProvider = FutureProvider<HouseConfig>((ref) async {
  final isAuthed = ref.watch(authProvider.select((a) => a.isAuthed));
  if (!isAuthed) throw StateError('not authenticated');
  final token = ref.read(authProvider).token;
  final res = await http.get(
    Uri.parse('$apiBase/api/config'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode == 401) {
    // Token verlopen of ongeldig — uitloggen zodat het loginscherm verschijnt.
    ref.read(authProvider.notifier).logout();
    throw StateError('session expired');
  }
  if (res.statusCode != 200) {
    throw StateError('config fetch failed: ${res.statusCode}');
  }
  return HouseConfig.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
});

/// ------------------------------- Bus ----------------------------------

/// Of de app de huisserver nu bereikt. [connecting] toont nog geen melding.
enum ServerLink { connecting, online, offline }

class ServerLinkController extends Notifier<ServerLink> {
  @override
  ServerLink build() => ServerLink.connecting;

  void online() {
    if (state != ServerLink.online) state = ServerLink.online;
  }

  void offline() {
    if (state != ServerLink.offline) state = ServerLink.offline;
  }

  void reset() {
    if (state != ServerLink.connecting) state = ServerLink.connecting;
  }
}

final serverLinkProvider =
    NotifierProvider<ServerLinkController, ServerLink>(
  ServerLinkController.new,
);

class BusState {
  final Map<String, dynamic> values;
  const BusState(this.values);
  BusState update(String ga, dynamic v) => BusState({...values, ga: v});
}

class BusController extends Notifier<BusState> {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _disposed = false;
  bool _socketLive = false;
  bool _connectInFlight = false;
  int _healthMisses = 0;
  bool _routeProbeInFlight = false;
  int _retryDelay = 2; // seconds, doubles on each failure up to 30s
  /// Incremented on every `_connect()` call. Stale calls detect they're
  /// outdated and stop without corrupting the connection.
  int _connectGen = 0;
  Timer? _reconnectTimer;
  Timer? _healthTimer;
  static const _dimHoldDuration = Duration(milliseconds: 1200);
  static const _batchWindow = Duration(milliseconds: 80);
  final Map<String, ({int percent, DateTime until})> _dimHolds = {};
  final Map<String, dynamic> _pendingGas = {};
  Timer? _batchTimer;

  void patchDimPercent(String ga, int percent) {
    final p = percent.clamp(0, 100);
    _dimHolds[ga] = (percent: p, until: DateTime.now().add(_dimHoldDuration));
    _pendingGas.remove(ga);
    state = state.update(ga, p);
  }

  void _applyIncomingGa(String ga, dynamic value) {
    final hold = _dimHolds[ga];
    if (hold != null) {
      if (DateTime.now().isBefore(hold.until)) {
        if (value is num && (value.round() - hold.percent).abs() > 2) {
          return;
        }
        _dimHolds.remove(ga);
      } else {
        _dimHolds.remove(ga);
      }
    }
    _pendingGas[ga] = value;
    _batchTimer ??= Timer(_batchWindow, _flushBatch);
  }

  void _flushBatch() {
    _batchTimer = null;
    if (_pendingGas.isEmpty) return;
    final next = Map<String, dynamic>.from(state.values);
    next.addAll(_pendingGas);
    _pendingGas.clear();
    state = _mergeDimHolds(BusState(next));
  }

  BusState _mergeDimHolds(BusState base) {
    var next = base;
    final now = DateTime.now();
    _dimHolds.removeWhere((ga, hold) {
      if (now.isBefore(hold.until)) {
        next = next.update(ga, hold.percent);
        return false;
      }
      return true;
    });
    return next;
  }

  Future<void> sendLightDim({
    required String deviceId,
    required String dimGa,
    required int percent,
  }) async {
    patchDimPercent(dimGa, percent);
    await send({
      'kind': 'light.dim',
      'deviceId': deviceId,
      'percent': percent,
    });
  }

  @override
  BusState build() {
    ref.onDispose(() {
      _disposed = true;
      _batchTimer?.cancel();
      _reconnectTimer?.cancel();
      _healthTimer?.cancel();
      _sub?.cancel();
      _ch?.sink.close();
    });
    _healthTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _probeHealth();
    });
    // LAN <-> cloud gewisseld: socket en snapshot opnieuw via de nieuwe route.
    void onRouteSwitch() {
      if (_disposed) return;
      reconnectNow();
    }
    serverRouteEpoch.addListener(onRouteSwitch);
    ref.onDispose(() => serverRouteEpoch.removeListener(onRouteSwitch));
    // Bus starts before auth restore / login finish; reconnect when session is ready.
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.restoreComplete && next.isAuthed) {
        final wasReady = (prev?.restoreComplete ?? false) && (prev?.isAuthed ?? false);
        if (!wasReady) reconnectNow();
      } else if (prev?.isAuthed == true && !next.isAuthed) {
        _socketLive = false;
        _reconnectTimer?.cancel();
        _sub?.cancel();
        _sub = null;
        try {
          _ch?.sink.close();
        } catch (_) {}
        _ch = null;
        ref.read(serverLinkProvider.notifier).reset();
      }
    });
    Future.microtask(_connect);
    return const BusState({});
  }

  Future<bool> _healthOk() async {
    try {
      final res = await http
          .get(Uri.parse('$apiBase/api/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Stekker uit de server laat de websocket vaak half-open. Een health-check
  /// merkt dat sneller dan de TCP-timeout, en haalt de verbinding meteen terug
  /// zodra de server weer antwoordt.
  Future<void> _probeHealth() async {
    if (_disposed) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthed || !auth.restoreComplete) return;
    final ok = await _healthOk();
    if (_disposed) return;
    final still = ref.read(authProvider);
    if (!still.isAuthed || !still.restoreComplete) return;
    if (ok) {
      _healthMisses = 0;
      if (!_socketLive && !_connectInFlight) {
        _retryDelay = 2;
        _connect();
      }
      return;
    }
    _healthMisses++;
    if (_healthMisses < 2) return;
    // Route kwijt (wifi weg, of juist thuisgekomen)? Andere route proberen
    // vóór we "offline" melden. Een wissel triggert zelf de reconnect.
    if (!kIsWeb && remoteApiBase != null && !_routeProbeInFlight) {
      _routeProbeInFlight = true;
      final before = activeRoute;
      try {
        final k = await chooseServerRoute();
        if (_disposed) return;
        if (k != RouteKind.none && k != before) {
          _healthMisses = 0;
          return;
        }
      } finally {
        _routeProbeInFlight = false;
      }
    }
    ref.read(serverLinkProvider.notifier).offline();
    if (_socketLive && !_connectInFlight) _dropLiveSocket();
  }

  void _dropLiveSocket() {
    _socketLive = false;
    _connectGen++;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _scheduleReconnect();
  }

  Future<void> _connect() async {
    final gen = ++_connectGen;
    _reconnectTimer?.cancel();
    if (_disposed) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthed || !auth.restoreComplete) return;
    _connectInFlight = true;
    try {
    // Always re-fetch the full state snapshot on (re)connect so we catch
    // any updates that arrived while the WebSocket was down.
    try {
      final snap = await http.get(
        Uri.parse('$apiBase/api/state'),
        headers: {'authorization': 'Bearer ${auth.token}'},
      );
      if (snap.statusCode == 200) {
        final data = jsonDecode(snap.body) as Map<String, dynamic>;
        final list = (data['states'] as List).cast<Map<String, dynamic>>();
        state = _mergeDimHolds(BusState({
          for (final s in list) s['ga'] as String: s['value'],
        }));
        final locks = (data['hvacLocks'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        ref.read(hvacLockProvider.notifier).snapshot(locks);
        final fpVirtual =
            (data['fireplaceVirtual'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        ref.read(fireplaceVirtualProvider.notifier).snapshot(fpVirtual);
        final wtwLogics =
            (data['wtwLogics'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        ref.read(wtwLogicProvider.notifier).snapshot(wtwLogics);
      } else if (snap.statusCode == 401) {
        // Access-token verlopen? Eerst stil vernieuwen; pas daarna uitloggen.
        final ok = await ref.read(authProvider.notifier).tryRefresh();
        if (!ok) {
          ref.read(authProvider.notifier).logout();
          return;
        }
        if (gen != _connectGen || _disposed) return;
        _scheduleReconnect();
        return;
      }
    } catch (_) {/* offline — ws will provide state */}

    if (gen != _connectGen || _disposed) return;
    await primeMediaStates(ref);
    if (gen != _connectGen || _disposed) return;

    try {
      final wsUrl = apiBase.replaceFirst(RegExp('^http'), 'ws');
      final auth2 = ref.read(authProvider);
      _ch = WebSocketChannel.connect(
          Uri.parse('$wsUrl/ws?token=${auth2.token}'));
      await _ch!.ready;
      if (gen != _connectGen) {
        try { _ch?.sink.close(); } catch (_) {}
        return;
      }
      _retryDelay = 2; // reset backoff on successful connection
      _socketLive = true;
      _healthMisses = 0;
      ref.read(serverLinkProvider.notifier).online();

      _sub = _ch!.stream.listen(
        (raw) {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (msg['type']) {
            case 'snapshot':
              final list =
                  (msg['payload'] as List).cast<Map<String, dynamic>>();
              state = _mergeDimHolds(BusState({
                for (final s in list) s['ga'] as String: s['value'],
              }));
            case 'state':
              final s = msg['payload'] as Map<String, dynamic>;
              _applyIncomingGa(s['ga'] as String, s['value']);
            case 'media.snapshot':
              final list =
                  (msg['payload'] as List).cast<Map<String, dynamic>>();
              ref.read(mediaStateProvider.notifier).snapshot(
                    list.map(MediaState.fromJson).toList(),
                  );
            case 'media.state':
              final p = msg['payload'] as Map<String, dynamic>;
              ref
                  .read(mediaStateProvider.notifier)
                  .update(MediaState.fromJson(p));
            case 'hvac.lock.snapshot':
              final list =
                  (msg['payload'] as List).cast<Map<String, dynamic>>();
              ref.read(hvacLockProvider.notifier).snapshot(list);
            case 'hvac.lock':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(hvacLockProvider.notifier).applyLock(
                    p['deviceId'] as String,
                    (p['untilMs'] as num).toInt(),
                  );
            case 'fireplace.virtual.snapshot':
              final fpList =
                  (msg['payload'] as List).cast<Map<String, dynamic>>();
              ref.read(fireplaceVirtualProvider.notifier).snapshot(fpList);
            case 'fireplace.virtual':
              final fp = msg['payload'] as Map<String, dynamic>;
              ref.read(fireplaceVirtualProvider.notifier).apply(
                    fp['deviceId'] as String,
                    fp['on'] as bool,
                  );
            case 'wtw.logic.snapshot':
              final wtwList =
                  (msg['payload'] as List?)?.cast<Map<String, dynamic>>() ??
                      const [];
              ref.read(wtwLogicProvider.notifier).snapshot(wtwList);
            case 'intercom.ring':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(intercomRingProvider.notifier).push(IntercomRing(
                    intercomId: p['intercomId'] as String,
                    name: p['name'] as String,
                    ts: p['ts'] as int,
                  ));
            case 'intercom.cleared':
              ref.read(intercomRingProvider.notifier).markAnsweredElsewhere();
            case 'intercom.line':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(intercomLineProvider.notifier).setLine(
                    p['intercomId'] as String? ?? '',
                    p['state'] as String? ?? 'idle',
                  );
            case 'config_changed':
              ref.invalidate(configProvider);
            case 'scene.heard':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(knxSceneHeardProvider.notifier).setHeard(KnxSceneHeard(
                    roomId: p['roomId'] as String? ?? '',
                    ga: p['ga'] as String? ?? '',
                    number: (p['number'] as num?)?.toInt() ?? 1,
                    trusted: p['trusted'] == true,
                    timeout: p['timeout'] == true,
                    memberIds: [
                      for (final id in (p['memberIds'] as List?) ?? const [])
                        if ('$id'.trim().isNotEmpty) '$id'.trim(),
                    ],
                    reason: p['reason'] as String?,
                    existingId: p['existingId'] as String?,
                    existingName: p['existingName'] as String?,
                    learnedMembers: [
                      for (final m in (p['members'] as List?) ?? const [])
                        if (m is Map<String, dynamic>) m,
                    ],
                    src: (p['src'] as String?)?.trim(),
                    switchName: (p['switchName'] as String?)?.trim(),
                    buttonName: (p['buttonName'] as String?)?.trim(),
                    sceneName: (p['sceneName'] as String?)?.trim(),
                  ));
          }
        },
        onError: (_) {
          if (gen == _connectGen) _scheduleReconnect();
        },
        onDone: () {
          if (gen == _connectGen) _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      if (gen == _connectGen) _scheduleReconnect();
    }
    } finally {
      if (gen == _connectGen) _connectInFlight = false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _socketLive = false;
    final closeCode = _ch?.closeCode;
    _sub?.cancel();
    _sub = null;
    try { _ch?.sink.close(); } catch (_) {}
    _ch = null;
    // Server rejected the JWT — force re-login instead of hammering.
    if (closeCode == 4401) {
      ref.read(authProvider.notifier).logout();
      return;
    }
    final auth = ref.read(authProvider);
    if (!auth.isAuthed || !auth.restoreComplete) {
      ref.read(serverLinkProvider.notifier).reset();
      return;
    }
    ref.read(serverLinkProvider.notifier).offline();
    final delay = _retryDelay;
    _retryDelay = (_retryDelay * 2).clamp(2, 30);
    final jitterMs = math.Random().nextInt(math.min(delay * 250, 3000));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay, milliseconds: jitterMs), () {
      if (!_disposed) _connect();
    });
  }

  /// Reconnect immediately (e.g. after coming back to foreground).
  void reconnectNow() {
    _socketLive = false;
    _sub?.cancel();
    _sub = null;
    try { _ch?.sink.close(); } catch (_) {}
    _ch = null;
    _retryDelay = 2;
    _connect();
  }

  Future<void> send(Map<String, dynamic> command) async {
    final auth = ref.read(authProvider);
    final res = await http.post(
      Uri.parse('$apiBase/api/command'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode(command),
    );
    if (res.statusCode == 401) {
      ref.read(authProvider.notifier).logout();
    }
  }

  /// Like [send] but verifies the response and throws the backend error
  /// message on failure, so the UI can show why a command did not work.
  Future<void> sendChecked(Map<String, dynamic> command) async {
    final auth = ref.read(authProvider);
    final res = await http.post(
      Uri.parse('$apiBase/api/command'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode(command),
    );
    if (res.statusCode == 401) {
      ref.read(authProvider.notifier).logout();
      throw Exception('Sessie verlopen — log opnieuw in');
    }
    if (res.statusCode >= 400) {
      String msg = 'Opdracht mislukt';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['error'] is String && (body['error'] as String).isNotEmpty) {
          msg = body['error'] as String;
        }
      } catch (_) {
        /* keep default */
      }
      throw Exception(msg);
    }
  }
}

final busProvider =
    NotifierProvider<BusController, BusState>(BusController.new);

/// -------------------------- Intercom ring flow ------------------------

class IntercomRing {
  final String intercomId;
  final String name;
  final int ts;
  final bool answeredElsewhere;
  const IntercomRing({
    required this.intercomId,
    required this.name,
    required this.ts,
    this.answeredElsewhere = false,
  });

  IntercomRing copyWith({bool? answeredElsewhere}) => IntercomRing(
        intercomId: intercomId,
        name: name,
        ts: ts,
        answeredElsewhere: answeredElsewhere ?? this.answeredElsewhere,
      );
}

class IntercomRingController extends Notifier<IntercomRing?> {
  Timer? _autoClear;

  @override
  IntercomRing? build() {
    ref.onDispose(() => _autoClear?.cancel());
    return null;
  }

  void push(IntercomRing r) {
    _autoClear?.cancel();
    state = r;
  }

  /// Bel stopt; popup blijft ±3 s met “Opgenomen elders”.
  void markAnsweredElsewhere() {
    final cur = state;
    if (cur == null || cur.answeredElsewhere) return;
    state = cur.copyWith(answeredElsewhere: true);
    _autoClear?.cancel();
    _autoClear = Timer(const Duration(seconds: 3), clear);
  }

  void clear() {
    _autoClear?.cancel();
    _autoClear = null;
    state = null;
  }
}

final intercomRingProvider =
    NotifierProvider<IntercomRingController, IntercomRing?>(
  IntercomRingController.new,
);

/// `idle`, `ringing`, `dialing` of `busy` per intercom. Leeg = nog onbekend.
class IntercomLineController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void setLine(String intercomId, String lineState) {
    final id = intercomId.trim();
    if (id.isEmpty) return;
    final next = Map<String, String>.from(state);
    next[id] = lineState;
    state = next;
  }
}

final intercomLineProvider =
    NotifierProvider<IntercomLineController, Map<String, String>>(
  IntercomLineController.new,
);

/// Alleen admin. Vraagt een backend-herstart aan (zelfde Node-proces).
Future<void> postAdminFullRestart(String token) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/admin/restart'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('Herstart geweigerd (${res.statusCode})');
  }
}

/// Wacht tot `/api/health` weer bereikbaar is na een herstart.
Future<void> waitForBackendOnline({
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final res = await http
          .get(Uri.parse('$apiBase/api/health'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return;
    } catch (_) {
      /* server nog offline */
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  throw StateError(
    'Server reageert niet binnen ${timeout.inSeconds} seconden na herstart',
  );
}
