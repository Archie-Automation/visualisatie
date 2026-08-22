import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../media_api.dart';
import '../models.dart';
import '../scene_api.dart';
import '../scene_entry.dart';
import '../theme.dart';
import 'responsive.dart';
import 'widgets/back_pill.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/glass_card.dart';
import 'widgets/scene_entry_tiles.dart';
import 'widgets/scene_icons.dart';

enum SceneScope { global, room }

enum _EditPane { overview, name, icon, devices }

/// Bottom sheet for one scene at a time (same chrome as the schedule editor).
class SceneEditorSheet extends ConsumerStatefulWidget {
  const SceneEditorSheet({
    super.key,
    required this.scenes,
    required this.scope,
    required this.config,
    this.roomId,
    this.initiallySelectedId,
    this.createNew = false,
  });

  final List<Scene> scenes;
  final SceneScope scope;
  final HouseConfig config;
  final String? roomId;
  final String? initiallySelectedId;
  final bool createNew;

  @override
  ConsumerState<SceneEditorSheet> createState() => _SceneEditorSheetState();
}

class _SceneEditorSheetState extends ConsumerState<SceneEditorSheet> {
  late SceneDraft _draft;
  late String _id;
  bool _saving = false;
  _EditPane _pane = _EditPane.overview;
  SceneDraft? _paneSnapshot;

  @override
  void initState() {
    super.initState();
    if (widget.createNew) {
      _id = 'scn-${DateTime.now().millisecondsSinceEpoch}';
      _draft = SceneDraft(name: 'Nieuwe Scene', icon: 'star', entries: []);
      return;
    }
    Scene? match;
    final want = widget.initiallySelectedId;
    if (want != null) {
      for (final s in widget.scenes) {
        if (s.id == want) {
          match = s;
          break;
        }
      }
    }
    match ??= widget.scenes.isEmpty ? null : widget.scenes.first;
    if (match == null) {
      _id = 'scn-${DateTime.now().millisecondsSinceEpoch}';
      _draft = SceneDraft(name: 'Nieuwe Scene', icon: 'star', entries: []);
      return;
    }
    _id = match.id;
    _draft = SceneDraft.fromScene(match, widget.config);
  }

  bool get _atSheetRoot => _pane == _EditPane.overview;

  bool get _readyToSave =>
      _draft.name.trim().isNotEmpty && _draft.entries.isNotEmpty;

  void _openPane(_EditPane pane) {
    setState(() {
      _paneSnapshot = _draft.copy();
      _pane = pane;
    });
  }

  void _leavePane({required bool revert}) {
    setState(() {
      if (revert && _paneSnapshot != null) {
        _draft = _paneSnapshot!;
      }
      _paneSnapshot = null;
      _pane = _EditPane.overview;
    });
  }

  String? _paneError(_EditPane pane) {
    switch (pane) {
      case _EditPane.overview:
        return null;
      case _EditPane.name:
        if (_draft.name.trim().isEmpty) return 'Vul een naam in.';
        return null;
      case _EditPane.icon:
        return null;
      case _EditPane.devices:
        if (_draft.entries.isEmpty) return 'Kies minstens één apparaat.';
        return null;
    }
  }

