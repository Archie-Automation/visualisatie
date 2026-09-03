import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../ui/widgets/luxe_form.dart';

Map<String, dynamic> ensureVoipMap(Map<String, dynamic> house) {
  final v = house['voip'];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    house['voip'] = m;
    return m;
  }
  final m = <String, dynamic>{
    'enabled': false,
    'endpoints': <Map<String, dynamic>>[],
    'groups': <Map<String, dynamic>>[],
  };
  house['voip'] = m;
  return m;
}

String randomVoipPassword() {
  final r = Random.secure();
  final b = List<int>.generate(12, (_) => r.nextInt(256));
  return base64UrlEncode(b).replaceAll('=', '');
}

List<Map<String, dynamic>> houseUserMaps(Map<String, dynamic> house) {
  final raw = house['users'];
  if (raw is! List) return [];
  return [
    for (final u in raw)
      if (u is Map<String, dynamic>) u else if (u is Map) Map<String, dynamic>.from(u),
  ];
}

List<Map<String, dynamic>> voipEndpointMaps(Map<String, dynamic> house) {
  final raw = ensureVoipMap(house)['endpoints'];
  if (raw is! List) {
    ensureVoipMap(house)['endpoints'] = <Map<String, dynamic>>[];
    return ensureVoipMap(house)['endpoints'] as List<Map<String, dynamic>>;
  }
  return raw.cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> voipGroupMaps(Map<String, dynamic> house) {
  final raw = ensureVoipMap(house)['groups'];
  if (raw is! List) {
    ensureVoipMap(house)['groups'] = <Map<String, dynamic>>[];
    return ensureVoipMap(house)['groups'] as List<Map<String, dynamic>>;
  }
  return raw.cast<Map<String, dynamic>>();
}

String voipSipHost(Map<String, dynamic> house) {
  return ((ensureVoipMap(house)['host'] as String?) ?? '').trim();
}

int voipSipPort(Map<String, dynamic> house) {
  final p = ensureVoipMap(house)['sipPort'];
  if (p is int && p > 0) return p;
  if (p is num) return p.toInt();
  return 5060;
}

bool isLoopbackSipHost(String host) {
  final x = host.trim().toLowerCase();
  return x.isEmpty ||
      x == 'localhost' ||
      x == '127.0.0.1' ||
      x == '::1' ||
      x == '[::1]';
}

void setVoipSipHost(Map<String, dynamic> house, String value) {
  final t = value.trim();
  final v = ensureVoipMap(house);
  if (t.isEmpty) {
    v.remove('host');
  } else {
    v['host'] = t;
  }
}

String sipClientLoginText({
  required String host,
  required int port,
  required String ext,
  required String password,
}) {
  final server = host.isEmpty ? '(zet SIP-serveradres)' : host;
  final extOut = ext.isEmpty ? '(nog geen nummer)' : ext;
  final uri = host.isEmpty || ext.isEmpty ? '' : 'sip:$extOut@$server';
  return 'server=$server\n'
      'port=$port\n'
      'ext=$extOut\n'
      'user=$extOut\n'
      'pass=$password'
      '${uri.isEmpty ? '' : '\nuri=$uri'}';
}

Set<String> usedSipExts(
  Map<String, dynamic> house, {
  String? exceptEndpointId,
}) {
  final used = <String>{};
  for (final ep in voipEndpointMaps(house)) {
    if (exceptEndpointId != null && '${ep['id']}' == exceptEndpointId) continue;
    final e = (ep['ext'] as String?)?.trim() ?? '';
    if (e.isNotEmpty) used.add(e);
  }
  for (final g in voipGroupMaps(house)) {
    final e = (g['ext'] as String?)?.trim() ?? '';
    if (e.isNotEmpty) used.add(e);
  }
  final raw = house['intercoms'];
  if (raw is List) {
    for (final ic in raw) {
      if (ic is! Map) continue;
      final o = ic['intercom'];
      if (o is! Map) continue;
      final e = (o['sipExt'] as String?)?.trim() ?? '';
      if (e.isNotEmpty) used.add(e);
    }
  }
  return used;
}

String nextSipExt(Map<String, dynamic> house, {String? exceptEndpointId}) {
  final used = usedSipExts(house, exceptEndpointId: exceptEndpointId);
  var n = 201;
  while (used.contains('$n')) {
    n += 1;
  }
  return '$n';
}

void ensureSipAccountSecrets(Map<String, dynamic> house, Map<String, dynamic> ep) {
  if ((ep['ext'] as String?)?.trim().isEmpty ?? true) {
    ep['ext'] = nextSipExt(house, exceptEndpointId: '${ep['id']}');
  }
  if ((ep['password'] as String?)?.trim().isEmpty ?? true) {
    ep['password'] = randomVoipPassword();
  }
}

/// Per-user SIP number + password. Host is house-level; URI is derived.
class VoipSipAccountFields extends StatefulWidget {
  const VoipSipAccountFields({
    super.key,
    required this.house,
    required this.ep,
    required this.onChanged,
    this.includeHost = false,
  });

  final Map<String, dynamic> house;
  final Map<String, dynamic> ep;
  final VoidCallback onChanged;
  final bool includeHost;

  @override
  State<VoipSipAccountFields> createState() => _VoipSipAccountFieldsState();
}

class _VoipSipAccountFieldsState extends State<VoipSipAccountFields> {
  @override
  void initState() {
    super.initState();
    _fillIfMissing();
  }

  @override
  void didUpdateWidget(covariant VoipSipAccountFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ep != widget.ep) _fillIfMissing();
  }

  void _fillIfMissing() {
    final extEmpty = (widget.ep['ext'] as String?)?.trim().isEmpty ?? true;
    final pwEmpty = (widget.ep['password'] as String?)?.trim().isEmpty ?? true;
    if (!extEmpty && !pwEmpty) return;
    ensureSipAccountSecrets(widget.house, widget.ep);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ext = (widget.ep['ext'] as String?) ?? '';
    final host = voipSipHost(widget.house);
    final port = voipSipPort(widget.house);
    final taken = usedSipExts(widget.house, exceptEndpointId: '${widget.ep['id']}');
    final extClash = ext.trim().isNotEmpty && taken.contains(ext.trim());
    final uri = host.isNotEmpty && ext.trim().isNotEmpty
        ? '$ext@$host'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.includeHost) ...[
          VoipSipHostField(house: widget.house, onChanged: widget.onChanged),
          const SizedBox(height: 8),
        ],
        _VoipLine(
          label: 'SIP-nummer',
          value: ext,
          helper: extClash
              ? 'Dit nummer is al in gebruik.'
              : 'Uniek toestelnummer op de SIP-server. Programmeur mag dit wijzigen.',
          helperMaxLines: 2,
          onChanged: (s) {
            widget.ep['ext'] = s.trim();
            widget.onChanged();
          },
        ),
        _VoipLine(
          label: 'SIP-wachtwoord',
          value: (widget.ep['password'] as String?) ?? '',
          helper: 'Alleen voor dit toestel. Niet het inlogwachtwoord van de app.',
          helperMaxLines: 2,
          onChanged: (s) {
            widget.ep['password'] = s;
            widget.onChanged();
          },
        ),
        if (uri.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              'SIP-adres: $uri',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        SelectableText(
          sipClientLoginText(
            host: host,
            port: port,
            ext: ext,
            password: (widget.ep['password'] as String?) ?? '',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(
              text: sipClientLoginText(
                host: host,
                port: port,
                ext: ext,
                password: (widget.ep['password'] as String?) ?? '',
              ),
            ));
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Kopieer SIP-inlog'),
        ),
        TextButton(
          onPressed: () {
            widget.ep['password'] = randomVoipPassword();
            widget.onChanged();
          },
          child: const Text('Nieuw wachtwoord'),
        ),
      ],
    );
  }
}

