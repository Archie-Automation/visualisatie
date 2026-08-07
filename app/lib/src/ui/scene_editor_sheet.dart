import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../media_api.dart';
import '../models.dart';
import '../scene_api.dart';
import '../scene_entry.dart';
import '../theme.dart';
import 'responsive.dart';
import 'widgets/scene_entry_tiles.dart';
import 'widgets/scene_icons.dart';

enum SceneScope { global, room }

/// Full-screen bottom sheet that lets a customer manage scenes. The
/// editor speaks in device/state terms – no group addresses are ever
/// exposed to the user. Each device selected into a scene gets a little
/// mini-controller (on/off switch, dimmer slider, setpoint…) and a
/// "Huidige stand overnemen" button that captures the live bus value.
class SceneEditorSheet extends ConsumerStatefulWidget {
  const SceneEditorSheet({
    super.key,
    required this.scenes,
    required this.scope,
    required this.config,
    this.roomId,
    this.initiallySelectedId,
  });

  final List<Scene> scenes;
  final SceneScope scope;
  final HouseConfig config;
  final String? roomId;
  final String? initiallySelectedId;

  @override
  ConsumerState<SceneEditorSheet> createState() => _SceneEditorSheetState();
}

class _SceneEditorSheetState extends ConsumerState<SceneEditorSheet> {
  /// Scene metadata keyed by scene id – we store the full draft separately
  /// so users can switch between scenes without losing edits.
  late final Map<String, SceneDraft> _drafts;
  late List<Scene> _scenes;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scenes = [...widget.scenes];
    _drafts = {
      for (final s in _scenes) s.id: SceneDraft.fromScene(s, widget.config),
    };
    _selectedId = widget.initiallySelectedId ??
        (_scenes.isNotEmpty ? _scenes.first.id : null);
  }

  SceneDraft? get _draft =>
      _selectedId == null ? null : _drafts[_selectedId];

  void _touch() => setState(() {});

  SceneEntry _liveSnapshot(SceneEntry entry) {
    if (entry is MediaEntry) {
      return entry.snapshotMedia(ref.read(mediaStateProvider)[entry.device.id]);
    }
    return entry.snapshot(ref.read(busProvider));
  }
  void _addScene() {
    final id = 'scn-${DateTime.now().millisecondsSinceEpoch}';
    final stub = Scene(
      id: id,
      name: 'Nieuwe Scene',
      icon: 'star',
      actions: const [],
    );
    setState(() {
      _scenes = [..._scenes, stub];
      _drafts[id] = SceneDraft(name: stub.name, icon: stub.icon, entries: []);
      _selectedId = id;
    });
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _scenes = _scenes.where((s) => s.id != id).toList();
      _drafts.remove(id);
      _selectedId = _scenes.isNotEmpty ? _scenes.first.id : null;
    });
  }

  Future<void> _addDevices() async {
    final draft = _draft;
    if (draft == null) return;
    final excluded = {for (final e in draft.entries) e.device.id};
    final picked = await pickDevicesForScene(
      context,
      config: widget.config,
      excludeIds: excluded,
    );
    if (picked == null || picked.isEmpty) return;
    final bus = ref.read(busProvider);
    setState(() {
      for (final d in picked) {
        final entry = d.defaultSceneEntry();
        if (entry == null) continue;
        draft.entries.add(
          entry is MediaEntry
              ? entry.snapshotMedia(ref.read(mediaStateProvider)[d.id])
              : entry.snapshot(bus),
        );
      }
    });
  }

  void _replaceEntry(int i, SceneEntry next) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      draft.entries[i] = next;
    });
  }

  void _removeEntry(int i) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => draft.entries.removeAt(i));
  }

  void _snapshotAll() {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      for (int i = 0; i < draft.entries.length; i++) {
        draft.entries[i] = _liveSnapshot(draft.entries[i]);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Fold drafts back into scene payloads.
      final out = <Scene>[];
      for (final s in _scenes) {
        final d = _drafts[s.id];
        if (d == null) {
          out.add(s);
          continue;
        }
        out.add(d.toScene(s.id));
      }
      final api = ref.read(sceneApiProvider);
      if (widget.scope == SceneScope.global) {
        await api.saveGlobal(out);
      } else if (widget.roomId != null) {
        await api.saveRoom(widget.roomId!, out);
      }
      ref.invalidate(configProvider);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LuxeColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          content: Text('Opslaan mislukt: $err'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Bounded height avoids Flexible + min Column layout loops (Flutter web).
    final sheetHeight = (mq.size.height * 0.92 - mq.viewInsets.bottom)
        .clamp(320.0, mq.size.height * 0.92);
    return SizedBox(
      height: sheetHeight,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: LuxeColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: LuxeShadows.lift,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHandle(),
              _buildHeader(),
              _buildScenePickerRail(),
              Divider(height: 1, color: LuxeColors.lineSoft),
              Expanded(child: _buildEditor()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: EdgeInsets.only(top: 10),
        child: Container(
          width: 48,
          height: 5,
          decoration: BoxDecoration(
            color: LuxeColors.inkFaint.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );

  Widget _buildHeader() => Padding(
        padding: EdgeInsets.fromLTRB(28, 16, 16, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.scope == SceneScope.global
                        ? 'SCENES · HOOFDPAGINA'
                        : 'SCENES · KAMER',
                    style: TextStyle(
                      color: LuxeColors.inkSoft,
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Beheer jouw sferen',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );

  static const _sceneChipHeight = 76.0;
  static const _sceneListHeight = 84.0;

  Widget _buildScenePickerRail() {
    final phone = context.isPhone;
    return ColoredBox(
      color: LuxeColors.surfaceDim.withValues(alpha: 0.55),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          phone ? 18 : 14,
          0,
          phone ? 36 : 28,
        ),
        child: SizedBox(
          height: _sceneListHeight,
          child: _buildSceneList(),
        ),
      ),
    );
  }

  Widget _buildSceneList() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _scenes.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        if (i == _scenes.length) return _addTile();
        final s = _scenes[i];
        final draft = _drafts[s.id];
        final name = draft?.name ?? s.name;
        final icon = draft?.icon ?? s.icon;
        final selected = s.id == _selectedId;
        return _chip(
          label: name,
          icon: sceneIconFor(icon),
          selected: selected,
          onTap: () => setState(() => _selectedId = s.id),
        );
      },
    );
  }

  static const _sceneChipShadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0C000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 160),
        width: 130,
        height: _sceneChipHeight,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? LuxeColors.ink : LuxeColors.surface,
          border: Border.all(color: LuxeColors.lineSoft),
          boxShadow: _sceneChipShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? LuxeColors.brassGlow : LuxeColors.ink),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? LuxeColors.onInk : LuxeColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile() => SizedBox(
        height: _sceneChipHeight,
        child: GestureDetector(
        onTap: _addScene,
        child: Container(
          width: 88,
          height: _sceneChipHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: LuxeColors.ink.withValues(alpha: 0.2),
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 22),
                SizedBox(height: 4),
                Text(
                  'NIEUW',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildEditor() {
    final draft = _draft;
    final phone = context.isPhone;
    final hPad = context.listHPad;
    if (draft == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Text('Nog geen scenes. Tik op Nieuw om te beginnen.'),
        ),
      );
    }
    final roomGroups = groupSceneEntriesByRoom(widget.config, draft.entries);
    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 22, hPad, 24),
      children: [
        _NameField(
          key: ValueKey('name-$_selectedId'),
          initial: draft.name,
          onChanged: (v) {
            draft.name = v;
            _touch();
          },
        ),
        const SizedBox(height: 18),
        _IconPicker(
          selected: draft.icon,
          onSelected: (name) {
            draft.icon = name;
            _touch();
          },
        ),
        SizedBox(height: 22),
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('APPARATEN IN DEZE SCENE', style: _kSectionStyle),
              if (draft.entries.isNotEmpty) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Huidige stand'),
                  onPressed: _snapshotAll,
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              Text('APPARATEN IN DEZE SCENE', style: _kSectionStyle),
              const Spacer(),
              if (draft.entries.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Huidige stand'),
                  onPressed: _snapshotAll,
                ),
            ],
          ),
        SizedBox(height: phone ? 10 : 6),
        if (draft.entries.isEmpty)
          _EmptyHint(onAdd: _addDevices)
        else ...[
          for (final group in roomGroups)
            SceneDeviceRoomSection(
              title: group.title,
              padding: EdgeInsets.zero,
              separateCards: true,
              children: [
                for (final i in group.indices)
                  _EntryCard(
                    key: ValueKey(
                        'entry-$_selectedId-${draft.entries[i].device.id}'),
                    entry: draft.entries[i],
                    embedded: true,
                    onChanged: (e) => _replaceEntry(i, e),
                    onRemove: () => _removeEntry(i),
                    onSnapshot: () =>
                        _replaceEntry(i, _liveSnapshot(draft.entries[i])),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          _AddDeviceButton(onTap: _addDevices),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          icon: Icon(Icons.delete_outline,
              size: 18, color: LuxeColors.danger),
          label: Text('Scene verwijderen',
              style: TextStyle(color: LuxeColors.danger)),
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: LuxeColors.onInk),
                    )
                  : const Text('Opslaan'),
            ),
          ),
        ],
      ),
    );
  }
}

