import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'device_label.dart';
import 'demo/demo_bus.dart';
import 'demo/demo_house.dart';
import 'demo/demo_session.dart';
import 'energy_state.dart';
import 'saved_houses.dart';
import 'media_api.dart';
import 'server_route.dart';
import 'hvac_switch_lock.dart';
import 'fireplace_virtual.dart';
import 'wtw_logic.dart';
import 'models.dart';
import 'roles.dart';

export 'device_label.dart' show deviceLabel;

/// Gezet vanuit [registerDemoHooks]. De bus zelf blijft vrij van media/alarm.
typedef DemoSessionHook = void Function(Ref ref, {required bool active});

/// Lezen en schrijven gaan via de notifier zelf. `ref.read(busProvider)`
/// vanuit een bus-commando is een afhankelijkheid op zichzelf en gooit.
typedef DemoBusRead = Map<String, dynamic> Function();
typedef DemoBusWrite = void Function(Map<String, dynamic> patches);
typedef DemoCommandHook = void Function(
  Ref ref,
  Map<String, dynamic> command,
  DemoBusRead readBus,
  DemoBusWrite writeBus,
);

DemoSessionHook? demoSessionHook;
DemoCommandHook? demoCommandHook;
void Function()? demoDisposeHook;

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

/// Persist and apply a new LAN URL.
///
/// Wisselt alleen het adres. De sessie blijft staan tot de aanroeper die
/// parkeert of intrekt. Zo gaat een token van huis A niet naar huis B, en
/// wordt een andere woning niet uitgelogd.
Future<void> setApiBase(String raw) async {
  final next = normalizeApiBase(raw);
  final prev = localApiBase;
  _apiBaseOverride = next;
  final sp = await SharedPreferences.getInstance();
  await sp.setString(_kApiBasePrefKey, next);
  if (next != prev) {
    await clearServerRoute();
  }
}

/// Huidige server + sessie in de lokale lijst zetten. Lege [name] laat een
/// bestaande naam staan. Demo en web slaan niets op.
Future<void> rememberActiveHouse({String name = ''}) async {
  if (kIsWeb) return;
  final session = await _sessionFromPrefs();
  if (session == null && name.trim().isEmpty) {
    final sp = await SharedPreferences.getInstance();
    final hasBase = sp.getString(_kApiBasePrefKey)?.trim().isNotEmpty == true;
    if (!hasBase) return;
  }
  if (session != null && isDemoToken(session.token)) return;
  final house = await HouseStore.upsert(
    localUrl: localApiBase,
    remoteUrl: remoteApiBase,
    serverId: knownServerId,
    name: name,
  );
  await HouseStore.setActive(house.key);
  if (session != null && !isDemoToken(session.token)) {
    await HouseStore.saveSession(house.key, session);
  }
}

/// Sessie van het huis dat nu actief is bewaren vóór een wissel.
Future<void> parkActiveHouse() => rememberActiveHouse();

/// Na de eerste route-keuze: bestaande installatie in de lijst opnemen.
Future<void> adoptCurrentServer() => rememberActiveHouse();

/// Ander huis actief maken. True als er een sessie klaarstond.
///
/// Het vorige huis blijft in de lijst, met zijn eigen token. Die sturen we
/// niet naar de nieuwe server.
Future<bool> openSavedHouse(SavedHouse house, AuthController auth) async {
  if (kIsWeb) return false;
  await parkActiveHouse();
  // Eerst lokaal uitloggen, dan het adres. Anders gaat het token van het
  // vorige huis nog één keer naar de nieuwe server.
  await auth.clearLocal();
  await setApiBase(house.localUrl);
  await setRemoteApiBase(house.remoteUrl);
  if (house.serverId != null) await setKnownServerId(house.serverId);
  await HouseStore.setActive(house.key);
  await chooseServerRoute();
  final session = await HouseStore.sessionFor(house.key);
  if (session == null) {
    await auth.clearLocal();
    return false;
  }
  await auth.applySession(session.toApplyBody());
  return true;
}

Future<HouseSession?> _sessionFromPrefs() async {
  final sp = await SharedPreferences.getInstance();
  final token = sp.getString('token');
  if (token == null || token.isEmpty || isDemoToken(token)) return null;
  final role = sp.getString('role')?.trim();
  return HouseSession(
    token: token,
    username: sp.getString('username') ?? '',
    role: (role == null || role.isEmpty) ? null : role,
    refreshToken: _blank(sp.getString('refresh_token')),
    sessionId: _blank(sp.getString(kSessionIdPrefKey)),
  );
}

