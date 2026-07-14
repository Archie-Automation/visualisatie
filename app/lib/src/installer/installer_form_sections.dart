import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../hvac_switch_lock.dart';
import '../room_control_category.dart';

const _uuid = Uuid();

const lutronKnxRoles = [
  'switch',
  'dim_value',
  'byte',
  'percent',
  'temperature',
  'bit',
  'setpoint',
  'position',
  'scene_number',
];

const universalKnxRoles = ['bit', 'byte', 'percent', 'temperature', 'raw_int'];

/// Rol → DPT-label voor installateur (backend: ROLE_DPT in knxBus).
const universalRoleDptLabels = <String, String>{
  'bit': 'DPT 1.001 — aan/uit (bit)',
  'byte': 'DPT 5.010 — byte (0–255)',
  'percent': 'DPT 5.001 — percentage (0–100)',
  'temperature': 'DPT 9.001 — temperatuur (°C)',
  'raw_int': 'DPT 5.010 — geheel getal',
};

const universalStyles = ['primary', 'neutral', 'brass', 'danger'];

/// Zelfde lijst als in JSON — geen kopie, anders gaan .add() verloren.
List<Map<String, dynamic>> _ensureList(Map<String, dynamic> parent, String key) {
  final v = parent[key];
  if (v is List) {
    for (var i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is Map && e is! Map<String, dynamic>) {
        v[i] = Map<String, dynamic>.from(e);
      }
    }
    return v.cast<Map<String, dynamic>>();
  }
  final list = <Map<String, dynamic>>[];
  parent[key] = list;
  return list;
}

Map<String, dynamic> _ensureMap(Map<String, dynamic> parent, String key) {
  final v = parent[key];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    parent[key] = m;
    return m;
  }
  final m = <String, dynamic>{};
  parent[key] = m;
  return m;
}

bool _roleIsBool(String role) => role == 'switch' || role == 'bit';

/// Eén KNX-telegram (GA + rol + waarde) — gedeeld door Lutron-keypad en universeel paneel.
class KnxTelegramEditor extends StatelessWidget {
  const KnxTelegramEditor({
    super.key,
    required this.title,
    required this.knx,
    required this.roles,
    required this.onChanged,
    this.showPulseMs = false,
    this.roleLabels,
  });

  final String title;
  final Map<String, dynamic> knx;
  final List<String> roles;
  final VoidCallback onChanged;
  final bool showPulseMs;
  /// Optioneel: rol → weergavenaam (bijv. DPT-omschrijving).
  final Map<String, String>? roleLabels;

  @override
  Widget build(BuildContext context) {
    final role = (knx['role'] as String?) ?? roles.first;
    if (!roles.contains(role)) {
      knx['role'] = roles.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        _InstallerStrField(
          label: 'Groepadres (x/y/z)',
          value: knx['ga'] as String? ?? '',
          onChanged: (v) {
            knx['ga'] = v;
            onChanged();
          },
        ),
        _InstallerDropdown(
          label: roleLabels != null ? 'Datatype (DPT)' : 'KNX-rol',
          value: knx['role'] as String? ?? roles.first,
          options: roles,
          optionLabels: roleLabels,
          onChanged: (v) {
            knx['role'] = v;
            onChanged();
          },
        ),
        if (_roleIsBool(role))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Waarde (aan)'),
            value: knx['value'] == true || knx['value'] == 1,
            onChanged: (v) {
              knx['value'] = v;
              onChanged();
            },
          )
        else
          _InstallerStrField(
            label: 'Waarde',
            value: '${knx['value'] ?? 0}',
            number: true,
            onChanged: (v) {
              final n = num.tryParse(v);
              knx['value'] = n ?? 0;
              onChanged();
            },
          ),
        if (showPulseMs && _roleIsBool(role))
          _InstallerStrField(
            label: 'Pulsduur (ms, optioneel)',
            value: knx['pulseMs'] == null ? '' : '${knx['pulseMs']}',
            number: true,
            onChanged: (v) {
              if (v.trim().isEmpty) {
                knx.remove('pulseMs');
              } else {
                knx['pulseMs'] = int.tryParse(v) ?? 250;
              }
              onChanged();
            },
          ),
      ],
    );
  }
}

/// Lutron keypad → KNX mappings (geen JSON).
class LutronButtonToKnxListEditor extends StatelessWidget {
  const LutronButtonToKnxListEditor({
    super.key,
    required this.parent,
    this.listKey = 'buttonToKnx',
    required this.onChanged,
  });

  final Map<String, dynamic> parent;
  final String listKey;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final maps = _ensureList(parent, listKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Keypad-knoppen → KNX',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                maps.add({
                  'id': 'map-${_uuid.v4()}',
                  'label': 'Nieuwe knop',
                  'integrationId': 1,
                  'componentNumber': 1,
                  'actionNumber': 3,
                  'knx': {
                    'ga': '1/1/1',
                    'role': 'switch',
                    'value': true,
                    'pulseMs': 250,
                  },
                });
                onChanged();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Mapping'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (maps.isEmpty)
          Text(
            'Nog geen mappings. Voeg een regel toe als een Lutron-keypad een KNX-actie moet starten.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var i = 0; i < maps.length; i++)
          _LutronMappingCard(
            key: ValueKey(maps[i]['id'] ?? 'm$i'),
            mapping: maps[i],
            onChanged: onChanged,
            onDelete: () {
              maps.removeAt(i);
              onChanged();
            },
          ),
      ],
    );
  }
}

/// Vaste actienummers in het Lutron QSX/QS Integration Protocol.
const _lutronActions = <String, int?>{
  'Alle acties (elke druk)': null,
  'Druk (korte druk) — actie 3': 3,
  'Loslaten — actie 4': 4,
  'Vasthouden (lange druk) — actie 5': 5,
  'Dubbel tikken — actie 6': 6,
  'Aangepast…': -1, // schildwacht voor vrij veld
};

