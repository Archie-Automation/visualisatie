import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../ac_mode_config.dart';
import '../room_control_category.dart';
import '../theme.dart';
import '../ui/widgets/back_pill.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/glass_card.dart';
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

const universalKnxRoles = [
  'bit',
  'byte',
  'percent',
  'temperature',
  'raw_int',
  'scene',
];

/// Rol → DPT-label voor installateur (backend: ROLE_DPT in knxBus).
const universalRoleDptLabels = <String, String>{
  'bit': 'DPT 1.001 — aan/uit (bit)',
  'byte': 'DPT 5.010 — byte (0–255)',
  'percent': 'DPT 5.001 — percentage (0–100)',
  'temperature': 'DPT 9.001 — temperatuur (°C)',
  'raw_int': 'DPT 5.010 — geheel getal',
  'scene': 'DPT 18.001 — scene (oproepen / opslaan)',
};

void _ensureUniversalToggle(Map<String, dynamic> b) {
  final action = _ensureMap(b, 'action');
  b['actionOff'] ??= {
    'ga': action['ga'] ?? '1/1/1',
    'role': action['role'] ?? 'bit',
    'value': _clampKnxRoleValue(
      action['role'] as String? ?? 'bit',
      false,
    ),
  };
  b['statusGa'] ??= action['ga'] ?? '1/1/1';
  _syncUniversalSharedKnx(b);
}

void _syncUniversalSharedKnx(Map<String, dynamic> b) {
  final action = _ensureMap(b, 'action');
  final ga = action['ga'];
  final role = (action['role'] as String?) ?? 'bit';
  void sync(String key) {
    if (b[key] == null) return;
    final m = _ensureMap(b, key);
    m['ga'] = ga;
    m['role'] = role;
    m['value'] = _clampKnxRoleValue(role, m['value']);
  }

  sync('actionOff');
  sync('actionLong');
}

bool _universalHasLongPress(Map<String, dynamic> b, {required bool switchLayout}) {
  if (switchLayout) return false;
  final role = (_ensureMap(b, 'action')['role'] as String?) ?? 'bit';
  if (_roleIsScene(role)) return true;
  return b['actionLong'] != null;
}

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

bool _roleIsScene(String role) => role == 'scene';

({num min, num max, bool integer})? _knxValueBounds(String role) {
  switch (role) {
    case 'scene':
      return (min: 1, max: 64, integer: true);
    case 'byte':
    case 'raw_int':
    case 'scene_number':
      return (min: 0, max: 255, integer: true);
    case 'percent':
    case 'dim_value':
    case 'position':
      return (min: 0, max: 100, integer: true);
    case 'temperature':
    case 'setpoint':
      return (min: -273, max: 670760, integer: false);
    default:
      return null;
  }
}

num _clampKnxNum(num n, ({num min, num max, bool integer}) bounds) {
  var c = n.clamp(bounds.min, bounds.max);
  if (bounds.integer) c = c.round();
  return c;
}

dynamic _clampKnxRoleValue(String role, dynamic raw) {
  if (_roleIsBool(role)) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final n = num.tryParse('$raw'.replaceAll(',', '.'));
    return n != null && n != 0;
  }
  num n;
  if (raw is num) {
    n = raw;
  } else if (raw is bool) {
    n = raw ? 1 : 0;
  } else {
    n = num.tryParse('$raw'.replaceAll(',', '.')) ?? 0;
  }
  final bounds = _knxValueBounds(role);
  if (bounds == null) return n;
  return _clampKnxNum(n, bounds);
}

String _knxValueHint(String role) {
  final b = _knxValueBounds(role);
  if (b == null) return '';
  final lo = b.integer ? '${b.min.toInt()}' : '${b.min}';
  final hi = b.integer ? '${b.max.toInt()}' : '${b.max}';
  return '$lo–$hi';
}

String _knxValueCaption(String role) =>
    _roleIsScene(role) ? 'Scene (1–64)' : 'Waarde';

/// Alleen de waarde (GA/DPT zitten elders). Zelfde hoogte voor bit-dropdown en getalveld.
class _KnxValueField extends StatelessWidget {
  const _KnxValueField({
    required this.knx,
    required this.role,
    required this.onChanged,
    this.compact = false,
    this.hideLabel = false,
  });

