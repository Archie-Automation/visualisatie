import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../schedule_api.dart';
import '../scene_entry.dart';
import '../theme.dart';
import '../theme_auto_schedule.dart';
import 'widgets/scene_entry_tiles.dart';

/// Bottom sheet for creating and editing time/astro schedules. Uses the
/// same device-first approach as the scene editor: no group addresses
/// surface to the end user.
class ScheduleEditorSheet extends ConsumerStatefulWidget {
  const ScheduleEditorSheet({
    super.key,
    required this.schedules,
    required this.config,
    this.initiallySelectedId,
    this.lockedIds = const {},
    this.persistHouseSchedules = true,
    this.createNew = false,
  });

  final List<Schedule> schedules;
  final HouseConfig config;
  final String? initiallySelectedId;
  /// Non-deletable entries (tablet Auto weergave-schema).
  final Set<String> lockedIds;
  /// When false, only theme schedules are written (no PUT /schedules).
  final bool persistHouseSchedules;
  /// Open a blank schedule instead of picking from the list.
  final bool createNew;

  @override
  ConsumerState<ScheduleEditorSheet> createState() =>
      _ScheduleEditorSheetState();
}

/// Editor-local mutable draft. Kept out of the public [Schedule] model
/// because our JSON model is immutable and building a new copy per
/// keystroke would be both slow and fiddly.
class _Draft {
  String name;
  bool enabled;
  _TriggerKind kind;

  // Time trigger
  TimeOfDay time;
  List<bool> days;

  // Astro trigger
  AstroEvent astroEvent;
  int offsetMin;
  ScheduleGuard? notBefore;
  ScheduleGuard? notAfter;

  // Action
  _ActionKind actionKind;
  String? sceneId;
  List<SceneEntry> entries;

  _Draft({
    required this.name,
    required this.enabled,
    required this.kind,
    required this.time,
    required this.days,
    required this.astroEvent,
    required this.offsetMin,
    required this.actionKind,
    required this.entries,
  });

  static _Draft fresh() => _Draft(
        name: 'Nieuw tijdschema',
        enabled: true,
        kind: _TriggerKind.time,
        time: const TimeOfDay(hour: 18, minute: 0),
        days: List<bool>.from(kAllDays),
        astroEvent: AstroEvent.sunset,
        offsetMin: 0,
        actionKind: _ActionKind.scene,
        entries: [],
      );

  static _Draft fromSchedule(Schedule s, HouseConfig cfg) {
    final t = s.trigger;
    final a = s.action;
    final draft = fresh();
    draft
      ..name = s.name
      ..enabled = s.enabled;
    if (t is TimeTrigger) {
      draft
        ..kind = _TriggerKind.time
        ..time = _parseTimeOfDay(t.time)
        ..days = [...t.days];
    } else if (t is AstroTrigger) {
      draft
        ..kind = _TriggerKind.astro
        ..astroEvent = t.event
        ..offsetMin = t.offsetMin
        ..days = [...t.days]
        ..notBefore = t.notBefore
        ..notAfter = t.notAfter;
    }
    if (a is ScheduleSceneAction) {
      draft
        ..actionKind = _ActionKind.scene
        ..sceneId = a.sceneId;
    } else if (a is ScheduleActionsAction) {
      draft
        ..actionKind = _ActionKind.devices
        ..entries = _reconstructEntries(a.actions, cfg);
    }
    return draft;
  }

  Schedule toSchedule(String id) {
    final ScheduleTrigger trigger;
    if (kind == _TriggerKind.time) {
      trigger = TimeTrigger(time: _hhmm(time), days: List<bool>.from(days));
    } else {
      trigger = AstroTrigger(
        event: astroEvent,
        offsetMin: offsetMin,
        days: List<bool>.from(days),
        notBefore: notBefore,
        notAfter: notAfter,
      );
    }
    final ScheduleAction action;
    if (isThemeScheduleId(id)) {
      action = ScheduleThemeAction(toLight: id == kThemeLightOnId);
    } else if (actionKind == _ActionKind.scene) {
      action = ScheduleSceneAction(sceneId: sceneId ?? '');
    } else {
      final acts = <SceneAction>[];
      for (final e in entries) {
        acts.addAll(e.toActions());
      }
      action = ScheduleActionsAction(actions: acts);
    }
    return Schedule(
      id: id,
      name: name.trim().isEmpty ? 'Tijdschema' : name.trim(),
      enabled: enabled,
      trigger: trigger,
      action: action,
    );
  }

