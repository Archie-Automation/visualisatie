import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live stand van het KNX-alarm. Geen code, alleen wat de server meestuurt.
const knxAlarmSensorKinds = <String, String>{
  'magneetcontact': 'Deur- / raamcontact',
  'pir_beweging': 'Bewegingsmelder',
  'trilcontact': 'Trilcontact',
  'glasbreuk': 'Glasbreuk',
  'rookmelder': 'Rookmelder',
  'watermelder': 'Watermelder',
  'gasmelder': 'Gasdetector',
  'paniekknop': 'Paniekknop',
  'sabotage': 'Sabotagecontact',
};

String knxAlarmSensorKindLabel(String? kind) =>
    knxAlarmSensorKinds[kind] ?? 'Sensor';

class KnxAlarmSensorState {
  const KnxAlarmSensorState({
    required this.id,
    required this.name,
    required this.ga,
    required this.kind,
    required this.aanwezig,
    required this.afwezig,
    required this.inloop,
    required this.open,
    required this.bypassed,
  });

  final String id;
  final String name;
  final String ga;
  final String kind;
  final bool aanwezig;
  final bool afwezig;
  final bool inloop;
  final bool open;
  final bool bypassed;

  factory KnxAlarmSensorState.fromJson(Map<String, dynamic> j) {
    return KnxAlarmSensorState(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      ga: '${j['ga'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      aanwezig: j['aanwezig'] == true,
      afwezig: j['afwezig'] == true,
      inloop: j['inloop'] == true,
      open: j['open'] == true,
      bypassed: j['bypassed'] == true,
    );
  }
}

class KnxAlarmStatus {
  const KnxAlarmStatus({
    required this.enabled,
    required this.pinSet,
    required this.phase,
    required this.mode,
    required this.deadlineMs,
    required this.siren,
    required this.exitSeconds,
    required this.entrySeconds,
    required this.sensors,
  });

  final bool enabled;
  final bool pinSet;
  final String phase;
  final String? mode;
  final int? deadlineMs;
  final bool siren;
  final int exitSeconds;
  final int entrySeconds;
  final List<KnxAlarmSensorState> sensors;

  bool get isEntry => phase == 'entry';

  static const empty = KnxAlarmStatus(
    enabled: false,
    pinSet: false,
    phase: 'off',
    mode: null,
    deadlineMs: null,
    siren: false,
    exitSeconds: 30,
    entrySeconds: 30,
    sensors: [],
  );

  factory KnxAlarmStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['sensors'];
    final sensors = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => KnxAlarmSensorState.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <KnxAlarmSensorState>[];
    final deadline = j['deadlineMs'];
    final mode = j['mode'];
    return KnxAlarmStatus(
      enabled: j['enabled'] == true,
      pinSet: j['pinSet'] == true,
      phase: '${j['phase'] ?? 'off'}',
      mode: mode is String && mode.isNotEmpty ? mode : null,
      deadlineMs: deadline is num ? deadline.toInt() : null,
      siren: j['siren'] == true,
      exitSeconds: j['exitSeconds'] is num ? (j['exitSeconds'] as num).toInt() : 30,
      entrySeconds:
          j['entrySeconds'] is num ? (j['entrySeconds'] as num).toInt() : 30,
      sensors: sensors,
    );
  }
}

class KnxAlarmController extends Notifier<KnxAlarmStatus> {
  @override
  KnxAlarmStatus build() => KnxAlarmStatus.empty;

  void apply(Map<String, dynamic> json) {
    state = KnxAlarmStatus.fromJson(json);
  }
}

final knxAlarmStatusProvider =
    NotifierProvider<KnxAlarmController, KnxAlarmStatus>(KnxAlarmController.new);
