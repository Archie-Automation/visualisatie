import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';

/// Opens [/installer] for admins, otherwise explains why it is blocked.
void openTechnischeConfiguratie(BuildContext context, AuthState auth) {
  if (auth.isAdmin) {
    context.push('/installer');
    return;
  }
  final user = auth.username ?? '—';
  final rol = auth.effectiveRole ?? 'onbekend';
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Beheerdersaccount nodig'),
      content: SingleChildScrollView(
        child: Text(
          'De volledige opbouw van het huis (verdiepingen, kamers, KNX, IP-adressen, '
          'camera’s, gebruikers) staat in het scherm Technische configuratie. Dat mag '
          'alleen een account met rol admin. De knop om backend en app te herstarten '
          'staat onder Project in dat scherm.\n\n'
          'U bent nu ingelogd als: $user\n'
          'Rol: $rol\n\n'
          'Log uit en meld u aan met een beheerdersaccount. In de meegeleverde '
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