  static List<SceneEntry> _reconstructEntries(
      List<SceneAction> actions, HouseConfig cfg) {
    // Reuse the same GA-matching logic the scene editor uses.
    final devices = cfg.allDevices.toList();
    final remaining = [...actions];
    final out = <SceneEntry>[];
    for (final d in devices) {
      final gas = deviceGroupAddresses(d);
      final mine = remaining.where((a) => gas.contains(a.ga)).toList();
      if (mine.isEmpty) continue;
      final entry = tryParseEntry(d, mine);
      if (entry == null) continue;
      out.add(entry);
      remaining.removeWhere((a) => gas.contains(a.ga));
    }
    return out;
  }
}

enum _TriggerKind { time, astro }
enum _ActionKind { scene, devices }

class _ScheduleEditorSheetState
    extends ConsumerState<ScheduleEditorSheet> {
  late List<Schedule> _schedules;
  late Map<String, _Draft> _drafts;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _schedules = [...widget.schedules];
    _drafts = {
      for (final s in _schedules) s.id: _Draft.fromSchedule(s, widget.config),
    };
    if (widget.createNew) {
      final id = 'sch-${DateTime.now().millisecondsSinceEpoch}';
      _schedules = [
        ..._schedules,
        Schedule(
          id: id,
          name: 'Nieuw tijdschema',
          enabled: true,
          trigger: TimeTrigger(
              time: '18:00', days: List<bool>.from(kAllDays)),
          action: const ScheduleSceneAction(sceneId: ''),
        ),
      ];
      _drafts[id] = _Draft.fresh();
      _selectedId = id;
    } else {
      _selectedId = widget.initiallySelectedId ??
          (_schedules.isNotEmpty ? _schedules.first.id : null);
    }
  }

  _Draft? get _draft =>
      _selectedId == null ? null : _drafts[_selectedId];

  Future<void> _deleteSelected() async {
    final id = _selectedId;
    if (id == null || widget.lockedIds.contains(id)) return;
    _schedules = _schedules.where((s) => s.id != id).toList();
    _drafts.remove(id);
    _selectedId = null;
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final out = <Schedule>[
        for (final s in _schedules)
          _drafts[s.id]?.toSchedule(s.id) ?? s,
      ];
      final themeOnes =
          out.where((s) => isThemeScheduleId(s.id)).toList(growable: false);
      final houseOnes =
          out.where((s) => !isThemeScheduleId(s.id)).toList(growable: false);

      if (themeOnes.isNotEmpty) {
        final current = ref.read(themeAutoScheduleProvider);
        await ref
            .read(themeAutoScheduleProvider.notifier)
            .save(current.mergeFromSchedules(themeOnes));
      }
      if (widget.persistHouseSchedules) {
        await ref.read(scheduleApiProvider).save(houseOnes);
      }
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
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: LuxeColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: LuxeShadows.lift,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              _header(),
              const Divider(height: 1),
              Flexible(child: _editor()),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() => Padding(
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

  Widget _header() {
    final name = _draft?.name.trim();
    final title = (name != null && name.isNotEmpty) ? name : 'Tijdschema';
    return Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TIJDSCHEMA',
                      style: TextStyle(
                        color: LuxeColors.inkSoft,
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium,
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
  }

  Widget _editor() {
    final d = _draft;
    if (d == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Text('Dit tijdschema is verwijderd.'),
        ),
      );
    }
    final locked = widget.lockedIds.contains(_selectedId);
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _NameField(
          key: ValueKey('name-$_selectedId'),
          initial: d.name,
          onChanged: (v) => setState(() => d.name = v),
        ),
        const SizedBox(height: 18),
        _TriggerTypeSelector(
          value: d.kind,
          onChanged: (v) => setState(() => d.kind = v),
        ),
        const SizedBox(height: 14),
        if (d.kind == _TriggerKind.time)
          _TimeTriggerEditor(draft: d, onTouch: () => setState(() {}))
        else
          _AstroTriggerEditor(draft: d, onTouch: () => setState(() {})),
        const SizedBox(height: 18),
        Text('ACTIE', style: _kSectionStyle),
        const SizedBox(height: 10),
        if (locked)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: LuxeColors.surface.withValues(alpha: 0.8),
              border: Border.all(color: LuxeColors.lineSoft),
            ),
            child: Text(
              _selectedId == kThemeLightOnId
                  ? 'Weergave â†’ licht thema'
                  : 'Weergave â†’ donker thema',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else ...[
          _ActionKindSelector(
            value: d.actionKind,
            onChanged: (v) => setState(() => d.actionKind = v),
          ),
          const SizedBox(height: 12),
          if (d.actionKind == _ActionKind.scene)
            _ScenePicker(
              config: widget.config,
              value: d.sceneId,
              onChanged: (v) => setState(() => d.sceneId = v),
            )
          else
            _DevicesActionEditor(
              draft: d,
              config: widget.config,
              onTouch: () => setState(() {}),
            ),
        ],
        if (!locked) ...[
          const SizedBox(height: 22),
          TextButton.icon(
            icon: Icon(Icons.delete_outline,
                size: 18, color: LuxeColors.danger),
            label: Text('Tijdschema verwijderen',
                style: TextStyle(color: LuxeColors.danger)),
            onPressed: _deleteSelected,
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            'Vast weergave-schema â€” niet verwijderbaar. Alleen zichtbaar '
            'als Weergave op Auto staat.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ],
      ],
    );
  }

  Widget _footer() {
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

/* --------------------------- sub-widgets ------------------------------ */

final _kSectionStyle = TextStyle(
  fontSize: 11,
  letterSpacing: 2.0,
  fontWeight: FontWeight.w700,
  color: LuxeColors.inkSoft,
);

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
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Naam',
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

class _TriggerTypeSelector extends StatelessWidget {
  const _TriggerTypeSelector({required this.value, required this.onChanged});
  final _TriggerKind value;
  final ValueChanged<_TriggerKind> onChanged;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TriggerKind>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: _TriggerKind.time,
          icon: Icon(Icons.access_time_rounded, size: 16),
          label: Text('Tijd'),
        ),
        ButtonSegment(
          value: _TriggerKind.astro,
          icon: Icon(Icons.wb_twilight, size: 16),
          label: Text('Zon'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _TimeTriggerEditor extends StatelessWidget {
  const _TimeTriggerEditor({required this.draft, required this.onTouch});
  final _Draft draft;
  final VoidCallback onTouch;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TIJDSTIP', style: _kSectionStyle),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: draft.time,
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx)
                    .copyWith(alwaysUse24HourFormat: true),
                child: child ?? const SizedBox.shrink(),
              ),
            );
            if (picked != null) {
              draft.time = picked;
              onTouch();
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: LuxeColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuxeColors.lineSoft),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: LuxeColors.inkSoft),
                SizedBox(width: 12),
                Text(
                  _hhmm(draft.time),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: LuxeColors.ink),
                ),
                Spacer(),
                Icon(Icons.chevron_right, color: LuxeColors.inkSoft),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _WeekdayRow(days: draft.days, onTouch: onTouch),
      ],
    );
  }
}

