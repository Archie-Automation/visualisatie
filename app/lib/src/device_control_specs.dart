import 'models.dart';

/// Setpoint limits and step size — mirrors climate / AC device tiles.
class SetpointSpec {
  const SetpointSpec({
    required this.min,
    required this.max,
    required this.step,
    this.relative = false,
  });

  final double min;
  final double max;
  final double step;

  /// Relatieve setpointverschuiving (K) in plaats van een absolute temperatuur.
  final bool relative;

  bool get signed => relative;

  /// Tile suffix. Absoluut blijft `°`, relatief is ` K`.
  String get tileSuffix => relative ? ' K' : '°';

  int get decimals => step < 1 ? 1 : 0;

  /// Waarde als de bus nog niets heeft teruggemeld.
  double get fallback => relative ? 0.0 : 21.0;

  double snap(num value) {
    final v = value.toDouble().clamp(min, max);
    if (step <= 0) return v;
    final n = ((v - min) / step).round();
    return double.parse((min + n * step).toStringAsFixed(decimals));
  }

  /// Grote cijfers op de tegel, zonder extra afronden naar de stap.
  String tileText(double value) => _text(value, tileSuffix);

  /// Scène-schuif: waarde op de stap, met eenheid.
  String format(double value) =>
      _text(snap(value), relative ? ' K' : ' °C');

  String _text(double value, String suffix) {
    var body = value.toStringAsFixed(decimals);
    final parsed = double.tryParse(body);
    if (parsed != null && parsed == 0 && body.startsWith('-')) {
      body = body.substring(1);
    }
    final magnitude = parsed ?? value;
    final shown = signed && magnitude > 0 ? '+$body' : body;
    return '$shown$suffix';
  }
}

/// `absolute`, `relative_6.010` of `relative_9.002`. Onbekend = absoluut.
String climateSetpointControl(Map<String, dynamic>? cfg) {
  final v = cfg?['setpointControl'] as String?;
  if (v == 'relative_6.010' || v == 'relative_9.002') return v!;
  return 'absolute';
}

SetpointSpec climateSetpointSpec(Device device) {
  final cfg = device.raw['climate'] as Map<String, dynamic>?;
  return climateSetpointSpecFromConfig(cfg);
}

SetpointSpec climateSetpointSpecFromConfig(Map<String, dynamic>? cfg) {
  final step = (cfg?['tempStep'] as num?)?.toDouble() ?? 0.5;
  final control = climateSetpointControl(cfg);
  if (control == 'absolute') {
    final min = (cfg?['minTemp'] as num?)?.toDouble() ?? 5.0;
    final max = (cfg?['maxTemp'] as num?)?.toDouble() ?? 35.0;
    if (min < max) {
      return SetpointSpec(min: min, max: max, step: step);
    }
    return SetpointSpec(min: 5, max: 35, step: step);
  }
  final hardMin = control == 'relative_6.010' ? -12.8 : -50.0;
  final hardMax = control == 'relative_6.010' ? 12.7 : 50.0;
  var min = (cfg?['minTemp'] as num?)?.toDouble() ?? -5.0;
  var max = (cfg?['maxTemp'] as num?)?.toDouble() ?? 5.0;
  if (!(min < max)) {
    min = -5;
    max = 5;
  }
  min = min.clamp(hardMin, hardMax).toDouble();
  max = max.clamp(hardMin, hardMax).toDouble();
  if (!(min < max)) {
    return SetpointSpec(
      min: hardMin,
      max: hardMax,
      step: step,
      relative: true,
    );
  }
  return SetpointSpec(min: min, max: max, step: step, relative: true);
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