class _LutronMappingCard extends StatefulWidget {
  const _LutronMappingCard({
    super.key,
    required this.mapping,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> mapping;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_LutronMappingCard> createState() => _LutronMappingCardState();
}

class _LutronMappingCardState extends State<_LutronMappingCard> {
  /// Geeft de huidige dropdown-sleutel terug op basis van `mapping['actionNumber']`.
  String _dropdownKey() {
    final cur = widget.mapping['actionNumber'];
    if (cur == null) return 'Alle acties (elke druk)';
    final num = cur is int ? cur : int.tryParse('$cur');
    for (final entry in _lutronActions.entries) {
      if (entry.value == num) return entry.key;
    }
    return 'Aangepast…';
  }

  @override
  Widget build(BuildContext context) {
    final mapping = widget.mapping;
    final knx = _ensureMap(mapping, 'knx');
    final dropKey = _dropdownKey();
    final isCustom = dropKey == 'Aangepast…';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mapping['label'] as String? ?? 'Mapping',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Verwijderen',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            _InstallerStrField(
              label: 'Label (in app)',
              value: mapping['label'] as String? ?? '',
              onChanged: (v) {
                mapping['label'] = v;
                widget.onChanged();
              },
            ),
            _InstallerStrField(
              label: 'Integration ID (Lutron)',
              value: '${mapping['integrationId'] ?? ''}',
              number: true,
              onChanged: (v) {
                mapping['integrationId'] = int.tryParse(v) ?? 1;
                widget.onChanged();
              },
            ),
            _InstallerStrField(
              label: 'Component-nummer (knopnummer op keypad)',
              value: '${mapping['componentNumber'] ?? ''}',
              number: true,
              onChanged: (v) {
                mapping['componentNumber'] = int.tryParse(v) ?? 1;
                widget.onChanged();
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey('action-$dropKey'),
                decoration: const InputDecoration(
                  labelText: 'Knopactie (Lutron QSX/QS)',
                  border: OutlineInputBorder(),
                ),
                value: dropKey,
                items: [
                  for (final label in _lutronActions.keys)
                    DropdownMenuItem(value: label, child: Text(label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final val = _lutronActions[v];
                  setState(() {
                    if (val == null) {
                      mapping.remove('actionNumber');
                    } else if (val == -1) {
                      // Aangepast — bewaar huidige waarde of zet 3
                      mapping['actionNumber'] ??= 3;
                    } else {
                      mapping['actionNumber'] = val;
                    }
                  });
                  widget.onChanged();
                },
              ),
            ),
            if (isCustom)
              _InstallerStrField(
                label: 'Actienummer (vrij invullen)',
                value: mapping['actionNumber'] == null
                    ? ''
                    : '${mapping['actionNumber']}',
                number: true,
                onChanged: (v) {
                  setState(() {
                    if (v.trim().isEmpty) {
                      mapping.remove('actionNumber');
                    } else {
                      mapping['actionNumber'] = int.tryParse(v);
                    }
                  });
                  widget.onChanged();
                },
              ),
            const SizedBox(height: 12),
            KnxTelegramEditor(
              title: 'KNX-actie bij dit event',
              knx: knx,
              roles: lutronKnxRoles,
              showPulseMs: true,
              onChanged: widget.onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Universeel knoppaneel — knoppen met KNX-telegrammen (geen JSON).
class UniversalPanelInstallerSection extends StatefulWidget {
  const UniversalPanelInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<UniversalPanelInstallerSection> createState() =>
      _UniversalPanelInstallerSectionState();
}

class _UniversalPanelInstallerSectionState
    extends State<UniversalPanelInstallerSection> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _addButton(List<Map<String, dynamic>> buttons) {
    buttons.add({
      'id': 'btn-${_uuid.v4()}',
      'label': 'Knop ${buttons.length + 1}',
      'style': 'neutral',
      'action': {'ga': '1/1/1', 'role': 'bit', 'value': true},
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final uni = _ensureMap(widget.device, 'universal');
    final buttons = _ensureList(uni, 'buttons');
    final currentIcon = uni['icon'] as String? ?? 'grid';
    const maxButtons = 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Universeel knoppaneel',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Geef het paneel een naam (zie het "Naam"-veld hierboven) en kies '
          'een icoon. Voeg maximaal 8 knoppen toe — elke knop stuurt een '
          'KNX-telegram. De knoppen verschijnen als één bedieningspaneel.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('Icoon voor de groepsknop',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _UniversalIconPicker(
          value: currentIcon,
          onChanged: (v) {
            uni['icon'] = v;
            _notify();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Knoppen (${buttons.length}/$maxButtons)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: buttons.length < maxButtons
                  ? () => _addButton(buttons)
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Toevoegen'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (buttons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nog geen knoppen. Tik op "Toevoegen".',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        for (var i = 0; i < buttons.length; i++)
          _UniversalButtonCard(
            key: ValueKey(buttons[i]['id'] ?? 'b$i'),
            button: buttons[i],
            onChanged: _notify,
            onDelete: () {
              buttons.removeAt(i);
              _notify();
            },
          ),
      ],
    );
  }
}

/// Grid of selectable icons for a universal panel.
class _UniversalIconPicker extends StatelessWidget {
  const _UniversalIconPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in kUniversalIconMap.entries)
          Tooltip(
            message: entry.key,
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: value == entry.key
                      ? accent.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: value == entry.key
                        ? accent
                        : Theme.of(context).dividerColor,
                    width: value == entry.key ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  entry.value,
                  size: 22,
                  color: value == entry.key
                      ? accent
                      : Theme.of(context)
                          .iconTheme
                          .color
                          ?.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _UniversalButtonMode { single, toggle }

class _UniversalButtonCard extends StatefulWidget {
  const _UniversalButtonCard({
    super.key,
    required this.button,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> button;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_UniversalButtonCard> createState() => _UniversalButtonCardState();
}

class _UniversalButtonCardState extends State<_UniversalButtonCard> {
  _UniversalButtonMode get _mode =>
      widget.button['actionOff'] != null
          ? _UniversalButtonMode.toggle
          : _UniversalButtonMode.single;

  void _setMode(_UniversalButtonMode mode) {
    final b = widget.button;
    final action = _ensureMap(b, 'action');
    if (mode == _UniversalButtonMode.toggle) {
      b['actionOff'] ??= {
        'ga': action['ga'] ?? '1/1/1',
        'role': action['role'] ?? 'bit',
        'value': false,
      };
      b['statusGa'] ??= action['ga'] ?? '1/1/1';
    } else {
      b.remove('actionOff');
      b.remove('statusGa');
      b.remove('statusOnValue');
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.button;
    final action = _ensureMap(b, 'action');
    final isToggle = _mode == _UniversalButtonMode.toggle;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b['label'] as String? ?? 'Knop',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Knop verwijderen',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            _InstallerStrField(
              key: ValueKey('ul-${b['id']}-label'),
              label: 'Label in de app',
              value: b['label'] as String? ?? '',
              onChanged: (v) {
                b['label'] = v;
                widget.onChanged();
              },
            ),
            _IconPickerField(
              label: 'Icoon (optioneel — vervangt de tekst als het label leeg is)',
              value: b['icon'] as String?,
              onChanged: (v) {
                if (v == null) {
                  b.remove('icon');
                } else {
                  b['icon'] = v;
                }
                widget.onChanged();
              },
            ),
            _InstallerDropdown(
              label: 'Stijl',
              value: (b['style'] as String?) ?? 'neutral',
              options: universalStyles,
              optionLabels: const {
                'primary': 'Primair (accent)',
                'neutral': 'Neutraal',
                'brass': 'Messing',
                'danger': 'Waarschuwing',
              },
              onChanged: (v) {
                b['style'] = v;
                widget.onChanged();
              },
            ),
            _InstallerDropdown(
              label: 'Gedrag',
              value: isToggle ? 'toggle' : 'single',
              options: const ['single', 'toggle'],
              optionLabels: const {
                'single': 'Enkele actie (elke druk hetzelfde)',
                'toggle': 'Schakelaar (toggle aan/uit)',
              },
              onChanged: (v) {
                _setMode(
                  v == 'toggle'
                      ? _UniversalButtonMode.toggle
                      : _UniversalButtonMode.single,
                );
              },
            ),
            const Divider(height: 24),
            KnxTelegramEditor(
              title: isToggle ? 'Actie — aan' : 'KNX bij drukken',
              knx: action,
              roles: universalKnxRoles,
              roleLabels: universalRoleDptLabels,
              onChanged: widget.onChanged,
            ),
            if (isToggle) ...[
              const Divider(height: 24),
              KnxTelegramEditor(
                title: 'Actie — uit',
                knx: _ensureMap(b, 'actionOff'),
                roles: universalKnxRoles,
                roleLabels: universalRoleDptLabels,
                onChanged: widget.onChanged,
              ),
              const SizedBox(height: 8),
              Text(
                'Status (aanbevolen bij toggle)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'De app leest dit groepsadres om te weten of de knop “aan” staat. '
                'Zonder status-GA wisselt elke druk tussen aan- en uit-actie.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _InstallerStrField(
                key: ValueKey('ul-${b['id']}-stga'),
                label: 'Status groepsadres',
                value: b['statusGa'] as String? ?? '',
                onChanged: (v) {
                  if (v.trim().isEmpty) {
                    b.remove('statusGa');
                  } else {
                    b['statusGa'] = v;
                  }
                  widget.onChanged();
                },
              ),
              if ((b['statusGa'] as String?)?.trim().isNotEmpty == true)
                if (_roleIsBool(action['role'] as String? ?? 'bit'))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Status “aan” = bit 1'),
                    value:
                        b['statusOnValue'] == true || b['statusOnValue'] == 1,
                    onChanged: (v) {
                      b['statusOnValue'] = v;
                      widget.onChanged();
                    },
                  )
                else
                  _InstallerStrField(
                    key: ValueKey('ul-${b['id']}-ston'),
                    label: 'Waarde die “aan” betekent',
                    value: '${b['statusOnValue'] ?? 1}',
                    number: true,
                    onChanged: (v) {
                      final n = num.tryParse(v);
                      b['statusOnValue'] = n ?? 1;
                      widget.onChanged();
                    },
                  ),
            ],

            // -- Bevestigingsoptie --------------------------------------------
            const Divider(height: 24),
            _UniversalButtonConfirmSection(
              button: b,
              onChanged: () {
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

}

// -- Universal button confirm section -------------------------------------------

/// Bevestigingsoptie per universele knop.
/// Keuze: geen / eenvoudig ja-nee / 4-cijferige PIN.
class _UniversalButtonConfirmSection extends StatefulWidget {
  const _UniversalButtonConfirmSection({
    super.key,
    required this.button,
    required this.onChanged,
  });

  final Map<String, dynamic> button;
  final VoidCallback onChanged;

  @override
  State<_UniversalButtonConfirmSection> createState() =>
      _UniversalButtonConfirmSectionState();
}

class _UniversalButtonConfirmSectionState
    extends State<_UniversalButtonConfirmSection> {

  // Returns null if no confirm, "simple" or "pin"
  String? get _confirmType {
    final c = widget.button['confirm'];
    if (c == null || c == false) return null;
    if (c is Map && c['pin'] != null) return 'pin';
    return 'simple';
  }

  void _setConfirmType(String? type) {
    final b = widget.button;
    if (type == null) {
      b.remove('confirm');
    } else if (type == 'simple') {
      b['confirm'] = {'title': 'Bevestigen'};
    } else {
      // pin — keep existing pin or set empty placeholder
      final existing = b['confirm'];
      final oldPin = (existing is Map) ? existing['pin'] as String? : null;
      b['confirm'] = {
        'title': 'PIN-bevestiging',
        'pin': oldPin ?? '0000',
      };
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final type = _confirmType;
    final confirm = widget.button['confirm'];
    final pin = (confirm is Map) ? confirm['pin'] as String? : null;
    final message = (confirm is Map) ? confirm['message'] as String? : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bevestiging', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          'Vraag de gebruiker om te bevestigen voordat de knop het commando verstuurt.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _InstallerDropdown(
          label: 'Bevestigingstype',
          value: type ?? 'none',
          options: const ['none', 'simple', 'pin'],
          optionLabels: const {
            'none': 'Geen bevestiging',
            'simple': 'Bevestigingsvraag (Ja / Nee)',
            'pin': 'PIN-code (4 cijfers)',
          },
          onChanged: (v) => _setConfirmType(v == 'none' ? null : v),
        ),
        if (type == 'simple' || type == 'pin') ...[
          _InstallerStrField(
            key: ValueKey('ucf-${widget.button['id']}-msg'),
            label: 'Bevestigingstekst (optioneel)',
            value: message ?? '',
            onChanged: (v) {
              final c = _ensureMap(widget.button, 'confirm');
              if (v.trim().isEmpty) c.remove('message'); else c['message'] = v.trim();
              widget.onChanged();
            },
          ),
        ],
        if (type == 'pin') ...[
          _InstallerStrField(
            key: ValueKey('ucf-${widget.button['id']}-pin'),
            label: '4-cijferige PIN *',
            value: pin ?? '',
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'[^0-9]'), '').substring(
                  0, v.replaceAll(RegExp(r'[^0-9]'), '').length.clamp(0, 4));
              final c = _ensureMap(widget.button, 'confirm');
              c['pin'] = digits;
              widget.onChanged();
            },
          ),
          if ((pin ?? '').length != 4)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Vul precies 4 cijfers in.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Climate installer section ────────────────────────────────────────────────

class ClimateInstallerSection extends StatefulWidget {
  const ClimateInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<ClimateInstallerSection> createState() =>
      _ClimateInstallerSectionState();
}

class _ClimateInstallerSectionState extends State<ClimateInstallerSection> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ga  = _ensureMap(widget.device, 'ga');
    final cfg = _ensureMap(widget.device, 'climate');

    final canHeat          = cfg['canHeat'] as bool? ?? true;
    final canCool          = cfg['canCool'] as bool? ?? false;
    final userCanSwitch    = cfg['userCanSwitchMode'] as bool? ?? false;
    final lockDurationRaw  = cfg['hvacSwitchLockDuration'] as String? ?? '4:00';
    final lockDuration     = HvacSwitchLockDuration.parse(lockDurationRaw);
    final showSwitchLock   = userCanSwitch && canHeat && canCool;

    String gaVal(String key) => ga[key] as String? ?? '';
    void setGa(String key, String v) {
      if (v.trim().isEmpty) ga.remove(key); else ga[key] = v.trim();
      _notify();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Thermostaat / Klimaat',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Stel per functie het juiste KNX-groepsadres in. '
          'Gebruik de capabilities-vlaggen onderaan om de app-weergave te configureren.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // ── Temperatuur ─────────────────────────────────────────────
        Text('Temperatuur', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-at'),
          label: 'GA gemeten temperatuur (DPT 9.001) *',
          value: gaVal('actual_temp'),
          onChanged: (v) => setGa('actual_temp', v),
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-sp'),
          label: 'GA gewenste temperatuur / setpoint (DPT 9.001) *',
          value: gaVal('setpoint'),
          onChanged: (v) => setGa('setpoint', v),
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-ss'),
          label: 'GA setpoint status (lezen, optioneel)',
          value: gaVal('setpoint_status'),
          onChanged: (v) => setGa('setpoint_status', v),
        ),
        const SizedBox(height: 12),

        // ── HVAC modus ──────────────────────────────────────────────
        Text('Verwarm / Koel modus', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'DPT 1.100: 1 = verwarmen, 0 = koelen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hvac'),
          label: 'GA verwarm/koel schakelaar (schrijven, als gebruiker omschakelt)',
          value: gaVal('hvac_mode'),
          onChanged: (v) => setGa('hvac_mode', v),
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hvacst'),
          label: 'GA verwarm/koel status (lezen, systeem meldt modus)',
          value: gaVal('hvac_mode_status'),
          onChanged: (v) => setGa('hvac_mode_status', v),
        ),
        const SizedBox(height: 12),

        // ── Vraagmeldingen ───────────────────────────────────────────
        Text('Vraagmeldingen', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Geeft aan of er in de ruimte actief warmte- of koudevraag is (DPT 1.x).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hd'),
          label: 'GA warmtevraag melding (lezen)',
          value: gaVal('heat_demand'),
          onChanged: (v) => setGa('heat_demand', v),
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-cd'),
          label: 'GA koudevraag melding (lezen)',
          value: gaVal('cool_demand'),
          onChanged: (v) => setGa('cool_demand', v),
        ),
        const SizedBox(height: 12),

        // ── Bedrijfsmodus (optioneel) ────────────────────────────────
        Text('Bedrijfsmodus (DPT 20.102)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-mode'),
          label: 'GA bedrijfsmodus (comfort/standby/nacht, schrijven)',
          value: gaVal('mode'),
          onChanged: (v) => setGa('mode', v),
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-modest'),
          label: 'GA bedrijfsmodus status (lezen)',
          value: gaVal('mode_status'),
          onChanged: (v) => setGa('mode_status', v),
        ),
        const SizedBox(height: 16),

        // ── Setpoint bereik en stapgrootte ───────────────────────────
        Text('Setpoint bereik & stapgrootte',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _InstallerStrField(
                key: ValueKey('cl-${widget.device['id']}-mint'),
                label: 'Min °C (standaard 5)',
                value: (cfg['minTemp'] as num?)?.toString() ?? '',
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) cfg['minTemp'] = n; else cfg.remove('minTemp');
                  _notify();
                },
                number: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InstallerStrField(
                key: ValueKey('cl-${widget.device['id']}-maxt'),
                label: 'Max °C (standaard 35)',
                value: (cfg['maxTemp'] as num?)?.toString() ?? '',
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) cfg['maxTemp'] = n; else cfg.remove('maxTemp');
                  _notify();
                },
                number: true,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<double>(
            value: (cfg['tempStep'] as num?)?.toDouble() ?? 0.5,
            decoration: const InputDecoration(
                labelText: 'Stapgrootte', isDense: true),
            items: const [
              DropdownMenuItem(value: 0.1, child: Text('0.1 °C')),
              DropdownMenuItem(value: 0.5, child: Text('0.5 °C')),
              DropdownMenuItem(value: 1.0, child: Text('1 °C')),
            ],
            onChanged: (v) {
              if (v != null) cfg['tempStep'] = v;
              _notify();
            },
          ),
        ),
        const SizedBox(height: 12),

        // ── Bedrijfsmodi ─────────────────────────────────────────────
        Text('Bedrijfsmodi (DPT 20.102)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Vink de modi uit die het systeem niet ondersteunt. '
          'Alleen zichtbaar als GA bedrijfsmodus is ingevuld.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Builder(builder: (context) {
          final modesMap = (cfg['modes'] as Map<String, dynamic>?) ??
              <String, dynamic>{};
          cfg['modes'] = modesMap;
          bool modeEnabled(String key) => modesMap[key] != false;
          void toggleMode(String key, bool v) {
            modesMap[key] = v;
            _notify();
          }
          return Column(
            children: [
              _SectionToggle(
                  label: 'Comfort (waarde 1)',
                  value: modeEnabled('comfort'),
                  onChanged: (v) => toggleMode('comfort', v)),
              _SectionToggle(
                  label: 'Standby (waarde 2)',
                  value: modeEnabled('standby'),
                  onChanged: (v) => toggleMode('standby', v)),
              _SectionToggle(
                  label: 'Economy (waarde 3)',
                  value: modeEnabled('economy'),
                  onChanged: (v) => toggleMode('economy', v)),
              _SectionToggle(
                  label: 'Gebouwbeveiliging (waarde 4)',
                  value: modeEnabled('buildingProtection'),
                  onChanged: (v) => toggleMode('buildingProtection', v)),
            ],
          );
        }),
        const SizedBox(height: 12),

        // ── Capabilities ─────────────────────────────────────────────
        Text('Mogelijkheden (bepaalt weergave in de app)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _SectionToggle(
          label: 'Systeem kan verwarmen',
          value: canHeat,
          onChanged: (v) { cfg['canHeat'] = v; _notify(); },
        ),
        _SectionToggle(
          label: 'Systeem kan koelen',
          value: canCool,
          onChanged: (v) { cfg['canCool'] = v; _notify(); },
        ),
        _SectionToggle(
          label: 'Gebruiker kan zelf omschakelen (verwarm ↔ koel)',
          value: userCanSwitch,
          onChanged: (v) {
            cfg['userCanSwitchMode'] = v;
            if (v && cfg['hvacSwitchLockDuration'] == null) {
              cfg['hvacSwitchLockDuration'] = '4:00';
            }
            _notify();
          },
        ),
        if (showSwitchLock) ...[
          const SizedBox(height: 4),
          _InstallerStrField(
            key: ValueKey('cl-${widget.device['id']}-hvaclock'),
            label: 'Vergrendeling na omschakelen (u:mm, bijv. 4:00)',
            value: lockDurationRaw,
            onChanged: (v) {
              final trimmed = v.trim();
              if (trimmed.isEmpty) {
                cfg.remove('hvacSwitchLockDuration');
              } else {
                cfg['hvacSwitchLockDuration'] = trimmed;
              }
              _notify();
            },
          ),
          if (!lockDuration.hasLock)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '0:00 = geen vergrendeling na omschakelen. '
                      'De gebruiker krijgt wel een waarschuwing dat '
                      'frequent omschakelen niet efficiënt is.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Na omschakelen is de knop ${lockDuration.formatForDialog()} '
                'niet bruikbaar.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
        if (!userCanSwitch && (canHeat || canCool))
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Het systeem bepaalt de modus. De app toont alleen de status-indicatie.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}

// ── Fan installer section ────────────────────────────────────────────────────

class FanInstallerSection extends StatefulWidget {
  const FanInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<FanInstallerSection> createState() => _FanInstallerSectionState();
}

class _FanInstallerSectionState extends State<FanInstallerSection> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final fan       = _ensureMap(widget.device, 'fan');
    final onOff     = _ensureMap(fan, 'onOff');
    final hasSpeed  = fan.containsKey('speed');
    final hasOsc    = fan.containsKey('oscillate');
    final hasDir    = fan.containsKey('direction');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ventilator', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Vul minimaal de Aan/Uit-GA in. Voeg optioneel snelheid, oscillatie en richting toe.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // ── Aan / Uit ──────────────────────────────────────────────────
        Text('Aan / Uit', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('fan-${widget.device['id']}-onoff-ga'),
          label: 'GA aan/uit (DPT 1.001)',
          value: onOff['ga'] as String? ?? '',
          onChanged: (v) { onOff['ga'] = v; _notify(); },
        ),
        _InstallerStrField(
          key: ValueKey('fan-${widget.device['id']}-onoff-st'),
          label: 'Status GA (optioneel)',
          value: onOff['statusGa'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) onOff.remove('statusGa'); else onOff['statusGa'] = v;
            _notify();
          },
        ),
        const SizedBox(height: 12),

        // ── Snelheid ───────────────────────────────────────────────────
        _SectionToggle(
          label: 'Snelheidsbesturing toevoegen',
          value: hasSpeed,
          onChanged: (v) {
            if (v) {
              fan['speed'] = {'ga': '1/1/2', 'speedMode': 'steps', 'steps': 3};
            } else {
              fan.remove('speed');
            }
            _notify();
          },
        ),
        if (hasSpeed) _FanSpeedSection(
          speed: _ensureMap(fan, 'speed'),
          deviceId: widget.device['id'] as String,
          onChanged: _notify,
        ),

        // ── Oscillatie ─────────────────────────────────────────────────
        _SectionToggle(
          label: 'Oscillatie toevoegen',
          value: hasOsc,
          onChanged: (v) {
            if (v) fan['oscillate'] = {'ga': '1/1/3'}; else fan.remove('oscillate');
            _notify();
          },
        ),
        if (hasOsc) ...[
          _InstallerStrField(
            key: ValueKey('fan-${widget.device['id']}-osc-ga'),
            label: 'GA oscillatie (DPT 1.001)',
            value: (_ensureMap(fan, 'oscillate'))['ga'] as String? ?? '',
            onChanged: (v) { _ensureMap(fan, 'oscillate')['ga'] = v; _notify(); },
          ),
          _InstallerStrField(
            key: ValueKey('fan-${widget.device['id']}-osc-st'),
            label: 'Status GA oscillatie (optioneel)',
            value: (_ensureMap(fan, 'oscillate'))['statusGa'] as String? ?? '',
            onChanged: (v) {
              final m = _ensureMap(fan, 'oscillate');
              if (v.trim().isEmpty) m.remove('statusGa'); else m['statusGa'] = v;
              _notify();
            },
          ),
        ],

        // ── Richting ───────────────────────────────────────────────────
        _SectionToggle(
          label: 'Richtingomkering toevoegen',
          value: hasDir,
          onChanged: (v) {
            if (v) fan['direction'] = {'ga': '1/1/4'}; else fan.remove('direction');
            _notify();
          },
        ),
        if (hasDir) ...[
          _InstallerStrField(
            key: ValueKey('fan-${widget.device['id']}-dir-ga'),
            label: 'GA richting (DPT 1.001)',
            value: (_ensureMap(fan, 'direction'))['ga'] as String? ?? '',
            onChanged: (v) { _ensureMap(fan, 'direction')['ga'] = v; _notify(); },
          ),
          _InstallerStrField(
            key: ValueKey('fan-${widget.device['id']}-dir-st'),
            label: 'Status GA richting (optioneel)',
            value: (_ensureMap(fan, 'direction'))['statusGa'] as String? ?? '',
            onChanged: (v) {
              final m = _ensureMap(fan, 'direction');
              if (v.trim().isEmpty) m.remove('statusGa'); else m['statusGa'] = v;
              _notify();
            },
          ),
        ],
      ],
    );
  }
}

class _FanSpeedSection extends StatelessWidget {
  const _FanSpeedSection({
    required this.speed,
    required this.deviceId,
    required this.onChanged,
  });

  final Map<String, dynamic> speed;
  final String deviceId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final speedMode = speed['speedMode'] as String? ?? 'steps';
    final steps     = (speed['steps'] as num?)?.toInt() ?? 3;
    final labels    = (speed['stepLabels'] as List?)
        ?.map((e) => e?.toString() ?? '')
        .toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerStrField(
          key: ValueKey('fan-$deviceId-spd-ga'),
          label: 'GA snelheid',
          value: speed['ga'] as String? ?? '',
          onChanged: (v) { speed['ga'] = v; onChanged(); },
        ),
        _InstallerStrField(
          key: ValueKey('fan-$deviceId-spd-st'),
          label: 'Status GA snelheid (optioneel)',
          value: speed['statusGa'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) speed.remove('statusGa'); else speed['statusGa'] = v;
            onChanged();
          },
        ),
        _InstallerDropdown(
          label: 'Bediening',
          value: speedMode,
          options: const ['steps', 'byte', 'percent'],
          optionLabels: const {
            'steps':   'Discrete standen (knoppen)',
            'byte':    'Continue byte-schuif (0–255, DPT 5.010)',
            'percent': 'Continue procent-schuif (0–100, DPT 5.001)',
          },
          onChanged: (v) {
            speed['speedMode'] = v;
            if (v != 'steps') speed.remove('steps');
            onChanged();
          },
        ),
        if (speedMode == 'steps') ...[
          _InstallerDropdown(
            label: 'Aantal standen',
            value: '$steps',
            options: const ['2', '3', '4', '5', '6', '7', '8', '9', '10'],
            onChanged: (v) {
              final n = int.tryParse(v) ?? 3;
              speed['steps'] = n;
              // Trim or grow labels list to match
              final cur = (speed['stepLabels'] as List?)
                  ?.map((e) => e?.toString() ?? '')
                  .toList() ?? [];
              while (cur.length < n) cur.add('');
              speed['stepLabels'] = cur.sublist(0, n);
              onChanged();
            },
          ),
          const SizedBox(height: 4),
          Text('Labels per stand (laat leeg voor "Stand 1", "Stand 2", …)',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          for (int i = 0; i < steps; i++)
            _InstallerStrField(
              key: ValueKey('fan-$deviceId-lbl-$i'),
              label: 'Stand ${i + 1}',
              value: i < labels.length ? labels[i] : '',
              onChanged: (v) {
                final cur = (speed['stepLabels'] as List?)
                    ?.map((e) => e?.toString() ?? '')
                    .toList() ?? List.filled(steps, '');
                while (cur.length <= i) cur.add('');
                cur[i] = v;
                speed['stepLabels'] = cur;
                onChanged();
              },
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Small toggle with a label — replaces a full SwitchListTile with less padding.
class _SectionToggle extends StatelessWidget {
  const _SectionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InstallerStrField extends StatefulWidget {
  const _InstallerStrField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.number = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool number;

  @override
  State<_InstallerStrField> createState() => _InstallerStrFieldState();
}

class _InstallerStrFieldState extends State<_InstallerStrField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_InstallerStrField old) {
    super.didUpdateWidget(old);
    // Sync only if the value changed externally (not from the user typing).
    if (old.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
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
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: widget.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// RGB/WW-driver — modus en GA’s zonder JSON.
class RgbwWwInstallerSection extends StatelessWidget {
  const RgbwWwInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cfg  = _ensureMap(device, 'rgbwWw');
    final mode = (cfg['mode'] as String?) ?? 'channels';
    final ga   = _ensureMap(device, 'ga');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('RGB / W / WW — Kleurbesturing',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Kies de modus die overeenkomt met uw KNX-installatie. '
          'In de app verschijnt automatisch een kleurenwiel of CCT-strip.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        _InstallerStrField(
          key: ValueKey('ga-${device['id']}-on'),
          label: 'GA Aan/Uit schakelaar (DPT 1.001, optioneel)',
          value: ga['on'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) ga.remove('on'); else ga['on'] = v.trim();
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        _InstallerDropdown(
          label: 'Modus',
          value: mode,
          options: const ['channels', 'rgb232', 'tunable_white', 'composite'],
          optionLabels: const {
            'channels':       'Losse kanalen (r / g / b / w / ww / cw)',
            'rgb232':         'DPT 232.600 — RGB op één GA',
            'tunable_white':  'Tunable White — CCT via ww+cw of kelvin+bright',
            'composite':      'Composite — ruwe bytes (fabrikant-specifiek)',
          },
          onChanged: (v) {
            cfg['mode'] = v;
            onChanged();
          },
        ),

        // ── channels ──────────────────────────────────────────────────────
        if (mode == 'channels') ...[
          Text('Groepsadressen (laat leeg als kanaal niet aanwezig is)',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          for (final entry in const {
            'r':  'Rood (DPT 5.010)',
            'g':  'Groen (DPT 5.010)',
            'b':  'Blauw (DPT 5.010)',
            'w':  'Wit (DPT 5.010) — onafhankelijk',
            'ww': 'Warm Wit (DPT 5.010)',
            'cw': 'Koud Wit (DPT 5.010)',
          }.entries)
            _InstallerStrField(
              key: ValueKey('ga-${device['id']}-${entry.key}'),
              label: 'GA ${entry.key} — ${entry.value}',
              value: ga[entry.key] as String? ?? '',
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  ga.remove(entry.key);
                } else {
                  ga[entry.key] = v;
                }
                onChanged();
              },
            ),
        ],

        // ── rgb232 ────────────────────────────────────────────────────────
        if (mode == 'rgb232')
          _InstallerStrField(
            label: 'GA rgb232 (DPT 232.600)',
            value: ga['rgb232'] as String? ?? '',
            onChanged: (v) {
              ga['rgb232'] = v.trim().isEmpty ? null : v;
              if (v.trim().isEmpty) ga.remove('rgb232');
              onChanged();
            },
          ),

        // ── tunable_white ─────────────────────────────────────────────────
        if (mode == 'tunable_white') ...[
          Text('Optie A — ww + cw kanalen',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          _InstallerStrField(
            label: 'GA ww (Warm Wit, DPT 5.010)',
            value: ga['ww'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) ga.remove('ww'); else ga['ww'] = v;
              onChanged();
            },
          ),
          _InstallerStrField(
            label: 'GA cw (Koud Wit, DPT 5.010)',
            value: ga['cw'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) ga.remove('cw'); else ga['cw'] = v;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          Text('Optie B — helderheid + Kelvin GA',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          _InstallerStrField(
            label: 'GA bright — helderheid (DPT 5.010)',
            value: ga['bright'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) ga.remove('bright'); else ga['bright'] = v;
              onChanged();
            },
          ),
          _InstallerStrField(
            label: 'GA kelvin — kleurtemperatuur (DPT 9.001)',
            value: ga['kelvin'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) ga.remove('kelvin'); else ga['kelvin'] = v;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _InstallerStrField(
                label: 'Min Kelvin (bijv. 2700)',
                value: '${cfg['kelvinMin'] ?? 2700}',
                number: true,
                onChanged: (v) {
                  cfg['kelvinMin'] = int.tryParse(v) ?? 2700;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InstallerStrField(
                label: 'Max Kelvin (bijv. 6500)',
                value: '${cfg['kelvinMax'] ?? 6500}',
                number: true,
                onChanged: (v) {
                  cfg['kelvinMax'] = int.tryParse(v) ?? 6500;
                  onChanged();
                },
              ),
            ),
          ]),
        ],

        // ── composite ─────────────────────────────────────────────────────
        if (mode == 'composite') ...[
          _InstallerStrField(
            label: 'GA composite',
            value: ga['composite'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) ga.remove('composite'); else ga['composite'] = v;
              onChanged();
            },
          ),
          _InstallerStrField(
            label: 'Aantal bytes (1–14, standaard 14)',
            value: '${cfg['payloadBytes'] ?? 14}',
            number: true,
            onChanged: (v) {
              cfg['payloadBytes'] = int.tryParse(v) ?? 14;
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}

class _InstallerDropdown extends StatelessWidget {
  const _InstallerDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabels,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  /// Weergavetekst per optie-waarde (bijv. DPT-omschrijving).
  final Map<String, String>? optionLabels;

  @override
  Widget build(BuildContext context) {
    final v = options.contains(value) ? value : options.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$v'),
        initialValue: v,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final o in options)
            DropdownMenuItem(
              value: o,
              child: Text(optionLabels?[o] ?? o),
            ),
        ],
        onChanged: (x) {
          if (x != null) onChanged(x);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WTW / HRV ventilatie installer section
// ─────────────────────────────────────────────────────────────────────────────

/// All selectable DPTs for WTW buttons (no hex).
const _wtwDptButtonOptions = <String>[
  '1.001', '1.002', '1.008', '1.009', '1.011',
  '5.001', '5.010',
  '6.001',
  '7.001', '8.001',
  '9.001', '9.002', '9.004', '9.005', '9.006', '9.007', '9.008', '9.009',
  '9.020', '9.021',
  '12.001', '13.001',
  '14.019', '14.068',
];

/// All selectable DPTs for WTW status items (includes hex).
const _wtwDptStatusOptions = <String>[
  '1.001', '1.002', '1.008', '1.009', '1.011',
  '5.001', '5.010',
  '6.001',
  '7.001', '8.001',
  '9.001', '9.002', '9.004', '9.005', '9.006', '9.007', '9.008', '9.009',
  '9.020', '9.021',
  '12.001', '13.001',
  '14.019', '14.068',
  'hex',
];

/// Human-readable label per DPT code.
const _wtwDptLabels = <String, String>{
  // 1-bit
  '1.001': 'Bit – aan/uit (DPT 1.001)',
  '1.002': 'Bit – true/false (DPT 1.002)',
  '1.008': 'Bit – omhoog/omlaag (DPT 1.008)',
  '1.009': 'Bit – open/dicht (DPT 1.009)',
  '1.011': 'Bit – actief/inactief (DPT 1.011)',
  // 1-byte
  '5.001': 'Percentage 0–100 % (DPT 5.001)',
  '5.010': 'Byte 0–255 / stand (DPT 5.010)',
  '6.001': 'Signed byte −128..127 (DPT 6.001)',
  // 2-byte int
  '7.001': 'Teller 0–65535 / dagen (DPT 7.001)',
  '8.001': 'Signed 2-byte (DPT 8.001)',
  // 2-byte float
  '9.001': 'Temperatuur °C (DPT 9.001)',
  '9.002': 'Temperatuurverschil K (DPT 9.002)',
  '9.004': 'Verlichtingssterkte lux (DPT 9.004)',
  '9.005': 'Windsnelheid m/s (DPT 9.005)',
  '9.006': 'Luchtdruk Pa (DPT 9.006)',
  '9.007': 'Relatieve vochtigheid %RH (DPT 9.007)',
  '9.008': 'Luchtkwaliteit / CO₂ ppm (DPT 9.008)',
  '9.009': 'Volumestroom m³/h (DPT 9.009)',
  '9.020': 'Spanning mV (DPT 9.020)',
  '9.021': 'Stroom mA (DPT 9.021)',
  // 4-byte int
  '12.001': 'Unsigned 32-bit (DPT 12.001)',
  '13.001': 'Signed 32-bit (DPT 13.001)',
  // 4-byte float
  '14.019': 'Elektrisch vermogen W (DPT 14.019)',
  '14.068': 'Windsnelheid m/s IEEE-754 (DPT 14.068)',
  // Special
  'hex': 'Hex-weergave (alleen status)',
};

/// Legacy alias used by the button editor DPT dropdown.
const _wtwDptOptions = _wtwDptButtonOptions;

class WtwInstallerSection extends StatefulWidget {
  const WtwInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });
  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<WtwInstallerSection> createState() => _WtwInstallerSectionState();
}

class _WtwInstallerSectionState extends State<WtwInstallerSection> {
  static const _uuid = Uuid();

  Map<String, dynamic> get _wtw {
    var m = widget.device['wtw'];
    if (m is! Map<String, dynamic>) {
      m = <String, dynamic>{};
      widget.device['wtw'] = m;
    }
    return m as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> get _buttons {
    final v = _wtw['buttons'];
    if (v is! List) {
      _wtw['buttons'] = <dynamic>[];
      return [];
    }
    return (v as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> get _status {
    final v = _wtw['status'];
    if (v is! List) {
      _wtw['status'] = <dynamic>[];
      return [];
    }
    return (v as List).cast<Map<String, dynamic>>();
  }

  void _addButton() {
    setState(() {
      _buttons.add({
        'id': _uuid.v4().substring(0, 8),
        'label': 'Stand ${_buttons.length + 1}',
        'ga': '',
        'dpt': '5.010',
        'value': _buttons.length + 1,
      });
      widget.onChanged();
    });
  }

  void _removeButton(int i) {
    setState(() {
      _buttons.removeAt(i);
      widget.onChanged();
    });
  }

  void _addStatus() {
    setState(() {
      _status.add({
        'id': _uuid.v4().substring(0, 8),
        'label': 'Melding ${_status.length + 1}',
        'ga': '',
        'dpt': '1.001',
        'unit': '',
      });
      widget.onChanged();
    });
  }

  void _removeStatus(int i) {
    setState(() {
      _status.removeAt(i);
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttons = _buttons;
    final statusItems = _status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // ── Standen / knoppen ─────────────────────────────────────────────
        Row(
          children: [
            Text('Standen / knoppen', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: buttons.length < 8 ? _addButton : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Toevoegen'),
            ),
          ],
        ),
        Text(
          'Iedere knop stuurt één KNX-telegram. Kies het DPT en de waarde '
          'die verstuurd moet worden. Optioneel terugkoppeling-GA voor actief-indicator.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < buttons.length; i++)
          _WtwButtonEditor(
            key: ValueKey(buttons[i]['id'] ?? i),
            button: buttons[i],
            index: i,
            onChanged: () => setState(widget.onChanged),
            onDelete: () => _removeButton(i),
          ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),

        // ── Status / storingsmeldingen ────────────────────────────────────
        Row(
          children: [
            Text('Status- en storingsmeldingen', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: statusItems.length < 12 ? _addStatus : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Toevoegen'),
            ),
          ],
        ),
        Text(
          'Elke melding leest een KNX-GA en toont de waarde opgemaakt '
          'volgens het DPT: bit → ja/nee, byte → getal, hex → hex-code, enz.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < statusItems.length; i++)
          _WtwStatusEditor(
            key: ValueKey(statusItems[i]['id'] ?? i),
            item: statusItems[i],
            index: i,
            onChanged: () => setState(widget.onChanged),
            onDelete: () => _removeStatus(i),
          ),
      ],
    );
  }
}

class _WtwButtonEditor extends StatelessWidget {
  const _WtwButtonEditor({
    super.key,
    required this.button,
    required this.index,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> button;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Knop ${index + 1}',
                    style: theme.textTheme.labelMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _StrField(
              label: 'Label',
              value: button['label'] as String? ?? '',
              onChanged: (v) { button['label'] = v; onChanged(); },
            ),
            _StrField(
              label: 'Groepsadres (GA)',
              value: button['ga'] as String? ?? '',
              hint: '1/2/3',
              onChanged: (v) { button['ga'] = v; onChanged(); },
            ),
            _DptDropdown(
              label: 'DPT / telegram-type',
              value: button['dpt'] as String? ?? '5.010',
              options: _wtwDptButtonOptions,
              onChanged: (v) { button['dpt'] = v; onChanged(); },
            ),
            _StrField(
              label: 'Waarde om te versturen',
              value: (button['value'] ?? '').toString(),
              hint: 'bijv. 1  of  0  of  50',
              onChanged: (v) {
                final n = num.tryParse(v);
                button['value'] = n ?? (v == 'true' ? true : (v == 'false' ? false : 0));
                onChanged();
              },
            ),
            _StrField(
              label: 'Terugkoppeling GA (optioneel)',
              value: button['statusGa'] as String? ?? '',
              hint: '1/2/4',
              onChanged: (v) {
                if (v.isEmpty) {
                  button.remove('statusGa');
                } else {
                  button['statusGa'] = v;
                }
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WtwStatusEditor extends StatelessWidget {
  const _WtwStatusEditor({
    super.key,
    required this.item,
    required this.index,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Melding ${index + 1}',
                    style: theme.textTheme.labelMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _StrField(
              label: 'Label (bijv. "Filter vuil")',
              value: item['label'] as String? ?? '',
              onChanged: (v) { item['label'] = v; onChanged(); },
            ),
            _StrField(
              label: 'Groepsadres (GA)',
              value: item['ga'] as String? ?? '',
              hint: '1/2/5',
              onChanged: (v) { item['ga'] = v; onChanged(); },
            ),
            _DptDropdown(
              label: 'DPT / weergave-opmaak',
              value: item['dpt'] as String? ?? '1.001',
              options: _wtwDptStatusOptions,
              onChanged: (v) { item['dpt'] = v; onChanged(); },
            ),
            _StrField(
              label: 'Eenheid (optioneel, bijv. "dagen" of "°C")',
              value: item['unit'] as String? ?? '',
              onChanged: (v) {
                if (v.isEmpty) {
                  item.remove('unit');
                } else {
                  item['unit'] = v;
                }
                onChanged();
              },
            ),
            _IconPickerField(
              label: 'Icoon (optioneel, altijd zichtbaar)',
              value: item['icon'] as String?,
              onChanged: (v) {
                if (v == null) item.remove('icon'); else item['icon'] = v;
                onChanged();
              },
            ),
            // icon0/icon1 only relevant for 1-bit DPTs
            if ((item['dpt'] as String? ?? '1.001').startsWith('1.')) ...[
              _IconPickerField(
                label: 'Icoon waarde 0 / OK',
                value: item['icon0'] as String?,
                onChanged: (v) {
                  if (v == null) item.remove('icon0'); else item['icon0'] = v;
                  onChanged();
                },
              ),
              _IconPickerField(
                label: 'Icoon waarde 1 / Actief / Alarm',
                value: item['icon1'] as String?,
                onChanged: (v) {
                  if (v == null) item.remove('icon1'); else item['icon1'] = v;
                  onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Small reusable helpers used only by the WTW section below.

class _StrField extends StatefulWidget {
  const _StrField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  State<_StrField> createState() => _StrFieldState();
}

class _StrFieldState extends State<_StrField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_StrField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _DptDropdown extends StatelessWidget {
  const _DptDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : options.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: current,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final o in options)
            DropdownMenuItem(
              value: o,
              child: Text(_wtwDptLabels[o] ?? o,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

/// Icon picker: dropdown showing all entries from [kUniversalIconMap] with a
/// small preview icon. Passes null to [onChanged] when "geen" is selected.
class _IconPickerField extends StatelessWidget {
  const _IconPickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  static const _none = '(geen)';

  @override
  Widget build(BuildContext context) {
    final sorted = kUniversalIconMap.keys.toList()..sort();
    final current = (value != null && kUniversalIconMap.containsKey(value))
        ? value!
        : _none;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: current,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(
            value: _none,
            child: Text('(geen)', style: TextStyle(color: Colors.grey)),
          ),
          for (final key in sorted)
            DropdownMenuItem(
              value: key,
              child: Row(
                children: [
                  Icon(kUniversalIconMap[key], size: 18),
                  const SizedBox(width: 8),
                  Text(key, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
        ],
        onChanged: (v) => onChanged(v == _none ? null : v),
      ),
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Meldingen installer section
   ══════════════════════════════════════════════════════════════════════════ */

class MeldingInstallerSection extends StatefulWidget {
  const MeldingInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });
  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<MeldingInstallerSection> createState() =>
      _MeldingInstallerSectionState();
}

class _MeldingInstallerSectionState extends State<MeldingInstallerSection> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(MeldingInstallerSection old) {
    super.didUpdateWidget(old);
    _reload();
  }

  void _reload() {
    final cfg = widget.device['melding'] as Map<String, dynamic>? ?? {};
    final raw = cfg['items'] as List<dynamic>? ?? [];
    _items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _commit() {
    final cfg = Map<String, dynamic>.from(
        widget.device['melding'] as Map<String, dynamic>? ?? {});
    cfg['items'] = _items;
    widget.device['melding'] = cfg;
    widget.onChanged();
  }

  void _addItem() {
    setState(() {
      _items.add({
        'id': 'melding_${DateTime.now().millisecondsSinceEpoch}',
        'label': 'Nieuwe melding',
        'ga': '',
        'dpt': '1.001',
        'urgency': 'minder_belangrijk',
      });
    });
    _commit();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
    _commit();
  }

  void _updateItem(int index, Map<String, dynamic> updated) {
    setState(() => _items[index] = updated);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.notifications_outlined, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Meldingen / Alarmen',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _items.length < 24 ? _addItem : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Toevoegen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Nog geen meldingen geconfigureerd.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          for (int i = 0; i < _items.length; i++)
            _MeldingItemEditor(
              key: ValueKey(_items[i]['id']),
              item: _items[i],
              index: i,
              total: _items.length,
              onChanged: (updated) => _updateItem(i, updated),
              onDelete: () => _removeItem(i),
            ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _MeldingItemEditor extends StatelessWidget {
  const _MeldingItemEditor({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final int index;
  final int total;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  void _set(String key, dynamic value) {
    final updated = Map<String, dynamic>.from(item);
    if (value == null) {
      updated.remove(key);
    } else {
      updated[key] = value;
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final urgency = item['urgency'] as String? ?? 'minder_belangrijk';
    final dpt = item['dpt'] as String? ?? '1.001';
    final is1bit = dpt.startsWith('1.');
    final urgencyColor = switch (urgency) {
      'urgent' => Colors.red.shade700,
      'belangrijk' => Colors.orange.shade700,
      _ => Colors.amber.shade700,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: urgencyColor.withOpacity(0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.drag_indicator, size: 18, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: urgencyColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${index + 1}. ${item['label'] ?? 'Melding'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red[400],
                  tooltip: 'Verwijder melding',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _StrField(
              label: 'Onderwerp (label)',
              value: item['label'] as String? ?? '',
              onChanged: (v) => _set('label', v.isEmpty ? 'Melding' : v),
            ),
            _StrField(
              label: 'KNX groepsadres (bijv. 1/2/3)',
              value: item['ga'] as String? ?? '',
              onChanged: (v) => _set('ga', v),
            ),
            _DptDropdown(
              label: 'DPT',
              value: dpt,
              options: const [
                '1.001', '1.002', '1.008', '1.009', '1.011',
                '5.001', '5.010', '6.001',
                '7.001', '8.001',
                '9.001', '9.002', '9.004', '9.005', '9.006',
                '9.007', '9.008', '9.009', '9.020', '9.021',
                '12.001', '13.001', '14.019', '14.068', 'hex',
              ],
              onChanged: (v) => _set('dpt', v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                value: urgency,
                decoration: const InputDecoration(
                  labelText: 'Urgentiecategorie',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'urgent',
                    child: Row(
                      children: [
                        Icon(Icons.error_rounded, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Urgent / Storing'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'belangrijk',
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Text('Belangrijk'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'minder_belangrijk',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Text('Minder belangrijk / Info'),
                      ],
                    ),
                  ),
                ],
                onChanged: (v) => _set('urgency', v ?? 'minder_belangrijk'),
              ),
            ),
            if (!is1bit) ...[
              _StrField(
                label: 'Actief wanneer waarde gelijk is aan (leeg = ≠ 0)',
                value: item['activeValue']?.toString() ?? '',
                onChanged: (v) {
                  final num = double.tryParse(v);
                  _set('activeValue', num);
                },
              ),
            ],
            _StrField(
              label: 'Tekst als actief (optioneel)',
              value: item['activeLabel'] as String? ?? '',
              onChanged: (v) => _set('activeLabel', v.isEmpty ? null : v),
            ),
            _StrField(
              label: 'Tekst als inactief (optioneel)',
              value: item['inactiveLabel'] as String? ?? '',
              onChanged: (v) => _set('inactiveLabel', v.isEmpty ? null : v),
            ),
            _IconPickerField(
              label: 'Icoon (optioneel)',
              value: item['icon'] as String?,
              onChanged: (v) => _set('icon', v),
            ),
          ],
        ),
      ),
    );
  }
}
