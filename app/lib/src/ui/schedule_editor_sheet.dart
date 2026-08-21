import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../schedule_api.dart';
import '../scene_entry.dart';
import '../theme.dart';
import '../theme_auto_schedule.dart';
import 'widgets/back_pill.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/glass_card.dart';
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
enum _EditPane { overview, name, when, action }

class _ScheduleEditorSheetState
    extends ConsumerState<ScheduleEditorSheet> {
  late Map<String, _Draft> _drafts;
  String? _selectedId;
  bool _saving = false;
  _EditPane _pane = _EditPane.overview;

  @override
  void initState() {
    super.initState();
    if (widget.createNew) {
      final id = 'sch-${DateTime.now().millisecondsSinceEpoch}';
      _drafts = {id: _Draft.fresh()};
      _selectedId = id;
      return;
    }
    Schedule? match;
    final want = widget.initiallySelectedId;
    if (want != null) {
      for (final s in widget.schedules) {
        if (s.id == want) {
          match = s;
          break;
        }
      }
    }
    match ??= widget.schedules.isEmpty ? null : widget.schedules.first;
    if (match == null) {
      _drafts = {};
      _selectedId = null;
      return;
    }
    _drafts = {match.id: _Draft.fromSchedule(match, widget.config)};
    _selectedId = match.id;
    if (widget.lockedIds.contains(match.id)) {
      _pane = _EditPane.when;
    }
  }

  _Draft? get _draft =>
      _selectedId == null ? null : _drafts[_selectedId];

  List<Schedule> _houseSchedulesFromServer() {
    final fromProvider = ref.read(schedulesProvider).value;
    final source = fromProvider ?? widget.schedules;
    return [
      for (final s in source)
        if (!isThemeScheduleId(s.id)) s,
    ];
  }

  Future<void> _deleteSelected() async {
    final id = _selectedId;
    if (id == null || widget.lockedIds.contains(id)) return;
    if (isThemeScheduleId(id)) return;
    setState(() => _saving = true);
    try {
      if (widget.persistHouseSchedules) {
        await ref.read(scheduleApiProvider).save(
              _houseSchedulesFromServer().where((s) => s.id != id).toList(),
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop(<Schedule>[]);
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

  Future<void> _save() async {
    final id = _selectedId;
    final draft = _draft;
    if (id == null || draft == null) return;
    setState(() => _saving = true);
    try {
      final edited = draft.toSchedule(id);
      if (isThemeScheduleId(id)) {
        final current = ref.read(themeAutoScheduleProvider);
        await ref
            .read(themeAutoScheduleProvider.notifier)
            .save(current.mergeFromSchedules([edited]));
      } else if (widget.persistHouseSchedules) {
        final existing = _houseSchedulesFromServer();
        final idx = existing.indexWhere((s) => s.id == id);
        final next = [...existing];
        if (idx >= 0) {
          next[idx] = edited;
        } else {
          next.add(edited);
        }
        await ref.read(scheduleApiProvider).save(next);
      }
      if (!mounted) return;
      Navigator.of(context).pop([edited]);
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

  bool get _themeLocked => widget.lockedIds.contains(_selectedId);

  bool get _atSheetRoot =>
      _pane == _EditPane.overview ||
      (_themeLocked && _pane == _EditPane.when);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: _atSheetRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _pane = _EditPane.overview);
      },
      child: Padding(
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
                _header(),
                Flexible(child: _editor()),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final d = _draft;
    final name = d?.name.trim();
    final overviewTitle =
        (name != null && name.isNotEmpty) ? name : 'Tijdschema';
    final locked = _themeLocked;
    final (title, infoTitle, infoBody) = switch (_pane) {
      _EditPane.overview => (
          overviewTitle,
          'Tijdschema',
          'Naam, wanneer het loopt, en wat er gebeurt. Tik een onderdeel aan om het in te stellen.',
        ),
      _EditPane.name => (
          'Naam',
          'Naam',
          'Hoe dit tijdschema in de lijst heet.',
        ),
      _EditPane.when => (
          'Wanneer',
          locked ? 'Weergave' : 'Wanneer',
          locked
              ? 'Hier kun je alleen het tijdstip aanpassen. '
                  'Naam en actie (licht of donker) staan vast.'
              : 'Tijd is een vast tijdstip. Zon volgt zonsopkomst of zonsondergang.\n\n'
                  'Verschuiving: minuten voor of na het zon-event.\n'
                  'Dagen: op welke weekdagen het mag lopen.\n'
                  'Begrenzing: optioneel venster, bijvoorbeeld niet voor 18:00.',
        ),
      _EditPane.action => (
          'Actie',
          'Actie',
          'Kies een bestaande scene, of stel apparaten hier direct in.',
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
                  setState(() => _pane = _EditPane.overview);
                },
              ),
            ),
          ],
        ),
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
    return switch (_pane) {
      _EditPane.overview => _overview(d),
      _EditPane.name => _namePane(d),
      _EditPane.when => _whenPane(d),
      _EditPane.action => _actionPane(d),
    };
  }

  Widget _overview(_Draft d) {
    final locked = _themeLocked;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      children: [
        GlassCard(
          radius: 16,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (!locked) ...[
                _SettingRow(
                  title: 'Naam',
                  subtitle: _nameSummary(d),
                  onTap: () => setState(() => _pane = _EditPane.name),
                ),
                Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
              ],
              _SettingRow(
                title: 'Wanneer',
                subtitle: _whenSummary(d),
                onTap: () => setState(() => _pane = _EditPane.when),
              ),
              if (!locked) ...[
                Divider(height: 1, indent: 16, color: LuxeColors.lineSoft),
                _SettingRow(
                  title: 'Actie',
                  subtitle: _actionSummary(d, locked: locked),
                  onTap: () => setState(() => _pane = _EditPane.action),
                ),
              ],
            ],
          ),
        ),
        if (!locked) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            icon: Icon(Icons.delete_outline,
                size: 18, color: LuxeColors.danger),
            label: Text('Tijdschema verwijderen',
                style: TextStyle(color: LuxeColors.danger)),
            onPressed: _deleteSelected,
          ),
        ],
      ],
    );
  }

  Widget _namePane(_Draft d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        _NameField(
          key: ValueKey('name-$_selectedId'),
          initial: d.name,
          onChanged: (v) => setState(() => d.name = v),
        ),
      ],
    );
  }

  Widget _whenPane(_Draft d) {
    final touch = () => setState(() {});
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      children: [
        _TriggerTypeSelector(
          value: d.kind,
          onChanged: (v) => setState(() => d.kind = v),
        ),
        const SizedBox(height: 14),
        if (d.kind == _TriggerKind.time)
          _TimeTriggerEditor(draft: d, onTouch: touch)
        else ...[
          _AstroTriggerEditor(draft: d, onTouch: touch),
          const SizedBox(height: 18),
          _SubBlock(
            title: 'VERSCHUIVING',
            child: _OffsetStepper(draft: d, onTouch: touch),
          ),
        ],
        const SizedBox(height: 18),
        _SubBlock(
          title: 'DAGEN',
          child: _WeekdayRow(days: d.days, onTouch: touch),
        ),
        if (d.kind == _TriggerKind.astro) ...[
          const SizedBox(height: 18),
          _SubBlock(
            title: 'BEGRENZING',
            infoTitle: 'Begrenzing',
            infoBody:
                'Optioneel. Voer alleen uit binnen een tijdvenster. '
                'Bijvoorbeeld: bij zonsondergang, maar niet voor 18:00.\n\n'
                'Niet voor: later als de zon eerder is.\n'
                'Niet na: overslaan als de zon later is.',
            child: Column(
              children: [
                _GuardRow(
                  label: 'Niet voor',
                  guard: d.notBefore,
                  onChanged: (g) {
                    d.notBefore = g;
                    touch();
                  },
                ),
                const SizedBox(height: 8),
                _GuardRow(
                  label: 'Niet na',
                  guard: d.notAfter,
                  onChanged: (g) {
                    d.notAfter = g;
                    touch();
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionPane(_Draft d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      children: [
        if (_themeLocked)
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
                  ? 'Weergave → licht thema'
                  : 'Weergave → donker thema',
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
      ],
    );
  }

  String _nameSummary(_Draft d) {
    final n = d.name.trim();
    return n.isEmpty ? 'Geen naam' : n;
  }

  String _whenSummary(_Draft d) {
    final days = _daysSummary(d.days);
    if (d.kind == _TriggerKind.time) {
      return '${_hhmm(d.time)}  ·  $days';
    }
    final off = d.offsetMin;
    final offStr = off == 0
        ? ''
        : off > 0
            ? ' +${off}m'
            : ' ${off}m';
    return '${d.astroEvent.label}$offStr  ·  $days';
  }

  String _actionSummary(_Draft d, {required bool locked}) {
    if (locked) {
      return _selectedId == kThemeLightOnId
          ? 'Weergave: licht'
          : 'Weergave: donker';
    }
    if (d.actionKind == _ActionKind.scene) {
      final id = d.sceneId;
      if (id == null || id.isEmpty) return 'Geen scene';
      for (final s in widget.config.scenes) {
        if (s.id == id) return 'Scene: ${s.name}';
      }
      for (final f in widget.config.floors) {
        for (final r in f.rooms) {
          for (final s in r.scenes) {
            if (s.id == id) return 'Scene: ${s.name}  ·  ${r.name}';
          }
        }
      }
      return 'Scene: (verwijderd)';
    }
    final n = d.entries.length;
    if (n == 0) return 'Geen apparaten';
    return n == 1 ? '1 apparaat' : '$n apparaten';
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

InputDecoration _boxDecoration({String? hint}) => InputDecoration(
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: LuxeColors.surface.withValues(alpha: 0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
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

class _SubBlock extends StatelessWidget {
  const _SubBlock({
    required this.title,
    required this.child,
    this.trailing,
    this.infoTitle,
    this.infoBody,
  });
  final String title;
  final String? trailing;
  final String? infoTitle;
  final String? infoBody;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: _kSectionStyle)),
            if (trailing != null)
              Text(trailing!, style: Theme.of(context).textTheme.titleMedium),
            if (infoTitle != null && infoBody != null)
              LuxeInfoIconButton(title: infoTitle!, body: infoBody!),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
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
      textCapitalization: TextCapitalization.sentences,
      decoration: _boxDecoration(hint: 'Naam van dit schema'),
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
        InkWell(
          onTap: () async {
            final picked = await showLuxeDigitalTimePicker(
              context,
              initial: draft.time,
            );
            if (picked != null) {
              draft.time = picked;
              onTouch();
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
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
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: LuxeColors.ink),
                ),
                Spacer(),
                Icon(Icons.chevron_right, color: LuxeColors.inkSoft),
              ],
            ),
          ),
        ),
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
      ],
    );
  }
}

class _OffsetStepper extends StatelessWidget {
  const _OffsetStepper({required this.draft, required this.onTouch});
  final _Draft draft;
  final VoidCallback onTouch;

  static const _min = -240;
  static const _max = 240;

  void _set(int next) {
    draft.offsetMin = next.clamp(_min, _max);
    onTouch();
  }

  @override
  Widget build(BuildContext context) {
    final off = draft.offsetMin.clamp(_min, _max);
    return Row(
      children: [
        _HoldStepButton(
          tooltip: 'Een minuut eerder',
          icon: Icons.remove_rounded,
          enabled: off > _min,
          onStep: () => _set(draft.offsetMin - 1),
        ),
        Expanded(
          child: Text(
            _offsetLabel(off),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        _HoldStepButton(
          tooltip: 'Een minuut later',
          icon: Icons.add_rounded,
          enabled: off < _max,
          onStep: () => _set(draft.offsetMin + 1),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: off == 0 ? null : () => _set(0),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

class _HoldStepButton extends StatefulWidget {
  const _HoldStepButton({
    required this.icon,
    required this.onStep,
    required this.enabled,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onStep;
  final bool enabled;
  final String? tooltip;

  @override
  State<_HoldStepButton> createState() => _HoldStepButtonState();
}

class _HoldStepButtonState extends State<_HoldStepButton> {
  Timer? _hold;
  Timer? _repeat;
  int _ticks = 0;

  void _clear() {
    _hold?.cancel();
    _repeat?.cancel();
    _hold = null;
    _repeat = null;
    _ticks = 0;
  }

  void _down() {
    if (!widget.enabled) return;
    widget.onStep();
    _hold = Timer(const Duration(milliseconds: 350), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) {
        if (!mounted || !widget.enabled) {
          _clear();
          return;
        }
        _ticks++;
        if (_ticks == 10) {
          _repeat?.cancel();
          _repeat = Timer.periodic(const Duration(milliseconds: 45), (_) {
            if (!mounted || !widget.enabled) {
              _clear();
              return;
            }
            widget.onStep();
          });
        }
        widget.onStep();
      });
    });
  }

  @override
  void didUpdateWidget(covariant _HoldStepButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _down() : null,
        onPointerUp: (_) => _clear(),
        onPointerCancel: (_) => _clear(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.enabled
                ? LuxeColors.surface
                : LuxeColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LuxeColors.lineSoft),
          ),
          child: Icon(
            widget.icon,
            color: widget.enabled ? LuxeColors.ink : LuxeColors.inkSoft,
          ),
        ),
      ),
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
    return Row(
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
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: days[i]
                            ? LuxeColors.brass
                            : Colors.transparent,
                        border: Border.all(
                          color: days[i]
                              ? LuxeColors.brass
                              : LuxeColors.ink.withValues(alpha: 0.22),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        names[i],
                        style: TextStyle(
                          color: days[i]
                              ? LuxeColors.onInk
                              : LuxeColors.inkSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: _kSectionStyle),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          decoration: BoxDecoration(
            color: LuxeColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: LuxeColors.lineSoft),
          ),
          child: Row(
            children: [
              Expanded(child: _guardBody(context, g)),
              if (g != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => onChanged(null),
                ),
            ],
          ),
        ),
      ],
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
              'Tik om toe te voegen',
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
          final picked = await showLuxeDigitalTimePicker(
            context,
            initial: initial,
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
              child: Text('${s.name}  ·  ${r.name}'),
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
      decoration: _boxDecoration(hint: 'Kies een scene'),
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

String _offsetLabel(int offsetMin) {
  final off = offsetMin;
  if (off == 0) return 'exact';
  return off > 0 ? '$off min na' : '${-off} min voor';
}

String _daysSummary(List<bool> m) {
  if (m.every((x) => x)) return 'elke dag';
  if (m.length >= 7 && !m[5] && !m[6] && m.take(5).every((x) => x)) {
    return 'doordeweeks';
  }
  if (m.length >= 7 && m[5] && m[6] && m.take(5).every((x) => !x)) {
    return 'weekend';
  }
  const names = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
  return [
    for (int i = 0; i < 7 && i < m.length; i++)
      if (m[i]) names[i],
  ].join(', ');
}

TimeOfDay _parseTimeOfDay(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
  );
}

Future<TimeOfDay?> showLuxeDigitalTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _DigitalTimePickerDialog(initial: initial),
  );
}

class _DigitalTimePickerDialog extends StatefulWidget {
  const _DigitalTimePickerDialog({required this.initial});
  final TimeOfDay initial;

  @override
  State<_DigitalTimePickerDialog> createState() =>
      _DigitalTimePickerDialogState();
}

class _DigitalTimePickerDialogState extends State<_DigitalTimePickerDialog> {
  static const _itemExtent = 44.0;
  late final FixedExtentScrollController _hours;
  late final FixedExtentScrollController _minutes;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
    _hours = FixedExtentScrollController(initialItem: _hour);
    _minutes = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      perspective: 0.004,
      diameterRatio: 1.15,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, i) {
          final active = i == selected;
          return Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: active ? 28 : 20,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? LuxeColors.ink : LuxeColors.inkSoft,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LuxeColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tijd',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _itemExtent * 5,
              child: Row(
                children: [
                  Expanded(
                    child: _wheel(
                      controller: _hours,
                      count: 24,
                      selected: _hour,
                      onChanged: (v) => setState(() => _hour = v),
                    ),
                  ),
                  Text(
                    ':',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: LuxeColors.ink,
                    ),
                  ),
                  Expanded(
                    child: _wheel(
                      controller: _minutes,
                      count: 60,
                      selected: _minute,
                      onChanged: (v) => setState(() => _minute = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Annuleren'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      TimeOfDay(hour: _hour, minute: _minute),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: LuxeColors.ink,
                      foregroundColor: LuxeColors.onInk,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Kies'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
