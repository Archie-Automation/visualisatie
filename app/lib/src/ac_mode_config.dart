/// Airco-modi: zichtbaarheid in de app (installateur-config).

/// Standaard modusopties voor nieuwe airco-apparaten.
const defaultAcModeOptions = <Map<String, dynamic>>[
  {'label': 'Auto', 'value': 0, 'icon': 'auto'},
  {'label': 'Koelen', 'value': 1, 'icon': 'snow'},
  {'label': 'Verwarmen', 'value': 2, 'icon': 'flame'},
  {'label': 'Ventileren', 'value': 3, 'icon': 'fan'},
  {'label': 'Drogen', 'value': 4, 'icon': 'drop'},
];

/// Standaard zichtbaar: alleen koelen en verwarmen.
const defaultAcModeVisibility = <String, bool>{
  'auto': false,
  'snow': true,
  'flame': true,
  'fan': false,
  'drop': false,
};

/// Sleutel voor [modeVisibility] — icon heeft voorrang, anders label/value.
String acModeVisibilityKey(Map<String, dynamic> option) {
  final icon = option['icon'] as String?;
  if (icon != null && icon.trim().isNotEmpty) return icon.trim();
  final label = (option['label'] as String? ?? '').toLowerCase();
  if (label.contains('auto')) return 'auto';
  if (label.contains('koel')) return 'snow';
  if (label.contains('verwarm')) return 'flame';
  if (label.contains('ventil')) return 'fan';
  if (label.contains('dro')) return 'drop';
  return 'mode_${option['value']}';
}

bool acModeDefaultVisible(String key) => key == 'flame' || key == 'snow';

/// Of een modusoptie in de app getoond wordt.
bool acModeVisible(
  Map<String, dynamic>? visibility,
  Map<String, dynamic> option,
) {
  final key = acModeVisibilityKey(option);
  if (visibility == null) return acModeDefaultVisible(key);
  if (visibility.containsKey(key)) return visibility[key] == true;
  return acModeDefaultVisible(key);
}

List<Map<String, dynamic>> acVisibleModeOptions(
  List<Map<String, dynamic>> options,
  Map<String, dynamic>? visibility,
) =>
    options.where((o) => acModeVisible(visibility, o)).toList(growable: false);

/// Zoek koel-/verwarmmodus in zichtbare opties.
int? acHvacModeValue(
  List<Map<String, dynamic>> options, {
  required bool heat,
}) {
  for (final o in options) {
    final icon = o['icon'] as String?;
    final label = (o['label'] as String? ?? '').toLowerCase();
    final match = heat
        ? (icon == 'flame' || label.contains('verwarm'))
        : (icon == 'snow' || label.contains('koel'));
    if (match) return (o['value'] as num).toInt();
  }
  return null;
}

Map<String, dynamic> acModeVisibilityForOptions(
  List<Map<String, dynamic>> options,
) {
  final out = <String, dynamic>{};
  for (final o in options) {
    final key = acModeVisibilityKey(o);
    out[key] = defaultAcModeVisibility[key] ?? acModeDefaultVisible(key);
  }
  return out;
}

/// Houd [modeVisibility] in sync na toevoegen/wijzigen/verwijderen van modi.
void syncAcModeVisibility(
  Map<String, dynamic> ac,
  List<Map<String, dynamic>> options,
) {
  final map = Map<String, dynamic>.from(
    (ac['modeVisibility'] as Map?)?.cast<String, dynamic>() ?? {},
  );
  final defaults = acModeVisibilityForOptions(options);
  final validKeys = options.map(acModeVisibilityKey).toSet();
  for (final key in validKeys) {
    map.putIfAbsent(key, () => defaults[key] ?? acModeDefaultVisible(key));
  }
  map.removeWhere((k, _) => !validKeys.contains(k));
  ac['modeVisibility'] = map;
}

/// Iconen voor airco-modusopties in installateur.
const kAcModeIconKeys = ['auto', 'snow', 'flame', 'fan', 'drop'];
