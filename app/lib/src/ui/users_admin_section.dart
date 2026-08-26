import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../models.dart';
import '../roles.dart';
import '../theme.dart';
import '../user_api.dart';
import '../user_credentials.dart';
import 'user_access_editor.dart';
import 'widgets/back_pill.dart';
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

  @override
  void initState() {
    super.initState();
    _reload();
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  bool _canToggleEnabled(Map<String, dynamic> user) {
    final selfId = widget.cfg.me?.id;
    final selfName = ref.read(authProvider).username;
    if (selfId != null && user['id'] == selfId) return false;
    if (selfName != null && user['username'] == selfName) return false;
    return true;
  }

  Future<void> _setEnabled(Map<String, dynamic> user, bool enabled) async {
    final token = ref.read(authProvider).token;
    final users = _users;
    if (token == null || users == null) return;
    final prev = user['enabled'] != false;
    setState(() => user['enabled'] = enabled);
    try {
      final saved = await saveHouseUsers(
        users: usersPayloadForSave(users),
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _users = saved;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => user['enabled'] = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.danger,
          shape: const StadiumBorder(),
          content: Text(
            'Opslaan mislukt: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final users = _users;
    final token = ref.read(authProvider).token;
    if (users == null || token == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserEditorSheet(
        cfg: widget.cfg,
        allUsers: [for (final u in users) _copyUser(u)],
        draft: existing != null ? _copyUser(existing) : _freshUser(),
        token: token,
      ),
    );
    if (changed == true && mounted) await _reload();
  }

  Map<String, dynamic> _freshUser() => {
        'id': 'usr-${_uuid.v4()}',
        'username': '',
        'displayName': '',
        'role': 'user',
        'enabled': true,
        '_new': true,
        'access': {
          'floors': '*',
          'rooms': '*',
          'functions': '*',
          'devices': '*',
          'scenes': '*',
          'editScenes': true,
        },
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_users == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
        child: Text(_error ?? 'Geen gebruikers'),
      );
    }

    final users = _users!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 9),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'GEBRUIKERS',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (var i = 0; i < users.length; i++) ...[
              if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
              _UserRow(
                user: users[i],
                canToggle: _canToggleEnabled(users[i]),
                onTap: () => _openEditor(existing: users[i]),
                onToggle: (v) => _setEnabled(users[i], v),
              ),
            ],
            if (users.isNotEmpty)
              Divider(height: 1, color: LuxeColors.lineSoft),
            _AddUserRow(onTap: () => _openEditor()),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _copyUser(Map<String, dynamic> u) {
  final copy = Map<String, dynamic>.from(u);
  final access = copy['access'];
  if (access is Map) {
    final a = Map<String, dynamic>.from(access);
    final rf = a['roomFunctions'];
    if (rf is Map) a['roomFunctions'] = Map<String, dynamic>.from(rf);
    copy['access'] = a;
  }
  return copy;
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.canToggle,
    required this.onTap,
    required this.onToggle,
  });

  final Map<String, dynamic> user;
  final bool canToggle;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final role = user['role'] as String? ?? 'user';
    final enabled = user['enabled'] != false;
    final name = (user['displayName'] as String?)?.trim();
    final username = user['username'] as String? ?? '';
    final title = (name == null || name.isEmpty) ? username : name;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Row(
          children: [
            Icon(
              isInstallerRole(role)
                  ? Icons.construction_outlined
                  : isSuperUserRole(role)
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
              size: 18,
              color: LuxeColors.brassDeep,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'Nieuwe gebruiker' : title,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (username.isNotEmpty) username,
                      roleLabel(role),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: canToggle ? onToggle : null,
              activeThumbColor: LuxeColors.brass,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddUserRow extends StatelessWidget {
  const _AddUserRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 20, color: LuxeColors.brassDeep),
            const SizedBox(width: 10),
            Text(
              'Gebruiker toevoegen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserEditorSheet extends ConsumerStatefulWidget {
  const _UserEditorSheet({
    required this.cfg,
    required this.allUsers,
    required this.draft,
    required this.token,
  });

  final HouseConfig cfg;
  final List<Map<String, dynamic>> allUsers;
  final Map<String, dynamic> draft;
  final String token;

  @override
  ConsumerState<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends ConsumerState<_UserEditorSheet> {
  late final Map<String, dynamic> _draft;
  late final TextEditingController _password;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _isNew => _draft['_new'] == true;

  String? get _selfId {
    final name = ref.read(authProvider).username;
    if (name == null) return widget.cfg.me?.id;
    for (final u in widget.allUsers) {
      if (u['username'] == name) return u['id'] as String?;
    }
    return widget.cfg.me?.id;
  }

  List<Map<String, dynamic>> _mergedUsers({required bool deleting}) {
    final id = _draft['id'];
    if (deleting) {
      return [for (final u in widget.allUsers) if (u['id'] != id) u];
    }
    final exists = widget.allUsers.any((u) => u['id'] == id);
    if (!exists) return [...widget.allUsers, _draft];
    return [
      for (final u in widget.allUsers)
        if (u['id'] == id) _draft else u,
    ];
  }

  Future<void> _save() async {
    final next = _mergedUsers(deleting: false);
    for (final u in next) {
      u['username'] = (u['username'] as String? ?? '').trim();
    }
    final credErr = validateUsersLoginCredentials(next);
    if (credErr != null) {
      setState(() => _error = credErr);
      return;
    }
    await _persist(next);
  }

  Future<void> _delete() async {
    if (_isNew) {
      Navigator.of(context).pop(false);
      return;
    }
    await _persist(_mergedUsers(deleting: true));
  }

  Future<void> _persist(List<Map<String, dynamic>> next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveHouseUsers(
        users: usersPayloadForSave(next),
        token: widget.token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final auth = ref.watch(authProvider);
    final title = () {
      final n = (_draft['displayName'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
      final u = (_draft['username'] as String?)?.trim();
      if (u != null && u.isNotEmpty) return u;
      return _isNew ? 'Nieuwe gebruiker' : 'Gebruiker';
    }();

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: mq.size.height * 0.92,
        child: Container(
          decoration: BoxDecoration(
            color: LuxeColors.cream,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: LuxeShadows.lift,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  child: SizedBox(
                    height: HeaderIconButton.size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: HeaderIconButton.size + 8),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: LuxeColors.ink,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: BackPill(
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      _UserEditor(
                        user: _draft,
                        floors: aclFloorsFromConfig(widget.cfg),
                        extras: AclHouseExtras.fromConfig(widget.cfg),
                        actorIsInstaller: auth.isInstaller,
                        isSelf: _draft['id'] == _selfId,
                        password: _password,
                        onChanged: () => setState(() {}),
                        onDelete: _saving ? null : _delete,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Annuleren'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: LuxeColors.ink,
                            foregroundColor: LuxeColors.onInk,
                            disabledBackgroundColor:
                                LuxeColors.ink.withValues(alpha: 0.28),
                            minimumSize: const Size.fromHeight(52),
                            shape: const StadiumBorder(),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: LuxeColors.onInk,
                                  ),
                                )
                              : const Text('Opslaan'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserEditor extends StatelessWidget {
  const _UserEditor({
    required this.user,
    required this.floors,
    required this.extras,
    required this.actorIsInstaller,
    required this.isSelf,
    required this.password,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> user;
  final List<AclNavFloor> floors;
  final AclHouseExtras extras;
  final bool actorIsInstaller;
  final bool isSelf;
  final TextEditingController password;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final role = normalizeRole(user['role'] as String?);
    final isInstallerAccount = role == AppRole.installer;
    final lockInstaller = isInstallerAccount && !actorIsInstaller;
    final canChangeRole = actorIsInstaller || !isInstallerAccount;

    final roleItems = <DropdownMenuItem<String>>[
      if (actorIsInstaller || isInstallerAccount)
        const DropdownMenuItem(value: 'installer', child: Text('Installer')),
      const DropdownMenuItem(value: 'superuser', child: Text('Super user')),
      const DropdownMenuItem(value: 'user', child: Text('Gebruiker')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label: 'Inlognaam'),
        TextFormField(
          initialValue: user['username'] as String? ?? '',
          enabled: !lockInstaller,
          decoration: _userFieldDecoration(
            hint: 'Uniek, waarmee deze persoon inlogt',
          ),
          onChanged: (v) {
            user['username'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        _FieldLabel(label: 'Weergavenaam'),
        TextFormField(
          initialValue: user['displayName'] as String? ?? '',
          decoration: _userFieldDecoration(),
          onChanged: (v) {
            user['displayName'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        _FieldLabel(label: 'Rol'),
        DropdownButtonFormField<String>(
          initialValue: switch (role) {
            AppRole.installer => 'installer',
            AppRole.superuser => 'superuser',
            AppRole.user => 'user',
          },
          decoration: _userFieldDecoration(),
          items: roleItems,
          onChanged: canChangeRole
              ? (v) {
                  if (v == null) return;
                  user['role'] = v;
                  onChanged();
                }
              : null,
        ),
        if (!lockInstaller) ...[
          const SizedBox(height: 16),
          _FieldLabel(
            label: user['_new'] == true
                ? 'Code'
                : 'Nieuwe code (leeg = ongewijzigd)',
          ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: _userFieldDecoration(
              hint: user['_new'] == true ? 'Minstens 4 tekens' : null,
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
          Text(
            'Vrijgegeven toegang',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          UserAccessEditor(
            user: user,
            floors: floors,
            extras: extras,
            onChanged: onChanged,
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            role == AppRole.installer
                ? 'Installer heeft alle toegang, inclusief technische configuratie. '
                    'Dit account bestaat standaard; zet de schakelaar in de lijst uit als de installer klaar is.'
                : 'Super user (eigenaar) ziet alles in de app, behalve technische configuratie. '
                    'Kan gebruikers en mede-superusers aanmaken, en de installer in de lijst uitzetten.',
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

InputDecoration _userFieldDecoration({String? hint}) => InputDecoration(
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: LuxeColors.surface.withValues(alpha: 0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: LuxeColors.line),
      ),
    );

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
