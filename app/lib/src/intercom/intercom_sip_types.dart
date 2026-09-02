/// Fase van een SIP-intercomsessie in de app.
enum IntercomSipPhase {
  idle,
  ringing,
  inCall,
  /// CANCEL: bel is gestopt, popup mag nog even blijven.
  answeredElsewhere,
}

/// Fabrikant / transport van de intercom (geen KNX — KNX is alleen deur/poort).
enum IntercomKind {
  doorbird,
  twoN,
  sip,
  axis,
  mobotix,
  siedle,
  comelit,
  unifi,
  other;

  static IntercomKind? parse(String? s) => switch (s) {
        'doorbird' => IntercomKind.doorbird,
        'twoN' => IntercomKind.twoN,
        'sip' => IntercomKind.sip,
        'axis' => IntercomKind.axis,
        'mobotix' => IntercomKind.mobotix,
        'siedle' => IntercomKind.siedle,
        'comelit' => IntercomKind.comelit,
        'unifi' => IntercomKind.unifi,
        'other' => IntercomKind.other,
        _ => null,
      };

  String toJson() => switch (this) {
        IntercomKind.doorbird => 'doorbird',
        IntercomKind.twoN => 'twoN',
        IntercomKind.sip => 'sip',
        IntercomKind.axis => 'axis',
        IntercomKind.mobotix => 'mobotix',
        IntercomKind.siedle => 'siedle',
        IntercomKind.comelit => 'comelit',
        IntercomKind.unifi => 'unifi',
        IntercomKind.other => 'other',
      };
}
