import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOrderKey = 'system_order_v1';
const _kHiddenKey = 'system_hidden_v1';

// ---------------------------------------------------------------------------
//  Volgorde
// ---------------------------------------------------------------------------

class SystemOrderNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    Future.microtask(_restore);
    return const [];
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kOrderKey);
    if (raw == null) return;
    try {
      state = List<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
  }

  Future<void> reorder(List<String> names) async {
    state = names;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kOrderKey, jsonEncode(names));
  }
}

final systemOrderProvider =
    NotifierProvider<SystemOrderNotifier, List<String>>(
  SystemOrderNotifier.new,
);

// ---------------------------------------------------------------------------
//  Zichtbaarheid
// ---------------------------------------------------------------------------

class SystemHiddenNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    Future.microtask(_restore);
    return const {};
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kHiddenKey);
    if (raw == null) return;
    try {
      state = Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {}
  }

  Future<void> setHidden(Set<String> hidden) async {
    state = hidden;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kHiddenKey, jsonEncode(hidden.toList()));
  }

  bool isHidden(String name) => state.contains(name);
}

final systemHiddenProvider =
    NotifierProvider<SystemHiddenNotifier, Set<String>>(
  SystemHiddenNotifier.new,
);

// ---------------------------------------------------------------------------
//  Hulpfuncties
// ---------------------------------------------------------------------------

List<T> applySystemOrder<T>(
  List<String> order,
  List<T> chips,
  String Function(T) nameOf,
) {
  if (order.isEmpty) return chips;
  final byName = {for (final c in chips) nameOf(c): c};
  final result = <T>[];
  for (final name in order) {
    final c = byName[name];
    if (c != null) result.add(c);
  }
  for (final c in chips) {
    if (!result.contains(c)) result.add(c);
  }
  return result;
}