  void _savePane() {
    final err = _paneError(_pane);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LuxeColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          content: Text(err),
        ),
      );
      return;
    }
    setState(() {
      _paneSnapshot = null;
      _pane = _EditPane.overview;
    });
  }

  SceneEntry _liveSnapshot(SceneEntry entry) {
    if (entry is MediaEntry) {
      return entry.snapshotMedia(ref.read(mediaStateProvider)[entry.device.id]);
    }
    return entry.snapshot(ref.read(busProvider));
  }

  Future<void> _addDevices() async {
    final excluded = {for (final e in _draft.entries) e.device.id};
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
        _draft.entries.add(
          entry is MediaEntry
              ? entry.snapshotMedia(ref.read(mediaStateProvider)[d.id])
              : entry.snapshot(bus),
        );
      }
    });
  }

  Future<void> _delete() async {
    if (widget.createNew) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final out = widget.scenes.where((s) => s.id != _id).toList();
      await _persist(out);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (err) {
      if (!mounted) return;
      _showSaveError(err);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_readyToSave) return;
    setState(() => _saving = true);
    try {
      final edited = _draft.toScene(_id);
      final out = [...widget.scenes];
      final idx = out.indexWhere((s) => s.id == _id);
      if (idx >= 0) {
        out[idx] = edited;
      } else {
        out.add(edited);
      }
      await _persist(out);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (err) {
      if (!mounted) return;
      _showSaveError(err);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persist(List<Scene> out) async {
    final api = ref.read(sceneApiProvider);
    if (widget.scope == SceneScope.global) {
      await api.saveGlobal(out);
    } else if (widget.roomId != null) {
      await api.saveRoom(widget.roomId!, out);
    }
    ref.invalidate(configProvider);
  }

  void _showSaveError(Object err) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: LuxeColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        content: Text('Opslaan mislukt: $err'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sheetHeight = (mq.size.height * 0.92 - mq.viewInsets.bottom)
        .clamp(320.0, mq.size.height * 0.92);
    return PopScope(
      canPop: _atSheetRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leavePane(revert: true);
      },
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: LuxeColors.cream,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: LuxeShadows.lift,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _header(),
                Expanded(child: _editor()),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final name = _draft.name.trim();
    final overviewTitle = name.isNotEmpty ? name : 'Scene';
    final (title, infoTitle, infoBody) = switch (_pane) {
      _EditPane.overview => (
          overviewTitle,
          'Scene',
          widget.scope == SceneScope.global
              ? 'Overkoepelende scene voor het hele huis. Naam, icoon en apparaten moeten ingevuld zijn om op te slaan.'
              : 'Kamer-scene. Naam, icoon en apparaten moeten ingevuld zijn om op te slaan.',
        ),
      _EditPane.name => (
          'Naam',
          'Naam',
          'Hoe deze scene in de lijst heet.',
        ),
      _EditPane.icon => (
          'Icoon',
          'Icoon',
          'Kies een icoon zodat de scene herkenbaar is in de strip.',
        ),
      _EditPane.devices => (
          'Apparaten',
          'Apparaten',
          'Zet elk apparaat op de stand die deze scene moet activeren. '
              'Optioneel: wachttijd vóór een apparaat, of huidige stand overnemen.',
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: SizedBox(
        height: HeaderIconButton.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: HeaderIconButton.size + 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: LuxeColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: LuxeInfoIconButton(title: infoTitle, body: infoBody),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: BackPill(
                onTap: () {
                  if (_atSheetRoot) {
                    Navigator.of(context).pop();
                    return;
                  }
                  _leavePane(revert: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor() {
    return switch (_pane) {
      _EditPane.overview => _overview(),
      _EditPane.name => _namePane(),
      _EditPane.icon => _iconPane(),
      _EditPane.devices => _devicesPane(),
    };
  }

  Widget _overview() {
    final n = _draft.entries.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      children: [
        GlassCard(
          radius: 16,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingRow(
                title: 'Naam',
                subtitle: _draft.name.trim().isEmpty
                    ? 'Geen naam'
                    : _draft.name.trim(),
                done: _draft.name.trim().isNotEmpty,
                onTap: () => _openPane(_EditPane.name),
              ),
              Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              _SettingRow(
                title: 'Icoon',
                subtitle: _draft.icon == null || _draft.icon!.isEmpty
                    ? 'Geen icoon'
                    : 'Gekozen',
                leading: Icon(
                  sceneIconFor(_draft.icon),
                  size: 22,
                  color: LuxeColors.ink,
                ),
                done: _draft.icon != null && _draft.icon!.isNotEmpty,
                onTap: () => _openPane(_EditPane.icon),
              ),
              Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              _SettingRow(
                title: 'Apparaten',
                subtitle: n == 0
                    ? 'Geen apparaten'
                    : (n == 1 ? '1 apparaat' : '$n apparaten'),
                done: n > 0,
                onTap: () => _openPane(_EditPane.devices),
              ),
            ],
          ),
        ),
        if (!widget.createNew) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            icon:
                Icon(Icons.delete_outline, size: 18, color: LuxeColors.danger),
            label: Text(
              'Scene verwijderen',
              style: TextStyle(color: LuxeColors.danger),
            ),
            onPressed: _saving ? null : _delete,
          ),
        ],
      ],
    );
  }

  Widget _namePane() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        _NameField(
          key: ValueKey('name-$_id'),
          initial: _draft.name,
          onChanged: (v) => setState(() => _draft.name = v),
        ),
      ],
    );
  }

  Widget _iconPane() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        _IconPicker(
          selected: _draft.icon,
          onSelected: (name) => setState(() => _draft.icon = name),
        ),
      ],
    );
  }

  Widget _devicesPane() {
    final phone = context.isPhone;
    final roomGroups = groupSceneEntriesByRoom(widget.config, _draft.entries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      children: [
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('APPARATEN IN DEZE SCENE', style: _kSectionStyle),
              if (_draft.entries.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Huidige stand'),
                  onPressed: () {
                    setState(() {
                      for (int i = 0; i < _draft.entries.length; i++) {
                        _draft.entries[i] = _liveSnapshot(_draft.entries[i]);
                      }
                    });
                  },
                ),
            ],
          )
        else
          Row(
            children: [
              Text('APPARATEN IN DEZE SCENE', style: _kSectionStyle),
              const Spacer(),
              if (_draft.entries.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Huidige stand'),
                  onPressed: () {
                    setState(() {
                      for (int i = 0; i < _draft.entries.length; i++) {
                        _draft.entries[i] = _liveSnapshot(_draft.entries[i]);
                      }
                    });
                  },
                ),
            ],
          ),
        SizedBox(height: phone ? 10 : 6),
        if (_draft.entries.isEmpty)
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
                    key: ValueKey('entry-$_id-${_draft.entries[i].device.id}'),
                    entry: _draft.entries[i],
                    embedded: true,
                    onChanged: (e) => setState(() => _draft.entries[i] = e),
                    onRemove: () => setState(() => _draft.entries.removeAt(i)),
                    onSnapshot: () => setState(
                      () => _draft.entries[i] =
                          _liveSnapshot(_draft.entries[i]),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          _AddDeviceButton(onTap: _addDevices),
        ],
      ],
    );
  }

  Widget _footer() {
    if (_pane != _EditPane.overview) {
      return _footerButtons(
        cancelLabel: 'Annuleren',
        onCancel: _saving ? null : () => _leavePane(revert: true),
        saveLabel: 'Opslaan',
        onSave: _saving ? null : _savePane,
      );
    }
    return _footerButtons(
      cancelLabel: 'Annuleren',
      onCancel: _saving ? null : () => Navigator.of(context).pop(),
      saveLabel: 'Scene opslaan',
      onSave: (_saving || !_readyToSave) ? null : _save,
    );
  }

  Widget _footerButtons({
    required String cancelLabel,
    required VoidCallback? onCancel,
    required String saveLabel,
    required VoidCallback? onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: Text(cancelLabel),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                disabledBackgroundColor:
                    LuxeColors.ink.withValues(alpha: 0.28),
                disabledForegroundColor:
                    LuxeColors.onInk.withValues(alpha: 0.7),
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: _saving && _pane == _EditPane.overview
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LuxeColors.onInk,
                      ),
                    )
                  : Text(saveLabel),
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

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.done = false,
    this.leading,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool done;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: LuxeColors.brassDeep,
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: LuxeColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

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
        icon: Icon(Icons.download_rounded, size: 20, color: LuxeColors.inkSoft),
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
      margin: const EdgeInsets.only(top: 10),
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: LuxeColors.ink.withValues(alpha: 0.25),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18),
            SizedBox(width: 8),
            Text(
              'Apparaten toevoegen',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
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
      margin: const EdgeInsets.only(top: 8),
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
          const SizedBox(height: 6),
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
        hintText: 'Naam van de scene',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: LuxeColors.line),
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
    return Wrap(
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
                color: name == selected ? LuxeColors.ink : LuxeColors.surface,
                border: Border.all(
                  color: name == selected ? LuxeColors.brass : LuxeColors.line,
                ),
              ),
              child: Icon(
                sceneIconFor(name),
                size: 20,
                color: name == selected ? LuxeColors.brassGlow : LuxeColors.ink,
              ),
            ),
          ),
      ],
    );
  }
}
