import 'models.dart';

/// Setpoint limits and step size — mirrors climate / AC device tiles.
class SetpointSpec {
  const SetpointSpec({
    required this.min,
    required this.max,
    required this.step,
  });

  final double min;
  final double max;
  final double step;

  int get decimals => step < 1 ? 1 : 0;

  double snap(num value) {
    final v = value.toDouble().clamp(min, max);
    if (step <= 0) return v;
    final n = ((v - min) / step).round();
    return double.parse((min + n * step).toStringAsFixed(decimals));
  }

  String format(double value) =>
      '${snap(value).toStringAsFixed(decimals)} °C';
}

SetpointSpec climateSetpointSpec(Device device) {
  final cfg = device.raw['climate'] as Map<String, dynamic>?;
  return SetpointSpec(
    min: (cfg?['minTemp'] as num?)?.toDouble() ?? 5.0,
    max: (cfg?['maxTemp'] as num?)?.toDouble() ?? 35.0,
    step: (cfg?['tempStep'] as num?)?.toDouble() ?? 0.5,
  );
}

SetpointSpec acSetpointSpec(Device device) {
  final sp = ((device.raw['ac'] as Map?)?['setpoint'] as Map?)
      ?.cast<String, dynamic>();
  return SetpointSpec(
    min: (sp?['min'] as num?)?.toDouble() ?? 16.0,
    max: (sp?['max'] as num?)?.toDouble() ?? 30.0,
    step: (sp?['step'] as num?)?.toDouble() ?? 0.5,
  );
}

/// Fan speed UI mode — same rules as [FanTile].
class FanSpeedSpec {
  const FanSpeedSpec({
    required this.mode,
    required this.steps,
    required this.max,
    this.stepLabels,
  });

  /// `steps`, `percent`, or `byte`.
  final String mode;
  final int steps;
  final int max;
  final List<String>? stepLabels;

  bool get isSteps => mode == 'steps';
  bool get isByte => mode == 'byte';
}

FanSpeedSpec fanSpeedSpec(Device device) {
  final cfg = device.raw['fan'] as Map<String, dynamic>?;
  final speedCfg = cfg?['speed'] as Map?;
  final mode = speedCfg?['speedMode'] as String? ??
      ((speedCfg?['steps'] != null) ? 'steps' : 'percent');
  final steps = (speedCfg?['steps'] as num?)?.toInt() ?? 3;
  final labels = (speedCfg?['stepLabels'] as List?)
      ?.map((e) => e?.toString() ?? '')
      .toList();
  final max = mode == 'steps'
      ? steps
      : mode == 'byte'
          ? 255
          : 100;
  return FanSpeedSpec(
    mode: mode,
    steps: steps,
    max: max,
    stepLabels: labels,
  );
}

/// Default 5-step flame mapping when no stepRanges / legacySteps are configured.
const kDefaultFlameStepPercents = [20, 40, 60, 80, 100];

int defaultFlameStepFromPercent(int pct) {
  for (var i = 0; i < kDefaultFlameStepPercents.length; i++) {
    if (pct <= kDefaultFlameStepPercents[i]) return kDefaultFlameStepPercents[i];
  }
  return kDefaultFlameStepPercents.last;
}

const kFanPercentLevels = [0, 25, 50, 75, 100];
const kFanByteLevels = [0, 64, 128, 192, 255];

int nearestFanLevel(int value, {required bool byteMode}) {
  final levels = byteMode ? kFanByteLevels : kFanPercentLevels;
  return levels.reduce(
    (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
  );
}
