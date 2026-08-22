import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../roles.dart';

/// Opens [/installer] for installers, otherwise explains why it is blocked.
void openTechnischeConfiguratie(BuildContext context, AuthState auth) {
  if (auth.isInstaller) {
    context.push('/installer');
    return;
  }
  final user = auth.username ?? '—';
  final rol = roleLabel(auth.effectiveRole);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Installer-account nodig'),
      content: SingleChildScrollView(
        child: Text(
          'De volledige opbouw van het huis (verdiepingen, kamers, KNX, IP-adressen, '
          'camera’s) staat in het scherm Technische configuratie. Dat mag alleen een '
          'installer. Super user beheert gebruikers via Instellingen → Gebruikers.\n\n'
          'U bent nu ingelogd als: $user\n'
          'Rol: $rol\n\n'
          'Log uit en meld u aan met een installer-account. In de meegeleverde '
          'demo-configuratie is dat vaak gebruikersnaam admin en wachtwoord admin '
          '(zolang het bootstrap-wachtwoord nog niet is gewijzigd).',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
