import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

/// Een gekoppeld apparaat (refresh-sessie) op de server.
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.userId,
    required this.username,
    required this.device,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
  });
  final String id;
  final String userId;
  final String username;
  final String device;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime expiresAt;

  static DeviceSession fromJson(Map<String, dynamic> j) {
    DateTime d(String k) =>
        DateTime.tryParse((j[k] as String?) ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return DeviceSession(
      id: (j['id'] as String?) ?? '',
      userId: (j['userId'] as String?) ?? '',
      username: (j['username'] as String?) ?? '',
      device: (j['device'] as String?) ?? '',
      createdAt: d('createdAt'),
      lastUsedAt: d('lastUsedAt'),
      expiresAt: d('expiresAt'),
    );
  }
}

/// Eigen apparaten; staff kan met [userId] die van een ander opvragen.
Future<List<DeviceSession>> fetchDeviceSessions({
  required String token,
  String? userId,
}) async {
  final uri = Uri.parse('$apiBase/api/auth/sessions').replace(
    queryParameters: {if (userId != null) 'userId': userId},
  );
  final res = await http
      .get(uri, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    throw StateError('apparaten ophalen mislukt (${res.statusCode})');
  }
  final b = jsonDecode(res.body) as Map<String, dynamic>;
  return ((b['sessions'] as List?) ?? const [])
      .map((e) => DeviceSession.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList()
    ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
}

Future<bool> revokeDeviceSession({
  required String token,
  required String id,
}) async {
  final res = await http
      .delete(
        Uri.parse('$apiBase/api/auth/sessions/$id'),
        headers: {'authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 8));
  return res.statusCode == 200;
}
