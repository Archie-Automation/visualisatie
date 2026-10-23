import '../models.dart';

/// Vertaalt een app-commando naar buswaarden. Zelfde adressen als status,
/// zodat de tegels meteen meebewegen. Er gaat niets het netwerk op.
Map<String, dynamic> demoCommandPatches(
  HouseConfig cfg,
  Map<String, dynamic> bus,
  Map<String, dynamic> command,
) {
  final id = command['deviceId'] as String?;
  if (id == null) return const {};
  final device = cfg.deviceById(id);
  if (device == null) return const {};

  final out = <String, dynamic>{};
  void put(String? ga, dynamic value) {
    if (ga == null || ga.isEmpty) return;
    out[ga] = value;
  }

  switch (command['kind']) {
    case 'light.switch':
      final on = command['on'] == true;
      final sw = device.ga['switch'] ?? device.ga['on'];
      put(sw, on);
      put(device.ga['switch_status'], on);
      if (!on) {
        put(device.ga['dim_value'], 0);
        put(device.ga['dim_status'], 0);
      } else {
        final dim = device.ga['dim_status'] ?? device.ga['dim_value'];
        final cur = dim == null ? null : (out[dim] ?? bus[dim]);
        if (dim != null && (cur is! num || cur <= 0)) {
          put(device.ga['dim_value'], 100);
          put(device.ga['dim_status'], 100);
        }
      }
    case 'light.dim':
      final pct = (command['percent'] as num?)?.round().clamp(0, 100) ?? 0;
      put(device.ga['dim_value'], pct);
      put(device.ga['dim_status'], pct);
      final on = pct > 0;
      put(device.ga['switch'], on);
      put(device.ga['switch_status'], on);
    case 'shading.position':
      final pct = (command['percent'] as num?)?.round().clamp(0, 100) ?? 0;
      put(device.ga['position'], pct);
      put(device.ga['position_status'], pct);
      put(device.ga['moving'], false);
    case 'shading.slats':
      final pct = (command['percent'] as num?)?.round().clamp(0, 100) ?? 0;
      put(device.ga['slat'], pct);
      put(device.ga['slat_status'], pct);
    case 'shading.move':
      put(device.ga['moving'], command['direction'] != 'stop');
    case 'climate.setpoint':
      final c = command['celsius'];
      put(device.ga['setpoint'], c);
      put(device.ga['setpoint_status'], c);
      _syncDemand(device, bus, out, c);
    case 'climate.mode':
      final heat = command['heat'] == true;
      put(device.ga['hvac_mode'], heat);
      put(device.ga['hvac_mode_status'], heat);
      final sp = bus[device.ga['setpoint_status'] ?? device.ga['setpoint'] ?? ''];
      _syncDemand(device, bus, out, sp, heat: heat);
    case 'climate.opmode':
      put(device.ga['mode'], command['mode']);
      put(device.ga['mode_status'], command['mode']);
    case 'fireplace.on':
      final on = command['on'] == true;
      final fp = device.raw['fireplace'];
      final onOff = fp is Map ? fp['onOff'] : null;
      if (onOff is Map) {
        put(onOff['ga'] as String?, on);
        put(onOff['statusGa'] as String?, on);
      }
      if (!on && fp is Map) {
        final flame = fp['flame'];
        if (flame is Map) {
          put(flame['ga'] as String?, 0);
          put(flame['statusGa'] as String?, 0);
        }
      }
    case 'fireplace.flame':
      final fp = device.raw['fireplace'];
      final flame = fp is Map ? fp['flame'] : null;
      if (flame is! Map) break;
      final pct = _flamePercent(flame, command['value']);
      put(flame['ga'] as String?, pct);
      put(flame['statusGa'] as String?, pct);
    case 'wtw.press':
      _zehnderPress(device, command, out);
    case 'wtw.setBoostMinutes':
      final minutes = (command['minutes'] as num?)?.round().clamp(1, 180) ?? 30;
      final wtw = device.raw['wtw'];
      final z = wtw is Map ? wtw['zehnder'] : null;
      if (z is Map) {
        final sec = minutes * 60;
        put(z['boostTimeGa'] as String?, sec);
        put(z['boostTimeStatusGa'] as String?, sec);
      }
    case 'melding.reset':
      final m = device.raw['melding'];
      final items = m is Map ? m['items'] : null;
      if (items is! List) break;
      final itemId = command['itemId'];
      for (final raw in items) {
        if (raw is! Map) continue;
        if (raw['id'] != itemId && raw['ga'] != itemId) continue;
        if (raw['resetMode'] == 'same_ga') put(raw['ga'] as String?, false);
        if (raw['resetMode'] == 'reset_ga') put(raw['resetGa'] as String?, true);
      }
    default:
      break;
  }
  return out;
}

int _flamePercent(Map flame, Object? value) {
  final ranges = flame['stepRanges'];
  if (ranges is List && ranges.isNotEmpty) {
    final step = value is num ? value.round() : 1;
    final idx = (step - 1).clamp(0, ranges.length - 1);
    final row = ranges[idx];
    if (row is Map && row['write'] is num) return (row['write'] as num).round();
  }
  if (value is num) return value.round().clamp(0, 100);
  return 0;
}

bool _heating(Device device, Map<String, dynamic> bus, Map<String, dynamic> out) {
  final ga = device.ga['hvac_mode_status'] ?? device.ga['hvac_mode'];
  if (ga == null) return true;
  final v = out.containsKey(ga) ? out[ga] : bus[ga];
  if (v == false || v == 0) return false;
  return true;
}

void _putDemand(Map<String, dynamic> out, String? ga, bool v) {
  if (ga == null || ga.isEmpty) return;
  out[ga] = v;
}

void _syncDemand(
  Device device,
  Map<String, dynamic> bus,
  Map<String, dynamic> out,
  Object? setpoint, {
  bool? heat,
}) {
  final actualGa = device.ga['actual_temp'];
  final actual = actualGa == null ? null : bus[actualGa];
  if (actual is! num || setpoint is! num) return;
  final heating = heat ?? _heating(device, bus, out);
  final demand = heating ? actual < setpoint - 0.05 : actual > setpoint + 0.05;
  _putDemand(
    out,
    heating ? device.ga['heat_demand'] : device.ga['cool_demand'],
    demand,
  );
  _putDemand(
    out,
    heating ? device.ga['cool_demand'] : device.ga['heat_demand'],
    false,
  );
}

void _zehnderPress(Device device, Map<String, dynamic> command, Map<String, dynamic> out) {
  final wtw = device.raw['wtw'];
  final z = wtw is Map ? wtw['zehnder'] : null;
  if (z is! Map) return;
  const ids = ['away', 'stand1', 'stand2', 'stand3', 'auto', 'boost'];
  void status(String id, bool on) {
    final ga = z['${id}StatusGa'];
    if (ga is String && ga.isNotEmpty) out[ga] = on;
  }

  final id = command['buttonId'] as String? ?? '';
  if (id == 'auto') {
    final on = command['on'] == true;
    status('auto', on);
    if (on) {
      for (final other in ids) {
        if (other != 'auto') status(other, false);
      }
    }
    return;
  }
  if (!ids.contains(id)) return;
  for (final other in ids) {
    status(other, other == id);
  }
}
