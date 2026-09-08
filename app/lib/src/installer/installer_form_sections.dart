import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../ac_mode_config.dart';
import '../room_control_category.dart';
import '../theme.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/heater_icon.dart';
import '../ui/widgets/luxe_form.dart';
import 'knx_ga_catalog.dart';

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
          LuxeSwitchRow(
            title: 'Waarde (aan)',
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

    return LuxeInsetCard(
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

    return LuxeInsetCard(
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
                  LuxeSwitchRow(
                    title: 'Status “aan” = bit 1',
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

class _InstallerInfoTitle extends StatelessWidget {
  const _InstallerInfoTitle({
    required this.title,
    required this.body,
    this.trailing,
  });
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          LuxeInfoIconButton(title: title, body: body),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _OverviewColHeader extends StatelessWidget {
  const _OverviewColHeader(this.cells);
  final List<({String label, int flex, double? width})> cells;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            if (cells[i].width != null)
              SizedBox(
                width: cells[i].width,
                child: Text(cells[i].label, style: style),
              )
            else
              Expanded(
                flex: cells[i].flex,
                child: Text(cells[i].label, style: style),
              ),
          ],
        ],
      ),
    );
  }
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
    final showSwitchLock   = userCanSwitch && canHeat && canCool;

    String gaVal(String key) => ga[key] as String? ?? '';
    void setGa(String key, String v) {
      if (v.trim().isEmpty) ga.remove(key); else ga[key] = v.trim();
      _notify();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InstallerInfoTitle(
          title: 'Temperatuur',
          body:
              'Gemeten temperatuur en setpoint: DPT 9.001. '
              'Setpoint-status is optioneel: als die er is, toont de app '
              'wat de thermostaat terugmeldt.',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-at'),
          label: 'Gemeten temperatuur',
          value: gaVal('actual_temp'),
          onChanged: (v) => setGa('actual_temp', v),
          gaSearch: true,
          gaDptHint: 'DPT9.001',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-sp'),
          label: 'Setpoint',
          value: gaVal('setpoint'),
          onChanged: (v) => setGa('setpoint', v),
          gaSearch: true,
          gaDptHint: 'DPT9.001',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-ss'),
          label: 'Setpoint status (lezen)',
          value: gaVal('setpoint_status'),
          onChanged: (v) => setGa('setpoint_status', v),
          gaSearch: true,
          gaDptHint: 'DPT9.001',
        ),
        const SizedBox(height: 12),
        const _InstallerInfoTitle(
          title: 'Verwarm / koel',
          body:
              'DPT 1.100: 1 = verwarmen, 0 = koelen. '
              'Schakelaar alleen nodig als de gebruiker zelf mag omschakelen. '
              'Status is wat het systeem terugmeldt.',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hvac'),
          label: 'Schakelaar (schrijven)',
          value: gaVal('hvac_mode'),
          onChanged: (v) => setGa('hvac_mode', v),
          gaSearch: true,
          gaDptHint: 'DPT1.100',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hvacst'),
          label: 'Status (lezen)',
          value: gaVal('hvac_mode_status'),
          onChanged: (v) => setGa('hvac_mode_status', v),
          gaSearch: true,
          gaDptHint: 'DPT1.100',
        ),
        const SizedBox(height: 12),
        const _InstallerInfoTitle(
          title: 'Vraagmeldingen',
          body:
              'Optioneel. Geeft in de app aan of er in de ruimte warmte- '
              'of koudevraag is (DPT 1).',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-hd'),
          label: 'Warmtevraag (lezen)',
          value: gaVal('heat_demand'),
          onChanged: (v) => setGa('heat_demand', v),
          gaSearch: true,
          gaDptHint: 'DPT1',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-cd'),
          label: 'Koudevraag (lezen)',
          value: gaVal('cool_demand'),
          onChanged: (v) => setGa('cool_demand', v),
          gaSearch: true,
          gaDptHint: 'DPT1',
        ),
        const SizedBox(height: 12),
        const _InstallerInfoTitle(
          title: 'Bedrijfsmodus',
          body:
              'DPT 20.102: comfort, standby, economy, gebouwbeveiliging. '
              'Schrijven en status zijn optioneel. '
              'Zet hieronder uit welke modi het systeem niet heeft; '
              'die knoppen verdwijnen in de app.',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-mode'),
          label: 'Modus (schrijven)',
          value: gaVal('mode'),
          onChanged: (v) => setGa('mode', v),
          gaSearch: true,
          gaDptHint: 'DPT20.102',
        ),
        _InstallerStrField(
          key: ValueKey('cl-${widget.device['id']}-modest'),
          label: 'Modus status (lezen)',
          value: gaVal('mode_status'),
          onChanged: (v) => setGa('mode_status', v),
          gaSearch: true,
          gaDptHint: 'DPT20.102',
        ),
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
                  label: 'Comfort',
                  value: modeEnabled('comfort'),
                  onChanged: (v) => toggleMode('comfort', v)),
              _SectionToggle(
                  label: 'Standby',
                  value: modeEnabled('standby'),
                  onChanged: (v) => toggleMode('standby', v)),
              _SectionToggle(
                  label: 'Economy',
                  value: modeEnabled('economy'),
                  onChanged: (v) => toggleMode('economy', v)),
              _SectionToggle(
                  label: 'Gebouwbeveiliging',
                  value: modeEnabled('buildingProtection'),
                  onChanged: (v) => toggleMode('buildingProtection', v)),
            ],
          );
        }),
        const SizedBox(height: 12),
        const _InstallerInfoTitle(
          title: 'Setpoint in de app',
          body:
              'Grenzen van de plus/min-knoppen. Leeg = 5 tot 35 °C. '
              'Stapgrootte is hoeveel de temperatuur per tik verandert.',
        ),
        Row(
          children: [
            Expanded(
              child: _InstallerStrField(
                key: ValueKey('cl-${widget.device['id']}-mint'),
                label: 'Min °C',
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
                label: 'Max °C',
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
        const _InstallerInfoTitle(
          title: 'Mogelijkheden',
          body:
              'Bepaalt wat de app toont. Mag de gebruiker niet omschakelen, '
              'dan zie je alleen of er verwarmd of gekoeld wordt. '
              'Vergrendeling na omschakelen: u:mm, bijvoorbeeld 4:00. '
              '0:00 = geen vergrendeling, wel een waarschuwing.',
        ),
        _SectionToggle(
          label: 'Kan verwarmen',
          value: canHeat,
          onChanged: (v) { cfg['canHeat'] = v; _notify(); },
        ),
        _SectionToggle(
          label: 'Kan koelen',
          value: canCool,
          onChanged: (v) { cfg['canCool'] = v; _notify(); },
        ),
        _SectionToggle(
          label: 'Gebruiker mag omschakelen',
          value: userCanSwitch,
          onChanged: (v) {
            cfg['userCanSwitchMode'] = v;
            if (v && cfg['hvacSwitchLockDuration'] == null) {
              cfg['hvacSwitchLockDuration'] = '4:00';
            }
            _notify();
          },
        ),
        if (showSwitchLock)
          _InstallerStrField(
            key: ValueKey('cl-${widget.device['id']}-hvaclock'),
            label: 'Vergrendeling (u:mm)',
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
      ],
    );
  }
}

// ── AC installer section ─────────────────────────────────────────────────────

class AcInstallerSection extends StatefulWidget {
  const AcInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<AcInstallerSection> createState() => _AcInstallerSectionState();
}

class _AcInstallerSectionState extends State<AcInstallerSection> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _addModeOption(Map<String, dynamic> ac, List<Map<String, dynamic>> options) {
    final used = options
        .map((o) => (o['value'] as num?)?.toInt() ?? 0)
        .toSet();
    var v = 0;
    while (used.contains(v)) v++;
    options.add({'label': 'Modus $v', 'value': v, 'icon': 'auto'});
    syncAcModeVisibility(ac, options);
    _notify();
  }

  void _removeModeOption(
    Map<String, dynamic> ac,
    List<Map<String, dynamic>> options,
    int index,
  ) {
    options.removeAt(index);
    syncAcModeVisibility(ac, options);
    _notify();
  }

  void _addFanOption(List<Map<String, dynamic>> options) {
    final used = options
        .map((o) => (o['value'] as num?)?.toInt() ?? 0)
        .toSet();
    var v = 0;
    while (used.contains(v)) v++;
    options.add({'label': 'Stand $v', 'value': v});
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final ac = _ensureMap(widget.device, 'ac');
    final onOff = _ensureMap(ac, 'onOff');
    final setpoint = _ensureMap(ac, 'setpoint');
    final hasMode = ac.containsKey('mode');
    final hasFan = ac.containsKey('fanSpeed');
    final hasActual = ac.containsKey('actualTemp');

    if (hasMode) {
      final mode = _ensureMap(ac, 'mode');
      final options = _ensureList(mode, 'options');
      if (options.isEmpty) {
        options.addAll(defaultAcModeOptions.map(Map<String, dynamic>.from));
      }
      syncAcModeVisibility(ac, options);
    }

    final mode = hasMode ? _ensureMap(ac, 'mode') : null;
    final modeOptions = mode != null
        ? _ensureList(mode, 'options')
        : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Aan / Uit', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('ac-${widget.device['id']}-on-ga'),
          label: 'GA aan/uit (DPT 1.001) *',
          value: onOff['ga'] as String? ?? '',
          onChanged: (v) { onOff['ga'] = v; _notify(); },
        ),
        _InstallerStrField(
          key: ValueKey('ac-${widget.device['id']}-on-st'),
          label: 'Status GA (optioneel)',
          value: onOff['statusGa'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              onOff.remove('statusGa');
            } else {
              onOff['statusGa'] = v;
            }
            _notify();
          },
        ),
        const SizedBox(height: 12),

        Text('Setpoint', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _InstallerStrField(
          key: ValueKey('ac-${widget.device['id']}-sp-ga'),
          label: 'GA setpoint (DPT 9.001) *',
          value: setpoint['ga'] as String? ?? '',
          onChanged: (v) { setpoint['ga'] = v; _notify(); },
        ),
        _InstallerStrField(
          key: ValueKey('ac-${widget.device['id']}-sp-st'),
          label: 'Status GA setpoint (optioneel)',
          value: setpoint['statusGa'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              setpoint.remove('statusGa');
            } else {
              setpoint['statusGa'] = v;
            }
            _notify();
          },
        ),
        Row(
          children: [
            Expanded(
              child: _InstallerStrField(
                key: ValueKey('ac-${widget.device['id']}-sp-min'),
                label: 'Min °C (standaard 16)',
                value: (setpoint['min'] as num?)?.toString() ?? '',
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) {
                    setpoint['min'] = n;
                  } else {
                    setpoint.remove('min');
                  }
                  _notify();
                },
                number: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InstallerStrField(
                key: ValueKey('ac-${widget.device['id']}-sp-max'),
                label: 'Max °C (standaard 30)',
                value: (setpoint['max'] as num?)?.toString() ?? '',
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) {
                    setpoint['max'] = n;
                  } else {
                    setpoint.remove('max');
                  }
                  _notify();
                },
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _SectionToggle(
          label: 'Gemeten temperatuur toevoegen',
          value: hasActual,
          onChanged: (v) {
            if (v) {
              ac['actualTemp'] = {'ga': '1/1/3'};
            } else {
              ac.remove('actualTemp');
            }
            _notify();
          },
        ),
        if (hasActual)
          _InstallerStrField(
            key: ValueKey('ac-${widget.device['id']}-act'),
            label: 'GA gemeten temperatuur (DPT 9.001)',
            value: (_ensureMap(ac, 'actualTemp'))['ga'] as String? ?? '',
            onChanged: (v) {
              _ensureMap(ac, 'actualTemp')['ga'] = v;
              _notify();
            },
          ),
        const SizedBox(height: 12),

        _SectionToggle(
          label: 'Modusbesturing toevoegen',
          value: hasMode,
          onChanged: (v) {
            if (v) {
              ac['mode'] = {
                'ga': '1/1/4',
                'options': defaultAcModeOptions
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList(),
              };
              ac['modeVisibility'] = Map<String, dynamic>.from(
                defaultAcModeVisibility,
              );
            } else {
              ac.remove('mode');
              ac.remove('modeVisibility');
            }
            _notify();
          },
        ),
        if (hasMode) ...[
          _InstallerStrField(
            key: ValueKey('ac-${widget.device['id']}-mode-ga'),
            label: 'GA modus (schrijven)',
            value: mode!['ga'] as String? ?? '',
            onChanged: (v) { mode['ga'] = v; _notify(); },
          ),
          _InstallerStrField(
            key: ValueKey('ac-${widget.device['id']}-mode-st'),
            label: 'Status GA modus (optioneel)',
            value: mode['statusGa'] as String? ?? '',
            onChanged: (v) {
              if (v.trim().isEmpty) {
                mode.remove('statusGa');
              } else {
                mode['statusGa'] = v;
              }
              _notify();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Modusopties', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: modeOptions.length < 12
                    ? () => _addModeOption(ac, modeOptions)
                    : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Toevoegen'),
              ),
            ],
          ),
          Text(
            'Label, KNX-waarde en icoon per modus. '
            'Koelen en Verwarmen zijn standaard zichtbaar in de app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < modeOptions.length; i++)
            _AcModeOptionEditor(
              key: ValueKey(
                'ac-${widget.device['id']}-mode-$i-${modeOptions[i]['value']}',
              ),
              option: modeOptions[i],
              index: i,
              visible: acModeVisible(
                _ensureMap(ac, 'modeVisibility'),
                modeOptions[i],
              ),
              onChanged: () {
                syncAcModeVisibility(ac, modeOptions);
                _notify();
              },
              onVisibilityChanged: (v) {
                _ensureMap(ac, 'modeVisibility')[
                    acModeVisibilityKey(modeOptions[i])] = v;
                _notify();
              },
              onDelete: modeOptions.length > 1
                  ? () => _removeModeOption(ac, modeOptions, i)
                  : null,
            ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),

        _SectionToggle(
          label: 'Ventilatorsnelheid toevoegen',
          value: hasFan,
          onChanged: (v) {
            if (v) {
              ac['fanSpeed'] = {
                'ga': '1/1/5',
                'options': [
                  {'label': 'Auto', 'value': 0},
                  {'label': '1', 'value': 1},
                  {'label': '2', 'value': 2},
                  {'label': '3', 'value': 3},
                ],
              };
            } else {
              ac.remove('fanSpeed');
            }
            _notify();
          },
        ),
        if (hasFan) ...[
          _InstallerStrField(
            key: ValueKey('ac-${widget.device['id']}-fan-ga'),
            label: 'GA ventilator (schrijven)',
            value: (_ensureMap(ac, 'fanSpeed'))['ga'] as String? ?? '',
            onChanged: (v) {
              _ensureMap(ac, 'fanSpeed')['ga'] = v;
              _notify();
            },
          ),
          _InstallerStrField(
            key: ValueKey('ac-${widget.device['id']}-fan-st'),
            label: 'Status GA ventilator (optioneel)',
            value: (_ensureMap(ac, 'fanSpeed'))['statusGa'] as String? ?? '',
            onChanged: (v) {
              final fan = _ensureMap(ac, 'fanSpeed');
              if (v.trim().isEmpty) {
                fan.remove('statusGa');
              } else {
                fan['statusGa'] = v;
              }
              _notify();
            },
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final fanOptions =
                  _ensureList(_ensureMap(ac, 'fanSpeed'), 'options');
              if (fanOptions.isEmpty) {
                fanOptions.addAll([
                  {'label': 'Auto', 'value': 0},
                  {'label': '1', 'value': 1},
                  {'label': '2', 'value': 2},
                  {'label': '3', 'value': 3},
                ]);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Ventilatorstanden',
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: fanOptions.length < 10
                            ? () => _addFanOption(fanOptions)
                            : null,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Toevoegen'),
                      ),
                    ],
                  ),
                  Text(
                    'Label en KNX-waarde per stand (bijv. Auto=0, laag=1, hoog=3).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < fanOptions.length; i++)
                    _AcFanOptionEditor(
                      key: ValueKey(
                        'ac-${widget.device['id']}-fan-$i-${fanOptions[i]['value']}',
                      ),
                      option: fanOptions[i],
                      index: i,
                      onChanged: _notify,
                      onDelete: fanOptions.length > 1
                          ? () {
                              fanOptions.removeAt(i);
                              _notify();
                            }
                          : null,
                    ),
                ],
              );
            },
          ),
        ],
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
      child: LuxeSwitchRow(
        title: label,
        value: value,
        onChanged: onChanged,
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
    this.hint,
    this.gaSearch = false,
    this.gaDptHint,
    this.compact = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool number;
  final String? hint;
  final bool gaSearch;
  final String? gaDptHint;
  /// No label above the field — for one-row tables.
  final bool compact;

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

  bool get _gaSearchEnabled {
    if (widget.number) return false;
    if (widget.gaSearch) return true;
    return knxFieldLooksLikeGa(label: widget.label);
  }

  Future<void> _pickGa() async {
    final addr = await showGaSearchDialog(context, dptHint: widget.gaDptHint);
    if (addr == null || !mounted) return;
    _c.text = addr;
    widget.onChanged(addr);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final gaSearch = _gaSearchEnabled;
    final resolvedName = gaSearch && _c.text.trim().isNotEmpty
        ? KnxGaCatalog.instance.nameFor(_c.text)
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.compact) LuxeFieldLabel(widget.label),
          TextField(
            controller: _c,
            decoration: luxeFilledDecoration(
              hint: widget.compact ? null : widget.hint,
              helper: widget.compact ? null : resolvedName,
              suffixIcon: gaSearch
                  ? IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Groepsadres zoeken',
                      onPressed: _pickGa,
                    )
                  : null,
            ).copyWith(
              contentPadding: widget.compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                  : null,
            ),
            keyboardType: widget.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            onChanged: (s) {
              widget.onChanged(s);
              if (gaSearch) setState(() {});
            },
          ),
        ],
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
        _InstallerStrField(
          key: ValueKey('ga-${device['id']}-on'),
          label: 'GA Aan/Uit schakelaar (DPT 1.001, optioneel)',
          value: ga['on'] as String? ?? '',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              ga.remove('on');
            } else {
              ga['on'] = v.trim();
            }
            onChanged();
          },
        ),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeFieldLabel(label),
          DropdownButtonFormField<String>(
            key: ValueKey('$label-$v'),
            initialValue: v,
            decoration: luxeFilledDecoration(),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WTW / HRV ventilatie installer section
// ─────────────────────────────────────────────────────────────────────────────

/// DPTs for WTW stand-knoppen. Bit-waarde alleen 0/1; byte 0–255.
const _wtwDptButtonOptions = <String>[
  '5.010',
  '1.001',
  '5.001',
];

/// Status: bits, stand, tijd/teller, klimaat van de WTW.
const _wtwDptStatusOptions = <String>[
  '1.001',
  '5.001',
  '5.010',
  '7.001',
  '9.001',
  '9.007',
  '9.008',
  '9.009',
  'hex',
];

/// Human-readable label per DPT code.
const _wtwDptLabels = <String, String>{
  '1.001': 'Bit 0/1 (DPT 1.001)',
  '5.001': 'Procent 0–100 (DPT 5.001)',
  '5.010': 'Byte 0–255 (DPT 5.010)',
  '7.001': '2 byte teller (DPT 7.001)',
  '9.001': 'Temperatuur °C (DPT 9.001)',
  '9.007': 'Relatieve vochtigheid %RH (DPT 9.007)',
  '9.008': 'CO₂ ppm (DPT 9.008)',
  '9.009': 'Volumestroom m³/h (DPT 9.009)',
  'hex': 'Hex-weergave (alleen status)',
};

bool _wtwDptIsBit(String dpt) => dpt.startsWith('1.');

({int min, int max}) _wtwValueRange(String dpt) {
  if (_wtwDptIsBit(dpt)) return (min: 0, max: 1);
  if (dpt == '5.001') return (min: 0, max: 100);
  if (dpt == '7.001') return (min: 0, max: 65535);
  return (min: 0, max: 255);
}

int _clampWtwValue(String dpt, num n) {
  final r = _wtwValueRange(dpt);
  return n.round().clamp(r.min, r.max);
}

List<String> _wtwDptOptionsWithCurrent(List<String> options, String value) {
  if (value.isEmpty || options.contains(value)) return options;
  return [...options, value];
}

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
    final buttons = _buttons;
    final statusItems = _status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InstallerInfoTitle(
          title: 'Standen / knoppen',
          body:
              'Knoptekst is wat op de knop staat. Stand: byte 0–255, bit 0/1 of procent 0–100. '
              'Boost: 1-bit plus tijd in minuten (KNX krijgt seconden). '
              'Status met 2-byte kan een aflopende teller zijn (filterdagen, resterende tijd).',
          trailing: TextButton.icon(
            onPressed: buttons.length < 8 ? _addButton : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Toevoegen'),
          ),
        ),
        if (buttons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nog geen standen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          const _OverviewColHeader([
            (label: 'Knoptekst', flex: 2, width: null),
            (label: 'Soort', flex: 0, width: 108.0),
            (label: 'Groepsadres', flex: 2, width: null),
            (label: 'DPT', flex: 2, width: null),
            (label: 'Waarde', flex: 1, width: null),
            (label: 'Status-GA', flex: 2, width: null),
            (label: '', flex: 0, width: 40.0),
          ]),
          for (int i = 0; i < buttons.length; i++)
            _WtwButtonEditor(
              key: ValueKey(buttons[i]['id'] ?? i),
              button: buttons[i],
              onChanged: () => setState(widget.onChanged),
              onDelete: () => _removeButton(i),
            ),
        ],
        const SizedBox(height: 16),
        _InstallerInfoTitle(
          title: 'Status- en storingsmeldingen',
          body:
              'Elke regel leest een KNX-GA. Teller: resterende tijd telt in de app af '
              '(seconden, minuten of dagen — bijv. filter). Icoon 0/1 alleen bij 1-bit.',
          trailing: TextButton.icon(
            onPressed: statusItems.length < 12 ? _addStatus : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Toevoegen'),
          ),
        ),
        if (statusItems.isEmpty)
          Text(
            'Nog geen statusmeldingen.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          const _OverviewColHeader([
            (label: 'Label', flex: 2, width: null),
            (label: 'Groepsadres', flex: 2, width: null),
            (label: 'DPT', flex: 2, width: null),
            (label: 'Teller', flex: 0, width: 108.0),
            (label: 'Eenheid', flex: 1, width: null),
            (label: 'Icoon', flex: 1, width: null),
            (label: 'Icoon 0', flex: 1, width: null),
            (label: 'Icoon 1', flex: 1, width: null),
            (label: '', flex: 0, width: 40.0),
          ]),
          for (int i = 0; i < statusItems.length; i++)
            _WtwStatusEditor(
              key: ValueKey(statusItems[i]['id'] ?? i),
              item: statusItems[i],
              onChanged: () => setState(widget.onChanged),
              onDelete: () => _removeStatus(i),
            ),
        ],
      ],
    );
  }
}

