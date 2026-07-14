import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api.dart' show apiBase;

Future<Map<String, dynamic>> fetchInstallerHouse(String token) async {
  final res = await http.get(
    Uri.parse('$apiBase/api/installer/house'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('Installateur-config ophalen mislukt (${res.statusCode})');
  }
  // Deep-cast ensures all nested Maps are Map<String, dynamic>, not
  // Map<String, String> — the Flutter web DDC runtime can narrow the type
  // when all values in a JSON object happen to be strings, which causes
  // runtime type errors when we later write non-string values.
  return _deepCastMap(jsonDecode(res.body) as Map);
}

Map<String, dynamic> _deepCastMap(Map raw) {
  return raw.map((k, v) => MapEntry(k as String, _deepCastValue(v)));
}

dynamic _deepCastValue(dynamic v) {
  if (v is Map) return _deepCastMap(v);
  if (v is List) return v.map(_deepCastValue).toList();
  return v;
}

Future<int> putInstallerHouse(String token, Map<String, dynamic> house) async {
  final res = await http.put(
    Uri.parse('$apiBase/api/installer/house'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode(house),
  );
  if (res.statusCode != 200) {
    final body =
        res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
    final err = body['error'] as String?;
    final issues = body['issues'];
    if (issues is List) {
      throw StateError('Validatiefout:\n${issues.join('\n')}');
    }
    throw StateError(err ?? 'Opslaan mislukt (${res.statusCode})');
  }
  final out = jsonDecode(res.body) as Map<String, dynamic>;
  return (out['version'] as num?)?.toInt() ?? 0;
}

/// Live KNX tunnel state from the backend (installer only).
class InstallerKnxStatus {
  const InstallerKnxStatus({
    required this.connected,
    required this.simulate,
    required this.host,
    required this.port,
  });

  final bool connected;
  final bool simulate;
  final String host;
  final int port;

  factory InstallerKnxStatus.fromJson(Map<String, dynamic> j) {
    return InstallerKnxStatus(
      connected: j['connected'] == true,
      simulate: j['simulate'] == true,
      host: j['host'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 3671,
    );
  }
}

Future<InstallerKnxStatus> fetchInstallerKnxStatus(String token) async {
  final res = await http.get(
    Uri.parse('$apiBase/api/installer/knx-status'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('KNX-status ophalen mislukt (${res.statusCode})');
  }
  return InstallerKnxStatus.fromJson(
    jsonDecode(res.body) as Map<String, dynamic>,
  );
}

class InstallerLutronStatus {
  const InstallerLutronStatus({
    required this.connected,
    required this.loggedIn,
    required this.host,
    required this.port,
    this.lastError,
  });

  final bool connected;
  final bool loggedIn;
  final String host;
  final int port;
  final String? lastError;

  factory InstallerLutronStatus.fromJson(Map<String, dynamic> j) {
    return InstallerLutronStatus(
      connected: j['connected'] == true,
      loggedIn: j['loggedIn'] == true,
      host: j['host'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 23,
      lastError: j['lastError'] as String?,
    );
  }
}

Future<InstallerLutronStatus> fetchInstallerLutronStatus(String token) async {
  final res = await http.get(
    Uri.parse('$apiBase/api/installer/lutron-status'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw StateError('Lutron-status ophalen mislukt (${res.statusCode})');
  }
  return InstallerLutronStatus.fromJson(
    jsonDecode(res.body) as Map<String, dynamic>,
  );
}

Future<InstallerLutronStatus> postInstallerLutronReconnect(String token) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/installer/lutron-reconnect'),
    headers: {'authorization': 'Bearer $token'},
  );
  final dynamic raw =
      res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
  final body = Map<String, dynamic>.from(raw as Map);
  if (res.statusCode != 200) {
    throw StateError(body['error'] as String? ?? 'Opnieuw verbinden mislukt');
  }
  return InstallerLutronStatus.fromJson(body);
}

Future<InstallerKnxStatus> postInstallerKnxReconnect(String token) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/installer/knx-reconnect'),
    headers: {'authorization': 'Bearer $token'},
  );
  final dynamic raw =
      res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
  final body = Map<String, dynamic>.from(raw as Map);
  if (res.statusCode != 200) {
    final err = body['error'] as String? ?? 'Opnieuw verbinden mislukt';
    throw StateError(err);
  }
  return InstallerKnxStatus.fromJson(body);
}

class InstallerSonosProbeResult {
  const InstallerSonosProbeResult({
    required this.ok,
    this.zoneName,
    this.state,
    this.error,
  });

  final bool ok;
  final String? zoneName;
  final String? state;
  final String? error;
}

Future<InstallerSonosProbeResult> postInstallerSonosProbe(
  String token, {
  required String host,
  int port = 1400,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/installer/sonos-probe'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode({'host': host, 'port': port}),
  );
  if (res.statusCode != 200) {
    throw StateError('Sonos-test mislukt (HTTP ${res.statusCode})');
  }
  final raw =
      res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
  final body = Map<String, dynamic>.from(raw as Map);
  return InstallerSonosProbeResult(
    ok: body['ok'] == true,
    zoneName: body['zoneName'] as String?,
    state: body['state'] as String?,
    error: body['error'] as String?,
  );
}

class InstallerCameraProbeResult {
  const InstallerCameraProbeResult({
    required this.ok,
    required this.role,
    required this.latencyMs,
    required this.profileLabel,
    this.width,
    this.height,
    this.error,
  });

  final bool ok;
  final String role;
  final int latencyMs;
  final String profileLabel;
  final int? width;
  final int? height;
  final String? error;

  factory InstallerCameraProbeResult.fromJson(Map<String, dynamic> j) {
    return InstallerCameraProbeResult(
      ok: j['ok'] == true,
      role: j['role'] as String? ?? 'live',
      latencyMs: (j['latencyMs'] as num?)?.toInt() ?? 0,
      profileLabel: j['profileLabel'] as String? ?? '',
      width: (j['width'] as num?)?.toInt(),
      height: (j['height'] as num?)?.toInt(),
      error: j['error'] as String?,
    );
  }
}

class InstallerCameraProbeSummary {
  const InstallerCameraProbeSummary({
    required this.live,
    required this.recommended,
    this.preview,
  });

  final InstallerCameraProbeResult live;
  final InstallerCameraProbeResult? preview;
  final InstallerCameraProbeRecommended recommended;

  factory InstallerCameraProbeSummary.fromJson(Map<String, dynamic> j) {
    final rec = j['recommended'] as Map<String, dynamic>? ?? {};
    return InstallerCameraProbeSummary(
      live: InstallerCameraProbeResult.fromJson(
        Map<String, dynamic>.from(j['live'] as Map? ?? {}),
      ),
      preview: j['preview'] != null
          ? InstallerCameraProbeResult.fromJson(
              Map<String, dynamic>.from(j['preview'] as Map),
            )
          : null,
      recommended: InstallerCameraProbeRecommended.fromJson(rec),
    );
  }
}

class InstallerCameraProbeRecommended {
  const InstallerCameraProbeRecommended({
    required this.go2rtcFfmpeg,
    required this.go2rtcVideoOnly,
  });

  final bool go2rtcFfmpeg;
  final bool go2rtcVideoOnly;

  factory InstallerCameraProbeRecommended.fromJson(Map<String, dynamic> j) {
    return InstallerCameraProbeRecommended(
      go2rtcFfmpeg: j['go2rtcFfmpeg'] == true,
      go2rtcVideoOnly: j['go2rtcVideoOnly'] != false,
    );
  }
}

Future<InstallerCameraProbeSummary> postInstallerCameraProbe(
  String token, {
  required String rtsp,
  String previewRtsp = '',
  String codec = '',
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/installer/camera-probe'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'rtsp': rtsp,
      if (previewRtsp.isNotEmpty) 'previewRtsp': previewRtsp,
      if (codec.isNotEmpty) 'codec': codec,
    }),
  );
  if (res.statusCode != 200) {
    throw StateError('Camera-test mislukt (HTTP ${res.statusCode})');
  }
  return InstallerCameraProbeSummary.fromJson(
    Map<String, dynamic>.from(jsonDecode(res.body) as Map),
  );
}
