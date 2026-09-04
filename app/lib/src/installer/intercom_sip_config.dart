import 'voip_installer_section.dart';

/// Stored house.json shape for intercom + belgroep. Indoor SIP (tablets /
/// phones) is provisioned in the background — not shown in this UI.
///
/// ```json
/// {
///   "voip": {
///     "enabled": true,
///     "endpoints": [
///       { "id": "ep-usr-1", "userId": "usr-1", "name": "Keukentablet",
///         "type": "panel", "ext": "201", "password": "<auto>" }
///     ],
///     "groups": [
///       { "id": "grp-woning", "name": "Deurbel belgroep", "ext": "900",
///         "memberIds": ["ep-usr-1"], "timeoutSec": 30 }
///     ]
///   },
///   "intercoms": [
///     {
///       "id": "dev-ic-voordeur",
///       "type": "intercom",
///       "name": "Voordeur",
///       "intercom": {
///         "sipExt": "100",
///         "sipPassword": "<zoals op het deurstation>",
///         "rtsp": "rtsp://user:pass@192.168.1.50:554/stream",
///         "dtmfDigit": "#",
///         "ringGroupId": "grp-woning"
///       }
///     }
///   ]
/// }
/// ```
const defaultBelgroepName = 'Deurbel belgroep';
const defaultDtmfDigit = '#';
const defaultRingTimeoutSec = 30;
const minRingTimeoutSec = 5;
const maxRingTimeoutSec = 180;

final _rtspRe = RegExp(r'^rtsps?://\S+$', caseSensitive: false);
final _dtmfRe = RegExp(r'^[0-9A-D#*]$', caseSensitive: false);

Map<String, dynamic> ensureIntercomMap(Map<String, dynamic> device) {
  final o = device['intercom'];
  if (o is Map<String, dynamic>) return o;
  if (o is Map) {
    final m = Map<String, dynamic>.from(o);
    device['intercom'] = m;
    return m;
  }
  final m = <String, dynamic>{};
  device['intercom'] = m;
  return m;
}

void ensureIntercomDefaults(Map<String, dynamic> device) {
  final o = ensureIntercomMap(device);
  if ((device['name'] as String?) == null) device['name'] = 'Voordeur';
  if ((o['dtmfDigit'] as String?)?.trim().isEmpty ?? true) {
    o['dtmfDigit'] = defaultDtmfDigit;
  }
}

/// Enable indoor SIP provisioning without exposing PBX details.
void enableIntercomCalling(Map<String, dynamic> house) {
  ensureVoipMap(house)['enabled'] = true;
}

Map<String, dynamic> createBelgroep(Map<String, dynamic> house) {
  enableIntercomCalling(house);
  final group = <String, dynamic>{
    'id': 'grp-${DateTime.now().microsecondsSinceEpoch}',
    'name': defaultBelgroepName,
    'ext': '',
    'memberIds': [
      for (final ep in voipEndpointMaps(house)) ep['id'],
    ],
    'timeoutSec': defaultRingTimeoutSec,
  };
  voipGroupMaps(house).add(group);
  return group;
}

void deleteBelgroep(Map<String, dynamic> house, String groupId) {
  voipGroupMaps(house).removeWhere((g) => '${g['id']}' == groupId);
  final raw = house['intercoms'];
  if (raw is! List) return;
  for (final ic in raw) {
    if (ic is! Map) continue;
    final o = ic['intercom'];
    if (o is Map && '${o['ringGroupId']}' == groupId) {
      o.remove('ringGroupId');
    }
  }
}

int belgroepTimeoutSec(Map<String, dynamic> group) {
  final t = group['timeoutSec'];
  if (t is int && t >= minRingTimeoutSec) return t;
  if (t is num && t >= minRingTimeoutSec) return t.toInt();
  return defaultRingTimeoutSec;
}

void setBelgroepTimeoutSec(Map<String, dynamic> group, String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null) return;
  group['timeoutSec'] = n.clamp(minRingTimeoutSec, maxRingTimeoutSec);
}

bool isValidRtspUrl(String raw) => _rtspRe.hasMatch(raw.trim());

bool isValidDtmfDigit(String raw) => _dtmfRe.hasMatch(raw.trim());

String? validateIntercomName(String raw) {
  if (raw.trim().isEmpty) return 'Vul een naam in, bijvoorbeeld Voordeur.';
  return null;
}

String? validateIntercomSipUser(String raw) {
  if (raw.trim().isEmpty) {
    return 'Vul het account in zoals ingesteld op het deurstation.';
  }
  return null;
}

String? validateIntercomSipPassword(String raw) {
  if (raw.isEmpty) return 'Vul het wachtwoord in zoals ingesteld op het deurstation.';
  return null;
}

String? validateRtspUrl(String raw, {bool required = true}) {
  final t = raw.trim();
  if (t.isEmpty) {
    return required ? 'Vul de camerastream in (begint met rtsp://).' : null;
  }
  if (!isValidRtspUrl(t)) {
    return 'Ongeldige stream. Gebruik rtsp:// of rtsps://, zoals in de handleiding.';
  }
  return null;
}

String? validateDtmfDigit(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'Vul een deuropen-code in. Standaard is #.';
  if (!isValidDtmfDigit(t)) {
    return 'Gebruik één teken: 0–9, #, * of A–D.';
  }
  return null;
}

String? validateRingTimeout(String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null) return 'Vul het aantal seconden in.';
  if (n < minRingTimeoutSec) {
    return 'Minstens $minRingTimeoutSec seconden, anders stopt het bellen te vroeg.';
  }
  if (n > maxRingTimeoutSec) return 'Maximaal $maxRingTimeoutSec seconden.';
  return null;
}

String? validateRingGroupId(
  String? groupId,
  List<Map<String, dynamic>> groups,
) {
  final id = groupId?.trim() ?? '';
  if (id.isEmpty) return 'Kies welke belgroep overgaat als er wordt aangebeld.';
  if (!groups.any((g) => '${g['id']}' == id)) {
    return 'Deze belgroep bestaat niet meer. Kies een andere.';
  }
  return null;
}

List<String> intercomWizardIssues({
  required Map<String, dynamic> device,
  required Map<String, dynamic> house,
}) {
  final o = ensureIntercomMap(device);
  final groups = voipGroupMaps(house);
  return [
    validateIntercomName((device['name'] as String?) ?? ''),
    validateIntercomSipUser((o['sipExt'] as String?) ?? ''),
    validateIntercomSipPassword((o['sipPassword'] as String?) ?? ''),
    validateRtspUrl((o['rtsp'] as String?) ?? ''),
    validateDtmfDigit((o['dtmfDigit'] as String?) ?? defaultDtmfDigit),
    validateRingGroupId(o['ringGroupId'] as String?, groups),
  ].whereType<String>().toList();
}
