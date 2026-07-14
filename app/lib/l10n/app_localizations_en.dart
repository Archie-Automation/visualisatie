// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginWelcomeTitle => 'Welcome home.';

  @override
  String get loginSubtitle => 'Sign in to take control of the ambience.';

  @override
  String get loginUserLabel => 'Username';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginAction => 'Log in';

  @override
  String get loginErrorBadCredentials => 'Incorrect username or password';

  @override
  String get loginErrorNetwork =>
      'Cannot reach the server. Start the backend (port 4000) and try again.';

  @override
  String get installerLoginTitle => 'Installer configuration';

  @override
  String get installerLoginDescription =>
      'Sign in with an administrator account to edit the house, devices, and KNX.';

  @override
  String get installerLoginAdminOnlyError =>
      'Only administrator accounts can sign in to the installer app.';
}
