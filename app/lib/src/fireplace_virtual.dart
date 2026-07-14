import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Server-gesynchroniseerde aan/uit voor discrete openhaarden (virtueel).
class FireplaceVirtualStore extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void snapshot(List<Map<String, dynamic>> entries) {
    state = {
      for (final e in entries)
        e['deviceId'] as String: e['on'] as bool,
    };
  }

  void apply(String deviceId, bool on) {
    state = {...state, deviceId: on};
  }

  /// Aan/uit voor discrete haard: server-state heeft voorrang, anders bus.
  static bool resolveOn({
    required bool discreteMode,
    required Map<String, bool> virtual,
    required String deviceId,
    required bool busOn,
  }) {
    if (!discreteMode) return busOn;
    return virtual[deviceId] ?? busOn;
  }
}

final fireplaceVirtualProvider =
    NotifierProvider<FireplaceVirtualStore, Map<String, bool>>(
  FireplaceVirtualStore.new,
);
