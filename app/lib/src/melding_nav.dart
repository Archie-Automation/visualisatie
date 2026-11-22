import 'package:go_router/go_router.dart';

/// Opent de meldingenpagina. Tijdens splash blijft het verzoek liggen
/// tot het startscherm er is.
class MeldingNav {
  static GoRouter? router;
  static var pending = false;
  static const path = '/system/meldingen';

  static void request() {
    final r = router;
    final loc = r?.state.matchedLocation;
    if (r != null &&
        loc != null &&
        loc != '/splash' &&
        loc != '/login' &&
        loc != '/wachtwoord') {
      pending = false;
      if (loc != path) r.go(path);
      return;
    }
    pending = true;
  }

  static bool take() {
    final v = pending;
    pending = false;
    return v;
  }
}