final _kSectionStyle = TextStyle(
  fontSize: 11,
  letterSpacing: 2.0,
  fontWeight: FontWeight.w700,
  color: LuxeColors.inkSoft,
);

/* --------------------------- sub-widgets ------------------------------ */

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    this.embedded = false,
    required this.onChanged,
    required this.onRemove,
    required this.onSnapshot,
  });
  final SceneEntry entry;
  final bool embedded;
  final ValueChanged<SceneEntry> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final actions = [
      SceneEntryDelayToggleButton(
        delayMs: entry.delayMs,
        onChanged: (ms) => onChanged(entry.withDelayMs(ms)),
      ),
      IconButton(
        tooltip: 'Huidige stand overnemen',
        icon: Icon(Icons.download_rounded,
            size: 20, color: LuxeColors.inkSoft),
        visualDensity: VisualDensity.compact,
        onPressed: onSnapshot,
      ),
      IconButton(
        tooltip: 'Verwijderen',
        icon: const Icon(Icons.close_rounded, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: onRemove,
      ),
    ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (phone) ...[
          SceneEntryHeader(
            deviceName: entry.device.name,
            summary: entry.summary(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: SceneEntryHeader(
                  deviceName: entry.device.name,
                  summary: entry.summary(),
                ),
              ),
              ...actions,
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 6),
          child: SceneEntryControls(
            entry: entry,
            onChanged: onChanged,
          ),
        ),
      ],
    );

    if (embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
        child: body,
      );
    }

    return Container(
      margin: EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxeColors.lineSoft),
        boxShadow: LuxeShadows.soft,
      ),
      child: body,
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: LuxeColors.ink.withValues(alpha: 0.25),
            style: BorderStyle.solid,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18),
            SizedBox(width: 8),
            Text('Apparaten toevoegen',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                )),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: LuxeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nog geen apparaten',
              style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 6),
          Text(
            'Voeg lampen, zonwering, airco en andere apparaten toe. Zet ze op '
            'de stand die deze scene moet activeren — of gebruik “Huidige '
            'stand overnemen” om de huidige waarden over te nemen.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Apparaten toevoegen'),
            style: FilledButton.styleFrom(
              backgroundColor: LuxeColors.ink,
              foregroundColor: LuxeColors.onInk,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Naam van de scene',
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ICOON', style: _kSectionStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final name in kSceneIconPalette)
              GestureDetector(
                onTap: () => onSelected(name),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: name == selected
                        ? LuxeColors.ink
                        : LuxeColors.surface,
                    border: Border.all(
                      color: name == selected
                          ? LuxeColors.brass
                          : LuxeColors.line,
                    ),
                  ),
                  child: Icon(
                    sceneIconFor(name),
                    size: 20,
                    color:
                        name == selected ? LuxeColors.brassGlow : LuxeColors.ink,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
