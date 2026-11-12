import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Laatste bekende stand van een QSX-zone. Blijft staan als je de kamer verlaat.
class LutronZoneLive {
  const LutronZoneLive({
    required this.id,
    required this.level,
    required this.recall,
    this.hue,
    this.saturation,
    this.kelvin,
  });

  final int id;
  final double level;
  final double recall;
  final double? hue;
  final double? saturation;
  final double? kelvin;

  factory LutronZoneLive.fromJson(Map<String, dynamic> j) {
    final level = (j['level'] as num?)?.toDouble() ?? 0;
    final recallRaw = (j['recall'] as num?)?.toDouble();
    return LutronZoneLive(
      id: (j['id'] as num).toInt(),
      level: level.clamp(0, 100),
      recall: (recallRaw ?? (level > 0 ? level : 0)).clamp(0, 100),
      hue: (j['hue'] as num?)?.toDouble(),
      saturation: (j['saturation'] as num?)?.toDouble(),
      kelvin: (j['kelvin'] as num?)?.toDouble(),
    );
  }
}

class LutronZoneController extends Notifier<Map<int, LutronZoneLive>> {
  @override
  Map<int, LutronZoneLive> build() => const {};

  void note({
    required int id,
    required num level,
    double? hue,
    double? saturation,
    double? kelvin,
  }) {
    final prev = state[id];
    final lv = level.toDouble().clamp(0, 100).toDouble();
    state = {
      ...state,
      id: LutronZoneLive(
        id: id,
        level: lv,
        recall: lv > 0 ? lv : (prev?.recall ?? 0),
        hue: hue ?? prev?.hue,
        saturation: saturation ?? prev?.saturation,
        kelvin: kelvin ?? prev?.kelvin,
      ),
    };
  }

  void applyJson(Map<String, dynamic> j) {
    final live = LutronZoneLive.fromJson(j);
    final prev = state[live.id];
    state = {
      ...state,
      live.id: LutronZoneLive(
        id: live.id,
        level: live.level,
        recall: live.level > 0
            ? live.level
            : (live.recall > 0 ? live.recall : (prev?.recall ?? 0)),
        hue: live.hue ?? prev?.hue,
        saturation: live.saturation ?? prev?.saturation,
        kelvin: live.kelvin ?? prev?.kelvin,
      ),
    };
  }

  void replaceAll(List<dynamic> rows) {
    final next = <int, LutronZoneLive>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final live = LutronZoneLive.fromJson(Map<String, dynamic>.from(row));
      final prev = state[live.id];
      next[live.id] = LutronZoneLive(
        id: live.id,
        level: live.level,
        recall: live.level > 0
            ? live.level
            : (live.recall > 0 ? live.recall : (prev?.recall ?? 0)),
        hue: live.hue ?? prev?.hue,
        saturation: live.saturation ?? prev?.saturation,
        kelvin: live.kelvin ?? prev?.kelvin,
      );
    }
    state = next;
  }
}

final lutronZoneProvider =
    NotifierProvider<LutronZoneController, Map<int, LutronZoneLive>>(
  LutronZoneController.new,
);