/// House-level registrar. Shown on every user/phone; editing changes all toestellen.
class VoipSipHostField extends StatelessWidget {
  const VoipSipHostField({
    super.key,
    required this.house,
    required this.onChanged,
    this.helper,
  });

  final Map<String, dynamic> house;
  final VoidCallback onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return _VoipLine(
      label: 'SIP-serveradres (NUC)',
      value: voipSipHost(house),
      helper: helper ??
          'Zelfde adres voor alle toestellen. LAN-IP of hostname; de programmeur mag dit wijzigen.',
      helperMaxLines: 3,
      onChanged: (s) {
        setVoipSipHost(house, s);
        onChanged();
      },
    );
  }
}

String userSipLabel(Map<String, dynamic> u) {
  final dn = (u['displayName'] as String?)?.trim() ?? '';
  final un = (u['username'] as String?)?.trim() ?? '';
  if (dn.isNotEmpty && un.isNotEmpty && dn != un) return '$dn ($un)';
  if (dn.isNotEmpty) return dn;
  if (un.isNotEmpty) return un;
  return '${u['id']}';
}

Set<String> sipTakenUserIds(Map<String, dynamic> house) {
  return {
    for (final ep in voipEndpointMaps(house))
      if ((ep['userId'] as String?)?.trim().isNotEmpty == true)
        (ep['userId'] as String).trim(),
  };
}