class _WtwButtonEditor extends StatelessWidget {
  const _WtwButtonEditor({
    super.key,
    required this.button,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> button;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  bool get _isBoost => button['kind'] == 'boost';

  String get _dpt =>
      _isBoost ? '1.001' : (button['dpt'] as String? ?? '5.010');

  void _setKind(String kind) {
    if (kind == 'boost') {
      button['kind'] = 'boost';
      button['dpt'] = '1.001';
      button['value'] = 1;
      button['minutes'] ??= 30;
    } else {
      button.remove('kind');
      button.remove('timeGa');
      button.remove('timeStatusGa');
      button.remove('minutes');
      if (_wtwDptIsBit(button['dpt'] as String? ?? '')) {
        button['dpt'] = '5.010';
        button['value'] = _clampWtwValue('5.010', 1);
      }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final dpt = _dpt;
    final isBit = _wtwDptIsBit(dpt);
    final range = _wtwValueRange(dpt);
    final valueInt = _clampWtwValue(
      dpt,
      button['value'] is num
          ? button['value'] as num
          : (button['value'] == true ? 1 : 0),
    );
    final dptOptions = _isBoost
        ? const ['1.001']
        : _wtwDptOptionsWithCurrent(_wtwDptButtonOptions, dpt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _StrField(
                  label: 'Knoptekst',
                  value: button['label'] as String? ?? '',
                  compact: true,
                  onChanged: (v) {
                    button['label'] = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 108,
                child: _WtwKindDropdown(
                  key: ValueKey('${button['id']}-kind-${_isBoost}'),
                  value: _isBoost ? 'boost' : 'stand',
                  onChanged: _setKind,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _StrField(
                  label: 'Groepsadres',
                  value: button['ga'] as String? ?? '',
                  compact: true,
                  gaSearch: true,
                  gaDptHint: 'DPT$dpt',
                  onChanged: (v) {
                    button['ga'] = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _DptDropdown(
                  key: ValueKey('${button['id']}-dpt-$dpt'),
                  label: 'DPT',
                  value: dpt,
                  options: dptOptions,
                  compact: true,
                  onChanged: _isBoost
                      ? (_) {}
                      : (v) {
                          button['dpt'] = v;
                          button['value'] = _clampWtwValue(
                            v,
                            button['value'] is num
                                ? button['value'] as num
                                : (button['value'] == true ? 1 : 0),
                          );
                          onChanged();
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: isBit
                    ? DropdownButtonFormField<int>(
                        initialValue: valueInt,
                        isExpanded: true,
                        decoration: luxeFilledDecoration().copyWith(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0')),
                          DropdownMenuItem(value: 1, child: Text('1')),
                        ],
                        onChanged: _isBoost
                            ? null
                            : (v) {
                                if (v == null) return;
                                button['value'] = v;
                                onChanged();
                              },
                      )
                    : _StrField(
                        label: 'Waarde',
                        value: '$valueInt',
                        compact: true,
                        number: true,
                        hint: '${range.min}–${range.max}',
                        onChanged: (v) {
                          final n = num.tryParse(v);
                          if (n == null) return;
                          button['value'] = _clampWtwValue(dpt, n);
                          onChanged();
                        },
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _StrField(
                  label: 'Status-GA',
                  value: button['statusGa'] as String? ?? '',
                  compact: true,
                  gaSearch: true,
                  gaDptHint: _isBoost ? 'DPT1.001' : 'DPT$dpt',
                  onChanged: (v) {
                    if (v.isEmpty) {
                      button.remove('statusGa');
                    } else {
                      button['statusGa'] = v;
                    }
                    onChanged();
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: LuxeColors.inkSoft,
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
          if (_isBoost) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _StrField(
                    label: 'Boost-tijd GA (minuten, DPT 7.001)',
                    value: button['timeGa'] as String? ?? '',
                    gaSearch: true,
                    gaDptHint: 'DPT7.001',
                    onChanged: (v) {
                      if (v.isEmpty) {
                        button.remove('timeGa');
                      } else {
                        button['timeGa'] = v;
                      }
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _StrField(
                    label: 'Tijd-status GA',
                    value: button['timeStatusGa'] as String? ?? '',
                    gaSearch: true,
                    gaDptHint: 'DPT7.001',
                    onChanged: (v) {
                      if (v.isEmpty) {
                        button.remove('timeStatusGa');
                      } else {
                        button['timeStatusGa'] = v;
                      }
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 108,
                  child: _StrField(
                    label: 'Minuten',
                    value: '${(button['minutes'] as num?)?.round() ?? 30}',
                    number: true,
                    hint: '1–65535',
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n == null) return;
                      button['minutes'] = n.clamp(1, 65535);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 50),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WtwKindDropdown extends StatelessWidget {
  const _WtwKindDropdown({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: luxeFilledDecoration().copyWith(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: const [
        DropdownMenuItem(value: 'stand', child: Text('Stand')),
        DropdownMenuItem(value: 'boost', child: Text('Boost')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _WtwStatusEditor extends StatelessWidget {
  const _WtwStatusEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final is1bit = (item['dpt'] as String? ?? '1.001').startsWith('1.');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _StrField(
              label: 'Label',
              value: item['label'] as String? ?? '',
              compact: true,
              onChanged: (v) {
                item['label'] = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _StrField(
              label: 'Groepsadres',
              value: item['ga'] as String? ?? '',
              compact: true,
              gaSearch: true,
              gaDptHint: 'DPT${item['dpt'] ?? '1.001'}',
              onChanged: (v) {
                item['ga'] = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _DptDropdown(
              label: 'DPT',
              value: item['dpt'] as String? ?? '1.001',
              options: _wtwDptOptionsWithCurrent(
                _wtwDptStatusOptions,
                item['dpt'] as String? ?? '1.001',
              ),
              compact: true,
              onChanged: (v) {
                item['dpt'] = v;
                if (v.startsWith('1.')) item.remove('countdown');
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: is1bit
                ? const SizedBox.shrink()
                : DropdownButtonFormField<String>(
                    key: ValueKey('${item['id']}-countdown'),
                    initialValue: () {
                      final c = item['countdown'] as String? ?? 'off';
                      return const ['off', 'seconds', 'minutes', 'days']
                              .contains(c)
                          ? c
                          : 'off';
                    }(),
                    isExpanded: true,
                    decoration: luxeFilledDecoration().copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Uit')),
                      DropdownMenuItem(value: 'seconds', child: Text('Sec')),
                      DropdownMenuItem(value: 'minutes', child: Text('Min')),
                      DropdownMenuItem(value: 'days', child: Text('Dagen')),
                    ],
                    onChanged: (v) {
                      if (v == null || v == 'off') {
                        item.remove('countdown');
                      } else {
                        item['countdown'] = v;
                      }
                      onChanged();
                    },
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _StrField(
              label: 'Eenheid',
              value: item['unit'] as String? ?? '',
              compact: true,
              onChanged: (v) {
                if (v.isEmpty) {
                  item.remove('unit');
                } else {
                  item['unit'] = v;
                }
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _IconPickerField(
              label: 'Icoon',
              value: item['icon'] as String?,
              compact: true,
              onChanged: (v) {
                if (v == null) {
                  item.remove('icon');
                } else {
                  item['icon'] = v;
                }
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: is1bit
                ? _IconPickerField(
                    label: 'Icoon 0',
                    value: item['icon0'] as String?,
                    compact: true,
                    onChanged: (v) {
                      if (v == null) {
                        item.remove('icon0');
                      } else {
                        item['icon0'] = v;
                      }
                      onChanged();
                    },
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: is1bit
                ? _IconPickerField(
                    label: 'Icoon 1',
                    value: item['icon1'] as String?,
                    compact: true,
                    onChanged: (v) {
                      if (v == null) {
                        item.remove('icon1');
                      } else {
                        item['icon1'] = v;
                      }
                      onChanged();
                    },
                  )
                : const SizedBox.shrink(),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: LuxeColors.inkSoft,
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

// Small reusable helpers used only by the WTW section below.

class _StrField extends StatelessWidget {
  const _StrField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.gaSearch = false,
    this.gaDptHint,
    this.number = false,
    this.hint,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;
  final bool gaSearch;
  final String? gaDptHint;
  final bool number;
  final String? hint;

  @override
  Widget build(BuildContext context) => _InstallerStrField(
        label: label,
        value: value,
        compact: compact,
        gaSearch: gaSearch,
        gaDptHint: gaDptHint,
        number: number,
        hint: hint,
        onChanged: onChanged,
      );
}

class _DptDropdown extends StatelessWidget {
  const _DptDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.compact = false,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : options.first;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) LuxeFieldLabel(label),
          DropdownButtonFormField<String>(
            initialValue: current,
            isExpanded: true,
            decoration: luxeFilledDecoration().copyWith(
              contentPadding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                  : null,
            ),
            items: [
              for (final o in options)
                DropdownMenuItem(
                  value: o,
                  child: Text(
                    _wtwDptLabels[o] ?? o,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
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
    this.compact = false,
  });
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool compact;

  static const _none = '(geen)';

  @override
  Widget build(BuildContext context) {
    final sorted = kUniversalIconMap.keys.toList()..sort();
    final current = (value != null && kUniversalIconMap.containsKey(value))
        ? value!
        : _none;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact && label.isNotEmpty) LuxeFieldLabel(label),
          DropdownButtonFormField<String>(
            initialValue: current,
            isExpanded: true,
            decoration: luxeFilledDecoration().copyWith(
              contentPadding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                  : null,
            ),
            items: [
              const DropdownMenuItem(
                value: _none,
                child: Text('(geen)'),
              ),
              for (final key in sorted)
                DropdownMenuItem(
                  value: key,
                  child: Row(
                    children: [
                      iconWidgetForData(
                            kUniversalIconMap[key],
                            size: 18,
                            color: LuxeColors.ink,
                          ) ??
                          Icon(kUniversalIconMap[key], size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(key, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => onChanged(v == _none ? null : v),
          ),
        ],
      ),
    );
  }
}

class _AcIconPickerField extends StatelessWidget {
  const _AcIconPickerField({
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
    final current = (value != null && value!.isNotEmpty) ? value! : _none;
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
          for (final key in kAcModeIconKeys)
            DropdownMenuItem(
              value: key,
              child: Row(
                children: [
                  Icon(deviceControlOptionIcon(iconKey: key), size: 18),
                  const SizedBox(width: 8),
                  Text(key),
                ],
              ),
            ),
        ],
        onChanged: (v) => onChanged(v == _none ? null : v),
      ),
    );
  }
}

class _AcModeOptionEditor extends StatelessWidget {
  const _AcModeOptionEditor({
    super.key,
    required this.option,
    required this.index,
    required this.visible,
    required this.onChanged,
    required this.onVisibilityChanged,
    this.onDelete,
  });

  final Map<String, dynamic> option;
  final int index;
  final bool visible;
  final VoidCallback onChanged;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final label = option['label'] as String? ?? 'Modus';
    return LuxeInsetCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. $label',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red[400],
                    tooltip: 'Modus verwijderen',
                    onPressed: onDelete,
                  ),
              ],
            ),
            _InstallerStrField(
              key: ValueKey('ac-mode-$index-label'),
              label: 'Label',
              value: label,
              onChanged: (v) {
                option['label'] = v.isEmpty ? 'Modus' : v;
                onChanged();
              },
            ),
            _InstallerStrField(
              key: ValueKey('ac-mode-$index-value'),
              label: 'KNX-waarde (geheel getal)',
              value: (option['value'] as num?)?.toString() ?? '0',
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null) option['value'] = n;
                onChanged();
              },
              number: true,
            ),
            _AcIconPickerField(
              label: 'Icoon',
              value: option['icon'] as String?,
              onChanged: (v) {
                if (v == null) {
                  option.remove('icon');
                } else {
                  option['icon'] = v;
                }
                onChanged();
              },
            ),
            LuxeSwitchRow(
              title: 'Zichtbaar in app',
              value: visible,
              onChanged: onVisibilityChanged,
            ),
          ],
        ),
    );
  }
}

class _AcFanOptionEditor extends StatelessWidget {
  const _AcFanOptionEditor({
    super.key,
    required this.option,
    required this.index,
    required this.onChanged,
    this.onDelete,
  });

  final Map<String, dynamic> option;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return LuxeInsetCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Stand ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.red[400],
                    tooltip: 'Stand verwijderen',
                    onPressed: onDelete,
                  ),
              ],
            ),
            _InstallerStrField(
              key: ValueKey('ac-fan-$index-label'),
              label: 'Label',
              value: option['label'] as String? ?? '',
              onChanged: (v) {
                option['label'] = v;
                onChanged();
              },
            ),
            _InstallerStrField(
              key: ValueKey('ac-fan-$index-value'),
              label: 'KNX-waarde (geheel getal)',
              value: (option['value'] as num?)?.toString() ?? '0',
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null) option['value'] = n;
                onChanged();
              },
              number: true,
            ),
          ],
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
        _InstallerInfoTitle(
          title: 'Meldingen',
          body:
              'Elke regel is één KNX-punt. Urgentie bepaalt de kleur in de app. '
              'Bij 1-bit is actief = 1. Bij andere DPT’s kun je de drempelwaarde zetten. '
              'Optionele teksten en icoon voor actief/inactief.',
          trailing: TextButton.icon(
            onPressed: _items.length < 24 ? _addItem : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Toevoegen'),
          ),
        ),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nog geen meldingen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          const _OverviewColHeader([
            (label: 'Onderwerp', flex: 2, width: null),
            (label: 'Groepsadres', flex: 2, width: null),
            (label: 'DPT', flex: 2, width: null),
            (label: 'Urgentie', flex: 2, width: null),
            (label: 'Actief bij', flex: 1, width: null),
            (label: 'Tekst aan', flex: 1, width: null),
            (label: 'Tekst uit', flex: 1, width: null),
            (label: 'Icoon', flex: 1, width: null),
            (label: '', flex: 0, width: 40.0),
          ]),
          for (int i = 0; i < _items.length; i++)
            _MeldingItemEditor(
              key: ValueKey(_items[i]['id']),
              item: _items[i],
              onChanged: (updated) => _updateItem(i, updated),
              onDelete: () => _removeItem(i),
            ),
        ],
      ],
    );
  }
}

class _MeldingItemEditor extends StatelessWidget {
  const _MeldingItemEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _StrField(
              label: 'Onderwerp',
              value: item['label'] as String? ?? '',
              compact: true,
              onChanged: (v) => _set('label', v.isEmpty ? 'Melding' : v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _StrField(
              label: 'Groepsadres',
              value: item['ga'] as String? ?? '',
              compact: true,
              gaSearch: true,
              gaDptHint: 'DPT$dpt',
              onChanged: (v) => _set('ga', v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _DptDropdown(
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
              compact: true,
              onChanged: (v) => _set('dpt', v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: urgency,
              isExpanded: true,
              decoration: luxeFilledDecoration().copyWith(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'urgent',
                  child: Text('Urgent'),
                ),
                DropdownMenuItem(
                  value: 'belangrijk',
                  child: Text('Belangrijk'),
                ),
                DropdownMenuItem(
                  value: 'minder_belangrijk',
                  child: Text('Info'),
                ),
              ],
              onChanged: (v) => _set('urgency', v ?? 'minder_belangrijk'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: is1bit
                ? const SizedBox.shrink()
                : _StrField(
                    label: 'Actief bij',
                    value: item['activeValue']?.toString() ?? '',
                    compact: true,
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      _set('activeValue', n);
                    },
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _StrField(
              label: 'Tekst aan',
              value: item['activeLabel'] as String? ?? '',
              compact: true,
              onChanged: (v) => _set('activeLabel', v.isEmpty ? null : v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _StrField(
              label: 'Tekst uit',
              value: item['inactiveLabel'] as String? ?? '',
              compact: true,
              onChanged: (v) => _set('inactiveLabel', v.isEmpty ? null : v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _IconPickerField(
              label: 'Icoon',
              value: item['icon'] as String?,
              compact: true,
              onChanged: (v) => _set('icon', v),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: LuxeColors.inkSoft,
              tooltip: 'Verwijder melding',
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Media (Sonos / Bluesound) KNX rocker ─────────────────────────────────────

class MediaKnxInstallerSection extends StatefulWidget {
  const MediaKnxInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<MediaKnxInstallerSection> createState() =>
      _MediaKnxInstallerSectionState();
}

class _MediaKnxInstallerSectionState extends State<MediaKnxInstallerSection> {
  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  Map<String, dynamic>? _knxIfPresent() {
    final v = widget.device['knx'];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      widget.device['knx'] = m;
      return m;
    }
    return null;
  }

  Map<String, dynamic> _knx() => _ensureMap(widget.device, 'knx');

  void _pruneKnx() {
    final knx = _knxIfPresent();
    if (knx == null) return;
    for (final key in [
      'playPause',
      'volumeDim',
      'mute',
      'previous',
      'next',
      'previousPreset',
      'nextPreset',
    ]) {
      final v = knx[key];
      if (v is! List) continue;
      final nonempty =
          v.where((e) => e.toString().trim().isNotEmpty).length;
      if (nonempty == 0 && v.length <= 1) knx.remove(key);
    }
    if (knx['volumeAffectsGroup'] != true) knx.remove('volumeAffectsGroup');
    if (knx.isEmpty) widget.device.remove('knx');
  }

  List<String> _stored(String key) {
    final v = _knxIfPresent()?[key];
    if (v is List) {
      return [for (final e in v) e?.toString() ?? ''];
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return [];
  }

  int _fieldCount(String key) {
    final n = _stored(key).length;
    return n == 0 ? 1 : n;
  }

  String _fieldValue(String key, int i) {
    final list = _stored(key);
    if (i < list.length) return list[i];
    return '';
  }

  void _writeList(String key, List<String> list) {
    final knx = _knx();
    knx[key] = list;
    _pruneKnx();
    _notify();
  }

  void _setField(String key, int index, String raw) {
    final list = [..._stored(key)];
    while (list.length <= index) {
      list.add('');
    }
    list[index] = raw;
    _knx()[key] = list;
  }

  void _addField(String key) {
    final list = [..._stored(key)];
    if (list.isEmpty) list.add('');
    list.add('');
    _writeList(key, list);
  }

  void _removeField(String key, int index) {
    final list = [..._stored(key)];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    _writeList(key, list);
  }

  Widget _gaGroup({
    required String title,
    required String body,
    required String keyName,
    required String dptHint,
  }) {
    final stored = _stored(keyName);
    final count = _fieldCount(keyName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InstallerInfoTitle(title: title, body: body),
          for (var i = 0; i < count; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InstallerStrField(
                    key: ValueKey(
                      '${widget.device['id']}-mknx-$keyName-$i',
                    ),
                    label: count == 1 ? 'Groepsadres' : 'Groepsadres ${i + 1}',
                    value: _fieldValue(keyName, i),
                    onChanged: (v) => _setField(keyName, i, v),
                    gaSearch: true,
                    gaDptHint: dptHint,
                  ),
                ),
                if (stored.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: IconButton(
                      tooltip: 'Adres verwijderen',
                      onPressed: () => _removeField(keyName, i),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red[400],
                      ),
                    ),
                  ),
              ],
            ),
          LuxeAddRow(
            label: 'Adres toevoegen',
            onTap: () => _addField(keyName),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupOn = _knxIfPresent()?['volumeAffectsGroup'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('KNX-drukknoppen', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Optioneel. De NUC luistert op de bus — de telefoon hoeft niet open.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _gaGroup(
          title: 'Play / pauze',
          body:
              'DPT 1.001. Drukken (1) wisselt play/pauze. '
              'Loslaten (0) wordt genegeerd, anders pauzeert een drukknop meteen. '
              'Meerdere adressen mogelijk.',
          keyName: 'playPause',
          dptHint: 'DPT1.001',
        ),
        _gaGroup(
          title: 'Volume dim op/neer',
          body:
              'DPT 3.007, één groepadres voor omhoog én omlaag. '
              'Vasthouden herhaalt stappen van 5% tot het stoptelegram (0). '
              'Zakt niet onder 5%, zodat er altijd geluid blijft; mute is apart. '
              'Standaard alleen deze zone; zie de schakelaar hieronder voor de groep.',
          keyName: 'volumeDim',
          dptHint: 'DPT3.007',
        ),
        _gaGroup(
          title: 'Mute / unmute',
          body:
              'DPT 1.001. Drukken (1) wisselt mute. '
              'Loslaten (0) wordt genegeerd, anders unmutet een drukknop meteen weer. '
              'Meerdere adressen mogelijk.',
          keyName: 'mute',
          dptHint: 'DPT1.001',
        ),
        _gaGroup(
          title: 'Terug',
          body:
              'DPT 1.001. Elke 1 doet hetzelfde als de knop links van play/pauze in de app '
              '(vorig nummer, of vorige radiozender uit de favorieten). '
              '0 wordt genegeerd.',
          keyName: 'previous',
          dptHint: 'DPT1.001',
        ),
        _gaGroup(
          title: 'Volgende',
          body:
              'DPT 1.001. Elke 1 doet hetzelfde als de knop rechts van play/pauze in de app '
              '(volgend nummer, of volgende radiozender uit de favorieten). '
              '0 wordt genegeerd.',
          keyName: 'next',
          dptHint: 'DPT1.001',
        ),
        _gaGroup(
          title: 'Vorige preset',
          body:
              'DPT 1.001. Elke 1 speelt de vorige Sonos-favoriet of BluOS-preset '
              '(hele lijst, ook afspeellijsten; springt van de eerste naar de laatste). '
              '0 wordt genegeerd.',
          keyName: 'previousPreset',
          dptHint: 'DPT1.001',
        ),
        _gaGroup(
          title: 'Volgende preset',
          body:
              'DPT 1.001. Elke 1 speelt de volgende Sonos-favoriet of BluOS-preset '
              '(hele lijst, ook afspeellijsten; springt van de laatste naar de eerste). '
              '0 wordt genegeerd.',
          keyName: 'nextPreset',
          dptHint: 'DPT1.001',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: LuxeSwitchRow(
            title: 'Andere zones in de groep meenemen',
            subtitle:
                'Uit: alleen het volume van deze zone. '
                'Aan: dezelfde schaling als de groepsvolume-slider in de app. '
                'Play, pauze en skip volgen de groep altijd via Sonos/Bluesound.',
            value: groupOn,
            onChanged: (v) {
              if (v) {
                _knx()['volumeAffectsGroup'] = true;
              } else {
                _knxIfPresent()?.remove('volumeAffectsGroup');
              }
              _pruneKnx();
              _notify();
            },
          ),
        ),
      ],
    );
  }
}
