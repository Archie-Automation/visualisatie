import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/widgets/luxe_form.dart';

/// Installer form for `house.energy`. KNX group addresses only.
class EnergyInstallerSection extends StatelessWidget {
  const EnergyInstallerSection({
    super.key,
    required this.energy,
    required this.onChanged,
  });

  final Map<String, dynamic> energy;
  final VoidCallback onChanged;

  Map<String, dynamic> get _knx {
    final k = energy['knx'];
    if (k is Map<String, dynamic>) return k;
    final m = <String, dynamic>{};
    energy['knx'] = m;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = energy['enabled'] == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Energie', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'KNX-groepsadressen voor net, PV, accu en tellers. De NUC leest de '
          'bus en stuurt één snapshot naar de app. Een ontbrekend telegram '
          'blijft leeg en wordt geen 0 W.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: LuxeColors.inkSoft),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tonen onder Systemen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            LuxeOnOffSwitch(
              value: enabled,
              onChanged: (v) {
                energy['enabled'] = v;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Net: positief = afname, negatief = teruglevering. '
          'Accu: positief = ontladen, negatief = laden. '
          'Woning = net + PV + accu. Schaalfactor 1 als de bus al in die '
          'eenheid staat, 1000 als de bus kW stuurt en het veld watt is, '
          '-1 om het teken te draaien.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: LuxeColors.inkFaint),
        ),
        const SizedBox(height: 20),
        for (final point in _points) ...[
          _EnergyPointEditor(
            key: ValueKey(point.key),
            spec: point,
            knx: _knx,
            onChanged: onChanged,
          ),
          const SizedBox(height: 18),
        ],
        const SizedBox(height: 8),
        _PricesEditor(energy: energy, onChanged: onChanged),
      ],
    );
  }
}

class _PricesEditor extends StatefulWidget {
  const _PricesEditor({required this.energy, required this.onChanged});

  final Map<String, dynamic> energy;
  final VoidCallback onChanged;

  @override
  State<_PricesEditor> createState() => _PricesEditorState();
}

class _PricesEditorState extends State<_PricesEditor> {
  late final TextEditingController _importSurcharge;
  late final TextEditingController _exportFixed;
  late final TextEditingController _exportSurcharge;
  late final TextEditingController _gasSurcharge;

  Map<String, dynamic> _prices({bool create = false}) {
    final raw = widget.energy['prices'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      final cast = raw.cast<String, dynamic>();
      widget.energy['prices'] = cast;
      return cast;
    }
    if (!create) return <String, dynamic>{};
    final created = <String, dynamic>{};
    widget.energy['prices'] = created;
    return created;
  }

  @override
  void initState() {
    super.initState();
    final prices = _prices();
    _importSurcharge = TextEditingController(text: _numText(prices['importSurchargeEurPerKwh']));
    _exportFixed = TextEditingController(text: _numText(prices['exportFixedEurPerKwh']));
    _exportSurcharge = TextEditingController(text: _numText(prices['exportSurchargeEurPerKwh']));
    _gasSurcharge = TextEditingController(text: _numText(prices['gasSurchargeEurPerM3']));
  }

  @override
  void dispose() {
    _importSurcharge.dispose();
    _exportFixed.dispose();
    _exportSurcharge.dispose();
    _gasSurcharge.dispose();
    super.dispose();
  }

  String _numText(Object? value) => value is num ? '$value' : '';