Map<String, dynamic>? sipEndpointForUser(
  Map<String, dynamic> house,
  Map<String, dynamic> user,
) {
  final uid = '${user['id']}';
  final sid = (user['sipEndpointId'] as String?)?.trim();
  for (final ep in voipEndpointMaps(house)) {
    if (ep['userId'] == uid) return ep;
    if (sid != null && sid.isNotEmpty && ep['id'] == sid) return ep;
  }
  return null;
}

void bindSipToUser(
  Map<String, dynamic> house,
  Map<String, dynamic> user, {
  String type = 'panel',
}) {
  final existing = sipEndpointForUser(house, user);
  if (existing != null) {
    user['sipEndpointId'] = existing['id'];
    existing['userId'] = user['id'];
    if (type == 'panel' || type == 'phone') existing['type'] = type;
    return;
  }
  final uid = '${user['id']}';
  var id = 'ep-$uid';
  final endpoints = voipEndpointMaps(house);
  if (endpoints.any((e) => e['id'] == id)) {
    id = 'ep-${DateTime.now().microsecondsSinceEpoch}';
  }
  final ep = <String, dynamic>{
    'id': id,
    'userId': uid,
    'name': userSipLabel(user),
    'type': type == 'phone' ? 'phone' : 'panel',
    'ext': nextSipExt(house),
    'password': randomVoipPassword(),
  };
  endpoints.add(ep);
  user['sipEndpointId'] = id;
  final groups = voipGroupMaps(house);
  if (groups.isNotEmpty) {
    final m = groups.first['memberIds'];
    if (m is List && !m.contains(id)) m.add(id);
  }
}

void unbindSipFromUser(Map<String, dynamic> house, Map<String, dynamic> user) {
  final uid = '${user['id']}';
  final sid = (user['sipEndpointId'] as String?)?.trim();
  final endpoints = voipEndpointMaps(house);
  final removed = <dynamic>[];
  endpoints.removeWhere((e) {
    final hit = e['userId'] == uid || (sid != null && e['id'] == sid);
    if (hit) removed.add(e['id']);
    return hit;
  });
  user.remove('sipEndpointId');
  for (final g in voipGroupMaps(house)) {
    final m = g['memberIds'];
    if (m is List) m.removeWhere((id) => removed.contains(id));
  }
}

void reassignSipEndpoint(
  Map<String, dynamic> house,
  Map<String, dynamic> ep,
  Map<String, dynamic> newUser,
) {
  final newId = '${newUser['id']}';
  if (ep['userId'] == newId) return;
  for (final u in houseUserMaps(house)) {
    if (u['sipEndpointId'] == ep['id']) u.remove('sipEndpointId');
  }
  unbindSipFromUser(house, newUser);
  ep['userId'] = newId;
  newUser['sipEndpointId'] = ep['id'];
}

class VoipInstallerSection extends StatefulWidget {
  const VoipInstallerSection({
    super.key,
    required this.house,
    required this.onChanged,
    required this.getToken,
  });

  final Map<String, dynamic> house;
  final VoidCallback onChanged;
  final Future<String?> Function() getToken;

  @override
  State<VoipInstallerSection> createState() => _VoipInstallerSectionState();
}

class _VoipInstallerSectionState extends State<VoipInstallerSection> {
  Map<String, dynamic>? _status;
  String? _statusErr;

  Map<String, dynamic> get _voip => ensureVoipMap(widget.house);

