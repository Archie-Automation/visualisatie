import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// Koppelcode (QR) om een telefoon zonder wachtwoord op dit huis te zetten.
class PairStart {
  const PairStart({
    required this.code,
    required this.expiresAt,
    required this.qr,
    required this.localUrl,
    this.remoteUrl,
  });
  final String code;
  final DateTime expiresAt;
  /// Link voor in de QR: opent de app en koppelt meteen.
  final String qr;
  final String localUrl;
  final String? remoteUrl;
}

Future<PairStart> startPairing({required String token, String? userId}) async {
  final res = await http
      .post(
        Uri.parse('$apiBase/api/auth/pair/start'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({if (userId != null) 'userId': userId}),
      )
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    throw StateError('koppelcode maken mislukt (${res.statusCode})');
  }
  final b = jsonDecode(res.body) as Map<String, dynamic>;
  return PairStart(
    code: b['code'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch((b['expiresAt'] as num).toInt()),
    qr: b['qr'] as String,
    localUrl: b['localUrl'] as String,
    remoteUrl: b['remoteUrl'] as String?,
  );
}

/// Inhoud van een gescande/geplakte koppel-link of losse code.
class PairInput {
  const PairInput({required this.code, this.localUrl, this.remoteUrl});
  final String code;
  final String? localUrl;
  final String? remoteUrl;

  /// Accepteert `XXXX-XXXX`, of een link als
  /// `https://huis.archiecloud.nl/pair?code=XXXX-XXXX&local=http://...`
  /// (of de oudere hash-vorm `/#/pair?...`).
  static PairInput? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains('://')) {
      final uri = Uri.tryParse(s);
      if (uri == null) return null;
      var params = uri.queryParameters;
      if (!params.containsKey('code') && uri.fragment.contains('?')) {
        params = Uri.splitQueryString(uri.fragment.split('?').last);
      }
      final code = params['code'];
      if (code == null || code.isEmpty) return null;
      final origin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      final remote = params['remote'];
      final local = params['local'];
      return PairInput(
        code: code,
        localUrl: local ?? (remote == null ? origin : null),
        remoteUrl: remote ?? (local != null && local != origin ? origin : null),
      );
    }
    final cleaned = s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (cleaned.length != 8) return null;
    return PairInput(code: '${cleaned.substring(0, 4)}-${cleaned.substring(4)}');
  }
}

/// Antwoord van de server bij een geldige code.
class PairClaim {
  const PairClaim({required this.session, required this.localUrl, this.remoteUrl});
  /// `{ token, refreshToken, user }` voor [AuthController.applySession].
  final Map<String, dynamic> session;
  final String localUrl;
  final String? remoteUrl;
}

Future<PairClaim> claimPairCode({
  required String base,
  required String code,
}) async {
  final res = await http
      .post(
        Uri.parse('$base/api/auth/pair/claim'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'code': code, 'device': deviceLabel()}),
      )
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    String msg = 'koppelen mislukt (${res.statusCode})';
    try {
      final e = (jsonDecode(res.body) as Map)['error'];
      if (e is String && e.isNotEmpty) msg = e;
    } catch (_) {}
    throw StateError(msg);
  }
  final b = jsonDecode(res.body) as Map<String, dynamic>;
  return PairClaim(
    session: b,
    localUrl: (b['localUrl'] as String?) ?? base,
    remoteUrl: b['remoteUrl'] as String?,
  );
}
