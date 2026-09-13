import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'knx_scene_learn_sheet.dart';
import 'widgets/glass_card.dart';

/// Instellingen: KNX-hardware-scenes inlezen en bijstellen (staff).
class KnxSceneLearnSection extends ConsumerStatefulWidget {
  const KnxSceneLearnSection({super.key, required this.cfg});

  final HouseConfig cfg;

  @override
  ConsumerState<KnxSceneLearnSection> createState() =>
      _KnxSceneLearnSectionState();
}

class _KnxSceneLearnSectionState extends ConsumerState<KnxSceneLearnSection> {
  String? _roomId;

  HouseConfig get _cfg => ref.watch(configProvider).value ?? widget.cfg;

  List<(String id, String label)> get _rooms {
    final allowed = _cfg.knxSceneLearnRoomIds;
    if (allowed.isEmpty) return const [];
    final out = <(String, String)>[];
    for (final f in _cfg.floors) {
      for (final r in f.rooms) {
        if (!allowed.contains(r.id)) continue;
        out.add((r.id, '${f.name} · ${r.name}'));
      }
    }
    return out;
  }

  Room? _roomOf(String id) {
    for (final f in _cfg.floors) {
      for (final r in f.rooms) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final allowed = widget.cfg.knxSceneLearnRoomIds;
    String? first;
    for (final f in widget.cfg.floors) {
      for (final r in f.rooms) {
        if (allowed.contains(r.id)) {
          first = r.id;
          break;
        }
      }
      if (first != null) break;
    }
    _roomId = first;
  }

  Future<void> _openLearn({Scene? existing}) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => KnxSceneLearnSheet(
        roomId: roomId,
        config: _cfg,
        existing: existing,
      ),
    );
    if (ok == true) ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    if (!_cfg.hasKnxSceneLearnAddresses) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Text(
          'Geen scene-adressen in de technische configuratie. '
          'Vul ze in bij KNX en koppel elke GA aan een ruimte.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Text(
          _cfg.knxSceneLearnRoomIds.isEmpty
              ? 'Koppel elk scene-adres aan een ruimte in de technische configuratie (KNX).'
              : 'Geen kamers in dit huis.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final selected =
        rooms.any((r) => r.$1 == _roomId) ? _roomId! : rooms.first.$1;
    final room = _roomOf(selected);
    final knxScenes =
        room?.scenes.where((s) => s.isKnxHardware).toList() ?? const <Scene>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Kamer', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  isExpanded: true,
                  items: [
                    for (final r in rooms)
                      DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _roomId = v);
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _openLearn(),
                  child: const Text('Inlezen vanaf muurknop'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (knxScenes.isEmpty)
            Text(
              'Nog geen KNX-scene in deze kamer ingelezen. '
              'Inlezen vangt de muurknop; daarna stelt u de waarden bij en slaat u op in KNX '
              '(als store in ETS is vrijgegeven).',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            GlassCard(
              radius: 16,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < knxScenes.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
                    ListTile(
                      title: Text(knxScenes[i].name),
                      subtitle: Text(
                        '${knxScenes[i].knxGa}  ·  scene ${knxScenes[i].knxNumber}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openLearn(existing: knxScenes[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