  List<Map<String, dynamic>> get _endpoints {
    final raw = _voip['endpoints'];
    if (raw is! List) {
      _voip['endpoints'] = <Map<String, dynamic>>[];
    }
    return (_voip['endpoints'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> get _groups {
    final raw = _voip['groups'];
    if (raw is! List) {
      _voip['groups'] = <Map<String, dynamic>>[];
    }
    return (_voip['groups'] as List).cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final token = await widget.getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('$apiBase/api/voip/status'),
        headers: {'authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _statusErr = 'Status ${res.statusCode}');
        return;
      }
      setState(() {
        _status = jsonDecode(res.body) as Map<String, dynamic>;
        _statusErr = null;
      });
      _prefillHostFromStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusErr = '$e');
    }
  }

  void _prefillHostFromStatus() {
    if (voipSipHost(widget.house).isNotEmpty) return;
    final suggested = (_status?['suggestedHost'] as String?)?.trim() ?? '';
    if (isLoopbackSipHost(suggested)) return;
    setVoipSipHost(widget.house, suggested);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _users => houseUserMaps(widget.house);

  Future<void> _addSipForExistingUser(String type) async {
    final taken = sipTakenUserIds(widget.house);
    final free = _users.where((u) => !taken.contains('${u['id']}')).toList();
    if (free.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Geen vrij account. Maak eerst een gebruiker, of haal SIP van een ander account af.',
          ),
        ),
      );
      return;
    }
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(type == 'phone' ? 'Account voor telefoon' : 'Account voor paneel'),
          children: [
            for (final u in free)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, u),
                child: Text(userSipLabel(u)),
              ),
          ],
        );
      },
    );
    if (chosen == null) return;
    bindSipToUser(widget.house, chosen, type: type);
    widget.onChanged();
  }

  void _addGroup() {
    _groups.add({
      'id': 'grp-${DateTime.now().microsecondsSinceEpoch}',
      'name': 'Oproepgroep',
      'ext': '',
      'memberIds': _endpoints.map((e) => e['id']).toList(),
      'timeoutSec': 30,
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _voip['enabled'] == true;
    final ami = _status?['amiUp'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LuxeSwitchRow(
          title: 'Eigen SIP-server (VoIP)',
          subtitle: enabled
              ? (ami
                  ? 'PBX bereikbaar'
                  : 'Aan — Asterisk start na Opslaan (Docker-service asterisk)')
              : 'Uit. Deurstations blijven RTSP/webhook zoals nu.',
          value: enabled,
          onChanged: (v) {
            _voip['enabled'] = v;
            widget.onChanged();
            if (v) _prefillHostFromStatus();
          },
        ),
        if (_statusErr != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _statusErr!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (enabled) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Status vernieuwen'),
            ),
          ),
          const SizedBox(height: 8),
          VoipSipHostField(
            house: widget.house,
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 12),
          Text('Toestellen (één account per paneel of telefoon)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'SIP hangt niet aan alle logins. Koppel een bestaande gebruiker; '
            'elk account mag maar één keer. Dat paneel of die telefoon logt in met dat account. '
            'Op hardware: server = SIP-serveradres, poort ${voipSipPort(widget.house)}, gebruiker = nummer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _endpoints.length; i++)
            _EndpointCard(
              key: ValueKey(_endpoints[i]['id']),
              house: widget.house,
              ep: _endpoints[i],
              registered: _isReg(_endpoints[i]['ext'] as String?),
              onChanged: widget.onChanged,
              onDelete: () {
                final uid = '${_endpoints[i]['userId'] ?? ''}';
                Map<String, dynamic>? user;
                for (final u in _users) {
                  if ('${u['id']}' == uid) {
                    user = u;
                    break;
                  }
                }
                if (user != null) {
                  unbindSipFromUser(widget.house, user);
                } else {
                  final id = _endpoints[i]['id'];
                  _endpoints.removeAt(i);
                  for (final g in _groups) {
                    final m = g['memberIds'];
                    if (m is List) m.remove(id);
                  }
                }
                widget.onChanged();
              },
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _addSipForExistingUser('panel'),
                icon: const Icon(Icons.tablet_mac_outlined, size: 18),
                label: const Text('Paneel'),
              ),
              TextButton.icon(
                onPressed: () => _addSipForExistingUser('phone'),
                icon: const Icon(Icons.phone_outlined, size: 18),
                label: const Text('Telefoon'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Oproepgroepen', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Wie er overgaat als er wordt aangebeld. Bij opnemen stoppen de andere toestellen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _groups.length; i++)
            _GroupCard(
              key: ValueKey(_groups[i]['id']),
              group: _groups[i],
              endpoints: _endpoints,
              onChanged: widget.onChanged,
              onDelete: () {
                _groups.removeAt(i);
                widget.onChanged();
              },
            ),
          TextButton.icon(
            onPressed: _addGroup,
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: const Text('Groep toevoegen'),
          ),
        ],
        const Divider(height: 32),
        Text('Deurstations', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
      ],
    );
  }

  bool _isReg(String? ext) {
    final list = _status?['endpoints'];
    if (list is! List || ext == null) return false;
    for (final e in list) {
      if (e is Map && e['ext'] == ext) return e['registered'] == true;
    }
    return false;
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    super.key,
    required this.house,
    required this.ep,
    required this.registered,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> house;
  final Map<String, dynamic> ep;
  final bool registered;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final users = houseUserMaps(house);
    final taken = sipTakenUserIds(house);
    final currentId = (ep['userId'] as String?) ?? '';
    final choices = [
      for (final u in users)
        if ('${u['id']}' == currentId || !taken.contains('${u['id']}')) u,
    ];
    final currentOk = choices.any((u) => '${u['id']}' == currentId);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ep['name'] ?? ''}  ·  ${ep['ext'] ?? '(auto)'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (registered)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.circle, size: 10, color: Colors.green),
                  ),
                IconButton(
                  tooltip: 'Verwijderen',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: currentOk ? currentId : null,
              decoration: luxeFilledDecoration(
                hint: 'Gebruiker',
                helper: 'Dit account is het SIP-toestel. Niet delen.',
              ),
              items: [
                for (final u in choices)
                  DropdownMenuItem(
                    value: '${u['id']}',
                    child: Text(userSipLabel(u)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                Map<String, dynamic>? next;
                for (final u in users) {
                  if ('${u['id']}' == v) {
                    next = u;
                    break;
                  }
                }
                if (next == null) return;
                reassignSipEndpoint(house, ep, next);
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            _VoipLine(
              label: 'Naam op het toestel',
              value: ep['name'] as String? ?? '',
              onChanged: (s) {
                ep['name'] = s;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  (ep['type'] as String?) == 'phone' ? 'phone' : 'panel',
              decoration: luxeFilledDecoration(hint: 'Type'),
              items: const [
                DropdownMenuItem(value: 'panel', child: Text('Paneel / app')),
                DropdownMenuItem(value: 'phone', child: Text('SIP-telefoon')),
              ],
              onChanged: (v) {
                if (v == null) return;
                ep['type'] = v;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            VoipSipAccountFields(
              house: house,
              ep: ep,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.endpoints,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> endpoints;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final members = (group['memberIds'] is List)
        ? (group['memberIds'] as List).map((e) => '$e').toSet()
        : <String>{};
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _VoipLine(
                    label: 'Naam groep',
                    value: group['name'] as String? ?? '',
                    onChanged: (s) {
                      group['name'] = s;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Leden', style: Theme.of(context).textTheme.labelLarge),
            for (final ep in endpoints)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${ep['name']} (${ep['ext'] ?? 'auto'})'),
                value: members.contains('${ep['id']}'),
                onChanged: (v) {
                  final list = (group['memberIds'] is List)
                      ? List<dynamic>.from(group['memberIds'] as List)
                      : <dynamic>[];
                  if (v == true) {
                    if (!list.contains(ep['id'])) list.add(ep['id']);
                  } else {
                    list.remove(ep['id']);
                  }
                  group['memberIds'] = list;
                  onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _VoipLine extends StatefulWidget {
  const _VoipLine({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.helperMaxLines = 2,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? helper;
  final int helperMaxLines;

  @override
  State<_VoipLine> createState() => _VoipLineState();
}

class _VoipLineState extends State<_VoipLine> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _VoipLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: _c,
        decoration: luxeFilledDecoration(
          hint: widget.label,
          helper: widget.helper,
          helperMaxLines: widget.helperMaxLines,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