class _AstroTriggerEditor extends StatelessWidget {
  const _AstroTriggerEditor({required this.draft, required this.onTouch});
  final _Draft draft;
  final VoidCallback onTouch;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ZON-EVENEMENT', style: _kSectionStyle),
        const SizedBox(height: 8),
        SegmentedButton<AstroEvent>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: AstroEvent.sunrise,
              icon: Icon(Icons.wb_twilight, size: 16),
              label: Text('Opkomst'),
            ),
            ButtonSegment(
              value: AstroEvent.sunset,
              icon: Icon(Icons.nightlight_round, size: 16),
              label: Text('Ondergang'),
            ),
          ],
          selected: {draft.astroEvent},
          onSelectionChanged: (s) {
            draft.astroEvent = s.first;
            onTouch();
          },
        ),
        const SizedBox(height: 16),
        _OffsetSlider(draft: draft, onTouch: onTouch),
        const SizedBox(height: 16),
        _WeekdayRow(days: draft.days, onTouch: onTouch),
        const SizedBox(height: 16),
        Text('BEGRENZING (OPTIONEEL)', style: _kSectionStyle),
        const SizedBox(height: 6),
        Text(
          'Voer alleen uit binnen een tijdvenster. Bv. "bij zonsondergang, '
          'maar niet voor 18:00".',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        _GuardRow(
          label: 'Niet voor',
          guard: draft.notBefore,
          onChanged: (g) {
            draft.notBefore = g;
            onTouch();
          },
        ),
        const SizedBox(height: 8),
        _GuardRow(
          label: 'Niet na',
          guard: draft.notAfter,
          onChanged: (g) {
            draft.notAfter = g;
            onTouch();
          },
        ),
      ],
    );
  }
}