  final Map<String, dynamic> knx;
  final String role;
  final VoidCallback onChanged;
  final bool compact;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final bounds = _knxValueBounds(role);
    final label = hideLabel
        ? ''
        : (compact
            ? _knxValueCaption(role)
            : '${_knxValueCaption(role)} (${_knxValueHint(role)})');
    if (_roleIsBool(role)) {
      if (compact) {
        return _InstallerDropdown(
          compact: true,
          label: label,
          value: knx['value'] == true || knx['value'] == 1 ? '1' : '0',
          options: const ['1', '0'],
          optionLabels: const {
            '1': '1',
            '0': '0',
          },
          onChanged: (v) {
            knx['value'] = v == '1';
            onChanged();
          },
        );
      }
      return LuxeSwitchRow(
        title: 'Waarde (aan)',
        value: knx['value'] == true || knx['value'] == 1,
        onChanged: (v) {
          knx['value'] = v;
          onChanged();
        },
      );
    }
    return _InstallerStrField(
      key: ValueKey('knx-val-$role-${identityHashCode(knx)}'),
      compact: compact,
      label: label.isEmpty ? 'Waarde' : label,
      hint: _knxValueHint(role),
      value: '${_clampKnxRoleValue(role, knx['value'])}',
      number: true,
      min: bounds?.min,
      max: bounds?.max,
      integer: bounds?.integer ?? false,
      onChanged: (v) {
        knx['value'] = _clampKnxRoleValue(role, v);
        onChanged();
      },
    );
  }
}

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
    this.compact = false,
  });

  final String title;
  final Map<String, dynamic> knx;
  final List<String> roles;
  final VoidCallback onChanged;
  final bool showPulseMs;
  /// Optioneel: rol → weergavenaam (bijv. DPT-omschrijving).
  final Map<String, String>? roleLabels;
  /// Eén rij: groepadres · DPT · waarde.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final roleRaw = (knx['role'] as String?) ?? roles.first;
    final role = roles.contains(roleRaw) ? roleRaw : roles.first;

    final gaField = _InstallerStrField(
      compact: compact,
      label: compact ? 'Groepadres' : 'Groepadres (x/y/z)',
      value: knx['ga'] as String? ?? '',
      onChanged: (v) {
        knx['ga'] = v;
        onChanged();
      },
    );
    final roleField = _InstallerDropdown(
      compact: compact,
      label: compact
          ? ''
          : (roleLabels != null ? 'Datatype (DPT)' : 'KNX-rol'),
      value: role,
      options: roles,
      optionLabels: roleLabels,
      onChanged: (v) {
        knx['role'] = v;
        knx['value'] = _clampKnxRoleValue(v, knx['value']);
        onChanged();
      },
    );
    final valueField = _KnxValueField(
      knx: knx,
      role: role,
      compact: compact,
      hideLabel: compact,
      onChanged: onChanged,
    );
    final pulseField = showPulseMs && _roleIsBool(role)
        ? _InstallerStrField(
            compact: compact,
            label: 'Pulsduur (ms)',
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
          )
        : null;

    if (compact) {
      Widget col(int flex, String caption, Widget child) => Expanded(
            flex: flex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    caption,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                child,
              ],
            ),
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                col(3, 'Groepadres', gaField),
                const SizedBox(width: 8),
                col(2, 'DPT', roleField),
                const SizedBox(width: 8),
                col(1, _roleIsScene(role) ? 'Scene' : 'Waarde', valueField),
              ],
            ),
            if (pulseField != null) ...[
              const SizedBox(height: 8),
              pulseField,
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        gaField,
        roleField,
        valueField,
        if (pulseField != null) pulseField,
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
    final layout = universalPanelLayout(_ensureMap(widget.device, 'universal'));
    final n = buttons.length + 1;
    final action = {'ga': '1/1/1', 'role': 'bit', 'value': true};
    buttons.add({
      'id': 'btn-${_uuid.v4()}',
      'label': layout == 'switch' ? 'Schakelaar $n' : 'Knop $n',
        'action': action,
      if (layout == 'switch') ...{
        'actionOff': {'ga': '1/1/1', 'role': 'bit', 'value': false},
        'statusGa': '1/1/1',
      },
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final uni = _ensureMap(widget.device, 'universal');
    final buttons = _ensureList(uni, 'buttons');
    final currentIcon = uni['icon'] as String? ?? 'grid';
    final layout = universalPanelLayout(uni);
    final canAdd = buttons.length < kUniversalMaxButtons;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IconPickerField(
          label: 'Icoon',
          value: currentIcon,
          onChanged: (v) {
            uni['icon'] = v ?? 'grid';
            _notify();
          },
        ),
        _InstallerDropdown(
          label: 'Weergave',
          value: layout,
          options: const ['switch', 'buttons'],
          optionLabels: const {
            'switch': 'Schakelaar',
            'buttons': 'Knoppenrij (max. 4)',
          },
          onChanged: (v) {
            uni['layout'] = v;
            if (v == 'switch') {
              for (final b in buttons) {
                _ensureUniversalToggle(b);
              }
            }
            _notify();
          },
        ),
        const SizedBox(height: 16),
        Text(
          layout == 'switch'
              ? 'Schakelaars (${buttons.length}/$kUniversalMaxButtons)'
              : 'Knoppen (${buttons.length}/$kUniversalMaxButtons)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (buttons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nog geen ${layout == 'switch' ? 'schakelaars' : 'knoppen'}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        for (var i = 0; i < buttons.length; i++)
          _UniversalButtonCard(
            key: ValueKey(buttons[i]['id'] ?? 'b$i'),
            button: buttons[i],
            switchLayout: layout == 'switch',
            onChanged: _notify,
            onDelete: () {
              buttons.removeAt(i);
              _notify();
            },
          ),
        if (canAdd)
          LuxeAddRow(
            label: layout == 'switch'
                ? 'Schakelaar toevoegen'
                : 'Knop toevoegen',
            onTap: () => _addButton(buttons),
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
    this.switchLayout = false,
  });

  final Map<String, dynamic> button;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool switchLayout;

  @override
  State<_UniversalButtonCard> createState() => _UniversalButtonCardState();
}

class _UniversalButtonCardState extends State<_UniversalButtonCard> {
  _UniversalButtonMode get _mode {
    if (widget.switchLayout) return _UniversalButtonMode.toggle;
    return widget.button['actionOff'] != null
        ? _UniversalButtonMode.toggle
        : _UniversalButtonMode.single;
  }

  @override
  void initState() {
    super.initState();
    if (widget.switchLayout) _ensureUniversalToggle(widget.button);
    _syncUniversalSharedKnx(widget.button);
  }

  @override
  void didUpdateWidget(_UniversalButtonCard old) {
    super.didUpdateWidget(old);
    if (widget.switchLayout) _ensureUniversalToggle(widget.button);
    _syncUniversalSharedKnx(widget.button);
  }

  void _setMode(_UniversalButtonMode mode) {
    final b = widget.button;
    if (mode == _UniversalButtonMode.toggle) {
      _ensureUniversalToggle(b);
    } else {
      b.remove('actionOff');
      b.remove('statusGa');
      b.remove('statusOnValue');
    }
    setState(() {});
    widget.onChanged();
  }

  void _notify() {
    setState(() {});
    widget.onChanged();
  }

  void _setLongPress(bool enabled) {
    final b = widget.button;
    if (enabled) {
      final action = _ensureMap(b, 'action');
      b['actionLong'] ??= {
        'ga': action['ga'],
        'role': action['role'],
        'value': action['value'],
      };
      _syncUniversalSharedKnx(b);
    } else {
      b.remove('actionLong');
      b.remove('confirmLong');
    }
    _notify();
  }

  bool get _statusInverted {
    final v = widget.button['statusOnValue'];
    return v == false || v == 0;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.button;
    final action = _ensureMap(b, 'action');
    final actionRole = action['role'] as String? ?? 'bit';
    final statusBounds = _knxValueBounds(actionRole);
    final isToggle = _mode == _UniversalButtonMode.toggle;
    final isScene = _roleIsScene(actionRole);
    final hasLongPress =
        _universalHasLongPress(b, switchLayout: widget.switchLayout);
    final captionStyle = Theme.of(context).textTheme.bodySmall;

    Widget captioned(String caption, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(caption, style: captionStyle),
            ),
            child,
          ],
        );

    return LuxeInsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: captioned(
                  'Label',
                  _InstallerStrField(
                    key: ValueKey('ul-${b['id']}-label'),
                    compact: true,
                    label: 'Label',
                    value: b['label'] as String? ?? '',
                    onChanged: (v) {
                      b['label'] = v;
                      widget.onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IconPickerField(
                  label: 'Icoon',
                  compact: true,
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
              ),
              IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!widget.switchLayout) ...[
            _InstallerDropdown(
              compact: true,
              label: 'Gedrag',
              value: isToggle ? 'toggle' : 'single',
              options: const ['single', 'toggle'],
              optionLabels: const {
                'single': 'Enkele actie',
                'toggle': 'Aan / uit',
              },
              onChanged: (v) {
                _setMode(
                  v == 'toggle'
                      ? _UniversalButtonMode.toggle
                      : _UniversalButtonMode.single,
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: captioned(
                  'Groepadres',
                  _InstallerStrField(
                    key: ValueKey('ul-${b['id']}-ga'),
                    compact: true,
                    label: 'Groepadres',
                    value: action['ga'] as String? ?? '',
                    onChanged: (v) {
                      action['ga'] = v;
                      _syncUniversalSharedKnx(b);
                      widget.onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: captioned(
                  'DPT',
                  _InstallerDropdown(
                    compact: true,
                    label: '',
                    value: universalKnxRoles.contains(actionRole)
                        ? actionRole
                        : universalKnxRoles.first,
                    options: universalKnxRoles,
                    optionLabels: universalRoleDptLabels,
                    onChanged: (v) {
                      action['role'] = v;
                      action['value'] = _clampKnxRoleValue(v, action['value']);
                      if (_roleIsScene(v)) {
                        b.remove('actionLong');
                      }
                      _syncUniversalSharedKnx(b);
                      _notify();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isToggle)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: captioned(
                    isScene ? 'Scene bij aan' : 'Waarde bij aan',
                    _KnxValueField(
                      knx: action,
                      role: actionRole,
                      compact: true,
                      hideLabel: true,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: captioned(
                    isScene ? 'Scene bij uit' : 'Waarde bij uit',
                    _KnxValueField(
                      knx: _ensureMap(b, 'actionOff'),
                      role: actionRole,
                      compact: true,
                      hideLabel: true,
                      onChanged: () {
                        _syncUniversalSharedKnx(b);
                        widget.onChanged();
                      },
                    ),
                  ),
                ),
              ],
            )
          else
            captioned(
              isScene ? 'Scene' : 'Waarde',
              _KnxValueField(
                knx: action,
                role: actionRole,
                compact: true,
                hideLabel: true,
                onChanged: widget.onChanged,
              ),
            ),
          if (isScene && !widget.switchLayout) ...[
            const SizedBox(height: 6),
            Text(
              'Korte druk roept de scene op. Lange druk slaat de huidige stand op.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!widget.switchLayout && !isScene) ...[
            LuxeSwitchRow(
              title: 'Lange druk',
              subtitle: 'Zelfde groepsadres en DPT, andere waarde',
              value: b['actionLong'] != null,
              onChanged: _setLongPress,
            ),
            if (b['actionLong'] != null)
              captioned(
                'Waarde lange druk',
                _KnxValueField(
                  knx: _ensureMap(b, 'actionLong'),
                  role: actionRole,
                  compact: true,
                  hideLabel: true,
                  onChanged: () {
                    _syncUniversalSharedKnx(b);
                    widget.onChanged();
                  },
                ),
              ),
          ],
          if (isToggle) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: captioned(
                    'Status groepsadres',
                    _InstallerStrField(
                      key: ValueKey('ul-${b['id']}-stga'),
                      compact: true,
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
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roleIsBool(actionRole)
                      ? LuxeSwitchRow(
                          title: 'Status omdraaien',
                          subtitle: _statusInverted
                              ? 'Status 0 is aan'
                              : 'Status 1 is aan',
                          value: _statusInverted,
                          onChanged: (v) {
                            if (v) {
                              b['statusOnValue'] = false;
                            } else {
                              b.remove('statusOnValue');
                            }
                            widget.onChanged();
                            setState(() {});
                          },
                        )
                      : captioned(
                          'Aan-waarde (${_knxValueHint(actionRole)})',
                          _InstallerStrField(
                            key: ValueKey('ul-${b['id']}-ston'),
                            compact: true,
                            label: 'Waarde die “aan” betekent',
                            hint: _knxValueHint(actionRole),
                            value: '${b['statusOnValue'] ?? 1}',
                            number: true,
                            min: statusBounds?.min,
                            max: statusBounds?.max,
                            integer: statusBounds?.integer ?? true,
                            onChanged: (v) {
                              b['statusOnValue'] =
                                  _clampKnxRoleValue(actionRole, v);
                              widget.onChanged();
                            },
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          _UniversalButtonConfirmSection(
            button: b,
            confirmKey: 'confirm',
            label: hasLongPress
                ? 'Bevestiging korte druk'
                : 'Bevestiging',
            onChanged: () {
              setState(() {});
              widget.onChanged();
            },
          ),
          if (hasLongPress) ...[
            const SizedBox(height: 8),
            _UniversalButtonConfirmSection(
              button: b,
              confirmKey: 'confirmLong',
              label: 'Bevestiging lange druk',
              onChanged: () {
                setState(() {});
                widget.onChanged();
              },
            ),
          ],
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
    this.confirmKey = 'confirm',
    this.label = 'Bevestiging',
  });

  final Map<String, dynamic> button;
  final VoidCallback onChanged;
  final String confirmKey;
  final String label;

  @override
  State<_UniversalButtonConfirmSection> createState() =>
      _UniversalButtonConfirmSectionState();
}

class _UniversalButtonConfirmSectionState
    extends State<_UniversalButtonConfirmSection> {

  // Returns null if no confirm, "simple" or "pin"
  String? get _confirmType {
    final c = widget.button[widget.confirmKey];
    if (c == null || c == false) return null;
    if (c is Map && c['pin'] != null) return 'pin';
    return 'simple';
  }

  void _setConfirmType(String? type) {
    final b = widget.button;
    final key = widget.confirmKey;
    if (type == null) {
      b.remove(key);
    } else if (type == 'simple') {
      b[key] = {'title': 'Bevestigen'};
    } else {
      final existing = b[key];
      final oldPin = (existing is Map) ? existing['pin'] as String? : null;
      b[key] = {
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
    final confirm = widget.button[widget.confirmKey];
    final pin = (confirm is Map) ? confirm['pin'] as String? : null;
    final message = (confirm is Map) ? confirm['message'] as String? : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _InstallerDropdown(
            compact: true,
            label: widget.label,
            value: type ?? 'none',
            options: const ['none', 'simple', 'pin'],
            optionLabels: const {
              'none': 'Geen',
              'simple': 'Ja / Nee',
              'pin': 'PIN',
            },
            onChanged: (v) => _setConfirmType(v == 'none' ? null : v),
        ),
        if (type == 'simple' || type == 'pin') ...[
          _InstallerStrField(
            key: ValueKey('ucf-${widget.button['id']}-${widget.confirmKey}-msg'),
            label: 'Bevestigingstekst (optioneel)',
            value: message ?? '',
            onChanged: (v) {
              final c = _ensureMap(widget.button, widget.confirmKey);
              if (v.trim().isEmpty) c.remove('message'); else c['message'] = v.trim();
              widget.onChanged();
            },
          ),
        ],
        if (type == 'pin') ...[
          _InstallerStrField(
            key: ValueKey('ucf-${widget.button['id']}-${widget.confirmKey}-pin'),
            label: '4-cijferige PIN *',
            value: pin ?? '',
            onChanged: (v) {
              final digits = v.replaceAll(RegExp(r'[^0-9]'), '').substring(
                  0, v.replaceAll(RegExp(r'[^0-9]'), '').length.clamp(0, 4));
              final c = _ensureMap(widget.button, widget.confirmKey);
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
  Map<String, dynamic> get _fan => _ensureMap(widget.device, 'fan');

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _setModel(String raw) {
    _fan.remove('onOff');
    _fan.remove('speed');
    _fan.remove('oscillate');
    _fan.remove('direction');
    if (raw == _wtwModelNone) {
      _fan.remove('model');
      _fan.remove('mv');
    } else {
      _fan['model'] = raw;
      final mv = _ensureMap(_fan, 'mv');
      mv.remove('logics');
    }
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final model = _fan['model'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ValueKey(model.isEmpty ? _wtwModelNone : model),
          child: _InstallerDropdown(
            label: 'Type ventilator',
            value: model.isEmpty ? _wtwModelNone : model,
            options: const [
              _wtwModelNone,
              'mv_1contact',
              'mv_scene',
              'mv_0_10v',
            ],
            optionLabels: const {
              _wtwModelNone: 'Kies type…',
              'mv_1contact': '2 standen, 1 contact (aan/uit)',
              'mv_scene': '3 standen, 2 contacten (scene sturing)',
              'mv_0_10v': '4 standen, 0–10V (percentage)',
            },
            onChanged: _setModel,
          ),
        ),
        if (model.startsWith('mv_'))
          _WtwMvInstaller(
            model: model,
            mv: _ensureMap(_fan, 'mv'),
            onChanged: _notify,
            showLogic: false,
          )
        else
          Text(
            'Kies eerst het type. Velden hangen daarvan af.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
    this.min,
    this.max,
    this.integer = false,
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
  final num? min;
  final num? max;
  /// Whole numbers only (byte, percent). Allows a decimal when false.
  final bool integer;

  @override
  State<_InstallerStrField> createState() => _InstallerStrFieldState();
}

/// Validates a KNX group address: `main/middle/sub` where
/// main = 0-31, middle = 0-7, sub = 0-255.
String? validateKnxGa(String input) {
  final s = input.trim();
  if (s.isEmpty) return null; // leeg is optioneel
  final parts = s.split('/');
  if (parts.length != 3) return 'Formaat: hoofd/midden/sub (bijv. 1/2/3)';
  final main = int.tryParse(parts[0]);
  final middle = int.tryParse(parts[1]);
  final sub = int.tryParse(parts[2]);
  if (main == null || middle == null || sub == null) {
    return 'Alleen gehele getallen gescheiden door /';
  }
  if (main < 0 || main > 31) return 'Hoofdgroep: 0–31 (is $main)';
  if (middle < 0 || middle > 7) return 'Middengroep: 0–7 (is $middle)';
  if (sub < 0 || sub > 255) return 'Subgroep: 0–255 (is $sub)';
  return null;
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

  /// Null = leave the typed text. Otherwise replace with a value inside [min]/[max].
  String? _clampNumericInput(String s) {
    final min = widget.min;
    final max = widget.max;
    if (min == null || max == null) return null;
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty || t == '-' || t == '.' || t == '-.') return null;
    final n = num.tryParse(t);
    if (n == null) return null;
    final c = widget.integer
        ? n.round().clamp(min, max)
        : n.clamp(min, max);
    if (c == n) return null;
    if (widget.integer) return '${c.round()}';
    return '$c';
  }

  @override
  Widget build(BuildContext context) {
    final gaSearch = _gaSearchEnabled;
    final gaError = gaSearch ? validateKnxGa(_c.text) : null;
    final resolvedName = gaSearch && _c.text.trim().isNotEmpty && gaError == null
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
              hint: widget.hint,
              helper: widget.compact ? null : resolvedName,
              error: gaError,
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
                ? TextInputType.numberWithOptions(
                    decimal: !widget.integer,
                    signed: widget.min != null && widget.min! < 0,
                  )
                : TextInputType.text,
            inputFormatters: [
              if (widget.number && widget.integer)
                FilteringTextInputFormatter.allow(
                  widget.min != null && widget.min! < 0
                      ? RegExp(r'-?\d*')
                      : RegExp(r'\d*'),
                )
              else if (widget.number)
                FilteringTextInputFormatter.allow(RegExp(r'-?\d*[.,]?\d*')),
            ],
            onChanged: (s) {
              if (widget.number) {
                final clamped = _clampNumericInput(s);
                if (clamped != null && clamped != s) {
                  _c.value = TextEditingValue(
                    text: clamped,
                    selection:
                        TextSelection.collapsed(offset: clamped.length),
                  );
                  widget.onChanged(clamped);
                  return;
                }
              }
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
    this.compact = false,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  /// Weergavetekst per optie-waarde (bijv. DPT-omschrijving).
  final Map<String, String>? optionLabels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = options.contains(value) ? value : options.first;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) LuxeFieldLabel(label),
          if (compact && label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          DropdownButtonFormField<String>(
            key: ValueKey('$label-$v'),
            initialValue: v,
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
                    optionLabels?[o] ?? o,
                    overflow: TextOverflow.ellipsis,
                  ),
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

/// Human-readable label per DPT code (meldingen- en WTW-installer).
const _wtwDptLabels = <String, String>{
  '1.001': 'Aan/uit (DPT 1.001)',
  '1.002': 'True/false (DPT 1.002)',
  '1.008': 'Op/neer (DPT 1.008)',
  '1.009': 'Open/dicht (DPT 1.009)',
  '1.011': 'Actief/inactief (DPT 1.011)',
  '5.001': 'Procent 0–100 (DPT 5.001)',
  '5.010': 'Byte 0–255 (DPT 5.010)',
  '6.001': 'Getal −128…127 (DPT 6.001)',
  '7.001': 'Teller 0–65535 (DPT 7.001)',
  '8.001': 'Getal −32768…32767 (DPT 8.001)',
  '9.001': 'Temperatuur °C (DPT 9.001)',
  '9.002': 'Temperatuurverschil K (DPT 9.002)',
  '9.004': 'Verlichting lux (DPT 9.004)',
  '9.005': 'Windsnelheid m/s (DPT 9.005)',
  '9.006': 'Luchtdruk Pa (DPT 9.006)',
  '9.007': 'Vochtigheid %RH (DPT 9.007)',
  '9.008': 'CO₂ ppm (DPT 9.008)',
  '9.009': 'Volumestroom m³/h (DPT 9.009)',
  '9.020': 'Spanning mV (DPT 9.020)',
  '9.021': 'Stroom mA (DPT 9.021)',
  '12.001': 'Teller 32-bit (DPT 12.001)',
  '13.001': 'Getal 32-bit (DPT 13.001)',
  '14.019': 'Vermogen W (DPT 14.019)',
  '14.068': 'Windsnelheid m/s (DPT 14.068)',
  'hex': 'Hex-weergave (alleen status)',
};

const _wtwModelNone = '__none__';

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
  Map<String, dynamic> get _wtw => _ensureMap(widget.device, 'wtw');

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _setModel(String raw) {
    _wtw.remove('buttons');
    _wtw.remove('status');
    if (raw == _wtwModelNone) {
      _wtw.remove('model');
      _wtw.remove('zehnder');
      _wtw.remove('duco');
      _wtw.remove('mv');
      _wtw.remove('modbus');
    } else {
      _wtw['model'] = raw;
      if (raw == 'zehnder_comfoConnect') {
        final z = _ensureMap(_wtw, 'zehnder');
        z['minutes'] ??= 30;
      }
      if (raw == 'duco_connectivity_board') {
        _ensureMap(_wtw, 'duco');
      }
      if (raw.startsWith('mv_')) {
        _ensureMap(_wtw, 'mv');
      }
      if (raw == 'modbus_universal') {
        _ensureMap(_wtw, 'modbus');
      }
    }
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final model = _wtw['model'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ValueKey(model.isEmpty ? _wtwModelNone : model),
          child: _InstallerDropdown(
          label: 'Type WTW',
          value: model.isEmpty ? _wtwModelNone : model,
          options: const [
            _wtwModelNone,
            'zehnder_comfoConnect',
            'duco_connectivity_board',
            'mv_1contact',
            'mv_scene',
            'mv_0_10v',
            'modbus_universal',
          ],
          optionLabels: const {
            _wtwModelNone: 'Kies type…',
            'zehnder_comfoConnect': 'Zehnder ComfoConnect',
            'duco_connectivity_board': 'Duco Connectivity Board',
            'mv_1contact':
                'Mechanische Ventilatie — 2 standen, 1 contact (aan/uit)',
            'mv_scene':
                'Mechanische Ventilatie — 3 standen, 2 contacten (scene sturing)',
            'mv_0_10v':
                'Mechanische Ventilatie — 4 standen, 0–10V (percentage)',
            'modbus_universal': 'Universeel (Modbus / vrij)',
          },
          onChanged: _setModel,
        ),
        ),
        if (model == 'zehnder_comfoConnect')
          _WtwZehnderInstaller(
            zehnder: _ensureMap(_wtw, 'zehnder'),
            onChanged: _notify,
          )
        else if (model == 'duco_connectivity_board')
          _WtwDucoInstaller(
            duco: _ensureMap(_wtw, 'duco'),
            onChanged: _notify,
          )
        else if (model.startsWith('mv_'))
          _WtwMvInstaller(
            model: model,
            mv: _ensureMap(_wtw, 'mv'),
            onChanged: _notify,
          )
        else if (model == 'modbus_universal')
          _WtwModbusInstaller(
            modbus: _ensureMap(_wtw, 'modbus'),
            onChanged: _notify,
          )
        else
          Text(
            'Kies eerst het type. Velden en functies hangen daarvan af.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _WtwZehnderInstaller extends StatelessWidget {
  const _WtwZehnderInstaller({
    required this.zehnder,
    required this.onChanged,
  });
  final Map<String, dynamic> zehnder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerInfoTitle(
          title: 'Standen',
          body:
              'Elke stand stuurt bit 1. Eigen status-GA bepaalt welke knop actief is. '
              'Stand 1–3, afwezig en boost werken alleen als automatisch uit is; '
              'de app zet Auto uit bij die keuze. Auto zelf is aan/uit.',
        ),
        _WtwBitGaPair(
          label: 'Stand 1',
          writeKey: 'stand1Ga',
          statusKey: 'stand1StatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        _WtwBitGaPair(
          label: 'Stand 2',
          writeKey: 'stand2Ga',
          statusKey: 'stand2StatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        _WtwBitGaPair(
          label: 'Stand 3',
          writeKey: 'stand3Ga',
          statusKey: 'stand3StatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        _WtwBitGaPair(
          label: 'Automatisch',
          writeKey: 'autoGa',
          statusKey: 'autoStatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        _WtwBitGaPair(
          label: 'Afwezig',
          writeKey: 'awayGa',
          statusKey: 'awayStatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        _InstallerInfoTitle(
          title: 'Boost',
          body:
              'Bit 1 schakelt boost in. Twee tijd-objecten: set (schrijven) en '
              'status-set (teruglezen), DPT 7.001 — app in minuten, bus in seconden. '
              'De afteller loopt in de app; bij 0:00 stopt het knipperen. '
              'Tijdens boost kun je een nieuwe duur zetten en opnieuw starten.',
        ),
        _WtwBitGaPair(
          label: 'Boost',
          writeKey: 'boostGa',
          statusKey: 'boostStatusGa',
          map: zehnder,
          onChanged: onChanged,
        ),
        _InstallerStrField(
          label: 'Ingestelde tijd GA (set, DPT 7.001)',
          value: zehnder['boostTimeGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT7.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              zehnder.remove('boostTimeGa');
            } else {
              zehnder['boostTimeGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Status ingestelde tijd GA (DPT 7.001)',
          value: zehnder['boostTimeStatusGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT7.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              zehnder.remove('boostTimeStatusGa');
            } else {
              zehnder['boostTimeStatusGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Standaard minuten',
          value: '${(zehnder['minutes'] as num?)?.round() ?? 30}',
          number: true,
          hint: '1–180',
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n == null) return;
            zehnder['minutes'] = n.clamp(1, 180);
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        _InstallerInfoTitle(
          title: 'Storing en filter',
          body:
              'Storing en filter vervangen zijn 1-bit. Filterdagen is DPT 7.001.',
        ),
        _InstallerStrField(
          label: 'Storing GA (DPT 1.001)',
          value: zehnder['faultGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT1.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              zehnder.remove('faultGa');
            } else {
              zehnder['faultGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Filter vervangen GA (DPT 1.001)',
          value: zehnder['filterGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT1.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              zehnder.remove('filterGa');
            } else {
              zehnder['filterGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Filter vervangen over (dagen, DPT 7.001)',
          value: zehnder['filterDaysGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT7.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              zehnder.remove('filterDaysGa');
            } else {
              zehnder['filterDaysGa'] = v.trim();
            }
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        _WtwLogicListEditor(zehnder: zehnder, onChanged: onChanged),
      ],
    );
  }
}

class _WtwDucoInstaller extends StatelessWidget {
  const _WtwDucoInstaller({
    required this.duco,
    required this.onChanged,
  });
  final Map<String, dynamic> duco;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerInfoTitle(
          title: 'Commando & status',
          body:
              'Eén command-GA (byte 0-255): 0=Auto, 7=Afwezig, 8=Stand 1, '
              '9=Stand 2, 10=Stand 3. Eén status-GA leest de huidige stand terug.',
        ),
        _InstallerStrField(
          label: 'Command GA (byte)',
          value: duco['commandGa'] as String? ?? '',
          gaSearch: true,
          onChanged: (v) {
            if (v.trim().isEmpty) {
              duco.remove('commandGa');
            } else {
              duco['commandGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Status GA (byte)',
          value: duco['statusGa'] as String? ?? '',
          gaSearch: true,
          onChanged: (v) {
            if (v.trim().isEmpty) {
              duco.remove('statusGa');
            } else {
              duco['statusGa'] = v.trim();
            }
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        _InstallerInfoTitle(
          title: 'Storing en filter',
          body: 'Storing en filter vervangen: 1-bit. Filterdagen: DPT 7.001 (2 bytes).',
        ),
        _InstallerStrField(
          label: 'Storing GA (DPT 1.001)',
          value: duco['faultGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT1.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              duco.remove('faultGa');
            } else {
              duco['faultGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Filter vervangen GA (DPT 1.001)',
          value: duco['filterGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT1.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              duco.remove('filterGa');
            } else {
              duco['filterGa'] = v.trim();
            }
            onChanged();
          },
        ),
        _InstallerStrField(
          label: 'Filter vervangen over (dagen, DPT 7.001)',
          value: duco['filterDaysGa'] as String? ?? '',
          gaSearch: true,
          gaDptHint: 'DPT7.001',
          onChanged: (v) {
            if (v.trim().isEmpty) {
              duco.remove('filterDaysGa');
            } else {
              duco['filterDaysGa'] = v.trim();
            }
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        _WtwLogicListEditor(
          zehnder: duco,
          onChanged: onChanged,
          hasBoost: false,
        ),
      ],
    );
  }
}

/* ---------- MV installer widget -------------------------------------- */

class _WtwMvInstaller extends StatefulWidget {
  const _WtwMvInstaller({
    required this.model,
    required this.mv,
    required this.onChanged,
    this.showLogic = true,
  });
  final String model;
  final Map<String, dynamic> mv;
  final VoidCallback onChanged;
  final bool showLogic;

  @override
  State<_WtwMvInstaller> createState() => _WtwMvInstallerState();
}

class _WtwMvInstallerState extends State<_WtwMvInstaller> {
  bool get _is1Contact => widget.model == 'mv_1contact';
  bool get _isScene => widget.model == 'mv_scene';
  bool get _is0_10v => widget.model == 'mv_0_10v';

  List<String> get _standOptions {
    if (_is1Contact) return const ['low', 'high'];
    if (_isScene) return const ['low', 'mid', 'high'];
    if (_is0_10v) {
      final stands = widget.mv['stands'] as List? ?? [];
      return ['low', ...stands.map((s) => (s as Map)['id']?.toString() ?? '')];
    }
    return const ['low', 'high'];
  }

  Map<String, String> get _standLabels {
    if (_is1Contact) return const {'low': 'Laag', 'high': 'Hoog'};
    if (_isScene) return const {'low': 'Laag', 'mid': 'Midden', 'high': 'Hoog'};
    if (_is0_10v) {
      final stands = widget.mv['stands'] as List? ?? [];
      final map = <String, String>{'low': 'Laag (0%)'};
      for (final s in stands) {
        if (s is Map) {
          final id = s['id']?.toString() ?? '';
          final label = s['label']?.toString() ?? id;
          final pct = (s['percent'] as num?)?.round() ?? 0;
          map[id] = '$label ($pct%)';
        }
      }
      return map;
    }
    return const {'low': 'Laag', 'high': 'Hoog'};
  }

  List<String> get _afterOptions => ['previous', ..._standOptions];

  Map<String, String> get _afterLabels => {
        'previous': 'Vorige stand',
        ..._standLabels,
      };

  void _gaField(String key, String label, {String? dpt}) {
    // helper, not used inline — we build them in build() instead
  }

  Widget _gaEditor(String key, String label, {String? dpt}) {
    return _InstallerStrField(
      label: label,
      value: widget.mv[key] as String? ?? '',
      gaSearch: true,
      gaDptHint: dpt,
      onChanged: (v) {
        if (v.trim().isEmpty) {
          widget.mv.remove(key);
        } else {
          widget.mv[key] = v.trim();
        }
        widget.onChanged();
      },
    );
  }

  Widget _intField(String key, String label) {
    return _InstallerStrField(
      label: label,
      value: widget.mv[key]?.toString() ?? '',
      onChanged: (v) {
        final n = int.tryParse(v.trim());
        if (n != null) {
          widget.mv[key] = n;
        } else {
          widget.mv.remove(key);
        }
        widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_is1Contact) ...[
          _InstallerInfoTitle(
            title: '2 standen, 1 contact (aan/uit)',
            body: 'Eén bitcontact: aan = hoog toerental, uit = laag.',
          ),
          _gaEditor('switchGa', 'Schakel GA (DPT 1.001)', dpt: 'DPT1.001'),
          _gaEditor('switchStatusGa', 'Status GA (DPT 1.001)', dpt: 'DPT1.001'),
        ],
        if (_isScene) ...[
          _InstallerInfoTitle(
            title: '3 standen, 2 contacten (scene sturing)',
            body:
                'Twee relaiscontacten via KNX scene:\n'
                '• Beide uit = laag\n'
                '• Contact 1 aan = midden\n'
                '• Contact 2 aan = hoog\n\n'
                'Tip: maak een kleine inschakelvertraging in KNX '
                'zodat er niet kort twee contacten tegelijk aan staan.\n'
                'Configureer één scene-adres met 3 scene-nummers '
                '(een per stand).',
          ),
          _gaEditor('sceneGa', 'Scene GA'),
          _intField('sceneLow', 'Scene-nummer Laag'),
          _intField('sceneMid', 'Scene-nummer Midden'),
          _intField('sceneHigh', 'Scene-nummer Hoog'),
        ],
        if (_is0_10v) ...[
          _InstallerInfoTitle(
            title: '4 standen, 0–10V (percentage)',
            body:
                'Byte-waarde 0–255 op de bus (= 0–100%). '
                'Maak hieronder max. 4 standen aan met een gewenst percentage.',
          ),
          _gaEditor('commandGa', 'Command GA (DPT 5.001)', dpt: 'DPT5.001'),
          _gaEditor('statusGa', 'Status GA (DPT 5.001)', dpt: 'DPT5.001'),
          const SizedBox(height: 8),
          _MvStandsEditor(
            mv: widget.mv,
            onChanged: () {
              widget.onChanged();
              setState(() {});
            },
          ),
        ],
        if (widget.showLogic) ...[
          const SizedBox(height: 12),
          _WtwLogicListEditor(
            zehnder: widget.mv,
            onChanged: widget.onChanged,
            hasBoost: false,
            defaultStandId: _is1Contact ? 'high' : 'high',
            standOptions: _standOptions,
            standLabelsOverride: _standLabels,
            afterOptions: _afterOptions,
            afterLabelsOverride: _afterLabels,
          ),
        ],
      ],
    );
  }
}

/* ---------- Modbus Universal installer -------------------------------- */

const _dptOptions = ['bit', 'byte', 'uint16', 'temperature'];
const _dptLabels = <String, String>{
  'bit': 'Bit (DPT 1.001)',
  'byte': 'Byte (DPT 5.010)',
  'uint16': 'Unsigned 16-bit (DPT 7.001)',
  'temperature': 'Temperatuur (DPT 9.001)',
};

class _WtwModbusInstaller extends StatefulWidget {
  const _WtwModbusInstaller({
    required this.modbus,
    required this.onChanged,
  });
  final Map<String, dynamic> modbus;
  final VoidCallback onChanged;

  @override
  State<_WtwModbusInstaller> createState() => _WtwModbusInstallerState();
}

class _WtwModbusInstallerState extends State<_WtwModbusInstaller> {
  Map<String, dynamic> get mb => widget.modbus;

  List<String> get _standOptions {
    final stands = mb['stands'] as List? ?? [];
    return [
      for (final s in stands)
        if (s is Map) s['id']?.toString() ?? '',
    ];
  }

  Map<String, String> get _standLabels {
    final stands = mb['stands'] as List? ?? [];
    final map = <String, String>{};
    for (final s in stands) {
      if (s is Map) {
        final id = s['id']?.toString() ?? '';
        final label = s['label']?.toString() ?? id;
        final val = s['value']?.toString() ?? '?';
        map[id] = '$label ($val)';
      }
    }
    return map;
  }

  List<String> get _afterOptions => ['previous', ..._standOptions];
  Map<String, String> get _afterLabels => {'previous': 'Vorige stand', ..._standLabels};

  Widget _gaEditor(String key, String label, {String? dpt}) {
    return _InstallerStrField(
      label: label,
      value: mb[key] as String? ?? '',
      gaSearch: true,
      gaDptHint: dpt,
      onChanged: (v) {
        if (v.trim().isEmpty) {
          mb.remove(key);
        } else {
          mb[key] = v.trim();
        }
        widget.onChanged();
      },
    );
  }

  Widget _dptDropdown(String key, String label) {
    final val = mb[key] as String? ?? 'byte';
    return _InstallerDropdown(
      label: label,
      value: _dptOptions.contains(val) ? val : 'byte',
      options: _dptOptions,
      optionLabels: _dptLabels,
      onChanged: (v) {
        mb[key] = v;
        widget.onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerInfoTitle(
          title: 'Commando & status',
          body:
              'Universele Modbus/KNX WTW of ventilatie. '
              'Kies het DPT voor commando en status, '
              'en maak standen aan met de gewenste waarde.',
        ),
        _gaEditor('commandGa', 'Command GA'),
        _dptDropdown('commandDpt', 'Command DPT'),
        _gaEditor('statusGa', 'Status GA'),
        _dptDropdown('statusDpt', 'Status DPT'),
        const SizedBox(height: 12),
        _ModbusStandsEditor(
          modbus: mb,
          onChanged: () {
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _ModbusDiagEditor(
          modbus: mb,
          onChanged: () {
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _WtwLogicListEditor(
          zehnder: mb,
          onChanged: widget.onChanged,
          hasBoost: false,
          defaultStandId: _standOptions.isNotEmpty ? _standOptions.first : '',
          standOptions: _standOptions,
          standLabelsOverride: _standLabels,
          afterOptions: _afterOptions,
          afterLabelsOverride: _afterLabels,
        ),
      ],
    );
  }
}

/* ---------- Modbus stands editor ------------------------------------- */

class _ModbusStandsEditor extends StatelessWidget {
  const _ModbusStandsEditor({required this.modbus, required this.onChanged});
  final Map<String, dynamic> modbus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final stands = _ensureList(modbus, 'stands');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Standen', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                stands.add(<String, dynamic>{
                  'id': 'stand${stands.length + 1}',
                  'label': 'Stand ${stands.length + 1}',
                  'value': stands.length,
                });
                onChanged();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Stand'),
            ),
          ],
        ),
        if (stands.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nog geen standen. Tik + om een stand aan te maken.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < stands.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: LuxeColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _InstallerStrField(
                            label: 'Label',
                            value: stands[i]['label']?.toString() ?? '',
                            onChanged: (v) {
                              stands[i]['label'] = v.trim();
                              final id = v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
                              stands[i]['id'] = id.isEmpty ? 'stand${i + 1}' : id;
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InstallerStrField(
                            label: 'Waarde',
                            value: stands[i]['value']?.toString() ?? '0',
                            onChanged: (v) {
                              final n = num.tryParse(v.trim());
                              if (n != null) {
                                stands[i]['value'] = n;
                                onChanged();
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            stands.removeAt(i);
                            onChanged();
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _InstallerStrField(
                            label: 'GA (optioneel)',
                            value: stands[i]['ga']?.toString() ?? '',
                            gaSearch: true,
                            onChanged: (v) {
                              if (v.trim().isEmpty) {
                                stands[i].remove('ga');
                              } else {
                                stands[i]['ga'] = v.trim();
                              }
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InstallerDropdown(
                            label: 'DPT (optioneel)',
                            value: (stands[i]['dpt'] as String?) ?? '',
                            options: const ['', ..._dptOptions],
                            optionLabels: const {
                              '': 'Standaard',
                              ..._dptLabels,
                            },
                            onChanged: (v) {
                              if (v.isEmpty) {
                                stands[i].remove('dpt');
                              } else {
                                stands[i]['dpt'] = v;
                              }
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 36),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ---------- Modbus diagnostics editor -------------------------------- */

class _ModbusDiagEditor extends StatelessWidget {
  const _ModbusDiagEditor({required this.modbus, required this.onChanged});
  final Map<String, dynamic> modbus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final diags = _ensureList(modbus, 'diagnostics');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerInfoTitle(
          title: 'Diagnostiek',
          body:
              'Storing, foutcode, filter, onderhoud — kies per item een DPT.\n'
              'Bit: aan/uit status. Byte: foutcode (0–255). Uint16: teller/dagen.\n'
              'Optioneel: reset-GA om een teller te resetten (bijv. filter-reset bit).',
          trailing: TextButton.icon(
            onPressed: () {
              diags.add(<String, dynamic>{
                'id': 'diag-${_uuid.v4().substring(0, 8)}',
                'label': '',
                'dpt': 'bit',
              });
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Item'),
          ),
        ),
        if (diags.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nog geen diagnostiek. Tik + om een item toe te voegen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < diags.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: LuxeColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _InstallerStrField(
                            label: 'Label',
                            value: diags[i]['label']?.toString() ?? '',
                            onChanged: (v) {
                              diags[i]['label'] = v.trim();
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InstallerDropdown(
                            label: 'DPT',
                            value: (diags[i]['dpt'] as String?) ?? 'bit',
                            options: _dptOptions,
                            optionLabels: _dptLabels,
                            onChanged: (v) {
                              diags[i]['dpt'] = v;
                              onChanged();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            diags.removeAt(i);
                            onChanged();
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _InstallerStrField(
                            label: 'GA',
                            value: diags[i]['ga']?.toString() ?? '',
                            gaSearch: true,
                            onChanged: (v) {
                              if (v.trim().isEmpty) {
                                diags[i].remove('ga');
                              } else {
                                diags[i]['ga'] = v.trim();
                              }
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InstallerStrField(
                            label: 'Reset GA (optioneel)',
                            value: diags[i]['resetGa']?.toString() ?? '',
                            gaSearch: true,
                            onChanged: (v) {
                              if (v.trim().isEmpty) {
                                diags[i].remove('resetGa');
                              } else {
                                diags[i]['resetGa'] = v.trim();
                              }
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 36),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ---------- MV 0-10V stands editor ----------------------------------- */

class _MvStandsEditor extends StatelessWidget {
  const _MvStandsEditor({required this.mv, required this.onChanged});
  final Map<String, dynamic> mv;
  final VoidCallback onChanged;

  static const _maxStands = 4;

  @override
  Widget build(BuildContext context) {
    final stands = _ensureList(mv, 'stands');
    final canAdd = stands.length < _maxStands;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Standen (max $_maxStands)',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: canAdd
                  ? () {
                      stands.add(<String, dynamic>{
                        'id': 'stand${stands.length + 1}',
                        'label': 'Stand ${stands.length + 1}',
                        'percent': 50,
                      });
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Stand'),
            ),
          ],
        ),
        if (stands.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nog geen standen. Tik + om een stand aan te maken (max $_maxStands).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < stands.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: LuxeColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _InstallerStrField(
                        label: 'Label',
                        value: stands[i]['label']?.toString() ?? '',
                        onChanged: (v) {
                          stands[i]['label'] = v.trim();
                          final id = v
                              .trim()
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]'), '_');
                          stands[i]['id'] =
                              id.isEmpty ? 'stand${i + 1}' : id;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InstallerStrField(
                        label: '%',
                        value: stands[i]['percent']?.toString() ?? '50',
                        onChanged: (v) {
                          final n = int.tryParse(v.trim());
                          if (n != null && n >= 0 && n <= 100) {
                            stands[i]['percent'] = n;
                            onChanged();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        stands.removeAt(i);
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WtwLogicListEditor extends StatelessWidget {
  const _WtwLogicListEditor({
    required this.zehnder,
    required this.onChanged,
    this.hasBoost = true,
    this.defaultStandId = 'stand3',
    this.standOptions,
    this.standLabelsOverride,
    this.afterOptions,
    this.afterLabelsOverride,
  });
  final Map<String, dynamic> zehnder;
  final VoidCallback onChanged;
  final bool hasBoost;
  final String defaultStandId;
  final List<String>? standOptions;
  final Map<String, String>? standLabelsOverride;
  final List<String>? afterOptions;
  final Map<String, String>? afterLabelsOverride;

  @override
  Widget build(BuildContext context) {
    final logics = _ensureList(zehnder, 'logics');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InstallerInfoTitle(
          title: 'Logica',
          body:
              'KNX-status → WTW-stand. Tik op een regel om te bewerken.\n\n'
              'Wanneer: één of meer groepsadressen = waarde (en/of).\n'
              'Dan: welke stand, voor hoe lang of tot een status.\n'
              'Daarna: waar de WTW heen gaat als de logica stopt.',
          trailing: TextButton.icon(
            onPressed: () {
              final newLogic = <String, dynamic>{
                'id': 'wtw-logic-${_uuid.v4()}',
                'enabled': true,
                'label': '',
                'when': <Map<String, dynamic>>[
                  {'ga': '', 'value': '1', 'minutes': 0},
                ],
                'whenJoin': 'or',
                'standId': defaultStandId,
                'end': 'duration',
                'minutes': 15,
                'untilWhen': <Map<String, dynamic>>[
                  {'ga': '', 'value': '0', 'minutes': 5},
                ],
                'untilJoin': 'or',
                'after': 'previous',
              };
              logics.add(newLogic);
              onChanged();
              _openLogicSheet(context, newLogic, isNew: true);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Logica'),
          ),
        ),
        if (logics.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nog geen logica. Tik + om een regel toe te voegen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < logics.length; i++)
          _WtwLogicSummaryCard(
            key: ValueKey(logics[i]['id'] ?? 'l$i'),
            logic: logics[i],
            onTap: () => _openLogicSheet(context, logics[i]),
            onToggle: (v) {
              logics[i]['enabled'] = v;
              onChanged();
            },
            onDelete: () {
              logics.removeAt(i);
              onChanged();
            },
          ),
      ],
    );
  }

  void _openLogicSheet(
    BuildContext context,
    Map<String, dynamic> logic, {
    bool isNew = false,
  }) {
    showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WtwLogicEditorSheet(
        logic: logic,
        isNew: isNew,
        hasBoost: hasBoost,
        standOptions: standOptions,
        standLabelsOverride: standLabelsOverride,
        afterOptions: afterOptions,
        afterLabelsOverride: afterLabelsOverride,
      ),
    ).then((saved) {
      if (saved == true) onChanged();
    });
  }
}

/* ---------- compact summary card for each logic ---------------------- */

class _WtwLogicSummaryCard extends StatelessWidget {
  const _WtwLogicSummaryCard({
    super.key,
    required this.logic,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });
  final Map<String, dynamic> logic;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  static const _standLabels = {
    'stand1': 'Stand 1',
    'stand2': 'Stand 2',
    'stand3': 'Stand 3',
    'away': 'Afwezig',
    'boost': 'Boost',
    'low': 'Laag',
    'mid': 'Midden',
    'high': 'Hoog',
  };

  String _whenSummary() {
    final mode = logic['triggerMode'] as String? ?? 'status';
    if (mode == 'tempRise') {
      final tr = logic['tempRise'] as Map? ?? {};
      final delta = (tr['deltaDeg'] as num?)?.toStringAsFixed(1) ?? '?';
      return 'Temp +${delta}°C';
    }
    _migrateWhen(logic);
    final clauses = logic['when'] as List? ?? [];
    if (clauses.isEmpty) return 'Geen trigger';
    final join = logic['whenJoin'] == 'and' ? ' EN ' : ' OF ';
    final parts = <String>[];
    for (final c in clauses) {
      if (c is! Map) continue;
      final ga = (c['ga'] as String? ?? '').trim();
      final val = (c['value'] ?? '1').toString();
      final min = (c['minutes'] as num?)?.round() ?? 0;
      if (ga.isEmpty) {
        parts.add('(geen GA)');
      } else {
        parts.add('$ga=$val${min > 0 ? ' ${min}m' : ''}');
      }
    }
    return parts.join(join);
  }

  String _actionSummary() {
    final standId = logic['standId'] as String? ?? 'stand3';
    final stand = _standLabels[standId] ?? standId;
    final end = logic['end'] as String? ?? 'duration';
    if (end == 'untilStatus') return '$stand tot status';
    final min = (logic['minutes'] as num?)?.round() ?? 15;
    return '$stand voor ${min}m';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = logic['enabled'] != false;
    final label = (logic['label'] as String? ?? '').trim();
    final name = label.isEmpty ? 'Naamloze logica' : label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Material(
          color: LuxeColors.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LuxeColors.lineSoft),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _whenSummary(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _actionSummary(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: LuxeColors.brassDeep,
                              ),
                        ),
                      ],
                    ),
                  ),
                  LuxeOnOffSwitch(
                    value: enabled,
                    onChanged: onToggle,
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: LuxeColors.inkSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- full-screen bottom sheet editor (like schedules) ---------- */

enum _WtwLogicPane { overview, name, when, action, after }

class _WtwLogicEditorSheet extends StatefulWidget {
  const _WtwLogicEditorSheet({
    required this.logic,
    this.isNew = false,
    this.hasBoost = true,
    this.standOptions,
    this.standLabelsOverride,
    this.afterOptions,
    this.afterLabelsOverride,
  });
  final Map<String, dynamic> logic;
  final bool isNew;
  final bool hasBoost;
  final List<String>? standOptions;
  final Map<String, String>? standLabelsOverride;
  final List<String>? afterOptions;
  final Map<String, String>? afterLabelsOverride;

  @override
  State<_WtwLogicEditorSheet> createState() => _WtwLogicEditorSheetState();
}

class _WtwLogicEditorSheetState extends State<_WtwLogicEditorSheet> {
  late Map<String, dynamic> _draft;
  _WtwLogicPane _pane = _WtwLogicPane.overview;

  static const _standLabels = {
    'stand1': 'Stand 1',
    'stand2': 'Stand 2',
    'stand3': 'Stand 3',
    'away': 'Afwezig',
    'boost': 'Boost',
  };
  static const _afterLabels = {
    'previous': 'Vorige stand',
    'auto': 'Automatisch',
    'stand1': 'Stand 1',
    'stand2': 'Stand 2',
    'stand3': 'Stand 3',
    'away': 'Afwezig',
  };

  static const _createSteps = [
    _WtwLogicPane.name,
    _WtwLogicPane.when,
    _WtwLogicPane.action,
    _WtwLogicPane.after,
  ];

  @override
  void initState() {
    super.initState();
    _migrateWhen(widget.logic);
    _migrateUntil(widget.logic);
    _draft = _deepCopyMap(widget.logic);
    if (widget.isNew) _pane = _WtwLogicPane.name;
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      if (e.value is Map<String, dynamic>) {
        out[e.key] = _deepCopyMap(e.value as Map<String, dynamic>);
      } else if (e.value is List) {
        out[e.key] = _deepCopyList(e.value as List);
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static List _deepCopyList(List src) {
    return [
      for (final item in src)
        if (item is Map<String, dynamic>)
          _deepCopyMap(item)
        else if (item is List)
          _deepCopyList(item)
        else
          item,
    ];
  }

  void _set(String key, Object? value) {
    setState(() {
      if (value == null || (value is String && value.trim().isEmpty)) {
        _draft.remove(key);
      } else {
        _draft[key] = value;
      }
    });
  }

  void _save() {
    widget.logic.clear();
    widget.logic.addAll(_draft);
    Navigator.of(context).pop(true);
  }

  void _delete() {
    Navigator.of(context).pop(true);
    // Caller checks if logic is still in the list — we signal "changed".
  }

  bool get _isCreate => widget.isNew;
  bool get _atRoot =>
      (!_isCreate && _pane == _WtwLogicPane.overview) ||
      (_isCreate && _pane == _WtwLogicPane.name);

  String? _paneError(_WtwLogicPane pane) {
    switch (pane) {
      case _WtwLogicPane.overview:
        return null;
      case _WtwLogicPane.name:
        final n = (_draft['label'] as String? ?? '').trim();
        return n.isEmpty ? 'Vul een naam in.' : null;
      case _WtwLogicPane.when:
        final mode = _draft['triggerMode'] as String? ?? 'status';
        if (mode == 'tempRise') {
          final tr = _draft['tempRise'] as Map<String, dynamic>?;
          if (tr == null || ((tr['ga'] as String?) ?? '').trim().isEmpty) {
            return 'Vul het temperatuur-groepsadres in.';
          }
          return null;
        }
        final clauses = _draft['when'] as List? ?? [];
        if (clauses.isEmpty) return 'Voeg minstens één trigger toe.';
        for (final c in clauses) {
          if (c is Map && ((c['ga'] as String?) ?? '').trim().isEmpty) {
            return 'Vul alle groepsadressen in.';
          }
        }
        return null;
      case _WtwLogicPane.action:
        return null;
      case _WtwLogicPane.after:
        return null;
    }
  }

  void _openPane(_WtwLogicPane pane) => setState(() => _pane = pane);

  void _back() {
    if (_isCreate) {
      final i = _createSteps.indexOf(_pane);
      if (i <= 0) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _pane = _createSteps[i - 1]);
      return;
    }
    setState(() => _pane = _WtwLogicPane.overview);
  }

  void _next() {
    final err = _paneError(_pane);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LuxeColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          content: Text(err),
        ),
      );
      return;
    }
    if (_isCreate) {
      final i = _createSteps.indexOf(_pane);
      if (i >= _createSteps.length - 1) {
        _save();
        return;
      }
      setState(() => _pane = _createSteps[i + 1]);
      return;
    }
    setState(() => _pane = _WtwLogicPane.overview);
  }

  /* ---- summaries for overview rows ---- */

  String _nameSummary() {
    final n = (_draft['label'] as String? ?? '').trim();
    return n.isEmpty ? 'Geen naam' : n;
  }

  String _whenSummary() {
    final mode = _draft['triggerMode'] as String? ?? 'status';
    if (mode == 'tempRise') {
      final tr = _draft['tempRise'] as Map<String, dynamic>? ?? {};
      final ga = (tr['ga'] as String? ?? '').trim();
      final delta = (tr['deltaDeg'] as num?)?.toStringAsFixed(1) ?? '?';
      final window = (tr['windowSec'] as num?)?.round() ?? '?';
      if (ga.isEmpty) return 'Temp. stijging (geen GA)';
      return '$ga  +${delta}°C  in ${window}s';
    }
    final clauses = _draft['when'] as List? ?? [];
    if (clauses.isEmpty) return 'Geen trigger';
    final join = _draft['whenJoin'] == 'and' ? ' EN ' : ' OF ';
    final parts = <String>[];
    for (final c in clauses) {
      if (c is! Map) continue;
      final ga = (c['ga'] as String? ?? '').trim();
      final val = (c['value'] ?? '1').toString();
      final min = (c['minutes'] as num?)?.round() ?? 0;
      if (ga.isEmpty) {
        parts.add('(geen GA)');
      } else {
        parts.add('$ga = $val${min > 0 ? ' (${min}m)' : ''}');
      }
    }
    if (parts.length > 2) return '${parts.length} triggers (${join.trim().toLowerCase()})';
    return parts.join(join);
  }

  String _actionSummary() {
    final standId = _draft['standId'] as String? ?? 'stand3';
    final stand = _standLabels[standId] ?? standId;
    final end = _draft['end'] as String? ?? 'duration';
    if (end == 'untilStatus') {
      final until = _draft['untilWhen'] as List? ?? [];
      final n = until.length;
      return '$stand tot ${n == 1 ? 'status' : '$n statussen'}';
    }
    final min = (_draft['minutes'] as num?)?.round() ?? 15;
    return '$stand voor $min min';
  }

  String _afterSummary() {
    final after = _draft['after'] as String? ?? 'previous';
    return _afterLabels[after] ?? after;
  }

  /* ---- build ---- */

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, scrollCtl) => Container(
          decoration: BoxDecoration(
            color: LuxeColors.cream,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: LuxeShadows.lift,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildHeader(ctx),
                Expanded(child: _buildBody(scrollCtl)),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final name = (_draft['label'] as String? ?? '').trim();
    final (title, infoTitle, infoBody) = switch (_pane) {
      _WtwLogicPane.overview => (
          name.isEmpty ? 'Logica' : name,
          'Logica',
          'Naam, trigger, actie en terugkeerstand. '
              'Tik op een rij om die sectie te bewerken.',
        ),
      _WtwLogicPane.name => (
          'Naam',
          'Naam',
          'Hoe deze logica in de lijst heet.',
        ),
      _WtwLogicPane.when => (
          'Wanneer',
          'Wanneer',
          'Eén of meer groepsadres-condities (AND/OR).\n\n'
              '• Groepsadres: het KNX-adres dat gecontroleerd wordt.\n'
              '• Waarde: volgens het DPT van dat adres (1, 0, getal, …).\n'
              '• Minuten: hoe lang de waarde waar moet zijn. 0 = direct.',
        ),
      _WtwLogicPane.action => (
          'Dan',
          'Dan',
          'Welke WTW-stand wordt geactiveerd en hoe lang.\n\n'
              '• Stand: de ventilatie-stand die wordt ingesteld.\n'
              '• Einde: voor x minuten, of tot een groepsadres-status.\n'
              '• Boost: schrijft de duur als boost-tijd op het toestel.',
        ),
      _WtwLogicPane.after => (
          'Daarna',
          'Daarna',
          'Waar de WTW heen gaat als de logica stopt.\n\n'
              '• Vorige stand: terug naar wat er vóór de logica was.\n'
              '• Automatisch: schakelt terug naar auto-modus.',
        ),
    };
    return Padding(
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
              alignment: Alignment.centerRight,
              child: LuxeInfoIconButton(title: infoTitle, body: infoBody),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: BackPill(
                onTap: () {
                  if (_atRoot) {
                    Navigator.of(context).pop(false);
                    return;
                  }
                  _back();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollCtl) {
    return switch (_pane) {
      _WtwLogicPane.overview => _overviewPane(scrollCtl),
      _WtwLogicPane.name => _namePane(scrollCtl),
      _WtwLogicPane.when => _whenPane(scrollCtl),
      _WtwLogicPane.action => _actionPane(scrollCtl),
      _WtwLogicPane.after => _afterPane(scrollCtl),
    };
  }

  /* ---- overview ---- */

  Widget _overviewPane(ScrollController ctl) {
    return ListView(
      controller: ctl,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      children: [
        GlassCard(
          radius: 16,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _LogicSettingRow(
                title: 'Naam',
                subtitle: _nameSummary(),
                done: _paneError(_WtwLogicPane.name) == null,
                onTap: () => _openPane(_WtwLogicPane.name),
              ),
              Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              _LogicSettingRow(
                title: 'Wanneer',
                subtitle: _whenSummary(),
                done: _paneError(_WtwLogicPane.when) == null,
                onTap: () => _openPane(_WtwLogicPane.when),
              ),
              Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              _LogicSettingRow(
                title: 'Dan',
                subtitle: _actionSummary(),
                done: true,
                onTap: () => _openPane(_WtwLogicPane.action),
              ),
              Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              _LogicSettingRow(
                title: 'Daarna',
                subtitle: _afterSummary(),
                done: true,
                onTap: () => _openPane(_WtwLogicPane.after),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          icon: Icon(Icons.delete_outline, size: 18, color: LuxeColors.danger),
          label:
              Text('Logica verwijderen', style: TextStyle(color: LuxeColors.danger)),
          onPressed: _delete,
        ),
      ],
    );
  }

  /* ---- name pane ---- */

  Widget _namePane(ScrollController ctl) {
    return ListView(
      controller: ctl,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        _InstallerStrField(
          label: 'Naam',
          value: _draft['label'] as String? ?? '',
          onChanged: (v) => _set('label', v.trim().isEmpty ? null : v.trim()),
        ),
      ],
    );
  }

  /* ---- when pane ---- */

  Widget _whenPane(ScrollController ctl) {
    final mode = _draft['triggerMode'] as String? ?? 'status';
    return ListView(
      controller: ctl,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(
                value: 'status',
                icon: Icon(Icons.sensors_rounded, size: 16),
                label: Text('Status'),
              ),
              ButtonSegment(
                value: 'tempRise',
                icon: Icon(Icons.thermostat_rounded, size: 16),
                label: Text('Temp. stijging'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                setState(() => _draft['triggerMode'] = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (mode == 'tempRise') _tempRiseEditor() else _statusClausesEditor(),
      ],
    );
  }

  Widget _statusClausesEditor() {
    final clauses = _ensureList(_draft, 'when');
    if (clauses.isEmpty) {
      clauses.add({'ga': '', 'value': '1', 'minutes': 0});
    }
    final join = _draft['whenJoin'] == 'and' ? 'and' : 'or';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WtwLogicSelect(
          value: join,
          options: const ['or', 'and'],
          labels: const {
            'or': 'OF (één van de statussen)',
            'and': 'EN (alle statussen)',
          },
          onChanged: (v) => setState(() => _draft['whenJoin'] = v),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < clauses.length; i++) ...[
          if (i > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: LuxeColors.brass.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    join == 'and' ? 'EN' : 'OF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: LuxeColors.brassDeep,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
          _WtwClauseCard(
            clause: clauses[i],
            index: i,
            defaultTrue: true,
            defaultMinutes: 0,
            minMinutes: 0,
            canDelete: clauses.length > 1,
            onChanged: () => setState(() {}),
            onDelete: () => setState(() => clauses.removeAt(i)),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            clauses.add({'ga': '', 'value': '1', 'minutes': 0});
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Status toevoegen'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }

  Widget _tempRiseEditor() {
    final tr = _draft.putIfAbsent(
      'tempRise',
      () => <String, dynamic>{
        'ga': '',
        'deltaDeg': 3.0,
        'windowSec': 20,
      },
    ) as Map<String, dynamic>;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Trigger wanneer de temperatuur met minstens X °C stijgt '
            'binnen Y seconden. Geschikt voor een sensor op een '
            'waterleiding (douche, warm water, …).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          _InstallerStrField(
            label: 'Temperatuur-GA (DPT 9.001)',
            value: tr['ga'] as String? ?? '',
            gaSearch: true,
            onChanged: (v) {
              tr['ga'] = v.trim();
              setState(() {});
            },
          ),
          _InstallerStrField(
            label: 'Stijging (°C)',
            hint: 'bijv. 3 — trigger bij +3 °C',
            value: '${(tr['deltaDeg'] as num?) ?? 3.0}',
            number: true,
            onChanged: (v) {
              final n = double.tryParse(v.replaceAll(',', '.'));
              if (n == null) return;
              tr['deltaDeg'] = double.parse(n.clamp(0.5, 50).toStringAsFixed(1));
              setState(() {});
            },
          ),
          _InstallerStrField(
            label: 'Binnen (seconden)',
            hint: 'bijv. 20 — temperatuur moet binnen 20s stijgen',
            value: '${(tr['windowSec'] as num?)?.round() ?? 20}',
            number: true,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n == null) return;
              tr['windowSec'] = n.clamp(5, 600);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  /* ---- action pane ---- */

  Widget _actionPane(ScrollController ctl) {
    final standId = _draft['standId'] as String? ?? 'stand3';
    final end = _draft['end'] as String? ?? 'duration';
    return ListView(
      controller: ctl,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      children: [
        _WtwLogicLabeled(
          label: 'stand',
          child: _WtwLogicSelect(
            value: standId,
            options: widget.standOptions ??
                (widget.hasBoost
                    ? const ['stand1', 'stand2', 'stand3', 'away', 'boost']
                    : const ['stand1', 'stand2', 'stand3', 'away']),
            labels: widget.standLabelsOverride ?? _standLabels,
            onChanged: (v) => _set('standId', v),
          ),
        ),
        const SizedBox(height: 4),
        _WtwLogicLabeled(
          label: 'einde',
          child: _WtwLogicSelect(
            value: end == 'untilStatus' ? 'untilStatus' : 'duration',
            options: const ['duration', 'untilStatus'],
            labels: const {
              'duration': 'Voor x minuten',
              'untilStatus': 'Tot groepsadres = waarde',
            },
            onChanged: (v) => _set('end', v),
          ),
        ),
        const SizedBox(height: 4),
        if (end != 'untilStatus')
          _InstallerStrField(
            label: standId == 'boost'
                ? 'boost-tijd / voor (min)'
                : 'voor (min)',
            value:
                '${(_draft['minutes'] as num?)?.round() ?? 15}',
            number: true,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n == null) return;
              _set('minutes', n.clamp(1, 1440));
            },
          )
        else ...[
          _buildUntilClauses(),
        ],
        if (standId == 'boost')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              end == 'untilStatus'
                  ? 'Boost schrijft boost-tijd op het toestel (180 min) tot de eindstatus; daarna de tegel-tijd terug.'
                  : 'Boost schrijft deze minuten als boost-tijd op het toestel. De tegel-tijd blijft en gaat na afloop terug.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildUntilClauses() {
    final clauses = _ensureList(_draft, 'untilWhen');
    if (clauses.isEmpty) {
      clauses.add({'ga': '', 'value': '0', 'minutes': 5});
    }
    final join = _draft['untilJoin'] == 'and' ? 'and' : 'or';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TOT', style: TextStyle(
          fontSize: 11,
          letterSpacing: 2.0,
          fontWeight: FontWeight.w700,
          color: LuxeColors.inkSoft,
        )),
        const SizedBox(height: 8),
        _WtwLogicSelect(
          value: join,
          options: const ['or', 'and'],
          labels: const {
            'or': 'OF (één van de statussen)',
            'and': 'EN (alle statussen)',
          },
          onChanged: (v) => setState(() => _draft['untilJoin'] = v),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < clauses.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: LuxeColors.brass.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    join == 'and' ? 'EN' : 'OF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: LuxeColors.brassDeep,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          _WtwClauseCard(
            clause: clauses[i],
            index: i,
            defaultTrue: false,
            defaultMinutes: 5,
            minMinutes: 1,
            canDelete: clauses.length > 1,
            onChanged: () => setState(() {}),
            onDelete: () => setState(() => clauses.removeAt(i)),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            clauses.add({'ga': '', 'value': '0', 'minutes': 5});
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Status toevoegen'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }

  /* ---- after pane ---- */

  Widget _afterPane(ScrollController ctl) {
    final after = _draft['after'] as String? ?? 'previous';
    return ListView(
      controller: ctl,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        Text(
          'Waar gaat de WTW heen als de logica stopt?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        _WtwLogicSelect(
          value: (widget.afterLabelsOverride ?? _afterLabels).containsKey(after) ? after : 'previous',
          options: widget.afterOptions ?? const [
            'previous',
            'auto',
            'stand1',
            'stand2',
            'stand3',
            'away',
          ],
          labels: widget.afterLabelsOverride ?? _afterLabels,
          onChanged: (v) => _set('after', v),
        ),
      ],
    );
  }

  /* ---- footer ---- */

  Widget _buildFooter() {
    if (_isCreate) {
      final last = _pane == _createSteps.last;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _back,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Terug'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  foregroundColor: LuxeColors.onInk,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: Text(last ? 'Opslaan' : 'Volgende'),
              ),
            ),
          ],
        ),
      );
    }
    if (_pane != _WtwLogicPane.overview) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _back,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Terug'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  foregroundColor: LuxeColors.onInk,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
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
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: const Text('Opslaan'),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------- setting row (matches schedule overview) ------------------- */

class _LogicSettingRow extends StatelessWidget {
  const _LogicSettingRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.done = false,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_rounded,
                    size: 18, color: LuxeColors.brassDeep),
              ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: LuxeColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/* ---------- single clause card (GA + value + minutes) ----------------- */

class _WtwClauseCard extends StatelessWidget {
  const _WtwClauseCard({
    required this.clause,
    required this.index,
    required this.defaultTrue,
    required this.defaultMinutes,
    required this.minMinutes,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> clause;
  final int index;
  final bool defaultTrue;
  final int defaultMinutes;
  final int minMinutes;
  final bool canDelete;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  String _valueOf() {
    final raw = clause['value'];
    if (raw != null && '$raw'.trim().isNotEmpty) return '$raw'.trim();
    final eq = clause['equals'];
    if (eq == false) return '0';
    if (eq == true) return '1';
    return defaultTrue ? '1' : '0';
  }

  void _setValue(String raw) {
    final v = raw.trim();
    if (v.isEmpty) {
      clause.remove('value');
    } else {
      clause['value'] = v;
    }
    if (v == '1' || v.toLowerCase() == 'true') {
      clause['equals'] = true;
    } else if (v == '0' || v.toLowerCase() == 'false') {
      clause['equals'] = false;
    } else {
      clause.remove('equals');
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status ${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                    color: LuxeColors.inkSoft,
                  ),
                ),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  tooltip: 'Verwijderen',
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 4),
          _InstallerStrField(
            label: 'Groepsadres',
            value: clause['ga'] as String? ?? '',
            gaSearch: true,
            onChanged: (v) {
              clause['ga'] = v.trim();
              onChanged();
            },
          ),
          _InstallerStrField(
            label: 'Waarde',
            hint: 'volgens DPT (1, 0, getal, …)',
            value: _valueOf(),
            onChanged: _setValue,
          ),
          _InstallerStrField(
            label: 'Minuten',
            hint: '0 = direct',
            value:
                '${(clause['minutes'] as num?)?.round() ?? defaultMinutes}',
            number: true,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n == null) return;
              clause['minutes'] = n.clamp(minMinutes, 1440);
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

/* ---------- shared helpers (migration, labels, select) ---------------- */

Map<String, dynamic> _clause({
  required String ga,
  required String value,
  required int minutes,
}) =>
    {'ga': ga, 'value': value, 'minutes': minutes};

void _migrateWhen(Map<String, dynamic> logic) {
  final raw = logic['when'];
  if (raw is List && raw.isNotEmpty) return;
  final first = _clause(
    ga: (logic['triggerGa'] as String?) ?? '',
    value: () {
      final v = logic['triggerValue'];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
      return logic['triggerEquals'] == false ? '0' : '1';
    }(),
    minutes: (logic['triggerMinutes'] as num?)?.round() ?? 0,
  );
  final when = <Map<String, dynamic>>[first];
  final orGa = (logic['orGa'] as String?)?.trim() ?? '';
  if (orGa.isNotEmpty) {
    when.add(
      _clause(
        ga: orGa,
        value: () {
          final v = logic['orValue'];
          if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
          return logic['orEquals'] == false ? '0' : '1';
        }(),
        minutes: (logic['orMinutes'] as num?)?.round() ?? 0,
      ),
    );
    logic['whenJoin'] ??= 'or';
  }
  logic['when'] = when;
}

void _migrateUntil(Map<String, dynamic> logic) {
  final raw = logic['untilWhen'];
  if (raw is List && raw.isNotEmpty) return;
  final ga = (logic['untilGa'] as String?) ?? '';
  logic['untilWhen'] = [
    _clause(
      ga: ga,
      value: () {
        final v = logic['untilValue'];
        if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
        return logic['untilEquals'] == true ? '1' : '0';
      }(),
      minutes: (logic['untilMinutes'] as num?)?.round() ??
          (logic['minutes'] as num?)?.round() ??
          5,
    ),
  ];
}

class _WtwLogicLabeled extends StatelessWidget {
  const _WtwLogicLabeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeFieldLabel(label),
          child,
        ],
      ),
    );
  }
}

class _WtwLogicSelect extends StatelessWidget {
  const _WtwLogicSelect({
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });
  final String value;
  final List<String> options;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('$v-${labels[v]}'),
      initialValue: v,
      isDense: false,
      isExpanded: true,
      decoration: luxeFilledDecoration().copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(labels[o] ?? o),
          ),
      ],
      onChanged: (x) {
        if (x != null) onChanged(x);
      },
    );
  }
}

class _WtwBitGaPair extends StatelessWidget {
  const _WtwBitGaPair({
    required this.label,
    required this.writeKey,
    required this.statusKey,
    required this.map,
    required this.onChanged,
  });
  final String label;
  final String writeKey;
  final String statusKey;
  final Map<String, dynamic> map;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InstallerStrField(
                  label: 'Commando-GA (DPT 1.001)',
                  value: map[writeKey] as String? ?? '',
                  gaSearch: true,
                  gaDptHint: 'DPT1.001',
                  onChanged: (v) {
                    if (v.trim().isEmpty) {
                      map.remove(writeKey);
                    } else {
                      map[writeKey] = v.trim();
                    }
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InstallerStrField(
                  label: 'Status-GA',
                  value: map[statusKey] as String? ?? '',
                  gaSearch: true,
                  gaDptHint: 'DPT1.001',
                  onChanged: (v) {
                    if (v.trim().isEmpty) {
                      map.remove(statusKey);
                    } else {
                      map[statusKey] = v.trim();
                    }
                    onChanged();
                  },
                ),
              ),
            ],
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
          if (compact && label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
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

/// Groepsadres en urgentie — kort, zelfde kolombreedte.
const double _kMeldingNarrowCol = 140;

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
              'Bij 1-bit is actief = 1. Bij andere DPT’s: gelijk, hoger dan of lager dan een waarde. '
              'Reset (optioneel): 0 op hetzelfde groepsadres, of 1 op een eigen reset-adres. '
              'Zet in ETS cyclisch zenden op het meldingsadres, anders blijft een cruciale storing na reset weg zolang de oorzaak bestaat. '
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
            (label: 'Onderwerp', flex: 3, width: null),
            (label: 'Groepsadres', flex: 0, width: _kMeldingNarrowCol),
            (label: 'DPT', flex: 2, width: null),
            (label: 'Urgentie', flex: 0, width: _kMeldingNarrowCol),
            (label: 'Actief bij', flex: 2, width: null),
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

  void _setAll(Map<String, dynamic> patch) {
    final updated = Map<String, dynamic>.from(item);
    for (final e in patch.entries) {
      if (e.value == null) {
        updated.remove(e.key);
      } else {
        updated[e.key] = e.value;
      }
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final urgency = item['urgency'] as String? ?? 'minder_belangrijk';
    final dpt = item['dpt'] as String? ?? '1.001';
    final is1bit = dpt.startsWith('1.');
    final resetMode = const {'same_ga', 'reset_ga'}.contains(item['resetMode'])
        ? item['resetMode'] as String
        : 'none';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
        children: [
          Expanded(
            flex: 3,
            child: _StrField(
              label: 'Onderwerp',
              value: item['label'] as String? ?? '',
              compact: true,
              onChanged: (v) => _set('label', v.isEmpty ? 'Melding' : v),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: _kMeldingNarrowCol,
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
          SizedBox(
            width: _kMeldingNarrowCol,
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
            flex: 2,
            child: is1bit
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: DropdownButtonFormField<String>(
                          initialValue: const {'eq', 'gt', 'lt', 'gte', 'lte'}
                                  .contains(item['activeCompare'])
                              ? item['activeCompare'] as String
                              : 'eq',
                          isExpanded: true,
                          decoration: luxeFilledDecoration().copyWith(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'eq', child: Text('=')),
                            DropdownMenuItem(value: 'gt', child: Text('>')),
                            DropdownMenuItem(value: 'lt', child: Text('<')),
                            DropdownMenuItem(value: 'gte', child: Text('≥')),
                            DropdownMenuItem(value: 'lte', child: Text('≤')),
                          ],
                          onChanged: (v) => _set(
                            'activeCompare',
                            v == null || v == 'eq' ? null : v,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _StrField(
                          label: 'Actief bij',
                          value: item['activeValue']?.toString() ?? '',
                          compact: true,
                          onChanged: (v) {
                            final n =
                                double.tryParse(v.replaceAll(',', '.'));
                            _set('activeValue', n);
                          },
                        ),
                      ),
                    ],
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
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('reset-$resetMode'),
                  initialValue: resetMode,
                  isExpanded: true,
                  decoration: luxeFilledDecoration().copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Geen reset')),
                    DropdownMenuItem(
                      value: 'same_ga',
                      child: Text('Reset: 0 op zelfde GA'),
                    ),
                    DropdownMenuItem(
                      value: 'reset_ga',
                      child: Text('Reset: 1 op eigen GA'),
                    ),
                  ],
                  onChanged: (v) {
                    switch (v) {
                      case 'same_ga':
                        _setAll({'resetMode': 'same_ga', 'resetGa': null});
                      case 'reset_ga':
                        _set('resetMode', 'reset_ga');
                      default:
                        _setAll({'resetMode': null, 'resetGa': null});
                    }
                  },
                ),
              ),
              if (resetMode == 'reset_ga') ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: _kMeldingNarrowCol,
                  child: _StrField(
                    label: 'Reset-GA',
                    value: item['resetGa'] as String? ?? '',
                    compact: true,
                    gaSearch: true,
                    gaDptHint: 'DPT1.001',
                    onChanged: (v) =>
                        _set('resetGa', v.trim().isEmpty ? null : v.trim()),
                  ),
                ),
              ],
            ],
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
              'Zakt niet onder 1%, zodat er altijd geluid blijft; mute is apart. '
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
