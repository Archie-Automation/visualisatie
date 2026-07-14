/// Fase van een SIP-intercomsessie in de app.
enum IntercomSipPhase {
  idle,
  ringing,
  inCall,
}

/// Fabrikant / transport van de intercom (geen KNX — KNX is alleen deur/poort).
enum IntercomKind {
  doorbird,
  twoN,
  sip;

  static IntercomKind? parse(String? s) => switch (s) {
        'doorbird' => IntercomKind.doorbird,
        'twoN' => IntercomKind.twoN,
        'sip' => IntercomKind.sip,
        _ => null,
      };

  String toJson() => switch (this) {
        IntercomKind.doorbird => 'doorbird',
        IntercomKind.twoN => 'twoN',
        IntercomKind.sip => 'sip',
      };
}