class _OffsetSlider extends StatelessWidget {
  const _OffsetSlider({required this.draft, required this.onTouch});
  final _Draft draft;
  final VoidCallback onTouch;
  @override
  Widget build(BuildContext context) {
    final off = draft.offsetMin.clamp(-240, 240);
    final label = off == 0
        ? 'exact'
        : off > 0
            ? '$off min na'
            : '${-off} min voor';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('VERSCHUIVING', style: _kSectionStyle),
            const Spacer(),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: LuxeColors.ink,
            inactiveTrackColor: LuxeColors.line,
            thumbColor: LuxeColors.brass,
          ),
          child: Slider(
            value: off.toDouble(),
            min: -240,
            max: 240,
            divisions: 96, // 5-minute steps
            onChanged: (v) {
              draft.offsetMin = v.round();
              onTouch();
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.days, required this.onTouch});
  final List<bool> days;
  final VoidCallback onTouch;
  @override
  Widget build(BuildContext context) {
    const names = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DAGEN', style: _kSectionStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
                  child: GestureDetector(
                    onTap: () {
                      days[i] = !days[i];
                      onTouch();
                    },
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: days[i]
                            ? LuxeColors.ink
                            : LuxeColors.surface,
                        border: Border.all(
                          color: days[i]
                              ? LuxeColors.ink
                              : LuxeColors.line,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        names[i],
                        style: TextStyle(
                          color: days[i]
                              ? LuxeColors.brassGlow
                              : LuxeColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _GuardRow extends StatelessWidget {
  const _GuardRow({
    required this.label,
    required this.guard,
    required this.onChanged,
  });
  final String label;
  final ScheduleGuard? guard;
  final ValueChanged<ScheduleGuard?> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = guard;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: _guardBody(context, g),
          ),
          if (g != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }

  Widget _guardBody(BuildContext context, ScheduleGuard? g) {
    if (g == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          tooltip: 'Kies begrenzing',
          offset: const Offset(0, 40),
          onSelected: (v) {
            if (v == 'time') {
              onChanged(const TimeGuard(time: '18:00'));
            } else if (v == 'sunrise') {
              onChanged(const AstroGuard(event: AstroEvent.sunrise));
            } else if (v == 'sunset') {
              onChanged(const AstroGuard(event: AstroEvent.sunset));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'time', child: Text('Vaste tijd')),
            PopupMenuItem(value: 'sunrise', child: Text('Zonsopkomst')),
            PopupMenuItem(value: 'sunset', child: Text('Zonsondergang')),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Geen â€” tik om toe te voegen',
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LuxeColors.brassDeep,
                      ),
            ),
          ),
        ),
      );
    }
    if (g is TimeGuard) {
      return InkWell(
        onTap: () async {
          final parts = g.time.split(':');
          final initial = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
          );
          final picked = await showTimePicker(
            context: context,
            initialTime: initial,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(alwaysUse24HourFormat: true),
              child: child ?? const SizedBox.shrink(),
            ),
          );
          if (picked != null) {
            onChanged(TimeGuard(time: _hhmm(picked)));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 8),
              Text(g.time,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    }
    g as AstroGuard;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            g.event == AstroEvent.sunrise
                ? Icons.wb_twilight
                : Icons.nightlight_round,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(g.event.label,
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ActionKindSelector extends StatelessWidget {
  const _ActionKindSelector({required this.value, required this.onChanged});
  final _ActionKind value;
  final ValueChanged<_ActionKind> onChanged;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ActionKind>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: _ActionKind.scene,
          icon: Icon(Icons.auto_awesome, size: 16),
          label: Text('Scene'),
        ),
        ButtonSegment(
          value: _ActionKind.devices,
          icon: Icon(Icons.lightbulb_outline, size: 16),
          label: Text('Apparaten'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _ScenePicker extends StatelessWidget {
  const _ScenePicker({
    required this.config,
    required this.value,
    required this.onChanged,
  });
  final HouseConfig config;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[];
    for (final s in config.scenes) {
      items.add(DropdownMenuItem(value: s.id, child: Text(s.name)));
    }
    for (final f in config.floors) {
      for (final r in f.rooms) {
        for (final s in r.scenes) {
          items.add(
            DropdownMenuItem(
              value: s.id,
              child: Text('${s.name}  Â·  ${r.name}'),
            ),
          );
        }
      }
    }
    if (items.isEmpty) {
      return Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LuxeColors.brass.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuxeColors.brass.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          'Er zijn nog geen scenes. Maak eerst een scene aan '
          'voordat je hem via een tijdschema kunt gebruiken.',
          style: TextStyle(color: LuxeColors.inkSoft, fontSize: 12),
        ),
      );
    }
    final current = items.any((i) => i.value == value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      items: items,
      decoration: InputDecoration(
        labelText: 'Scene',
        filled: true,
        fillColor: LuxeColors.surface.withValues(alpha: 0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _DevicesActionEditor extends ConsumerStatefulWidget {
  const _DevicesActionEditor({
    required this.draft,
    required this.config,
    required this.onTouch,
  });
  final _Draft draft;
  final HouseConfig config;
  final VoidCallback onTouch;

  @override
  ConsumerState<_DevicesActionEditor> createState() =>
      _DevicesActionEditorState();
}

class _DevicesActionEditorState
    extends ConsumerState<_DevicesActionEditor> {
  Future<void> _pick() async {
    final excluded = {for (final e in widget.draft.entries) e.device.id};
    final picked = await pickDevicesForScene(
      context,
      config: widget.config,
      excludeIds: excluded,
    );
    if (picked == null || picked.isEmpty) return;
    final bus = ref.read(busProvider);
    for (final d in picked) {
      final entry = d.defaultSceneEntry();
      if (entry == null) continue;
      widget.draft.entries.add(entry.snapshot(bus));
    }
    widget.onTouch();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.draft.entries;
    if (entries.isEmpty) {
      return Container(
        margin: EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(
          color: LuxeColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LuxeColors.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nog geen apparaten',
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 6),
            Text(
              'Kies de apparaten die dit schema moet aansturen en zet ze op '
              'de gewenste stand.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Apparaten kiezen'),
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          _DeviceEntryTile(
            entry: entries[i],
            locationLabel:
                widget.config.locationLabelForDevice(entries[i].device.id),
            onChanged: (e) {
              entries[i] = e;
              widget.onTouch();
            },
            onRemove: () {
              entries.removeAt(i);
              widget.onTouch();
            },
            onSnapshot: () {
              final bus = ref.read(busProvider);
              entries[i] = entries[i].snapshot(bus);
              widget.onTouch();
            },
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Apparaten toevoegen'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

class _DeviceEntryTile extends StatelessWidget {
  const _DeviceEntryTile({
    required this.entry,
    this.locationLabel,
    required this.onChanged,
    required this.onRemove,
    required this.onSnapshot,
  });

  final SceneEntry entry;
  final String? locationLabel;
  final ValueChanged<SceneEntry> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      decoration: BoxDecoration(
        color: LuxeColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SceneEntryHeader(
                  deviceName: entry.device.name,
                  summary: entry.summary(),
                  locationLabel: locationLabel,
                ),
              ),
              SceneEntryDelayToggleButton(
                delayMs: entry.delayMs,
                onChanged: (ms) => onChanged(entry.withDelayMs(ms)),
              ),
              IconButton(
                tooltip: 'Huidige stand overnemen',
                icon: const Icon(Icons.download_rounded, size: 20),
                onPressed: onSnapshot,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: onRemove,
              ),
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
      ),
    );
  }
}

/* ------------------------------ helpers ------------------------------- */

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _parseTimeOfDay(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
  );
}
