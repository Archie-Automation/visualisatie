import 'package:flutter/material.dart';

import '../knx_alarm.dart';
import '../theme.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/luxe_form.dart';

/// Installateur: KNX-sensoren voor alarm aanwezig en afwezig.
class KnxAlarmInstaller extends StatefulWidget {
  const KnxAlarmInstaller({
    super.key,
    required this.house,
    required this.onChanged,
  });

  final Map<String, dynamic> house;
  final VoidCallback onChanged;

  @override
  State<KnxAlarmInstaller> createState() => _KnxAlarmInstallerState();
}

class _KnxAlarmInstallerState extends State<KnxAlarmInstaller> {
  late Map<String, dynamic> _alarm;
  late final TextEditingController _exit;
  late final TextEditingController _entry;
  late final TextEditingController _siren;
  String? _openId;

  @override
  void initState() {
    super.initState();
    final raw = widget.house['knxAlarm'];
    _alarm = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    widget.house['knxAlarm'] = _alarm;
    _alarm['sensors'] ??= <dynamic>[];
    _exit = TextEditingController(text: '${_num(_alarm['exitSeconds'], 30)}');
    _entry = TextEditingController(text: '${_num(_alarm['entrySeconds'], 30)}');
    _siren = TextEditingController(text: '${_alarm['sirenGa'] ?? ''}');
  }

  @override
  void dispose() {
    _exit.dispose();
    _entry.dispose();
    _siren.dispose();
    super.dispose();
  }

