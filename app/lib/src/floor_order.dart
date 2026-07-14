import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _kKey = 'floor_order_v1';

class FloorOrderNotifier extends Notifier<List<String>> {
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

  Future<void> reorder(List<String> floorIds) async {
    state = floorIds;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, jsonEncode(floorIds));
  }
}

final floorOrderProvider =
    NotifierProvider<FloorOrderNotifier, List<String>>(
  FloorOrderNotifier.new,
);

List<Floor> applyFloorOrder(List<String> order, List<Floor> floors) {
  if (order.isEmpty) return floors;
  final byId = {for (final f in floors) f.id: f};
  final result = <Floor>[];
  for (final id in order) {
    final f = byId[id];
    if (f != null) result.add(f);
  }
  for (final f in floors) {
    if (!result.contains(f)) result.add(f);
  }
  return result;
}
