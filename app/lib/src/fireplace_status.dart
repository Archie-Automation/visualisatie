/// Status-bits en labels voor openhaarden met discrete puls + feedback.
bool fireplaceBusBit(Map<String, dynamic> busValues, String? ga) {
  if (ga == null || ga.trim().isEmpty) return false;
  final v = busValues[ga.trim()];
  return v == true || v == 1;
}

Map<String, dynamic>? fireplaceStatusBitsMap(Map<String, dynamic> cfg) {
  final sb = cfg['statusBits'];
  if (sb is Map<String, dynamic>) return sb;
  if (sb is Map) {
    return Map<String, dynamic>.from(
      sb.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
  return null;
}

bool fireplaceHasStatusBits(Map<String, dynamic> cfg) {
  final sb = fireplaceStatusBitsMap(cfg);
  if (sb == null) return false;
  for (final key in const ['error', 'fuel', 'working', 'ready']) {
    final m = sb[key];
    if (m is Map) {
      final ga = m['ga'];
      if (ga is String && ga.trim().isNotEmpty) return true;
    }
  }
  return false;
}

bool fireplaceStatusBitOn(
  Map<String, dynamic> busValues,
  Map<String, dynamic>? statusBits,
  String key,
) {
  if (statusBits == null) return false;
  final m = statusBits[key];
  if (m is! Map) return false;
  return fireplaceBusBit(busValues, m['ga'] as String?);
}

/// Combinaties eerst: Error+Fuel → Bijvullen, Working+Ready → Wachten/Koelen.
String? fireplaceComposeStatusLabel(
  Map<String, dynamic> busValues,
  Map<String, dynamic>? statusBits,
) {
  if (statusBits == null || !fireplaceHasStatusBits({'statusBits': statusBits})) {
    return null;
  }
  final error = fireplaceStatusBitOn(busValues, statusBits, 'error');
  final fuel = fireplaceStatusBitOn(busValues, statusBits, 'fuel');
  final working = fireplaceStatusBitOn(busValues, statusBits, 'working');
  final ready = fireplaceStatusBitOn(busValues, statusBits, 'ready');
  if (error && fuel) return 'Bijvullen';
  if (working && ready) return 'Wachten / Koelen';
  if (error) return 'Fout';
  if (fuel) return 'Geen brandstof';
  if (working) return 'Bezig';
  if (ready) return 'Gereed';
  return 'Uit';
}

/// Bij statusBits: Working = aan. Anders null (caller gebruikt virtual/bus).
bool? fireplaceWorkingOn(
  Map<String, dynamic> cfg,
  Map<String, dynamic> busValues,
) {
  if (!fireplaceHasStatusBits(cfg)) return null;
  return fireplaceStatusBitOn(
    busValues,
    fireplaceStatusBitsMap(cfg),
    'working',
  );
}
