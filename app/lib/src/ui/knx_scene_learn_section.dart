import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../scene_api.dart';
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
  HouseConfig get _cfg => ref.watch(configProvider).value ?? widget.cfg;

  Future<void> _openLearn({
    required String roomId,
    Scene? existing,
    KnxSceneLearnAddress? target,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => KnxSceneLearnSheet(
        roomId: roomId,
        config: _cfg,
        existing: existing,
        target: target,
      ),
    );
    if (ok == true) ref.invalidate(configProvider);
  }

  Future<void> _forget(String roomId, Scene scene) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inlezing verwijderen?'),
        content: Text(
          '“${scene.name}” verdwijnt uit de app. De KNX-scene in ETS blijft bestaan. '
          'Daarna kunt u opnieuw inlezen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(sceneApiProvider).forgetKnx(roomId, scene.id);
      ref.invalidate(configProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _overviewRooms(_cfg);
    if (!_cfg.hasKnxSceneLearnAddresses && blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Text(
          'Geen scene-adressen in de technische configuratie. '
          'Vul ze in bij KNX: ruimte, schakelaar, knop en fysiek adres.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: Text(
          'Koppel elk scene-adres aan een ruimte in de technische configuratie (KNX).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Per ruimte: schakelaar, knop en scene. Tik om in te lezen of bij te stellen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (var r = 0; r < blocks.length; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            _RoomOverviewCard(
              block: blocks[r],
              onOpen: (_, btn) => _openLearn(
                roomId: blocks[r].roomId,
                existing: btn.learned,
                target: btn.address,
              ),
              onForget: (scene) => _forget(blocks[r].roomId, scene),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomOverviewCard extends StatelessWidget {
  const _RoomOverviewCard({
    required this.block,
    required this.onOpen,
    required this.onForget,
  });

  final _RoomBlock block;
  final void Function(_SwitchBlock switchBlock, _ButtonRow button) onOpen;
  final void Function(Scene scene) onForget;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            block.roomLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (var s = 0; s < block.switches.length; s++) ...[
            if (s > 0) const SizedBox(height: 10),
            Text(
              block.switches[s].title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (block.switches[s].physicalAddress != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  block.switches[s].physicalAddress!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final btn in block.switches[s].buttons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(btn.title),
                subtitle: Text(btn.subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (btn.learned != null)
                      IconButton(
                        tooltip: 'Verwijderen om opnieuw in te lezen',
                        onPressed: () => onForget(btn.learned!),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => onOpen(block.switches[s], btn),
              ),
          ],
        ],
      ),
    );
  }
}

class _RoomBlock {
  const _RoomBlock({
    required this.roomId,
    required this.roomLabel,
    required this.switches,
  });
  final String roomId;
  final String roomLabel;
  final List<_SwitchBlock> switches;
}

class _SwitchBlock {
  const _SwitchBlock({
    required this.title,
    required this.buttons,
    this.physicalAddress,
  });
  final String title;
  final String? physicalAddress;
  final List<_ButtonRow> buttons;
}

class _ButtonRow {
  const _ButtonRow({
    required this.title,
    required this.subtitle,
    this.address,
    this.learned,
  });
  final String title;
  final String subtitle;
  final KnxSceneLearnAddress? address;
  final Scene? learned;
}

List<_RoomBlock> _overviewRooms(HouseConfig cfg) {
  final labels = <String, String>{};
  final order = <String>[];
  final learned = <String, List<Scene>>{};
  for (final f in cfg.floors) {
    for (final r in f.rooms) {
      order.add(r.id);
      labels[r.id] = '${f.name} · ${r.name}';
      final knx = r.scenes.where((s) => s.isKnxHardware).toList();
      if (knx.isNotEmpty) learned[r.id] = knx;
    }
  }

  final byRoom = <String, List<KnxSceneLearnAddress>>{};
  for (final a in cfg.knxSceneLearnAddresses) {
    final rid = a.roomId;
    if (rid == null || rid.isEmpty) continue;
    byRoom.putIfAbsent(rid, () => []).add(a);
  }

  final roomIds = <String>{...byRoom.keys, ...learned.keys};
  final out = <_RoomBlock>[];
  for (final id in order) {
    if (!roomIds.contains(id)) continue;
    out.add(_RoomBlock(
      roomId: id,
      roomLabel: labels[id] ?? id,
      switches: _switchesForRoom(byRoom[id] ?? const [], learned[id] ?? const []),
    ));
  }
  return out;
}

List<_SwitchBlock> _switchesForRoom(
  List<KnxSceneLearnAddress> addresses,
  List<Scene> scenes,
) {
  final usedScenes = <String>{};
  final groups = <String, List<KnxSceneLearnAddress>>{};
  final groupOrder = <String>[];
  for (final a in addresses) {
    final key = _switchKey(a);
    if (groups.putIfAbsent(key, () => []).isEmpty) groupOrder.add(key);
    groups[key]!.add(a);
  }

  final out = <_SwitchBlock>[];
  for (final key in groupOrder) {
    final rows = groups[key]!;
    final first = rows.first;
    out.add(_SwitchBlock(
      title: _switchTitle(first),
      physicalAddress: first.physicalAddress,
      buttons: [
        for (final a in rows)
          _buttonFromAddress(a, _sceneForAddress(a, scenes, usedScenes)),
      ],
    ));
  }

  final orphans = [
    for (final s in scenes)
      if (!usedScenes.contains(s.id)) s,
  ];
  if (orphans.isNotEmpty) {
    out.add(_SwitchBlock(
      title: addresses.isEmpty ? 'Schakelaar' : 'Overig',
      buttons: [
        for (final s in orphans) _buttonFromScene(s),
      ],
    ));
  }
  return out;
}

String _switchKey(KnxSceneLearnAddress a) {
  final phys = (a.physicalAddress ?? '').trim();
  final name = (a.switchName ?? '').trim();
  if (phys.isNotEmpty) return 'p:$phys';
  if (name.isNotEmpty) return 'n:${name.toLowerCase()}';
  return 'u:${a.ga}:${a.buttonName ?? ''}:${a.name ?? ''}';
}

String _switchTitle(KnxSceneLearnAddress a) {
  final name = (a.switchName ?? '').trim();
  if (name.isNotEmpty) return name;
  final phys = (a.physicalAddress ?? '').trim();
  if (phys.isNotEmpty) return phys;
  return 'Schakelaar';
}

Scene? _sceneForAddress(
  KnxSceneLearnAddress a,
  List<Scene> scenes,
  Set<String> used,
) {
  for (final s in scenes) {
    if (s.knxGa != a.ga) continue;
    used.add(s.id);
    return s;
  }
  return null;
}

_ButtonRow _buttonFromAddress(KnxSceneLearnAddress a, Scene? learned) {
  final button = (a.buttonName ?? '').trim();
  final scene = (a.name ?? '').trim();
  final learnedName = (learned?.name ?? '').trim();
  final titleParts = <String>[
    if (button.isNotEmpty) button else 'Knop',
    if (scene.isNotEmpty) scene,
    if (learnedName.isNotEmpty && learnedName.toLowerCase() != scene.toLowerCase())
      learnedName,
  ];
  final sub = <String>[
    a.ga,
    if (learned?.knxNumber != null) 'scene ${learned!.knxNumber}',
    if (learned == null) 'nog niet ingelezen',
  ];
  return _ButtonRow(
    title: titleParts.join(' · '),
    subtitle: sub.join('  ·  '),
    address: a,
    learned: learned,
  );
}

_ButtonRow _buttonFromScene(Scene s) {
  final button = (s.knxButtonName ?? '').trim();
  final titleParts = <String>[
    if (button.isNotEmpty) button else 'Knop',
    s.name,
  ];
  return _ButtonRow(
    title: titleParts.join(' · '),
    subtitle: '${s.knxGa}  ·  scene ${s.knxNumber}',
    learned: s,
  );
}
