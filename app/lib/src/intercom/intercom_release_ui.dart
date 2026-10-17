/// Of de knop Deur open op het intercomscherm hoort.
///
/// De server zet [canRelease] als KNX/HTTP/DoorBird-API écht kan.
/// Daarnaast: tijdens een SIP-gesprek (DTMF), of als het een ingestelde
/// DoorBird is — HTTP open-door werkt zonder gesprek.
bool intercomShowsDoorButton({
  required bool canRelease,
  required bool sipInCall,
  Map<String, dynamic>? intercomRaw,
}) {
  if (canRelease || sipInCall) return true;
  if (intercomRaw == null) return false;
  if (intercomRaw['kind'] == 'doorbird') return true;
  if (intercomRaw['releaseMode'] == 'doorbird') return true;
  final db = intercomRaw['doorbird'];
  if (db is Map && (db['host'] as String?)?.trim().isNotEmpty == true) {
    return true;
  }
  return false;
}
