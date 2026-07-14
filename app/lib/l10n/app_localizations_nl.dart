// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get loginWelcomeTitle => 'Welkom thuis.';

  @override
  String get loginSubtitle => 'Meld u aan om de sfeer over te nemen.';

  @override
  String get loginUserLabel => 'Gebruiker';

  @override
  String get loginPasswordLabel => 'Wachtwoord';

  @override
  String get loginAction => 'Inloggen';

  @override
  String get loginErrorBadCredentials => 'Onjuiste combinatie';

  @override
  String get loginErrorNetwork =>
      'Geen verbinding met de server. Start de backend (poort 4000) en probeer opnieuw.';

  @override
  String get installerLoginTitle => 'Installateursconfiguratie';

  @override
  String get installerLoginDescription =>
      'Log in met een beheerdersaccount om het huis, apparaten en KNX te bewerken.';

  @override
  String get installerLoginAdminOnlyError =>
      'Alleen beheerdersaccounts kunnen inloggen in de installateur-app.';
}
