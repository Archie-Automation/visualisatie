import 'package:flutter/material.dart';

/// A single KNX group address from an imported export (address + name + DPT).
class KnxGaEntry {
  const KnxGaEntry({
    required this.address,
    required this.name,
    required this.dpt,
    this.mainGroup,
    this.middleGroup,
  });

  final String address;
  final String name;
  final String dpt;
  final String? mainGroup;
  final String? middleGroup;

  factory KnxGaEntry.fromJson(Map<String, dynamic> j) => KnxGaEntry(
        address: j['address'] as String? ?? '',
        name: j['name'] as String? ?? '',
        dpt: j['dpt'] as String? ?? '',
        mainGroup: j['mainGroup'] as String?,
        middleGroup: j['middleGroup'] as String?,
      );
}

/// Process-wide holder for the imported GA catalog. Loaded once when the
/// installer house editor opens, then read by the GA search fields so the
/// installer can look up the right address by name when wiring any device
/// (also types that aren't auto-created, e.g. a fireplace).
class KnxGaCatalog {
  KnxGaCatalog._();
  static final KnxGaCatalog instance = KnxGaCatalog._();

  final ValueNotifier<List<KnxGaEntry>> entries =
      ValueNotifier<List<KnxGaEntry>>(const []);

  /// address -> name, for resolving a display name next to a GA field.
  final Map<String, String> _nameByAddress = {};

  void setEntries(List<KnxGaEntry> list) {
    entries.value = list;
    _nameByAddress
      ..clear()
      ..addEntries(list.map((e) => MapEntry(e.address, e.name)));
  }

  bool get isEmpty => entries.value.isEmpty;

  String? nameFor(String address) => _nameByAddress[address.trim()];
}

/// Opens a searchable picker over the imported GA catalog and returns the
/// selected address (or null when cancelled). When [dptHint] is set, matching
/// DPT entries float to the top.
Future<String?> showGaSearchDialog(
  BuildContext context, {
  String? dptHint,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _GaSearchDialog(dptHint: dptHint),
  );
}

class _GaSearchDialog extends StatefulWidget {
  const _GaSearchDialog({this.dptHint});
  final String? dptHint;

  @override
  State<_GaSearchDialog> createState() => _GaSearchDialogState();
}

class _GaSearchDialogState extends State<_GaSearchDialog> {
  String _query = '';

  List<KnxGaEntry> _filtered(List<KnxGaEntry> all) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [...all]
        : all
            .where((e) =>
                e.name.toLowerCase().contains(q) ||
                e.address.toLowerCase().contains(q))
            .toList();
    final hint = widget.dptHint;
    if (hint != null && hint.isNotEmpty) {
      list.sort((a, b) {
        final am = a.dpt == hint ? 0 : 1;
        final bm = b.dpt == hint ? 0 : 1;
        return am.compareTo(bm);
      });
    }
    return list.take(200).toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = KnxGaCatalog.instance.entries.value;
    return AlertDialog(
      title: const Text('Groepsadres zoeken'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Zoek op naam of adres (bv. openhaard of 5/1/1)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            if (all.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nog geen groepsadressen geïmporteerd.\n'
                      'Gebruik eerst "Importeer uit KNX (.xml)".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Builder(builder: (ctx) {
                  final list = _filtered(all);
                  if (list.isEmpty) {
                    return const Center(child: Text('Geen resultaten.'));
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(e.name.isEmpty ? e.address : e.name),
                        subtitle: Text(
                          [e.address, if (e.dpt.isNotEmpty) e.dpt].join('  ·  '),
                        ),
                        onTap: () => Navigator.pop(ctx, e.address),
                      );
                    },
                  );
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
      ],
    );
  }
}