  void _writeNumber(String key, String text) {
    final prices = _prices(create: true);
    final parsed = text.trim().replaceAll(',', '.');
    if (parsed.isEmpty) {
      prices.remove(key);
    } else {
      final n = double.tryParse(parsed);
      if (n == null || !n.isFinite) return;
      prices[key] = n;
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final prices = _prices();
    final enabled = prices['enabled'] == true;
    final exportMode = prices['exportMode'] == 'fixed' || prices['exportMode'] == 'market'
        ? prices['exportMode'] as String
        : 'none';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Prijzen', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'EnergyZero levert de marktprijs excl. btw. De opslag is euro per '
          'kWh of m³, ook excl. btw. Btw (21%) komt er alleen overheen als je '
          'dat aanzet. Teruglevering heeft een eigen tarief en wordt nooit de '
          'afnameprijs. Dagtotalen komen uit de teller sinds lokale middernacht. '
          'Zonder teller schat de NUC het uit het vermogen.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: LuxeColors.inkFaint),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'EnergyZero-prijzen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            LuxeOnOffSwitch(
              value: enabled,
              onChanged: (v) {
                _prices(create: true)['enabled'] = v;
                widget.onChanged();
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        const LuxeFieldLabel('Opslag afname (€/kWh, excl. btw)'),
        TextField(
          controller: _importSurcharge,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: luxeFilledDecoration(hint: '0'),
          onChanged: (v) => _writeNumber('importSurchargeEurPerKwh', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Btw op afname'),
          value: prices['importVat'] == true,
          onChanged: (v) {
            _prices(create: true)['importVat'] = v;
            widget.onChanged();
            setState(() {});
          },
        ),
        const LuxeFieldLabel('Teruglevering'),
        DropdownButtonFormField<String>(
          key: ValueKey('export-$exportMode'),
          initialValue: exportMode,
          isExpanded: true,
          decoration: luxeFilledDecoration(),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Geen tarief')),
            DropdownMenuItem(value: 'fixed', child: Text('Vast bedrag')),
            DropdownMenuItem(value: 'market', child: Text('EnergyZero + opslag')),
          ],
          onChanged: (v) {
            final next = _prices(create: true);
            if (v == null || v == 'none') {
              next.remove('exportMode');
            } else {
              next['exportMode'] = v;
            }
            widget.onChanged();
            setState(() {});
          },
        ),
        if (exportMode == 'fixed') ...[
          const SizedBox(height: 8),
          const LuxeFieldLabel('Terugleververgoeding (€/kWh)'),
          TextField(
            controller: _exportFixed,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: luxeFilledDecoration(hint: '0,08'),
            onChanged: (v) => _writeNumber('exportFixedEurPerKwh', v),
          ),
        ],
        if (exportMode == 'market') ...[
          const SizedBox(height: 8),
          const LuxeFieldLabel('Opslag teruglevering (€/kWh, excl. btw)'),
          TextField(
            controller: _exportSurcharge,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: luxeFilledDecoration(hint: '0 of negatief'),
            onChanged: (v) => _writeNumber('exportSurchargeEurPerKwh', v),
          ),
        ],
        if (exportMode != 'none')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Btw op teruglevering'),
            value: prices['exportVat'] == true,
            onChanged: (v) {
              _prices(create: true)['exportVat'] = v;
              widget.onChanged();
              setState(() {});
            },
          ),
        const SizedBox(height: 8),
        const LuxeFieldLabel('Opslag gas (€/m³, excl. btw)'),
        TextField(
          controller: _gasSurcharge,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: luxeFilledDecoration(hint: '0'),
          onChanged: (v) => _writeNumber('gasSurchargeEurPerM3', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Btw op gas'),
          value: prices['gasVat'] == true,
          onChanged: (v) {
            _prices(create: true)['gasVat'] = v;
            widget.onChanged();
            setState(() {});
          },
        ),
      ],
    );
  }
}

class _PointSpec {
  const _PointSpec(this.key, this.label, this.unit, this.defaultDpt);
  final String key;
  final String label;
  final String unit;
  final String defaultDpt;
}

const _points = <_PointSpec>[
  _PointSpec('gridPowerW', 'Netvermogen', 'W', 'float4'),
  _PointSpec('solarPowerW', 'PV-vermogen', 'W', 'float4'),
  _PointSpec('batteryPowerW', 'Accuvermogen', 'W', 'float4'),
  _PointSpec('batterySoc', 'Accupercentage', '%', 'percent'),
  _PointSpec('importEnergyKwh', 'Teller afname', 'kWh', 'float4'),
  _PointSpec('exportEnergyKwh', 'Teller teruglevering', 'kWh', 'float4'),
  _PointSpec('solarEnergyKwh', 'Teller PV', 'kWh', 'float4'),
  _PointSpec('gasM3', 'Gas', 'm³', 'float2'),
];

const _dptLabels = <String, String>{
  'float4': '4-byte float (DPT 14)',
  'float2': '2-byte float (DPT 9)',
  'int16': '16-bit signed (DPT 8)',
  'uint16': '16-bit unsigned (DPT 7)',
  'int32': '32-bit signed (DPT 13)',
  'uint32': '32-bit unsigned (DPT 12)',
  'percent': 'percentage (DPT 5.001)',
};

class _EnergyPointEditor extends StatefulWidget {
  const _EnergyPointEditor({
    super.key,
    required this.spec,
    required this.knx,
    required this.onChanged,
  });

  final _PointSpec spec;
  final Map<String, dynamic> knx;
  final VoidCallback onChanged;

  @override
  State<_EnergyPointEditor> createState() => _EnergyPointEditorState();
}

class _EnergyPointEditorState extends State<_EnergyPointEditor> {
  late final TextEditingController _ga;
  late final TextEditingController _scale;
  late String _dpt;

  Map<String, dynamic>? get _point {
    final p = widget.knx[widget.spec.key];
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return p.cast<String, dynamic>();
    return null;
  }

  @override
  void initState() {
    super.initState();
    final point = _point;
    _ga = TextEditingController(text: (point?['ga'] as String?) ?? '');
    final scale = point?['scale'];
    _scale = TextEditingController(text: scale is num ? '$scale' : '');
    final raw = point?['dpt'];
    _dpt = raw is String && _dptLabels.containsKey(raw)
        ? raw
        : widget.spec.defaultDpt;
  }

  @override
  void dispose() {
    _ga.dispose();
    _scale.dispose();
    super.dispose();
  }

  void _write() {
    final ga = _ga.text.trim();
    if (ga.isEmpty) {
      widget.knx.remove(widget.spec.key);
      widget.onChanged();
      setState(() {});
      return;
    }
    final point = _point ?? <String, dynamic>{};
    point['ga'] = ga;
    point['dpt'] = _dpt;
    final scaleText = _scale.text.trim().replaceAll(',', '.');
    if (scaleText.isEmpty) {
      point.remove('scale');
    } else {
      final n = double.tryParse(scaleText);
      if (n != null && n.isFinite && n != 0) point['scale'] = n;
    }
    widget.knx[widget.spec.key] = point;
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scaleText = _scale.text.trim().replaceAll(',', '.');
    final scaleBad = scaleText.isNotEmpty &&
        (double.tryParse(scaleText) == null || double.tryParse(scaleText) == 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LuxeFieldLabel('${widget.spec.label} (${widget.spec.unit})'),
        TextField(
          controller: _ga,
          decoration: luxeFilledDecoration(hint: '1/2/3'),
          onChanged: (_) => _write(),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.spec.key}-$_dpt'),
          initialValue: _dpt,
          isExpanded: true,
          decoration: luxeFilledDecoration(),
          items: [
            for (final entry in _dptLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _dpt = v;
            _write();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _scale,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: luxeFilledDecoration(
            hint: 'Schaalfactor, leeg = 1',
            error: scaleBad ? 'Gebruik een getal anders dan 0' : null,
          ),
          onChanged: (_) => _write(),
        ),
      ],
    );
  }
}