  int _num(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  List<Map<String, dynamic>> get _sensors {
    final raw = _alarm['sensors'];
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is Map<String, dynamic>)
          e
        else if (e is Map)
          Map<String, dynamic>.from(e),
    ];
  }

  void _commit() {
    final exit = int.tryParse(_exit.text.trim());
    final entry = int.tryParse(_entry.text.trim());
    if (exit != null) _alarm['exitSeconds'] = exit.clamp(0, 600);
    if (entry != null) _alarm['entrySeconds'] = entry.clamp(0, 600);
    final siren = _siren.text.trim();
    if (siren.isEmpty) {
      _alarm.remove('sirenGa');
    } else {
      _alarm['sirenGa'] = siren;
    }
    widget.house['knxAlarm'] = _alarm;
    widget.onChanged();
  }

  void _setSensors(List<Map<String, dynamic>> next) {
    _alarm['sensors'] = next;
    _commit();
    setState(() {});
  }

  Map<String, dynamic>? _open(List<Map<String, dynamic>> sensors) {
    final id = _openId;
    if (id == null) return null;
    for (final sensor in sensors) {
      if (sensor['id'] == id) return sensor;
    }
    return null;
  }

  String _subtitle(Map<String, dynamic> sensor) {
    final kind = knxAlarmSensorKindLabel('${sensor['kind']}');
    final ga = '${sensor['ga'] ?? ''}'.trim();
    final modes = <String>[
      if (sensor['aanwezig'] == true) 'Aanwezig',
      if (sensor['afwezig'] == true) 'Afwezig',
      if (sensor['inloop'] == true) 'Inloop',
    ];
    return [
      kind,
      if (ga.isNotEmpty) ga else 'Geen groepadres',
      if (modes.isNotEmpty) modes.join(', '),
    ].join(' · ');
  }

  void _addSensor() {
    final next = [..._sensors];
    final id = 's${DateTime.now().microsecondsSinceEpoch}';
    next.add({
      'id': id,
      'name': 'Sensor ${next.length + 1}',
      'ga': '',
      'kind': 'magneetcontact',
      'aanwezig': false,
      'afwezig': true,
      'inloop': false,
      'alarmOn': '1',
    });
    _openId = id;
    _setSensors(next);
  }

  @override
  Widget build(BuildContext context) {
    final sensors = _sensors;
    final open = _open(sensors);
    final legacyPin = _alarm['pinSet'] == true && _alarm['clearPin'] != true;
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        LuxeListCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LuxeSectionTitle(
                icon: Icons.security_outlined,
                title: 'KNX-alarm',
                trailing: LuxeInfoIconButton(
                  title: 'KNX-alarm',
                  body:
                      'Eén alarm in huis. Satel of KNX, niet allebei. '
                      'Sensoren op de bus, sirene, inloop en uitloop. '
                      'De alarmcode zet je per gebruiker onder Gebruikers.',
                ),
              ),
              LuxeSwitchRow(
                title: 'KNX-alarm',
                value: _alarm['enabled'] == true,
                onChanged: (v) {
                  _alarm['enabled'] = v;
                  if (v) {
                    final satel = widget.house['satel'];
                    if (satel is Map) satel['enabled'] = false;
                  }
                  _commit();
                  setState(() {});
                },
              ),
              const LuxeFieldLabel('Uitloop (seconden)'),
              TextField(
                controller: _exit,
                keyboardType: TextInputType.number,
                decoration: luxeFilledDecoration(),
                onChanged: (_) => _commit(),
              ),
              const SizedBox(height: 12),
              const LuxeFieldLabel('Inloop (seconden)'),
              TextField(
                controller: _entry,
                keyboardType: TextInputType.number,
                decoration: luxeFilledDecoration(),
                onChanged: (_) => _commit(),
              ),
              const SizedBox(height: 12),
              const LuxeFieldLabel('Sirene (groepadres)'),
              TextField(
                controller: _siren,
                decoration: luxeFilledDecoration(
                  helper: '1 = sirene aan, 0 = uit. Leeg = geen sirene.',
                ),
                onChanged: (_) => _commit(),
              ),
              if (legacyPin) ...[
                const SizedBox(height: 12),
                Text(
                  'Er staat nog een oude huiscode. Nieuwe codes zet je bij Gebruikers. '
                  'De oude code blijft geldig tot je hem wist.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      _alarm['clearPin'] = true;
                      _alarm.remove('pin');
                      _commit();
                      setState(() {});
                    },
                    child: const Text('Oude huiscode wissen'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (open != null)
          LuxeListCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _openId = null),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Sensoren'),
                  ),
                ),
                _SensorForm(
                  key: ValueKey(open['id'] ?? _openId),
                  sensor: open,
                  onChanged: _commit,
                  onDelete: () {
                    final next = [
                      for (final sensor in sensors)
                        if (sensor['id'] != open['id']) sensor,
                    ];
                    _openId = null;
                    _setSensors(next);
                  },
                ),
              ],
            ),
          )
        else
          LuxeListCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: LuxeSectionTitle(
                    icon: Icons.sensors,
                    title: 'Sensoren',
                  ),
                ),
                if (sensors.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nog geen sensoren',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                for (var i = 0; i < sensors.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                  LuxeNavRow(
                    icon: Icons.sensors_outlined,
                    title: () {
                      final name = '${sensors[i]['name'] ?? ''}'.trim();
                      return name.isEmpty ? 'Sensor' : name;
                    }(),
                    subtitle: _subtitle(sensors[i]),
                    trailing: IconButton(
                      tooltip: 'Sensor verwijderen',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final next = [...sensors]..removeAt(i);
                        _setSensors(next);
                      },
                    ),
                    onTap: () => setState(() => _openId = '${sensors[i]['id']}'),
                  ),
                ],
                if (sensors.isNotEmpty)
                  Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeAddRow(
                  label: 'Sensor toevoegen',
                  onTap: _addSensor,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SensorForm extends StatefulWidget {
  const _SensorForm({
    super.key,
    required this.sensor,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> sensor;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_SensorForm> createState() => _SensorFormState();
}

class _SensorFormState extends State<_SensorForm> {
  late final TextEditingController _name;
  late final TextEditingController _ga;

  @override
  void initState() {
    super.initState();
    if (!knxAlarmSensorKinds.containsKey('${widget.sensor['kind']}')) {
      widget.sensor['kind'] = 'magneetcontact';
    }
    _name = TextEditingController(text: '${widget.sensor['name'] ?? ''}');
    _ga = TextEditingController(text: '${widget.sensor['ga'] ?? ''}');
  }

  @override
  void dispose() {
    _name.dispose();
    _ga.dispose();
    super.dispose();
  }

  void _write() {
    widget.sensor['name'] = _name.text;
    widget.sensor['ga'] = _ga.text.trim();
    widget.onChanged();
  }

  /// Ontbrekend contact is NO.
  String get _contact => widget.sensor['alarmOn'] == '0' ? '0' : '1';

  set _contact(String v) {
    widget.sensor['alarmOn'] = v == '0' ? '0' : '1';
    widget.onChanged();
    setState(() {});
  }

  void _flag(String key, bool v) {
    widget.sensor[key] = v;
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeFieldLabel('Naam'),
        TextField(
          controller: _name,
          decoration: luxeFilledDecoration(),
          onChanged: (_) => _write(),
        ),
        const SizedBox(height: 8),
        const LuxeFieldLabel('Groepadres'),
        TextField(
          controller: _ga,
          decoration: luxeFilledDecoration(),
          onChanged: (_) => _write(),
        ),
        const SizedBox(height: 8),
        const LuxeFieldLabel('Type sensor'),
        DropdownButtonFormField<String>(
          initialValue: knxAlarmSensorKinds.containsKey(widget.sensor['kind'])
              ? widget.sensor['kind'] as String
              : 'magneetcontact',
          decoration: luxeFilledDecoration(),
          items: [
            for (final e in knxAlarmSensorKinds.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v == null) return;
            widget.sensor['kind'] = v;
            widget.onChanged();
            setState(() {});
          },
        ),
        _SensorCheck(
          label: 'Aanwezig',
          value: widget.sensor['aanwezig'] == true,
          onChanged: (v) => _flag('aanwezig', v),
        ),
        _SensorCheck(
          label: 'Afwezig',
          value: widget.sensor['afwezig'] == true,
          onChanged: (v) => _flag('afwezig', v),
        ),
        _SensorCheck(
          label: 'Inloop activeren',
          value: widget.sensor['inloop'] == true,
          onChanged: (v) => _flag('inloop', v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _SensorCheck(
                label: 'NO',
                value: _contact == '1',
                onChanged: (v) {
                  if (v) _contact = '1';
                },
              ),
            ),
            Expanded(
              child: _SensorCheck(
                label: 'NC',
                value: _contact == '0',
                onChanged: (v) {
                  if (v) _contact = '0';
                },
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onDelete,
            child: const Text('Verwijderen'),
          ),
        ),
      ],
    );
  }
}

class _SensorCheck extends StatelessWidget {
  const _SensorCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label),
    );
  }
}
