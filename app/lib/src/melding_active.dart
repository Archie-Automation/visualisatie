/// Wanneer een meldingen-punt als actief telt op de KNX-bus.
///
/// [activeCompare]: `eq` (default), `gt`, `lt`, `gte`, `lte`.
/// 1-bit blijft 1/true, tenzij [activeValue] iets anders zet.
bool meldingItemIsActive(Map<String, dynamic> item, dynamic busVal) {
  if (busVal == null) return false;
  final dpt = item['dpt'] as String? ?? '1.001';
  final activeVal = item['activeValue'];

  if (dpt.startsWith('1.')) {
    final target = activeVal ?? 1;
    if (busVal is bool) return busVal == (target == 1 || target == true);
    final n = num.tryParse(busVal.toString());
    final t = activeVal != null ? num.tryParse(activeVal.toString()) : 1;
    return n != null && t != null && n == t;
  }

  final n = num.tryParse(busVal.toString());
  if (n == null) return false;
  if (activeVal == null) return n != 0;
  final t = num.tryParse(activeVal.toString());
  if (t == null) return n != 0;

  return switch (item['activeCompare'] as String? ?? 'eq') {
    'gt' => n > t,
    'lt' => n < t,
    'gte' => n >= t,
    'lte' => n <= t,
    _ => n == t,
  };
}
