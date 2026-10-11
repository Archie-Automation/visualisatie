import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Deurbel terwijl de app dicht is.
///
/// Android: de server stuurt via Archie Cloud een FCM-databericht; dit bestand
/// toont daarop het native belscherm (flutter_callkit_incoming). Opnemen opent
/// de app op het intercomscherm. Zolang de app open is en de WebSocket leeft,
/// wordt het pushbericht genegeerd: dan rinkelt de app zelf al.
///
/// De Firebase-clientconfig komt van de server (`GET /api/push/config`), zodat
/// er geen google-services.json in de APK hoeft en één APK alle huizen dient.
/// iOS volgt later (PushKit/VoIP-push); daar doet dit bestand niets.
class PushService {
  PushService._();

  static const _kOptionsPref = 'push_firebase_options';
  static const _kTokenPref = 'push_token';
  static bool _started = false;
  static StreamSubscription<String>? _tokenSub;
  static StreamSubscription<RemoteMessage>? _msgSub;
  static bool Function()? _appRinging;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Na inloggen aanroepen. [appHandlesRing] geeft aan of de app zelf al
  /// rinkelt (WebSocket online); dan slaan we het pushbericht over.
  static Future<void> start({
    required String token,
    required bool Function() appHandlesRing,
  }) async {
    if (!supported) return;
    _appRinging = appHandlesRing;
    if (_started) return;
    _started = true;
    try {
      final cfg = await _fetchConfig(token);
      if (cfg == null) {
        debugPrint('[push] niet actief op deze server');
        _started = false;
        return;
      }
      await _ensureFirebase(cfg);
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, sound: true, badge: false);
      FirebaseMessaging.onBackgroundMessage(archiePushBackgroundHandler);
      _msgSub?.cancel();
      _msgSub = FirebaseMessaging.onMessage.listen((m) {
        if (_appRinging?.call() == true) {
          debugPrint('[push] genegeerd, app rinkelt zelf');
          return;
        }
        unawaited(handlePushData(m.data));
      });
      final t = await fm.getToken();
      if (t != null) await _register(t);
      _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => unawaited(_register(t)));
    } catch (e) {
      debugPrint('[push] start mislukt: $e');
      _started = false;
    }
  }

  /// Bij uitloggen: token van deze gebruiker op de server weghalen.
  static Future<void> stop({String? token}) async {
    if (!supported) return;
    _tokenSub?.cancel();
    _tokenSub = null;
    _msgSub?.cancel();
    _msgSub = null;
    _started = false;
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString(_kTokenPref);
    if (t == null || token == null) return;
    try {
      await http
          .delete(
            Uri.parse('$apiBase/api/push/register'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({'token': t}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    await sp.remove(_kTokenPref);
  }

  /// Testbel naar alleen deze gebruiker (Instellingen).
  static Future<String?> sendTest(String token) async {
    final res = await http.post(
      Uri.parse('$apiBase/api/push/test'),
      headers: {'authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) return null;
    try {
      return ((jsonDecode(res.body) as Map)['error'] as String?) ??
          'fout ${res.statusCode}';
    } catch (_) {
      return 'fout ${res.statusCode}';
    }
  }

  static Future<Map<String, String>?> _fetchConfig(String token) async {
    final res = await http.get(
      Uri.parse('$apiBase/api/push/config'),
      headers: {'authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final b = jsonDecode(res.body) as Map<String, dynamic>;
    if (b['enabled'] != true) return null;
    final f = (b['firebase'] as Map?)?.cast<String, dynamic>();
    if (f == null) return null;
    final out = <String, String>{};
    for (final k in ['apiKey', 'appId', 'projectId', 'messagingSenderId']) {
      final v = f[k];
      if (v is! String || v.isEmpty) return null;
      out[k] = v;
    }
    return out;
  }

  static Future<void> _ensureFirebase(Map<String, String> cfg) async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: cfg['apiKey']!,
        appId: cfg['appId']!,
        messagingSenderId: cfg['messagingSenderId']!,
        projectId: cfg['projectId']!,
      ),
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOptionsPref, jsonEncode(cfg));
  }

  /// Firebase in de achtergrond-isolate (app dicht) met de bewaarde config.
  static Future<void> ensureFirebaseFromPrefs() async {
    if (Firebase.apps.isNotEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kOptionsPref);
    if (raw == null) return;
    final cfg = (jsonDecode(raw) as Map).cast<String, String>();
    await _ensureFirebase(cfg);
  }

  static Future<void> _register(String fcmToken) async {
    final sp = await SharedPreferences.getInstance();
    final jwt = sp.getString('token');
    if (jwt == null) return;
    final sid = await storedSessionId();
    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/api/push/register'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $jwt',
            },
            body: jsonEncode({
              'token': fcmToken,
              'platform': 'android',
              if (sid != null) 'sessionId': sid,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        await sp.setString(_kTokenPref, fcmToken);
        debugPrint('[push] token geregistreerd');
      } else {
        debugPrint('[push] registreren mislukt: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[push] registreren mislukt: $e');
    }
  }

  /// Inhoud van een pushbericht afhandelen (voor- én achtergrond).
  static Future<void> handlePushData(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final intercomId = (data['intercomId'] as String?) ?? '';
    switch (type) {
      case 'intercom.ring':
        if (intercomId.isEmpty) return;
        final ts = data['ts']?.toString() ?? '';
        final name = (data['name'] as String?)?.trim();
        final sp = await SharedPreferences.getInstance();
        // Zelfde instelling als het paneel ("Beltijd"); sleutel uit doorbell_ringer.dart.
        final seconds = (sp.getInt('doorbell_panel_ring_seconds') ?? 30).clamp(10, 120);
        await FlutterCallkitIncoming.showCallkitIncoming(
          CallKitParams(
            id: callIdFor(intercomId, ts),
            nameCaller: (name == null || name.isEmpty) ? 'Deurbel' : name,
            appName: 'Archie OS',
            handle: 'Er staat iemand voor de deur',
            type: 1,
            duration: seconds * 1000,
            extra: <String, dynamic>{'intercomId': intercomId, 'ts': ts},
            android: const AndroidParams(
              isCustomNotification: true,
              isShowLogo: false,
              isShowCallID: false,
              isShowFullLockedScreen: true,
              ringtonePath: 'system_ringtone_default',
              backgroundColor: '#111111',
              actionColor: '#4CAF50',
              textColor: '#FFFFFF',
              incomingCallNotificationChannelName: 'Deurbel',
              missedCallNotificationChannelName: 'Gemiste deurbel',
              textAccept: 'Opnemen',
              textDecline: 'Negeren',
            ),
          ),
        );
      case 'intercom.cleared':
        await FlutterCallkitIncoming.endAllCalls();
      default:
        break;
    }
  }

  static String callIdFor(String intercomId, String ts) {
    // Vaste UUID-vorm per bel; het plugin-scherm dedupliceert op id.
    final h = (intercomId + ts).hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return '$h-0000-4000-8000-000000000000';
  }
}

/// Achtergrond-isolate (app dicht of in de achtergrond). Moet top-level zijn.
@pragma('vm:entry-point')
Future<void> archiePushBackgroundHandler(RemoteMessage message) async {
  try {
    await PushService.ensureFirebaseFromPrefs();
  } catch (_) {}
  await PushService.handlePushData(message.data);
}
