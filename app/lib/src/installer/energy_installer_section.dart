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
