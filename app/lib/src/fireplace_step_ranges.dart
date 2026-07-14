// Vlam met vaste percent-banden per stap (`fireplace.flame.stepRanges`).

List<Map<String, dynamic>>? parseFireplaceStepRanges(Map<String, dynamic>? flame) {
  final raw = flame?['stepRanges'];
  if (raw is! List || raw.length < 2) return null;
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is! Map) continue;
    out.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
  }
  return out.length >= 2 ? out : null;
}

/// `null` = ok, anders fouttekst voor de configurateur.
String? validateFireplaceStepRanges(List<Map<String, dynamic>> ranges) {
  if (ranges.length < 2 || ranges.length > 10) {
    return 'Kies tussen 2 en 10 stappen.';
  }
  final mins = <int>[];
  final maxs = <int>[];
  for (var i = 0; i < ranges.length; i++) {
    final r = ranges[i];
    final a = (r['min'] as num?)?.round();
    final b = (r['max'] as num?)?.round();
    if (a == null || b == null) {
      return 'Stap ${i + 1}: min en max zijn verplicht (0–100).';
    }
    if (a < 0 || a > 100 || b < 0 || b > 100) {
      return 'Stap ${i + 1}: min en max moeten tussen 0 en 100 liggen.';
    }
    if (a > b) {
      return 'Stap ${i + 1}: min mag niet groter zijn dan max.';
    }
    final w = r['write'];
    if (w != null) {
      final wi = (w as num).round();
      if (wi < 0 || wi > 100) {
        return 'Stap ${i + 1}: schrijf-% moet tussen 0 en 100 liggen.';
      }
    }
    mins.add(a);
    maxs.add(b);
  }
  for (var i = 0; i < ranges.length - 1; i++) {
    if (maxs[i] >= mins[i + 1]) {
      return 'Stap ${i + 1} en ${i + 2}: de percent-banden overlappen of '
          'grenzen aan elkaar. Zorg dat het maximum van stap ${i + 1} '
          'strikt kleiner is dan het minimum van stap ${i + 2} '
          '(bijv. …–20 en 21–…).';
    }
  }
  return null;
}

int _writePctForStep(List<Map<String, dynamic>> ranges, int step1Based) {
  final i = (step1Based - 1).clamp(0, ranges.length - 1);
  final r = ranges[i];
  final w = r['write'];
  if (w is num) return w.round().clamp(0, 100);
  final a = (r['min'] as num).round();
  final b = (r['max'] as num).round();
  return ((a + b) / 2).round().clamp(0, 100);
}

/// Buspercent (0–100) → stap 1..N op basis van banden; anders dichtstbijzijnde stap.
int busPercentToFlameStep(List<Map<String, dynamic>> ranges, int busPct) {
  final p = busPct.clamp(0, 100);
  for (var i = 0; i < ranges.length; i++) {
    final a = (ranges[i]['min'] as num).round();
    final b = (ranges[i]['max'] as num).round();
    if (p >= a && p <= b) return i + 1;
  }
  var best = 1;
  var bestDist = 1 << 30;
  for (var i = 0; i < ranges.length; i++) {
    final mid = _writePctForStep(ranges, i + 1);
    final d = (p - mid).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i + 1;
    }
  }
  return best;
}

List<String> labelsForFireplaceStepRanges(List<Map<String, dynamic>> ranges) {
  return [
    for (var i = 0; i < ranges.length; i++)
      fireplaceStepLabel(ranges: ranges, step1Based: i + 1),
  ];
}

/// Label voor één vlamstand in de klant-app (geen %-bereik).
String fireplaceStepLabel({
  required List<Map<String, dynamic>>? ranges,
  required int step1Based,
}) {
  if (ranges != null && ranges.length >= 2) {
    final i = step1Based - 1;
    if (i >= 0 && i < ranges.length) {
      final custom = (ranges[i]['label'] as String?)?.trim();
      if (custom != null && custom.isNotEmpty) return custom;
    }
  }
  return 'Stand $step1Based';
}

int writePercentForFlameStep(List<Map<String, dynamic>> ranges, int step1Based) =>
    _writePctForStep(ranges, step1Based);
