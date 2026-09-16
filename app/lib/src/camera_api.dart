import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// ----------------------------- Cameras -------------------------------
/// Passive, view-only. No microphone. Ever.

class CameraInfo {
  final String id;
  final String name;
  final String aspect;
  final String hlsUrl;
  final String webrtcUrl;
  final String whepUrl;
  final String snapshotUrl;

  const CameraInfo({
    required this.id,
    required this.name,
    required this.aspect,
    required this.hlsUrl,
    required this.webrtcUrl,
    required this.whepUrl,
    required this.snapshotUrl,
  });

  double get aspectRatio {
    final p = aspect.split(':');
    if (p.length != 2) return 16 / 9;
    final w = double.tryParse(p[0]) ?? 16;
    final h = double.tryParse(p[1]) ?? 9;
    if (h == 0) return 16 / 9;
    return w / h;
  }

  factory CameraInfo.fromJson(Map<String, dynamic> j) => CameraInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        aspect: (j['aspect'] as String?) ?? '16:9',
        hlsUrl: (j['hls'] as String?) ?? '',
        webrtcUrl: (j['webrtc'] as String?) ?? '',
        whepUrl: (j['whep'] as String?) ?? '',
        snapshotUrl: (j['snapshot'] as String?) ?? '',
      );
}

final cameraInfoProvider =
    FutureProvider.family<CameraInfo, String>((ref, id) async {
  ref.keepAlive();
  final isAuthed = ref.watch(authProvider.select((a) => a.isAuthed));
  if (!isAuthed) throw StateError('not authenticated');
  final token = ref.read(authProvider).token;
  final res = await http.get(
    Uri.parse('$apiBase/api/cameras/$id'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('camera fetch failed: ${res.statusCode}');
  }
  return CameraInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
});

/// Pre-warm go2rtc live producer before WebRTC connect (Synology SS cold-start).
Future<bool> warmCameraStream({
  required String cameraId,
  required String? token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/cameras/$cameraId/warm'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return false;
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  return j['warmed'] == true;
}

Future<bool> warmIntercomStream({
  required String intercomId,
  required String? token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/intercoms/$intercomId/warm'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) return false;
  final j = jsonDecode(res.body) as Map<String, dynamic>;
  return j['warmed'] == true;
}

/// ---------------------------- Intercoms -------------------------------
/// WebRTC with talk, optional door release.

class IntercomInfo {
  final String id;
  final String name;
  final String aspect;
  final String webrtcUrl;
  final String snapshotUrl;
  final bool canRelease;

  const IntercomInfo({
    required this.id,
    required this.name,
    required this.aspect,
    required this.webrtcUrl,
    required this.snapshotUrl,
    required this.canRelease,
  });

  double get aspectRatio {
    final p = aspect.split(':');
    if (p.length != 2) return 4 / 3;
    final w = double.tryParse(p[0]) ?? 4;
    final h = double.tryParse(p[1]) ?? 3;
    if (h == 0) return 4 / 3;
    return w / h;
  }

  factory IntercomInfo.fromJson(Map<String, dynamic> j) => IntercomInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        aspect: (j['aspect'] as String?) ?? '4:3',
        webrtcUrl: (j['webrtc'] as String?) ?? '',
        snapshotUrl: (j['snapshot'] as String?) ?? '',
        canRelease: (j['canRelease'] as bool?) ?? false,
      );
}

final intercomInfoProvider =
    FutureProvider.family<IntercomInfo, String>((ref, id) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) throw StateError('not authenticated');
  final res = await http.get(
    Uri.parse('$apiBase/api/intercoms/$id'),
    headers: {'authorization': 'Bearer ${auth.token}'},
  );
  if (res.statusCode != 200) {
    throw StateError('intercom fetch failed: ${res.statusCode}');
  }
  return IntercomInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
});

class IntercomCapture {
  final String id;
  final String intercomId;
  final String name;
  final int ts;
  final String source;

  const IntercomCapture({
    required this.id,
    required this.intercomId,
    required this.name,
    required this.ts,
    required this.source,
  });

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(ts);

  String get imageUrl => '$apiBase/api/intercoms/$intercomId/captures/$id';

  factory IntercomCapture.fromJson(Map<String, dynamic> j) => IntercomCapture(
        id: j['id'] as String,
        intercomId: j['intercomId'] as String,
        name: (j['name'] as String?) ?? '',
        ts: (j['ts'] as num).toInt(),
        source: (j['source'] as String?) ?? 'manual',
      );
}

final intercomCapturesProvider =
    FutureProvider.family<List<IntercomCapture>, String>((ref, id) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) throw StateError('not authenticated');
  final res = await http.get(
    Uri.parse('$apiBase/api/intercoms/$id/captures'),
    headers: {'authorization': 'Bearer ${auth.token}'},
  );
  if (res.statusCode != 200) {
    throw StateError('captures fetch failed: ${res.statusCode}');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = (body['captures'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map(IntercomCapture.fromJson)
      .toList();
  return list;
});

Future<IntercomCapture> takeIntercomCapture({
  required String intercomId,
  required String? token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/intercoms/$intercomId/captures'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('capture failed: ${res.statusCode}');
  }
  return IntercomCapture.fromJson(
    jsonDecode(res.body) as Map<String, dynamic>,
  );
}

Future<Uint8List> fetchIntercomCaptureJpeg({
  required String url,
  required String? token,
}) async {
  final res = await http.get(
    Uri.parse(url),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('capture image failed: ${res.statusCode}');
  }
  return res.bodyBytes;
}

/// Fires a door release on the server (KNX pulse).
Future<void> releaseIntercomDoor({
  required String intercomId,
  required String? token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/intercoms/$intercomId/release'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('release failed: ${res.statusCode}');
  }
}

/// Haalt de volledige SIP-configuratie op (inclusief wachtwoord) van de server.
/// Wordt gebruikt voor startup-registratie zodat de app inkomende SIP-oproepen
/// ontvangt ook als het intercom-scherm niet open is.
/// Geeft `null` terug als er geen SIP-config is voor dit intercom.
Future<Map<String, dynamic>?> fetchIntercomSipConfig({
  required String intercomId,
  required String token,
}) async {
  try {
    final res = await http.get(
      Uri.parse('$apiBase/api/intercoms/$intercomId/sip'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return null;
    final body = _deepCastMap(jsonDecode(res.body) as Map);
    return body['sip'] as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
}

/// SIP-inlog van de ingelogde gebruiker op de eigen PBX.
Future<Map<String, dynamic>?> fetchVoipMe({required String token}) async {
  try {
    final res = await http.get(
      Uri.parse('$apiBase/api/voip/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return null;
    return _deepCastMap(jsonDecode(res.body) as Map);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _deepCastMap(Map raw) =>
    raw.map((k, v) => MapEntry(k as String, _deepCastValue(v)));

dynamic _deepCastValue(dynamic v) {
  if (v is Map) return _deepCastMap(v);
  if (v is List) return v.map(_deepCastValue).toList();
  return v;
}
