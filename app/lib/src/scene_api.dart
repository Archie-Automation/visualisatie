import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';

/// Fire-and-forget: ask the backend to execute a scene by id.
Future<void> runScene({
  required String sceneId,
  required String token,
}) async {
  final res = await http.post(
    Uri.parse('$apiBase/api/scenes/$sceneId/run'),
    headers: {'authorization': 'Bearer $token'},
  );
  if (res.statusCode != 200) {
    throw Exception('scene run failed: ${res.statusCode} ${res.body}');
  }
}

/// Persist the global (house-wide) scene list.
Future<void> saveGlobalScenes({
  required List<Scene> scenes,
  required String token,
}) async {
  final res = await http.put(
    Uri.parse('$apiBase/api/scenes'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode({'scenes': scenes.map((s) => s.toJson()).toList()}),
  );
  if (res.statusCode != 200) {
    throw Exception('scene save failed: ${res.statusCode} ${res.body}');
  }
}

/// Persist the scene list of a single room.
Future<void> saveRoomScenes({
  required String roomId,
  required List<Scene> scenes,
  required String token,
}) async {
  final res = await http.put(
    Uri.parse('$apiBase/api/rooms/$roomId/scenes'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode({'scenes': scenes.map((s) => s.toJson()).toList()}),
  );
  if (res.statusCode != 200) {
    throw Exception('scene save failed: ${res.statusCode} ${res.body}');
  }
}

/// Non-auth provider we use purely for invocation context. The UI imports
/// [runScene] directly through consumer widgets in most cases – this is here
/// so widgets can read the current auth token without deep-chaining.
final sceneApiProvider = Provider<_SceneApi>((ref) => _SceneApi(ref));

class _SceneApi {
  _SceneApi(this._ref);
  final Ref _ref;

  Future<void> run(String sceneId) => runScene(
        sceneId: sceneId,
        token: _ref.read(authProvider).token ?? '',
      );

  Future<void> saveGlobal(List<Scene> scenes) => saveGlobalScenes(
        scenes: scenes,
        token: _ref.read(authProvider).token ?? '',
      );

  Future<void> saveRoom(String roomId, List<Scene> scenes) => saveRoomScenes(
        roomId: roomId,
        scenes: scenes,
        token: _ref.read(authProvider).token ?? '',
      );
}
