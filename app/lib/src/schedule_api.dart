import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';

/// Read the list of schedules from the backend.
Future<List<Schedule>> fetchSchedules({required String token}) async {
  final res = await http.get(
    Uri.parse('$apiBase/api/schedules'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('fetch schedules failed: ${res.statusCode} ${res.body}');
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  return ((data['schedules'] as List?) ?? const [])
      .map((s) => Schedule.fromJson(s as Map<String, dynamic>))
      .toList();
}

/// Replace the full schedule list on the backend.
Future<void> saveSchedules({
  required List<Schedule> schedules,
  required String token,
}) async {
  final res = await http.put(
    Uri.parse('$apiBase/api/schedules'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body:
        jsonEncode({'schedules': schedules.map((s) => s.toJson()).toList()}),
  );
  if (res.statusCode != 200) {
    throw Exception('save schedules failed: ${res.statusCode} ${res.body}');
  }
}

/// Ask the backend to run a single schedule right now, ignoring its trigger.
Future<void> runScheduleNow({
  required String id,
  required String token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/schedules/$id/run'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('schedule run failed: ${res.statusCode} ${res.body}');
  }
}

/// Fetches the current schedule list and caches it. The editor invalidates
/// this after every save so the list re-fetches.
final schedulesProvider = FutureProvider<List<Schedule>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) return const [];
  return fetchSchedules(token: auth.token!);
});

final scheduleApiProvider = Provider<_ScheduleApi>((ref) => _ScheduleApi(ref));

class _ScheduleApi {
  _ScheduleApi(this._ref);
  final Ref _ref;

  String get _token => _ref.read(authProvider).token ?? '';

  Future<void> save(List<Schedule> schedules) =>
      saveSchedules(schedules: schedules, token: _token);

  Future<void> runNow(String id) => runScheduleNow(id: id, token: _token);
}
