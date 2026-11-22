import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

Future<Map<String, dynamic>?> fetchKnxAlarm(String? token) async {
  if (token == null || token.isEmpty) return null;
  try {
    final res = await http
        .get(
          Uri.parse('$apiBase/api/knx-alarm'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
  } catch (_) {}
  return null;
}

Future<({bool ok, String? message, Map<String, dynamic>? status})> _post(
  String path,
  Map<String, dynamic> body,
  String? token,
) async {
  if (token == null || token.isEmpty) {
    return (ok: false, message: 'Niet ingelogd.', status: null);
  }
  try {
    final res = await http
        .post(
          Uri.parse('$apiBase/api/knx-alarm/$path'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(res.body);
    final map = decoded is Map<String, dynamic> ? decoded : null;
    if (res.statusCode >= 200 && res.statusCode < 300 && map != null) {
      return (ok: true, message: null, status: map);
    }
    final message = map?['message'];
    return (
      ok: false,
      message: message is String && message.isNotEmpty ? message : 'Mislukt.',
      status: null,
    );
  } catch (_) {
    return (ok: false, message: 'Geen verbinding met de server.', status: null);
  }
}

Future<({bool ok, String? message, Map<String, dynamic>? status})> knxAlarmArm(
  String mode,
  String pin,
  String? token,
) =>
    _post('arm', {'mode': mode, 'pin': pin}, token);

Future<({bool ok, String? message, Map<String, dynamic>? status})> knxAlarmDisarm(
  String pin,
  String? token,
) =>
    _post('disarm', {'pin': pin}, token);

Future<({bool ok, String? message, Map<String, dynamic>? status})> knxAlarmBypass({
  required String id,
  required bool bypass,
  required String pin,
  required String? token,
}) =>
    _post('bypass', {'id': id, 'bypass': bypass, 'pin': pin}, token);
