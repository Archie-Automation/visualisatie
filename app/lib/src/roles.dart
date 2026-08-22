/// Canonical app roles. Stored `admin` is treated as installer.
enum AppRole { installer, superuser, user }

AppRole normalizeRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  if (r == 'admin' || r == 'installer') return AppRole.installer;
  if (r == 'superuser' || r == 'super_user' || r == 'super-user') {
    return AppRole.superuser;
  }
  return AppRole.user;
}

bool isInstallerRole(String? role) => normalizeRole(role) == AppRole.installer;

bool isSuperUserRole(String? role) => normalizeRole(role) == AppRole.superuser;

bool isStaffRole(String? role) {
  final n = normalizeRole(role);
  return n == AppRole.installer || n == AppRole.superuser;
}

String roleLabel(String? role) {
  switch (normalizeRole(role)) {
    case AppRole.installer:
      return 'Installer';
    case AppRole.superuser:
      return 'Super user';
    case AppRole.user:
      return 'Gebruiker';
  }
}

class HouseFunctionDef {
  const HouseFunctionDef(this.slug, this.label);
  final String slug;
  final String label;
}

const kHouseFunctionDefs = <HouseFunctionDef>[
  HouseFunctionDef('verlichting', 'Verlichting'),
  HouseFunctionDef('klimaat', 'Klimaat'),
  HouseFunctionDef('zonwering', 'Zonwering'),
  HouseFunctionDef('ventilatie', 'Ventilatie'),
  HouseFunctionDef('openhaard', 'Openhaard'),
  HouseFunctionDef('cameras', 'Camera\'s'),
  HouseFunctionDef('intercom', 'Intercom'),
  HouseFunctionDef('audio', 'Audio'),
  HouseFunctionDef('meldingen', 'Meldingen'),
  HouseFunctionDef('diverse', 'Diverse'),
  HouseFunctionDef('alarm', 'Alarm'),
];
