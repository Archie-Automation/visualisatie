import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../ui/widgets/confirm_dialog.dart';
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
  String? exceptIntercomId,
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
      if (exceptIntercomId != null && '${ic['id']}' == exceptIntercomId) {
        continue;
      }
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
          helper: extClash ? 'Dit nummer is al in gebruik.' : null,
          onChanged: (s) {
            widget.ep['ext'] = s.trim();
            widget.onChanged();
          },
        ),
        _VoipLine(
          label: 'SIP-wachtwoord',
          value: (widget.ep['password'] as String?) ?? '',
          onChanged: (s) {
            widget.ep['password'] = s;
            widget.onChanged();
          },
        ),
        if (uri.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              uri,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
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
          label: const Text('Kopieer inlog'),
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
      helper: helper,
      helperMaxLines: 2,
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
  Map<String, dynamic> user,
) {
  final existing = sipEndpointForUser(house, user);
  if (existing != null) {
    user['sipEndpointId'] = existing['id'];
    existing['userId'] = user['id'];
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
    'type': 'panel',
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

/// Indoor SIP stays automatic. This card only toggles calling on/off.
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

  @override
  Widget build(BuildContext context) {
    final enabled = _voip['enabled'] == true;
    final ami = _status?['amiUp'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionTitle(
          icon: Icons.doorbell_outlined,
          title: 'Intercom',
          subtitle:
              'Koppel een IP-deurstation aan tablets en telefoons. '
              'Indoor-accounts worden automatisch aangemaakt.',
          trailing: LuxeInfoIconButton(
            title: 'Deurbel-oproepen',
            body:
                'Zet dit aan om belknoppen naar tablets en telefoons te sturen. '
                'Elke gebruiker in een belgroep krijgt automatisch een eigen account. '
                'STUN, poorten en serveradres blijven op de achtergrond.\n\n'
                'Zet uit als dit huis alleen beeld of KNX-deur gebruikt, zonder bellen.',
          ),
        ),
        LuxeSwitchRow(
          title: 'Deurbel-oproepen naar tablets en telefoons',
          subtitle: enabled
              ? 'Toestellen in een belgroep gaan over bij aanbellen.'
              : 'Uit: alleen live beeld en deuropener, geen gesprek.',
          value: enabled,
          onChanged: (v) {
            _voip['enabled'] = v;
            widget.onChanged();
            if (v) _prefillHostFromStatus();
          },
        ),
        if (enabled) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(ami ? 'Server bereikbaar' : 'Verbinding controleren'),
            ),
          ),
          if (_statusErr != null)
            Text(
              _statusErr!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
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
