import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

Future<List<Map<String, dynamic>>> fetchHouseUsers({required String token}) async {
  final res = await http.get(
    Uri.parse('$apiBase/api/users'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('gebruikers ophalen mislukt: ${res.statusCode} ${res.body}');
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  return ((data['users'] as List?) ?? const [])
      .map((u) => Map<String, dynamic>.from(u as Map))
      .toList();
}

Future<List<Map<String, dynamic>>> saveHouseUsers({
  required List<Map<String, dynamic>> users,
  required String token,
}) async {
  final res = await http.put(
    Uri.parse('$apiBase/api/users'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode({'users': users}),
  );
  if (res.statusCode != 200) {
    String msg = 'opslaan mislukt (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] != null) msg = body['error'].toString();
    } catch (_) {}
    throw Exception(msg);
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  return ((data['users'] as List?) ?? const [])
      .map((u) => Map<String, dynamic>.from(u as Map))
      .toList();
}
