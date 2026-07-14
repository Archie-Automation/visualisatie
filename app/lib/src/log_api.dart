import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// ------------------------------- Logs --------------------------------
/// Server-side time-series of KNX group-address values, rendered as graphs.
/// Thermostats get an automatic log (measured + setpoint); installers can
/// define custom logs of arbitrary group addresses.

/// One series descriptor as returned by `GET /api/logs`.
class LogSeriesInfo {
  final String ga;
  final String label;
  final String? unit;
  final String? role;
  const LogSeriesInfo({
    required this.ga,
    required this.label,
    this.unit,
    this.role,
  });

  factory LogSeriesInfo.fromJson(Map<String, dynamic> j) => LogSeriesInfo(
        ga: j['ga'] as String,
        label: (j['label'] as String?) ?? (j['ga'] as String),
        unit: j['unit'] as String?,
        role: j['role'] as String?,
      );
}

/// A log available on the server.
class LogInfo {
  final String id;
  final String name;
  final String kind; // 'thermostat' | 'custom'
  final List<LogSeriesInfo> series;
  const LogInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.series,
  });

  factory LogInfo.fromJson(Map<String, dynamic> j) => LogInfo(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? (j['id'] as String),
        kind: (j['kind'] as String?) ?? 'custom',
        series: ((j['series'] as List?) ?? const [])
            .map((e) => LogSeriesInfo.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// A single recorded data point.
class LogPoint {
  final int ts; // epoch ms
  final double value;
  const LogPoint(this.ts, this.value);
}

/// A series with its recorded points for a time window.
class LogSeriesData {
  final String ga;
  final String label;
  final String? unit;
  final String? role;
  final List<LogPoint> points;
  const LogSeriesData({
    required this.ga,
    required this.label,
    this.unit,
    this.role,
    required this.points,
  });

  factory LogSeriesData.fromJson(Map<String, dynamic> j) => LogSeriesData(
        ga: j['ga'] as String,
        label: (j['label'] as String?) ?? (j['ga'] as String),
        unit: j['unit'] as String?,
        role: j['role'] as String?,
        points: ((j['points'] as List?) ?? const [])
            .map((p) => LogPoint(
                  (p[0] as num).toInt(),
                  (p[1] as num).toDouble(),
                ))
            .toList(),
      );
}

/// History payload for one log over [fromMs, toMs].
class LogData {
  final String id;
  final String name;
  final String kind;
  final int fromMs;
  final int toMs;
  final List<LogSeriesData> series;
  const LogData({
    required this.id,
    required this.name,
    required this.kind,
    required this.fromMs,
    required this.toMs,
    required this.series,
  });

  factory LogData.fromJson(Map<String, dynamic> j) => LogData(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? (j['id'] as String),
        kind: (j['kind'] as String?) ?? 'custom',
        fromMs: (j['from'] as num).toInt(),
        toMs: (j['to'] as num).toInt(),
        series: ((j['series'] as List?) ?? const [])
            .map((e) =>
                LogSeriesData.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Query key for [logHistoryProvider]. Records give value-equality so Riverpod
/// caches/refetches correctly as the window changes.
typedef LogQuery = ({String id, int fromMs, int toMs, int maxPoints});

/// List of all logs available on the server.
final logsListProvider = FutureProvider<List<LogInfo>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) throw StateError('not authenticated');
  final res = await http.get(
    Uri.parse('$apiBase/api/logs'),
    headers: {'authorization': 'Bearer ${auth.token}'},
  );
  if (res.statusCode != 200) {
    throw StateError('logs fetch failed: ${res.statusCode}');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return ((body['logs'] as List?) ?? const [])
      .map((e) => LogInfo.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
});

/// Historical, downsampled series for one log over a time window.
final logHistoryProvider =
    FutureProvider.family<LogData, LogQuery>((ref, q) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) throw StateError('not authenticated');
  final uri = Uri.parse(
    '$apiBase/api/logs/${Uri.encodeComponent(q.id)}/history'
    '?from=${q.fromMs}&to=${q.toMs}&maxPoints=${q.maxPoints}',
  );
  final res = await http.get(
    uri,
    headers: {'authorization': 'Bearer ${auth.token}'},
  );
  if (res.statusCode != 200) {
    throw StateError('log history fetch failed: ${res.statusCode}');
  }
  return LogData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
});