String? _blank(String? v) {
  final t = v?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
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
  /// Fabriekswachtwoord is nog actief. De app blijft op het wachtwoordscherm.
  final bool mustChangePassword;
  const AuthState({
    this.token,
    this.username,
    this.role,
    this.restoreComplete = false,
    this.mustChangePassword = false,
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
    if (u != null && u.isNotEmpty) {
      await sp.setString(kLastUsernamePrefKey, u);
    }
    // Telefoon bevriest de 20-minuten-timer. Vernieuw een verlopen token
    // vóór het huis laadt, anders ziet /api/config een 401 en trekt logout
    // het jaartoken in.
    if (t != null && !isDemoToken(t)) {
      final exp = _parseJwtExp(t);
      final due = exp == null ||
          !exp.isAfter(DateTime.now().add(const Duration(hours: 2)));
      if (due) {
        final outcome = await tryRefresh();
        if (outcome == RefreshOutcome.renewed) {
          _scheduleRefreshCheck();
          return;
        }
        if (outcome == RefreshOutcome.dead) {
          await logout();
          return;
        }
        t = sp.getString('token');
        u = sp.getString('username');
        r = sp.getString('role')?.trim();
        if (r != null && r.isEmpty) r = null;
      }
    }
    state = AuthState(
      token: t,
      username: u,
      role: r,
      restoreComplete: true,
      mustChangePassword: t != null && (sp.getBool('must_change_password') ?? false),
    );
    if (kDebugMode && t != null) {
      debugPrint(
        'Auth restore: user=$u role=$r isAdmin=${state.isAdmin}',
      );
    }
    if (t != null) _scheduleRefreshCheck();
  }

  /// Prospectsessie: het demohuis staat in de app, er is geen server.
  Future<void> enterDemo() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', kDemoToken);
    await sp.setString('username', 'Demo');
    await sp.setString('role', 'user');
    await sp.remove(_kRefreshPrefKey);
    await sp.remove(kSessionIdPrefKey);
    state = const AuthState(
      token: kDemoToken,
      username: 'Demo',
      role: 'user',
      restoreComplete: true,
    );
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
    if (res.statusCode == 403) {
      try {
        final err = (jsonDecode(res.body) as Map)['error'];
        if (err == 'remote_closed') {
          throw StateError(
            'Buitenshuis werkt alleen een koppelcode, geen wachtwoord.',
          );
        }
      } catch (e) {
        if (e is StateError) rethrow;
      }
      return false;
    }
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await applySession(
      body,
      mustChangePassword: body['mustChangePassword'] == true,
    );
    return true;
  }

  /// null = opgeslagen. Anders de fouttekst van de server.
  Future<String?> changePassword(String password) async {
    final token = state.token;
    if (token == null || isDemoToken(token)) return 'Niet ingelogd.';
    final res = await http.post(
      Uri.parse('$apiBase/api/auth/password'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode == 200) {
      await _setMustChange(false);
      return null;
    }
    try {
      final err = (jsonDecode(res.body) as Map)['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Wachtwoord niet opgeslagen.';
  }

  /// Health met dit token zegt of het fabriekswachtwoord nog weg moet.
  Future<void> syncPasswordRequirement() async {
    final token = state.token;
    if (token == null || isDemoToken(token)) return;
    try {
      final res = await http
          .get(
            Uri.parse('$apiBase/api/health'),
            headers: {'authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body is! Map || !body.containsKey('mustChangePassword')) return;
      await _setMustChange(body['mustChangePassword'] == true);
    } catch (_) {}
  }

  Future<void> requirePasswordChange() => _setMustChange(true);

  Future<void> _setMustChange(bool value) async {
    final sp = await SharedPreferences.getInstance();
    if (value) {
      await sp.setBool('must_change_password', true);
    } else {
      await sp.remove('must_change_password');
    }
    final cur = state;
    state = AuthState(
      token: cur.token,
      username: cur.username,
      role: cur.role,
      restoreComplete: cur.restoreComplete,
      mustChangePassword: value,
    );
  }

  /// Sessie uit een login- of koppel-antwoord overnemen:
  /// `{ token, user: {username, role}, refreshToken? }`.
  Future<void> applySession(
    Map<String, dynamic> body, {
    bool mustChangePassword = false,
  }) async {
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
    if (storedUsername.isNotEmpty) {
      await sp.setString(kLastUsernamePrefKey, storedUsername);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await sp.setString(_kRefreshPrefKey, refresh);
    }
    final sid = (body['sessionId'] as String?)?.trim();
    if (sid != null && sid.isNotEmpty) {
      await sp.setString(kSessionIdPrefKey, sid);
    }
    if (mustChangePassword) {
      await sp.setBool('must_change_password', true);
    } else {
      await sp.remove('must_change_password');
    }
    state = AuthState(
      token: token,
      username: storedUsername,
      role: roleStr,
      restoreComplete: true,
      mustChangePassword: mustChangePassword,
    );
    _scheduleRefreshCheck();
  }

  static const _kRefreshPrefKey = 'refresh_token';
  Timer? _refreshTimer;
  Future<RefreshOutcome>? _refreshing;

  /// Nieuw access-token op het refresh-token.
  /// [RefreshOutcome.dead] = refresh-token weg of ingetrokken. Access-token blijft
  /// staan tot de aanroeper [logout] doet.
  Future<RefreshOutcome> tryRefresh() {
    final inflight = _refreshing;
    if (inflight != null) return inflight;
    final run = _tryRefresh();
    _refreshing = run;
    return run.whenComplete(() {
      if (identical(_refreshing, run)) _refreshing = null;
    });
  }

  Future<RefreshOutcome> _tryRefresh() async {
    if (isDemoToken(state.token)) return RefreshOutcome.renewed;
    try {
      final sp = await SharedPreferences.getInstance();
      final rt = sp.getString(_kRefreshPrefKey);
      if (rt == null || rt.isEmpty) return RefreshOutcome.dead;
      final res = await http
          .post(
            Uri.parse('$apiBase/api/auth/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'refreshToken': rt,
              'device': deviceLabel(),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401) {
        await sp.remove(_kRefreshPrefKey);
        return RefreshOutcome.dead;
      }
      if (res.statusCode != 200) return RefreshOutcome.offline;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await applySession({...body, 'refreshToken': rt});
      return RefreshOutcome.renewed;
    } catch (_) {
      return RefreshOutcome.offline;
    }
  }

  /// Na een 401. [RefreshOutcome.dead] logt uit. Offline laat de sessie staan.
  Future<RefreshOutcome> refreshOrLogout() async {
    final outcome = await tryRefresh();
    if (outcome == RefreshOutcome.dead && state.isAuthed) await logout();
    return outcome;
  }

  /// Verloopt het token binnen twee uur (of is het al verlopen)? Dan stil vernieuwen.
  Future<void> ensureFresh() async {
    final t = state.token;
    if (t == null || isDemoToken(t)) return;
    final exp = _parseJwtExp(t);
    if (exp == null) return;
    final soon = DateTime.now().add(const Duration(hours: 2));
    if (exp.isAfter(soon)) return;
    final outcome = await tryRefresh();
    if (outcome == RefreshOutcome.dead) await logout();
  }

  void _scheduleRefreshCheck() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      ensureFresh();
    });
  }

  /// Actieve sessie weg, lokaal. Andere woningen blijven bewaard.
  /// Geen server-call: gebruiken bij een wissel naar een huis zonder sessie.
  Future<void> clearLocal() async {
    _refreshTimer?.cancel();
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await sp.remove('username');
    await sp.remove('role');
    await sp.remove(_kRefreshPrefKey);
    await sp.remove(kSessionIdPrefKey);
    await sp.remove('must_change_password');
    state = const AuthState(restoreComplete: true);
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    final houseKey = kIsWeb ? null : await HouseStore.activeKey();
    final sp = await SharedPreferences.getInstance();
    final rt = sp.getString(_kRefreshPrefKey);
    await sp.remove('token');
    await sp.remove('username');
    await sp.remove('role');
    await sp.remove(_kRefreshPrefKey);
    await sp.remove(kSessionIdPrefKey);
    await sp.remove('must_change_password');
    if (houseKey != null) await HouseStore.dropSession(houseKey);
    state = const AuthState(restoreComplete: true);
    if (rt != null && rt.isNotEmpty) {
      // Best effort: apparaat intrekken op déze server, niet op een andere.
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

/// Laatst gebruikte inlognaam. Blijft staan na uitloggen, zodat het veld gevuld is.
const kLastUsernamePrefKey = 'last_username';

/// Uitkomst van [AuthController.tryRefresh].
enum RefreshOutcome { renewed, offline, dead }

Future<String?> rememberedUsername() async {
  final sp = await SharedPreferences.getInstance();
  final v = sp.getString(kLastUsernamePrefKey)?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

/// Sessie-id van dit apparaat op de server, of null (oude login zonder refresh).
Future<String?> storedSessionId() async {
  final sp = await SharedPreferences.getInstance();
  final v = sp.getString(kSessionIdPrefKey);
  return (v == null || v.isEmpty) ? null : v;
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

bool passwordChangeRequired(http.Response res) {
  if (res.statusCode != 403) return false;
  try {
    return (jsonDecode(res.body) as Map)['error'] == 'password_change_required';
  } catch (_) {
    return false;
  }
}

/// ------------------------------- Config -------------------------------

final configProvider = FutureProvider<HouseConfig>((ref) async {
  // Token, niet alleen "ingelogd": wissel van woning moet dit huis opnieuw laden.
  final token = ref.watch(authProvider.select((a) => a.token));
  if (token == null) throw StateError('not authenticated');
  if (isDemoToken(token)) return demoHouse.config;
  var res = await http.get(
    Uri.parse('$apiBase/api/config'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode == 401) {
    final outcome = await ref.read(authProvider.notifier).refreshOrLogout();
    if (outcome == RefreshOutcome.renewed) {
      final token2 = ref.read(authProvider).token;
      if (token2 != null) {
        res = await http.get(
          Uri.parse('$apiBase/api/config'),
          headers: {'authorization': 'Bearer $token2'},
        );
      }
    } else if (outcome == RefreshOutcome.offline) {
      throw StateError('config fetch failed: 401');
    }
    if (res.statusCode == 401) {
      if (ref.read(authProvider).isAuthed) {
        await ref.read(authProvider.notifier).logout();
      }
      throw StateError('session expired');
    }
  }
  if (passwordChangeRequired(res)) {
    await ref.read(authProvider.notifier).requirePasswordChange();
    throw StateError('password change required');
  }
  if (res.statusCode != 200) {
    throw StateError('config fetch failed: ${res.statusCode}');
  }
  final cfg = HouseConfig.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  if (!kIsWeb) {
    unawaited(rememberActiveHouse(name: cfg.projectName));
  }
  return cfg;
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
  bool _refreshedForSocket = false;
  /// Incremented on every `_connect()` call. Stale calls detect they're
  /// outdated and stop without corrupting the connection.
  int _connectGen = 0;
  bool _demoSeeded = false;
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
      demoDisposeHook?.call();
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
      if (isDemoToken(next.token) && !isDemoToken(prev?.token)) {
        _demoSeeded = false;
      }
      if (next.restoreComplete && next.isAuthed) {
        final wasReady = (prev?.restoreComplete ?? false) && (prev?.isAuthed ?? false);
        final switched = wasReady && prev?.token != next.token;
        if (!wasReady || switched) {
          if (switched) {
            state = const BusState({});
            ref.read(energyStateProvider.notifier).clear();
          }
          reconnectNow();
        }
      } else if (prev?.isAuthed == true && !next.isAuthed) {
        if (isDemoToken(prev?.token)) {
          _demoSeeded = false;
          demoSessionHook?.call(ref, active: false);
        }
        ref.read(energyStateProvider.notifier).clear();
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
    if (isDemoToken(auth.token)) {
      ref.read(serverLinkProvider.notifier).online();
      return;
    }
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
    if (auth.mustChangePassword) {
      // De server weigert de bus tot het fabriekswachtwoord weg is.
      // Dat is geen storing.
      ref.read(serverLinkProvider.notifier).online();
      return;
    }
    _connectInFlight = true;
    try {
    if (isDemoToken(auth.token)) {
      if (!_demoSeeded) {
        state = BusState(Map<String, dynamic>.from(demoHouse.bus));
        _demoSeeded = true;
        demoSessionHook?.call(ref, active: true);
      }
      _socketLive = true;
      ref.read(serverLinkProvider.notifier).online();
      return;
    }
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
        final energy = data['energy'];
        if (energy is Map) {
          ref.read(energyStateProvider.notifier).apply(
                Map<String, dynamic>.from(energy),
              );
        }
      } else if (passwordChangeRequired(snap)) {
        await ref.read(authProvider.notifier).requirePasswordChange();
        if (gen != _connectGen || _disposed) return;
        ref.read(serverLinkProvider.notifier).online();
        return;
      } else if (snap.statusCode == 401) {
        final outcome = await ref.read(authProvider.notifier).refreshOrLogout();
        if (gen != _connectGen || _disposed || outcome == RefreshOutcome.dead) {
          return;
        }
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
      _refreshedForSocket = false;
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
            case 'energy.state':
              final energy = msg['payload'];
              if (energy is Map) {
                ref.read(energyStateProvider.notifier).apply(
                      Map<String, dynamic>.from(energy),
                    );
              }
            case 'intercom.ring':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(intercomRingProvider.notifier).push(IntercomRing(
                    intercomId: p['intercomId'] as String,
                    name: p['name'] as String,
                    ts: p['ts'] as int,
                    timeoutSec: (p['timeoutSec'] as num?)?.toInt(),
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
    // Verlopen toegangstoken. Eerst vernieuwen; uitloggen doet refreshOrLogout
    // alleen als het jaartoken echt dood is.
    if (closeCode == 4401) {
      unawaited(_onSocketRejected());
      return;
    }
    if (closeCode == 4403) {
      unawaited(ref.read(authProvider.notifier).requirePasswordChange());
      ref.read(serverLinkProvider.notifier).online();
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

  Future<void> _onSocketRejected() async {
    final outcome = await ref.read(authProvider.notifier).refreshOrLogout();
    if (_disposed || outcome == RefreshOutcome.dead) return;
    if (outcome == RefreshOutcome.renewed && !_refreshedForSocket) {
      _refreshedForSocket = true;
      _retryDelay = 2;
      _connect();
      return;
    }
    _scheduleReconnect();
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

  /// Schrijft demo-buswaarden zonder netwerk. Hooks doen media en zonwering.
  void reflectAll(Map<String, dynamic> patches) {
    if (patches.isEmpty) return;
    final next = Map<String, dynamic>.from(state.values)..addAll(patches);
    state = BusState(next);
  }

  void _applyDemoCommand(Map<String, dynamic> command) {
    final cfg = ref.read(configProvider).value;
    if (cfg != null) {
      reflectAll(demoCommandPatches(cfg, state.values, command));
    }
    demoCommandHook?.call(ref, command, () => state.values, reflectAll);
  }

  Future<void> send(Map<String, dynamic> command) async {
    final auth = ref.read(authProvider);
    if (isDemoToken(auth.token)) {
      _applyDemoCommand(command);
      return;
    }
    await _postCommand(command);
  }

  /// Like [send] but verifies the response and throws the backend error
  /// message on failure, so the UI can show why a command did not work.
  Future<void> sendChecked(Map<String, dynamic> command) async {
    final auth = ref.read(authProvider);
    if (isDemoToken(auth.token)) {
      _applyDemoCommand(command);
      return;
    }
    final res = await _postCommand(command);
    if (res.statusCode == 401) {
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

  Future<http.Response> _postCommand(Map<String, dynamic> command) async {
    Future<http.Response> post(String? token) {
      return http.post(
        Uri.parse('$apiBase/api/command'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode(command),
      );
    }

    var res = await post(ref.read(authProvider).token);
    if (res.statusCode != 401) return res;
    final outcome = await ref.read(authProvider.notifier).refreshOrLogout();
    if (outcome != RefreshOutcome.renewed) return res;
    return post(ref.read(authProvider).token);
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

  /// Afringduur van de belgroep, in seconden. Het paneel gaat zo lang over.
  final int? timeoutSec;
  const IntercomRing({
    required this.intercomId,
    required this.name,
    required this.ts,
    this.answeredElsewhere = false,
    this.timeoutSec,
  });

  IntercomRing copyWith({bool? answeredElsewhere, int? timeoutSec}) =>
      IntercomRing(
        intercomId: intercomId,
        name: name,
        ts: ts,
        answeredElsewhere: answeredElsewhere ?? this.answeredElsewhere,
        timeoutSec: timeoutSec ?? this.timeoutSec,
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
