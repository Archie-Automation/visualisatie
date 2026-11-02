import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Server-computed live energy view. The client does not sum the bus.
class EnergySnapshot {
  const EnergySnapshot({
    this.enabled = false,
    this.stale = false,
    this.gridPowerW,
    this.solarPowerW,
    this.batteryPowerW,
    this.batterySoc,
    this.housePowerW,
    this.importEnergyKwh,
    this.exportEnergyKwh,
    this.solarEnergyKwh,
    this.gasM3,
  });

  final bool enabled;
  final bool stale;
  final double? gridPowerW;
  final double? solarPowerW;
  final double? batteryPowerW;
  final double? batterySoc;
  final double? housePowerW;
  final double? importEnergyKwh;
  final double? exportEnergyKwh;
  final double? solarEnergyKwh;
  final double? gasM3;

  bool get hasAnyValue =>
      gridPowerW != null ||
      solarPowerW != null ||
      batteryPowerW != null ||
      batterySoc != null ||
      housePowerW != null ||
      importEnergyKwh != null ||
      exportEnergyKwh != null ||
      solarEnergyKwh != null ||
      gasM3 != null;

  factory EnergySnapshot.fromJson(Map<String, dynamic> j) => EnergySnapshot(
        enabled: j['enabled'] == true,
        stale: j['stale'] == true,
        gridPowerW: _num(j['gridPowerW']),
        solarPowerW: _num(j['solarPowerW']),
        batteryPowerW: _num(j['batteryPowerW']),
        batterySoc: _num(j['batterySoc']),
        housePowerW: _num(j['housePowerW']),
        importEnergyKwh: _num(j['importEnergyKwh']),
        exportEnergyKwh: _num(j['exportEnergyKwh']),
        solarEnergyKwh: _num(j['solarEnergyKwh']),
        gasM3: _num(j['gasM3']),
      );

  static double? _num(Object? v) {
    if (v is num && v.isFinite) return v.toDouble();
    return null;
  }
}

class EnergyController extends Notifier<EnergySnapshot> {
  @override
  EnergySnapshot build() => const EnergySnapshot();

  void apply(Map<String, dynamic> json) {
    state = EnergySnapshot.fromJson(json);
  }

  void show(EnergySnapshot snapshot) {
    state = snapshot;
  }

  void clear() {
    state = const EnergySnapshot();
  }
}

final energyStateProvider =
    NotifierProvider<EnergyController, EnergySnapshot>(EnergyController.new);

String formatPower(double watts) {
  final negative = watts < 0;
  final abs = watts.abs();
  final body = abs >= 1000
      ? '${_trim(abs / 1000, abs >= 10000 ? 1 : 2)} kW'
      : '${abs.round()} W';
  return negative ? '−$body' : body;
}

String formatKwh(double kwh) => '${_signed(kwh, kwh.abs() >= 100 ? 1 : 2)} kWh';

String formatGas(double m3) => '${_signed(m3, 2)} m³';

String formatSoc(double pct) => '${pct.round()}%';

/// Short label for the Systemen chip. Null when there is nothing to say.
String? energyChipLabel(EnergySnapshot snap) {
  if (!snap.enabled) return null;
  final grid = snap.gridPowerW;
  if (grid == null) return snap.stale ? 'geen verbinding' : null;
  if (snap.stale) return 'geen verbinding';
  if (grid.abs() < 30) return 'in balans';
  final n = formatPower(grid.abs());
  return grid < 0 ? '$n terug' : '$n afname';
}

String _signed(double v, int digits) {
  final body = _trim(v.abs(), digits);
  return v < 0 ? '−$body' : body;
}

String _trim(double v, int digits) {
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}
