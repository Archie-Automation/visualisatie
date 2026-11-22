import 'package:flutter/material.dart';

import '../knx_alarm.dart';

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
  late final TextEditingController _pin;
  late final TextEditingController _exit;
  late final TextEditingController _entry;
  late final TextEditingController _siren;

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
    _pin = TextEditingController();
    _exit = TextEditingController(text: '${_num(_alarm['exitSeconds'], 30)}');
    _entry = TextEditingController(text: '${_num(_alarm['entrySeconds'], 30)}');
    _siren = TextEditingController(text: '${_alarm['sirenGa'] ?? ''}');
  }

  @override
  void dispose() {
    _pin.dispose();
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
    final pin = _pin.text.trim();
    if (pin.isEmpty) {
      _alarm.remove('pin');
    } else {
      _alarm['pin'] = pin;
    }
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

  @override
  Widget build(BuildContext context) {
    final sensors = _sensors;
    final pinSet = _alarm['pinSet'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('KNX-alarm'),
          subtitle: const Text(
            'Naast Satel. Sensoren op de bus, een eigen code, sirene, inloop en uitloop.',
          ),
          value: _alarm['enabled'] == true,
          onChanged: (v) {
            _alarm['enabled'] = v;
            _commit();
            setState(() {});
          },
        ),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Nieuwe code',
            helperText: pinSet
                ? 'Er staat al een code. Leeg laten houdt die. Minimaal 4 cijfers.'
                : 'Minimaal 4 cijfers. Wordt bij opslaan gezet.',
          ),
          onChanged: (_) => _commit(),
        ),
        TextField(
          controller: _exit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Uitloop (seconden)'),
          onChanged: (_) => _commit(),
        ),
        TextField(
          controller: _entry,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Inloop (seconden)'),
          onChanged: (_) => _commit(),
        ),
        TextField(
          controller: _siren,
          decoration: const InputDecoration(
            labelText: 'Sirene (groepadres)',
            helperText: '1 = sirene aan, 0 = uit. Leeg = geen sirene.',
          ),
          onChanged: (_) => _commit(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Sensoren', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () {
                final next = [...sensors];
                next.add({
                  'id': 's${DateTime.now().microsecondsSinceEpoch}',
                  'name': 'Sensor ${next.length + 1}',
                  'ga': '',
                  'kind': 'magneetcontact',
                  'aanwezig': false,
                  'afwezig': true,
                  'inloop': false,
                  'alarmOn': '1',
                });
                _alarm['sensors'] = next;
                _commit();
                setState(() {});
              },
              child: const Text('Sensor toevoegen'),
            ),
          ],
        ),
        for (var i = 0; i < sensors.length; i++)
          _SensorCard(
            key: ValueKey(sensors[i]['id'] ?? i),
            sensor: sensors[i],
            onChanged: _commit,
            onDelete: () {
              final next = [...sensors]..removeAt(i);
              _alarm['sensors'] = next;
              _commit();
              setState(() {});
            },
          ),
      ],
    );
  }
}

class _SensorCard extends StatefulWidget {
  const _SensorCard({
    super.key,
    required this.sensor,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> sensor;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_SensorCard> createState() => _SensorCardState();
}

class _SensorCardState extends State<_SensorCard> {
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Naam'),
              onChanged: (_) => _write(),
            ),
            TextField(
              controller: _ga,
              decoration: const InputDecoration(labelText: 'Groepadres'),
              onChanged: (_) => _write(),
            ),
            DropdownButtonFormField<String>(
              initialValue: knxAlarmSensorKinds.containsKey(widget.sensor['kind'])
                  ? widget.sensor['kind'] as String
                  : 'magneetcontact',
              decoration: const InputDecoration(labelText: 'Type sensor'),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm aanwezig'),
              value: widget.sensor['aanwezig'] == true,
              onChanged: (v) {
                widget.sensor['aanwezig'] = v;
                widget.onChanged();
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm afwezig'),
              value: widget.sensor['afwezig'] == true,
              onChanged: (v) {
                widget.sensor['afwezig'] = v;
                widget.onChanged();
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hier mag worden ingelopen'),
              subtitle: const Text(
                'Openen start de inlooptijd. Andere sensoren zetten meteen de sirene aan.',
              ),
              value: widget.sensor['inloop'] == true,
              onChanged: (v) {
                widget.sensor['inloop'] = v;
                widget.onChanged();
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm als het bit uit staat'),
              value: widget.sensor['alarmOn'] == '0',
              onChanged: (v) {
                widget.sensor['alarmOn'] = v ? '0' : '1';
                widget.onChanged();
                setState(() {});
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDelete,
                child: const Text('Verwijderen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
