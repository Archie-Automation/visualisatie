import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../ui/widgets/luxe_form.dart';
import 'installer_form_sections.dart';

class DeviceGaOffsetPreview {
  const DeviceGaOffsetPreview({
    required this.count,
    this.before,
    this.after,
    this.error,
  });

  final int count;
  final String? before;
  final String? after;
  final String? error;

  bool get canApply =>
      error == null && count > 0 && before != null && before != after;
}

bool _isGroupAddress(String value) {
  final t = value.trim();
  if (!t.contains('/')) return false;
  return validateKnxGa(t) == null;
}

String? _shiftGroupAddress(
  String value, {
  required int main,
  required int middle,
  required int sub,
}) {
  final parts = value.trim().split('/');
  if (parts.length != 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2]);
  if (a == null || b == null || c == null) return null;
  final next = '${a + main}/${b + middle}/${c + sub}';
  if (validateKnxGa(next) != null) return null;
  return next;
}

class _GaSlot {
  _GaSlot(this.write, this.value);
  final void Function(String next) write;
  final String value;
}

void _collect(dynamic node, List<_GaSlot> out) {
  if (node is Map) {
    for (final entry in node.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'id') continue;
      if (value is String && _isGroupAddress(value)) {
        out.add(_GaSlot((next) => node[key] = next, value.trim()));
      } else {
        _collect(value, out);
      }
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      final value = node[i];
      if (value is String && _isGroupAddress(value)) {
        final index = i;
        out.add(_GaSlot((next) => node[index] = next, value.trim()));
      } else {
        _collect(value, out);
      }
    }
  }
}

/// Telt elk groepsadres in het apparaat, ook geneste velden.
int deviceGroupAddressCount(Map<String, dynamic> device) {
  final slots = <_GaSlot>[];
  _collect(device, slots);
  return slots.length;
}

DeviceGaOffsetPreview previewDeviceGaOffset(
  Map<String, dynamic> device, {
  required int main,
  required int middle,
  required int sub,
}) {
  final slots = <_GaSlot>[];
  _collect(device, slots);
  if (slots.isEmpty) {
    return const DeviceGaOffsetPreview(count: 0);
  }
  String? after;
  for (final slot in slots) {
    final next = _shiftGroupAddress(
      slot.value,
      main: main,
      middle: middle,
      sub: sub,
    );
    if (next == null) {
      final parts = slot.value.split('/');
      final a = int.parse(parts[0]) + main;
      final b = int.parse(parts[1]) + middle;
      final c = int.parse(parts[2]) + sub;
      final attempted = '$a/$b/$c';
      return DeviceGaOffsetPreview(
        count: slots.length,
        before: slot.value,
        error: '${slot.value} wordt $attempted. ${validateKnxGa(attempted)}',
      );
    }
    after ??= next;
  }
  return DeviceGaOffsetPreview(
    count: slots.length,
    before: slots.first.value,
    after: after,
  );
}

/// Past de offset toe. Geeft een fout terug en laat het apparaat ongemoeid
/// als één adres buiten 0–31 / 0–7 / 0–255 zou vallen.
String? applyDeviceGaOffset(
  Map<String, dynamic> device, {
  required int main,
  required int middle,
  required int sub,
}) {
  final preview = previewDeviceGaOffset(
    device,
    main: main,
    middle: middle,
    sub: sub,
  );
  if (preview.error != null) return preview.error;
  if (!preview.canApply) return null;
  final slots = <_GaSlot>[];
  _collect(device, slots);
  for (final slot in slots) {
    final next = _shiftGroupAddress(
      slot.value,
      main: main,
      middle: middle,
      sub: sub,
    );
    if (next == null) return 'Groepsadres ${slot.value} valt buiten het bereik';
    slot.write(next);
  }
  return null;
}

/// Eén rij: hoofd, midden en sub van elk groepsadres op dit apparaat.
class DeviceGaOffsetCard extends StatefulWidget {
  const DeviceGaOffsetCard({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  State<DeviceGaOffsetCard> createState() => _DeviceGaOffsetCardState();
}

class _DeviceGaOffsetCardState extends State<DeviceGaOffsetCard> {
  final _main = TextEditingController(text: '0');
  final _middle = TextEditingController(text: '0');
  final _sub = TextEditingController(text: '0');
  String? _inputError;

  @override
  void dispose() {
    _main.dispose();
    _middle.dispose();
    _sub.dispose();
    super.dispose();
  }

  int? _read(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty || t == '-') return 0;
    return int.tryParse(t);
  }

  void _onEdited() => setState(() => _inputError = null);

  DeviceGaOffsetPreview? get _preview {
    final main = _read(_main);
    final middle = _read(_middle);
    final sub = _read(_sub);
    if (main == null || middle == null || sub == null) return null;
    return previewDeviceGaOffset(
      widget.device,
      main: main,
      middle: middle,
      sub: sub,
    );
  }

  void _apply() {
    final main = _read(_main);
    final middle = _read(_middle);
    final sub = _read(_sub);
    if (main == null || middle == null || sub == null) {
      setState(() => _inputError = 'Gebruik hele getallen, bijvoorbeeld -2 of 10.');
      return;
    }
    final error = applyDeviceGaOffset(
      widget.device,
      main: main,
      middle: middle,
      sub: sub,
    );
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    _main.text = '0';
    _middle.text = '0';
    _sub.text = '0';
    widget.onChanged();
    final count = deviceGroupAddressCount(widget.device);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? '1 groepsadres verschoven'
              : '$count groepsadressen verschoven',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (deviceGroupAddressCount(widget.device) == 0) {
      return const SizedBox.shrink();
    }
    final preview = _preview;
    final message = _inputError ??
        preview?.error ??
        (preview == null
            ? 'Gebruik hele getallen, bijvoorbeeld -2 of 10.'
            : null);
    final canApply = _inputError == null && (preview?.canApply ?? false);
    final sample = preview == null || preview.before == null
        ? null
        : preview.count == 1
            ? '${preview.before} → ${preview.after}'
            : '${preview.count} adressen · ${preview.before} → ${preview.after}';

    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSectionTitle(
            icon: Icons.swap_horiz,
            title: 'Groepsadressen verschuiven',
            subtitle: 'Dezelfde stap op hoofd, midden en sub van elk adres.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _offsetField('Hoofd', _main),
              const SizedBox(width: 8),
              _offsetField('Midden', _middle),
              const SizedBox(width: 8),
              _offsetField('Sub', _sub),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  message ?? sample ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: message != null
                            ? LuxeColors.danger
                            : LuxeColors.inkSoft,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canApply ? _apply : null,
                child: const Text('Verschuiven'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offsetField(String label, TextEditingController controller) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeFieldLabel(label),
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
            ],
            decoration: luxeFilledDecoration(hint: '0'),
            onChanged: (_) => _onEdited(),
          ),
        ],
      ),
    );
  }
}
