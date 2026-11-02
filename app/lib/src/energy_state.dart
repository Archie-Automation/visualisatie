import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One EnergyZero hour after the installer's surcharge and VAT flag.
class EnergyPriceHour {
  const EnergyPriceHour({
    required this.fromMs,
    required this.tillMs,
    this.importEur,
    this.exportEur,
  });

  final int fromMs;
  final int tillMs;
  final double? importEur;
  final double? exportEur;
}

/// Server-computed live energy view. The client does not sum the bus
/// and does not turn watts into euros.
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
    this.todayImportKwh,
    this.todayExportKwh,
    this.todaySolarKwh,
    this.todayGasM3,
    this.todayImportPartial = false,
    this.todayExportPartial = false,
    this.todaySolarPartial = false,
    this.todayGasPartial = false,
    this.todayImportEstimated = false,
    this.todayExportEstimated = false,
    this.todaySolarEstimated = false,
    this.todayCostEur,
    this.todayFeedInEur,
    this.todayGasCostEur,
    this.todayNetEur,
    this.openHourImportEur,
    this.openHourFeedInEur,
    this.openHourGasEur,
    this.importPriceEurPerKwh,
    this.exportPriceEurPerKwh,
    this.gasPriceEurPerM3,
    this.tempoEurPerHour,
    this.priceStale = false,
    this.priceHours = const [],
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
  final double? todayImportKwh;
  final double? todayExportKwh;
  final double? todaySolarKwh;
  final double? todayGasM3;
  final bool todayImportPartial;
  final bool todayExportPartial;
  final bool todaySolarPartial;
  final bool todayGasPartial;
  final bool todayImportEstimated;
  final bool todayExportEstimated;
  final bool todaySolarEstimated;
  final double? todayCostEur;
  final double? todayFeedInEur;
  final double? todayGasCostEur;
  final double? todayNetEur;
  final double? openHourImportEur;
  final double? openHourFeedInEur;
  final double? openHourGasEur;
  final double? importPriceEurPerKwh;
  final double? exportPriceEurPerKwh;
  final double? gasPriceEurPerM3;
  /// Positive = paying. Negative = earning. A rate, not today's bill.
  final double? tempoEurPerHour;
  final bool priceStale;
  final List<EnergyPriceHour> priceHours;

  bool get hasToday =>
      todayImportKwh != null ||
      todayExportKwh != null ||
      todaySolarKwh != null ||
      todayGasM3 != null;

  bool get hasPrices =>
      importPriceEurPerKwh != null ||
      exportPriceEurPerKwh != null ||
      gasPriceEurPerM3 != null ||
      todayCostEur != null ||
      todayFeedInEur != null ||
      priceHours.isNotEmpty;

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
        todayImportKwh: _num(j['todayImportKwh']),
        todayExportKwh: _num(j['todayExportKwh']),
        todaySolarKwh: _num(j['todaySolarKwh']),
        todayGasM3: _num(j['todayGasM3']),
        todayImportPartial: j['todayImportPartial'] == true,
        todayExportPartial: j['todayExportPartial'] == true,
        todaySolarPartial: j['todaySolarPartial'] == true,
        todayGasPartial: j['todayGasPartial'] == true,
        todayImportEstimated: j['todayImportEstimated'] == true,
        todayExportEstimated: j['todayExportEstimated'] == true,
        todaySolarEstimated: j['todaySolarEstimated'] == true,
        todayCostEur: _num(j['todayCostEur']),
        todayFeedInEur: _num(j['todayFeedInEur']),
        todayGasCostEur: _num(j['todayGasCostEur']),
        todayNetEur: _num(j['todayNetEur']),
        openHourImportEur: _num(j['openHourImportEur']),
        openHourFeedInEur: _num(j['openHourFeedInEur']),
        openHourGasEur: _num(j['openHourGasEur']),
        importPriceEurPerKwh: _num(j['importPriceEurPerKwh']),
        exportPriceEurPerKwh: _num(j['exportPriceEurPerKwh']),
        gasPriceEurPerM3: _num(j['gasPriceEurPerM3']),
        tempoEurPerHour: _num(j['tempoEurPerHour']),
        priceStale: j['priceStale'] == true,
        priceHours: _hours(j['priceHours']),
      );

  EnergySnapshot copyWith({List<EnergyPriceHour>? priceHours}) {
    return EnergySnapshot(
      enabled: enabled,
      stale: stale,
      gridPowerW: gridPowerW,
      solarPowerW: solarPowerW,
      batteryPowerW: batteryPowerW,
      batterySoc: batterySoc,
      housePowerW: housePowerW,
      importEnergyKwh: importEnergyKwh,
      exportEnergyKwh: exportEnergyKwh,
      solarEnergyKwh: solarEnergyKwh,
      gasM3: gasM3,
      todayImportKwh: todayImportKwh,
      todayExportKwh: todayExportKwh,
      todaySolarKwh: todaySolarKwh,
      todayGasM3: todayGasM3,
      todayImportPartial: todayImportPartial,
      todayExportPartial: todayExportPartial,
      todaySolarPartial: todaySolarPartial,
      todayGasPartial: todayGasPartial,
      todayImportEstimated: todayImportEstimated,
      todayExportEstimated: todayExportEstimated,
      todaySolarEstimated: todaySolarEstimated,
      todayCostEur: todayCostEur,
      todayFeedInEur: todayFeedInEur,
      todayGasCostEur: todayGasCostEur,
      todayNetEur: todayNetEur,
      openHourImportEur: openHourImportEur,
      openHourFeedInEur: openHourFeedInEur,
      openHourGasEur: openHourGasEur,
      importPriceEurPerKwh: importPriceEurPerKwh,
      exportPriceEurPerKwh: exportPriceEurPerKwh,
      gasPriceEurPerM3: gasPriceEurPerM3,
      tempoEurPerHour: tempoEurPerHour,
      priceStale: priceStale,
      priceHours: priceHours ?? this.priceHours,
    );
  }

  static List<EnergyPriceHour> _hours(Object? raw) {
    if (raw is! List) return const [];
    final out = <EnergyPriceHour>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final from = item['from'];
      final till = item['till'];
      if (from is! num || till is! num) continue;
      out.add(EnergyPriceHour(
        fromMs: from.toInt(),
        tillMs: till.toInt(),
        importEur: _num(item['importEur']),
        exportEur: _num(item['exportEur']),
      ));
    }
    return out;
  }

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

String formatEur(double eur) {
  final body = eur.abs().toStringAsFixed(2).replaceAll('.', ',');
  return eur < 0 ? '−€ $body' : '€ $body';
}

String formatUnitPrice(double eur, String unit) {
  final body = eur.abs().toStringAsFixed(3).replaceAll('.', ',');
  final signed = eur < 0 ? '−€ $body' : '€ $body';
  return '$signed / $unit';
}

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
