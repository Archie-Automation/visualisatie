import 'package:flutter/material.dart';

import '../../rgb_color_favorites.dart';
import '../../theme.dart';
import 'confirm_dialog.dart';

/// Blad onder het favorieten-icoon: opslaan, toepassen, verwijderen.
class RgbFavoriteColorsSheet extends StatefulWidget {
  const RgbFavoriteColorsSheet({
    super.key,
    required this.storageId,
    required this.current,
    required this.onApply,
  });

  final String storageId;
  final RgbFavoriteColor current;
  final ValueChanged<RgbFavoriteColor> onApply;

  @override
  State<RgbFavoriteColorsSheet> createState() => _RgbFavoriteColorsSheetState();
}

class _RgbFavoriteColorsSheetState extends State<RgbFavoriteColorsSheet> {
  List<RgbFavoriteColor> _colors = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await RgbColorFavoriteStore.load(widget.storageId);
    if (!mounted) return;
    setState(() {
      _colors = list;
      _ready = true;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_ready) return;
    final next = List<RgbFavoriteColor>.of(_colors);
    final result = tryAddRgbFavorite(next, widget.current);
    if (result == RgbFavoriteSave.duplicate) {
      _snack('Die kleur staat er al bij.');
      return;
    }
    if (result == RgbFavoriteSave.full) {
      _snack(
        'Maximaal ${RgbFavoriteColor.maxCount} kleuren. '
        'Houd een kleur ingedrukt om er een te verwijderen.',
      );
      return;
    }
    setState(() => _colors = next);
    final ok = await RgbColorFavoriteStore.write(widget.storageId, next);
    if (!ok && mounted) _snack('Opslaan is niet gelukt.');
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuxeColors.cream,
        title: const Text('Kleur verwijderen?'),
        content: const Text('Deze favoriet verdwijnt van dit toestel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final next = List<RgbFavoriteColor>.of(_colors)..removeAt(index);
    setState(() => _colors = next);
    final saved = await RgbColorFavoriteStore.write(widget.storageId, next);
    if (!saved && mounted) _snack('Verwijderen is niet gelukt.');
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: LuxeColors.cream,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Favoriete kleuren',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const LuxeInfoIconButton(
                    title: 'Favoriete kleuren',
                    body: 'Tik op een kleur om die toe te passen. '
                        'Houd een kleur ingedrukt om hem te verwijderen. '
                        'De dimmer blijft staan.\n\n'
                        'Maximaal ${RgbFavoriteColor.maxCount} kleuren, '
                        'alleen op dit toestel.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!_ready)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_colors.isEmpty)
                Text(
                  'Nog geen kleuren opgeslagen.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: LuxeColors.inkSoft),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _colors.length; i++)
                      Tooltip(
                        message: 'Favoriet ${i + 1}',
                        child: Material(
                          color: _colors[i].swatch,
                          shape: CircleBorder(
                            side: BorderSide(color: LuxeColors.line),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final color = _colors[i];
                              Navigator.pop(context);
                              widget.onApply(color);
                            },
                            onLongPress: () => _delete(i),
                            child: const SizedBox(width: 56, height: 56),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _ready ? _save : null,
                icon: const Icon(Icons.add),
                label: const Text('Huidige kleur opslaan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
