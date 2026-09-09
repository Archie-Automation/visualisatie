import 'package:flutter_riverpod/flutter_riverpod.dart';

class WtwLogicActive {
  const WtwLogicActive({
    required this.deviceId,
    required this.logicId,
    required this.label,
    required this.standId,
    required this.end,
    this.untilMs,
    this.boostUntilMs,
  });

  final String deviceId;
  final String logicId;
  final String label;
  final String standId;
  final String end;
  final int? untilMs;
  final int? boostUntilMs;

  factory WtwLogicActive.fromJson(Map<String, dynamic> j) {
    int? asMs(Object? v) => v is num ? v.toInt() : null;
    return WtwLogicActive(
      deviceId: j['deviceId'] as String? ?? '',
      logicId: j['logicId'] as String? ?? '',
      label: (j['label'] as String? ?? '').trim(),
      standId: j['standId'] as String? ?? '',
      end: j['end'] as String? ?? 'duration',
      untilMs: asMs(j['untilMs']),
      boostUntilMs: asMs(j['boostUntilMs']),
    );
  }

  DateTime? get boostUntil {
    final ms = boostUntilMs ?? (standId == 'boost' ? untilMs : null);
    if (ms == null) return null;
    if (ms <= DateTime.now().millisecondsSinceEpoch) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

class WtwLogicStore extends Notifier<List<WtwLogicActive>> {
  @override
  List<WtwLogicActive> build() => const [];

  void snapshot(List<Map<String, dynamic>> raw) {
    state = [for (final e in raw) WtwLogicActive.fromJson(e)];
  }
}

extension WtwLogicActiveList on List<WtwLogicActive> {
  List<WtwLogicActive> forDevice(String id) =>
      [for (final r in this) if (r.deviceId == id) r];

  DateTime? boostUntilFor(String deviceId) {
    DateTime? best;
    for (final r in forDevice(deviceId)) {
      final t = r.boostUntil;
      if (t == null) continue;
      if (best == null || t.isAfter(best)) best = t;
    }
    return best;
  }

  bool boostActiveFor(String deviceId) =>
      forDevice(deviceId).any((r) => r.standId == 'boost');
}

final wtwLogicProvider =
    NotifierProvider<WtwLogicStore, List<WtwLogicActive>>(WtwLogicStore.new);
