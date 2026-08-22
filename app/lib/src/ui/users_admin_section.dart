import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../models.dart';
import '../roles.dart';
import '../theme.dart';
import '../user_api.dart';
import 'user_access_editor.dart';
import 'widgets/glass_card.dart';

class UsersAdminSection extends ConsumerStatefulWidget {
  const UsersAdminSection({super.key, required this.cfg, this.showTitle = false});

  final HouseConfig cfg;
  final bool showTitle;

  @override
  ConsumerState<UsersAdminSection> createState() => _UsersAdminSectionState();
}

class _UsersAdminSectionState extends ConsumerState<UsersAdminSection> {
  static const _uuid = Uuid();

  List<Map<String, dynamic>>? _users;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  String? _selectedId;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await fetchHouseUsers(token: token);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        if (_selectedId != null &&
            users.every((u) => u['id'] != _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final u in _users ?? const []) {
      if (u['id'] == id) return u;
    }
    return null;
  }

  Future<void> _save() async {
    final token = ref.read(authProvider).token;
    final users = _users;
    if (token == null || users == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await saveHouseUsers(users: users, token: token);
      if (!mounted) return;
      _password.clear();
      setState(() {
        _users = saved;
        _saving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gebruikers opgeslagen')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _addUser() {
    final id = 'usr-${_uuid.v4()}';
    final next = {
      'id': id,
      'username': 'nieuw',
      'displayName': 'Nieuwe gebruiker',
      'role': 'user',
      'enabled': true,
      'access': {
        'floors': '*',
        'rooms': '*',
        'functions': '*',
        'editScenes': true,
      },
    };
    setState(() {
      _users = [...?_users, next];
      _selectedId = id;
      _password.clear();
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _users = [...?_users]..removeWhere((u) => u['id'] == sel['id']);
      _selectedId = null;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_users == null) {
      return Padding(
        padding: const EdgeInsets.all(22),
        child: Text(_error ?? 'Geen gebruikers'),
      );
    }

    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Text(
              'Gebruikers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 9),
          child: GlassCard(
            padding: EdgeInsets.zero,
            radius: 18,
            child: Column(
              children: [
                for (var i = 0; i < _users!.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 50, color: LuxeColors.lineSoft),
                  _UserTile(
                    user: _users![i],
                    selected: _users![i]['id'] == _selectedId,
                    onTap: () {
                      _password.clear();
                      final u = _users![i];
                      u.remove('password');
                      setState(() => _selectedId = u['id'] as String);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _addUser,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Toevoegen'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Opslaan'),
              ),
            ],
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: GlassCard(
              radius: 18,
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 16),
              child: KeyedSubtree(
                key: ValueKey(selected['id']),
                child: _UserEditor(
                  user: selected,
                  floors: aclFloorsFromConfig(widget.cfg),
                  actorIsInstaller: auth.isInstaller,
                  isSelf: selected['id'] == _userIdFor(auth, _users!),
                  password: _password,
                  onChanged: () => setState(() {}),
                  onDelete: _deleteSelected,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _userIdFor(AuthState auth, List<Map<String, dynamic>> users) {
    final name = auth.username;
    if (name == null) return null;
    for (final u in users) {
      if (u['username'] == name) return u['id'] as String?;
    }
    return widget.cfg.me?.id;
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = user['role'] as String? ?? 'user';
    final enabled = user['enabled'] != false;
    final name = (user['displayName'] as String?)?.trim();
    final username = user['username'] as String? ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Icon(
              isInstallerRole(role)
                  ? Icons.construction_outlined
                  : isSuperUserRole(role)
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
              color: selected ? LuxeColors.brass : LuxeColors.ink,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name == null || name.isEmpty ? username : name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    [
                      username,
                      roleLabel(role),
                      if (!enabled) 'geblokkeerd',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: LuxeColors.inkSoft.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserEditor extends StatelessWidget {
  const _UserEditor({
    required this.user,
    required this.floors,
    required this.actorIsInstaller,
    required this.isSelf,
    required this.password,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> user;
  final List<AclNavFloor> floors;
  final bool actorIsInstaller;
  final bool isSelf;
  final TextEditingController password;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final role = normalizeRole(user['role'] as String?);
    final isInstallerAccount = role == AppRole.installer;
    final lockInstaller = isInstallerAccount && !actorIsInstaller;
    final canChangeRole = actorIsInstaller || !isInstallerAccount;
    final enabled = user['enabled'] != false;

    final roleItems = <DropdownMenuItem<String>>[
      if (actorIsInstaller || isInstallerAccount)
        const DropdownMenuItem(value: 'installer', child: Text('Installer')),
      const DropdownMenuItem(value: 'superuser', child: Text('Super user')),
      const DropdownMenuItem(value: 'user', child: Text('Gebruiker')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          lockInstaller ? 'Installer' : 'Gebruiker',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: user['username'] as String? ?? '',
          enabled: !lockInstaller,
          decoration: const InputDecoration(
            labelText: 'Gebruikersnaam',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            user['username'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: user['displayName'] as String? ?? '',
          decoration: const InputDecoration(
            labelText: 'Weergavenaam',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            user['displayName'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: switch (role) {
            AppRole.installer => 'installer',
            AppRole.superuser => 'superuser',
            AppRole.user => 'user',
          },
          decoration: const InputDecoration(
            labelText: 'Rol',
            border: OutlineInputBorder(),
          ),
          items: roleItems,
          onChanged: canChangeRole
              ? (v) {
                  if (v == null) return;
                  user['role'] = v;
                  onChanged();
                }
              : null,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            isInstallerAccount
                ? 'Installer mag inloggen'
                : 'Account actief',
          ),
          subtitle: isInstallerAccount && !actorIsInstaller
              ? const Text('Zet uit om de installer te blokkeren')
              : null,
          value: enabled,
          onChanged: isSelf
              ? null
              : (v) {
                  user['enabled'] = v;
                  onChanged();
                },
        ),
        if (!lockInstaller) ...[
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nieuw wachtwoord (leeg = ongewijzigd)',
              border: OutlineInputBorder(),
            ),
            onChanged: (s) {
              if (s.isEmpty) {
                user.remove('password');
              } else {
                user['password'] = s;
              }
              onChanged();
            },
          ),
        ],
        if (role == AppRole.user) ...[
          const SizedBox(height: 16),
          Text('Vrijgegeven toegang', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Functies, kamers of hele verdiepingen. Super user en installer zien altijd alles in de app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
          UserAccessEditor(
            user: user,
            floors: floors,
            onChanged: onChanged,
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            role == AppRole.installer
                ? 'Installer heeft alle toegang, inclusief technische configuratie.'
                : 'Super user heeft alle toegang in de app, behalve technische configuratie.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ],
        if (!isSelf && !lockInstaller) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Gebruiker verwijderen'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ],
    );
  }
}
