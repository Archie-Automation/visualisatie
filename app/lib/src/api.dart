import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'media_api.dart';
import 'hvac_switch_lock.dart';
import 'fireplace_virtual.dart';
import 'models.dart';

/// Returns the API base URL.
/// In release builds on web the app is served by the backend itself, so we
/// can derive the origin from the page URL — this makes the built PWA work
/// from any IP without a --dart-define.
/// In debug mode (flutter run) the Flutter dev server runs on a different port
/// than the backend, so we fall back to the compile-time env var / localhost.
String get apiBase {
  if (kIsWeb && kReleaseMode) {
    final origin = Uri.base.origin;
    return origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  }
  return const String.fromEnvironment('API_BASE',
      defaultValue: 'http://localhost:4000');
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

  bool get isAdmin {
    final r = effectiveRole;
    return r != null && r.toLowerCase() == 'admin';
  }
}

/// Scene/schedule editing: admins always; other users follow ACL on `me`.
bool canEditScenesInApp(AuthState auth, HouseConfig cfg) =>
    auth.isAdmin || (cfg.me?.canEditScenes ?? false);

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
  }

  Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$apiBase/api/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    final user = body['user'] as Map<String, dynamic>;
    final storedUsername = user['username'] as String;
    var roleStr = user['role'] as String?;
    roleStr = roleStr?.trim();
    if (roleStr == null || roleStr.isEmpty) {
      roleStr = _parseJwtRole(token);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await sp.setString('username', storedUsername);
    if (roleStr != null && roleStr.isNotEmpty) {
      await sp.setString('role', roleStr);
    } else {
      await sp.remove('role');
    }
    state = AuthState(
      token: token,
      username: storedUsername,
      role: roleStr,
      restoreComplete: true,
    );
    return true;
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await sp.remove('username');
    await sp.remove('role');
    state = const AuthState(restoreComplete: true);
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// ------------------------------- Config -------------------------------

final configProvider = FutureProvider<HouseConfig>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) throw StateError('not authenticated');
  final res = await http.get(
    Uri.parse('$apiBase/api/config'),
    headers: {'authorization': 'Bearer ${auth.token}'},
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

class BusState {
  final Map<String, dynamic> values;
  const BusState(this.values);
  BusState update(String ga, dynamic v) => BusState({...values, ga: v});
}

class BusController extends Notifier<BusState> {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _disposed = false;
  int _retryDelay = 2; // seconds, doubles on each failure up to 30s
  static const _dimHoldDuration = Duration(milliseconds: 1200);
  final Map<String, ({int percent, DateTime until})> _dimHolds = {};

  void patchDimPercent(String ga, int percent) {
    final p = percent.clamp(0, 100);
    _dimHolds[ga] = (percent: p, until: DateTime.now().add(_dimHoldDuration));
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
    state = state.update(ga, value);
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
      _sub?.cancel();
      _ch?.sink.close();
    });
    // Bus starts before auth restore / login finish; reconnect when session is ready.
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.restoreComplete && next.isAuthed) {
        final wasReady = (prev?.restoreComplete ?? false) && (prev?.isAuthed ?? false);
        if (!wasReady) reconnectNow();
      } else if (prev?.isAuthed == true && !next.isAuthed) {
        _sub?.cancel();
        _sub = null;
        try {
          _ch?.sink.close();
        } catch (_) {}
        _ch = null;
      }
    });
    Future.microtask(_connect);
    return const BusState({});
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final auth = ref.read(authProvider);
    if (!auth.isAuthed || !auth.restoreComplete) return;

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
      }
    } catch (_) {/* offline — ws will provide state */}

    if (_disposed) return;
    await primeMediaStates(ref);
    if (_disposed) return;

    try {
      final wsUrl = apiBase.replaceFirst(RegExp('^http'), 'ws');
      final auth2 = ref.read(authProvider);
      _ch = WebSocketChannel.connect(
          Uri.parse('$wsUrl/ws?token=${auth2.token}'));
      await _ch!.ready;
      _retryDelay = 2; // reset backoff on successful connection

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
            case 'intercom.ring':
              final p = msg['payload'] as Map<String, dynamic>;
              ref.read(intercomRingProvider.notifier).push(IntercomRing(
                    intercomId: p['intercomId'] as String,
                    name: p['name'] as String,
                    ts: p['ts'] as int,
                  ));
            case 'config_changed':
              ref.invalidate(configProvider);
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    try { _ch?.sink.close(); } catch (_) {}
    _ch = null;
    final delay = _retryDelay;
    _retryDelay = (_retryDelay * 2).clamp(2, 30);
    Future.delayed(Duration(seconds: delay), () {
      if (!_disposed) _connect();
    });
  }

  /// Reconnect immediately (e.g. after coming back to foreground).
  void reconnectNow() {
    _sub?.cancel();
    _sub = null;
    try { _ch?.sink.close(); } catch (_) {}
    _ch = null;
    _retryDelay = 2;
    _connect();
  }

  Future<void> _init() => _connect();

  Future<void> send(Map<String, dynamic> command) async {
    final auth = ref.read(authProvider);
    await http.post(
      Uri.parse('$apiBase/api/command'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode(command),
    );
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
  const IntercomRing({
    required this.intercomId,
    required this.name,
    required this.ts,
  });
}

class IntercomRingController extends Notifier<IntercomRing?> {
  @override
  IntercomRing? build() => null;

  void push(IntercomRing r) {
    state = r;
  }

  void clear() {
    state = null;
  }
}

final intercomRingProvider =
    NotifierProvider<IntercomRingController, IntercomRing?>(
  IntercomRingController.new,
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
