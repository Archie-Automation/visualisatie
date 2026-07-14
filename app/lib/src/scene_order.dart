import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _kKey = 'scene_order_v1';

class SceneOrderNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    Future.microtask(_restore);
    return const [];
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) return;
    try {
      state = List<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
  }

  Future<void> reorder(List<String> sceneIds) async {
    state = sceneIds;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, jsonEncode(sceneIds));
  }
}

final sceneOrderProvider =
    NotifierProvider<SceneOrderNotifier, List<String>>(
  SceneOrderNotifier.new,
);

/// Returns [scenes] sorted by the user-defined [order] (scene IDs).
/// Unknown IDs in [order] are ignored; new scenes not yet in [order] are
/// appended at the end in their original relative order.
List<Scene> applySceneOrder(List<String> order, List<Scene> scenes) {
  if (order.isEmpty) return scenes;
  final byId = {for (final s in scenes) s.id: s};
  final result = <Scene>[];
  for (final id in order) {
    final s = byId[id];
    if (s != null) result.add(s);
  }
  for (final s in scenes) {
    if (!result.contains(s)) result.add(s);
  }
  return result;
}
