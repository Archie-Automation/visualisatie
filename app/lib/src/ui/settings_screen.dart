import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../display_panel_config.dart';
import '../media_api.dart';
import '../models.dart';
import '../schedule_api.dart';
import '../software_version.dart';
import '../theme.dart';
import '../theme_mode.dart';
import '../theme_auto_schedule.dart';
import 'app_nav.dart';
import 'schedule_editor_sheet.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';
import 'widgets/admin_server_update_card.dart';
import 'installer_nav.dart';

/// Customer-facing settings screen: time / astro schedules.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfgAsync = ref.watch(configProvider);
    final schedAsync = ref.watch(schedulesProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: cfgAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (cfg) {
              final canEditSchedules = canEditScenesInApp(auth, cfg);
              return CustomScrollView(
                physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: _header(context, auth)),
                  const SliverToBoxAdapter(child: _AppearanceSection()),
                  SliverToBoxAdapter(
                    child: _schedulesSection(
                      context,
                      ref,
                      cfg,
                      schedAsync,
                      canEditSchedules: canEditSchedules,
                    ),
                  ),
                  const SliverToBoxAdapter(child: _DisplayPanelSection()),
                  const SliverToBoxAdapter(child: _SpotifySection()),
                  if (auth.isAdmin)
                    const SliverToBoxAdapter(child: _ServerUpdateSection()),
                  const SliverToBoxAdapter(child: _VersionFooter()),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _installerTile(BuildContext ctx, AuthState auth) {
    final locked = !auth.isAdmin;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
        radius: 28,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => openTechnischeConfiguratie(ctx, auth),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: locked ? LuxeColors.inkSoft : LuxeColors.ink,
                  size: 22,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TECHNISCHE CONFIGURATIE',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked
                            ? 'Alleen voor rol admin — tik voor uitleg. '
                                'Met admin: verdiepingen, kamers, KNX, IP, streams, gebruikers.'
                            : 'Verdiepingen, kamers, KNX, camera’s, IP, streams, gebruikers. '
                                'Ook: gereedschap-icoon op het dashboard. '
                                'Herstart backend/app: open dit scherm en kies links Project.',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: locked ? LuxeColors.inkSoft : null,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: locked ? LuxeColors.inkSoft : LuxeColors.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _popSettings(BuildContext context) {
    appBack(context);
  }

  Widget _header(BuildContext ctx, AuthState auth) {
    final uname = auth.username ?? '—';
    final rol = auth.effectiveRole ?? (auth.isAuthed ? 'onbekend' : '—');
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _GlassBack(onTap: () => _popSettings(ctx)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('INSTELLINGEN',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text('Voorkeuren',
                    style: Theme.of(ctx).textTheme.displayMedium),
                if (auth.isAuthed && auth.restoreComplete) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Ingelogd als $uname · rol: $rol',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _schedulesSection(
    BuildContext ctx,
    WidgetRef ref,
    HouseConfig cfg,
    AsyncValue<List<Schedule>> schedAsync, {
    required bool canEditSchedules,
  }) {
    final themeMode = ref.watch(themeModeProvider);
    final showThemeSchedules =
        isWallTabletThemeTarget && themeMode == ThemeMode.system;
    final themeSched = ref.watch(themeAutoScheduleProvider);
    final themeRows =
        showThemeSchedules ? themeSched.asSchedules() : const <Schedule>[];

    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
        radius: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!canEditSchedules)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Met dit account mag u geen tijdschema\'s wijzigen. '
                  'Vraag een beheerder om het recht aan te passen (editScenes) of gebruik een ander account.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TIJDSCHEMA\'S',
                            style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 2),
                        Text(
                          showThemeSchedules
                              ? 'Scenes, apparaten en weergave (Auto) automatisch.'
                              : 'Laat scenes of apparaten automatisch lopen.',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: canEditSchedules
                        ? 'Tijdschema toevoegen'
                        : 'Geen rechten om te wijzigen',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: canEditSchedules
                        ? () => _openEditor(ctx, ref, cfg,
                            canEditHouse: true)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            schedAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Kon tijdschema\'s niet laden: $e'),
              ),
              data: (list) {
                final display = [...themeRows, ...list];
                if (display.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Text(
                      canEditSchedules
                          ? 'Nog geen tijdschema\'s. Tik op + om er een aan te maken.'
                          : 'Er zijn nog geen tijdschema\'s, of u mag ze niet beheren.',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final s in display)
                      _ScheduleRow(
                        schedule: s,
                        config: cfg,
                        canEdit: isThemeScheduleId(s.id)
                            ? true
                            : canEditSchedules,
                        locked: isThemeScheduleId(s.id),
                        onEdit: () {
                          if (isThemeScheduleId(s.id)) {
                            _openEditor(ctx, ref, cfg,
                                initial: s,
                                canEditHouse: canEditSchedules);
                            return;
                          }
                          if (!canEditSchedules) return;
                          _openEditor(ctx, ref, cfg,
                              initial: s, canEditHouse: true);
                        },
                        onToggle: (enabled) async {
                          if (isThemeScheduleId(s.id)) {
                            final next = themeSched.mergeFromSchedules([
                              s.copyWith(enabled: enabled),
                            ]);
                            await ref
                                .read(themeAutoScheduleProvider.notifier)
                                .save(next);
                            return;
                          }
                          if (!canEditSchedules) return;
                          final next = [
                            for (final x in list)
                              x.id == s.id
                                  ? x.copyWith(enabled: enabled)
                                  : x
                          ];
                          try {
                            await ref.read(scheduleApiProvider).save(next);
                            if (!ctx.mounted) return;
                            ref.invalidate(schedulesProvider);
                          } catch (err) {
                            if (!ctx.mounted) return;
                            ref.invalidate(schedulesProvider);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: LuxeColors.danger,
                                shape: const StadiumBorder(),
                                content: Text('Opslaan mislukt: $err'),
                              ),
                            );
                          }
                        },
                        onRun: isThemeScheduleId(s.id)
                            ? null
                            : () async {
                                if (!canEditSchedules) return;
                                try {
                                  await ref
                                      .read(scheduleApiProvider)
                                      .runNow(s.id);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: LuxeColors.ink,
                                      shape: const StadiumBorder(),
                                      content: Text('${s.name} gestart'),
                                    ),
                                  );
                                } catch (err) {
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: LuxeColors.danger,
                                      shape: const StadiumBorder(),
                                      content: Text('Mislukt: $err'),
                                    ),
                                  );
                                }
                              },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext ctx,
    WidgetRef ref,
    HouseConfig cfg, {
    Schedule? initial,
    bool canEditHouse = true,
  }) async {
    final existing =
        canEditHouse ? (ref.read(schedulesProvider).value ?? []) : <Schedule>[];
    final themeMode = ref.read(themeModeProvider);
    final includeTheme =
        isWallTabletThemeTarget && themeMode == ThemeMode.system;
    final themeOnes = includeTheme
        ? ref.read(themeAutoScheduleProvider).asSchedules()
        : const <Schedule>[];
    final lockedIds = {
      for (final s in themeOnes) s.id,
    };
    final merged = [...themeOnes, ...existing];
    final saved = await showModalBottomSheet<List<Schedule>>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScheduleEditorSheet(
        schedules: merged,
        config: cfg,
        initiallySelectedId: initial?.id,
        lockedIds: lockedIds,
        persistHouseSchedules: canEditHouse,
      ),
    );
    if (saved != null) {
      ref.invalidate(schedulesProvider);
    }
  }
}

/// Lets the customer connect their own Spotify account (one-time OAuth).
/// Search/play then works inside the player popups via Spotify Connect.
class _DisplayPanelSection extends ConsumerStatefulWidget {
  const _DisplayPanelSection();

  @override
  ConsumerState<_DisplayPanelSection> createState() =>
      _DisplayPanelSectionState();
}

class _DisplayPanelSectionState extends ConsumerState<_DisplayPanelSection> {
  bool _saving = false;

  Future<void> _save(DisplayPanelSettings next) async {
    setState(() => _saving = true);
    try {
      await ref.read(displayPanelSettingsProvider.notifier).save(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<({String id, String label})> _roomOptions(HouseConfig cfg) {
    final out = <({String id, String label})>[];
    for (final f in cfg.floors) {
      for (final r in f.rooms) {
        out.add((id: r.id, label: '${f.name} · ${r.name}'));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(displayPanelSettingsProvider);
    final cfg = ref.watch(configProvider).maybeWhen(
          data: (c) => c,
          orElse: () => null,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
        radius: 28,
        child: settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (e, _) => Text('Wandtablet-instellingen: $e'),
          data: (settings) {
            final rooms = cfg != null ? _roomOptions(cfg) : const [];
            final useGa = settings.temperatureGa != null &&
                settings.temperatureGa!.trim().isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tablet_android_outlined,
                        color: LuxeColors.ink, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WANDTABLET',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Android wandtablet: na inactiviteit terug naar home, '
                  'daarna screensaver met klok en optionele ruimtetemperatuur.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inactiviteit & screensaver'),
                  subtitle: const Text('Alleen actief op Android-app'),
                  value: settings.enabled,
                  onChanged: _saving
                      ? null
                      : (v) => _save(settings.copyWith(enabled: v)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: settings.panelRoomId != null &&
                          rooms.any((r) => r.id == settings.panelRoomId)
                      ? settings.panelRoomId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Ruimte van dit scherm',
                    helperText:
                        'Koppel het wandtablet aan de ruimte waar het hangt',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Niet gekoppeld'),
                    ),
                    ...rooms.map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.label),
                      ),
                    ),
                  ],
                  onChanged: settings.enabled && !_saving
                      ? (id) {
                          if (id == null) {
                            _save(settings.copyWith(clearPanelRoom: true));
                          } else {
                            final label =
                                rooms.firstWhere((r) => r.id == id).label;
                            _save(settings.copyWith(
                              panelRoomId: id,
                              panelRoomName: label,
                            ));
                          }
                        }
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Geen screensaver bij open media-speler'),
                  subtitle: Text(
                    settings.panelRoomId != null
                        ? 'Alleen geblokkeerd als de Sonos/Bluesound van '
                            '${settings.panelRoomName ?? 'de gekoppelde ruimte'} '
                            'fullscreen open staat én speelt'
                        : 'Kies eerst een ruimte om dit te activeren',
                  ),
                  value: settings.suppressScreensaverWhenMusicPlaying &&
                      settings.panelRoomId != null,
                  onChanged: settings.enabled &&
                          !_saving &&
                          settings.panelRoomId != null
                      ? (v) => _save(settings.copyWith(
                            suppressScreensaverWhenMusicPlaying: v,
                          ))
                      : null,
                ),
                const SizedBox(height: 8),
                _MinutesDropdown(
                  label: 'Terug naar beginscherm',
                  value: settings.idleHomeMinutes,
                  enabled: settings.enabled && !_saving,
                  onChanged: (v) =>
                      _save(settings.copyWith(idleHomeMinutes: v)),
                ),
                const SizedBox(height: 12),
                _MinutesDropdown(
                  label: 'Screensaver',
                  value: settings.screensaverMinutes,
                  enabled: settings.enabled && !_saving,
                  allowOff: true,
                  onChanged: (v) =>
                      _save(settings.copyWith(screensaverMinutes: v)),
                ),
                const SizedBox(height: 16),
                Text('Temperatuur op screensaver',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text('Ruimte')),
                    ButtonSegment(value: true, label: Text('KNX GA')),
                  ],
                  selected: {useGa},
                  onSelectionChanged: settings.enabled && !_saving
                      ? (sel) {
                          if (sel.first) {
                            _save(settings.copyWith(
                              clearTemperatureRoom: true,
                              temperatureGa: settings.temperatureGa ?? '',
                            ));
                          } else {
                            _save(settings.copyWith(
                              clearTemperatureGa: true,
                              temperatureRoomId: settings.temperatureRoomId ??
                                  (rooms.isNotEmpty ? rooms.first.id : null),
                            ));
                          }
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                if (useGa)
                  _TemperatureGaField(
                    enabled: settings.enabled && !_saving,
                    initialGa: settings.temperatureGa ?? '',
                    onSave: (v) => _save(settings.copyWith(
                      temperatureGa: v.trim(),
                      clearTemperatureRoom: true,
                    )),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: settings.temperatureRoomId != null &&
                            rooms.any((r) => r.id == settings.temperatureRoomId)
                        ? settings.temperatureRoomId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Ruimte',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Geen temperatuur'),
                      ),
                      ...rooms.map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(r.label),
                        ),
                      ),
                    ],
                    onChanged: settings.enabled && !_saving
                        ? (id) {
                            if (id == null) {
                              _save(settings.copyWith(clearTemperatureRoom: true));
                            } else {
                              final label =
                                  rooms.firstWhere((r) => r.id == id).label;
                              _save(settings.copyWith(
                                temperatureRoomId: id,
                                temperatureRoomName: label,
                                clearTemperatureGa: true,
                              ));
                            }
                          }
                        : null,
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => ref
                            .read(displayPanelSettingsProvider.notifier)
                            .resetToHouseDefaults(),
                    child: const Text('Herstel house.json defaults'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TemperatureGaField extends StatefulWidget {
  const _TemperatureGaField({
    required this.enabled,
    required this.initialGa,
    required this.onSave,
  });

  final bool enabled;
  final String initialGa;
  final ValueChanged<String> onSave;

  @override
  State<_TemperatureGaField> createState() => _TemperatureGaFieldState();
}

class _TemperatureGaFieldState extends State<_TemperatureGaField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialGa);
  }

  @override
  void didUpdateWidget(covariant _TemperatureGaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGa != widget.initialGa &&
        _ctrl.text != widget.initialGa) {
      _ctrl.text = widget.initialGa;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: widget.enabled,
      controller: _ctrl,
      decoration: const InputDecoration(
        labelText: 'Groepadres temperatuur',
        hintText: 'bijv. 4/1/10',
        border: OutlineInputBorder(),
      ),
      onSubmitted: widget.enabled ? widget.onSave : null,
    );
  }
}

class _MinutesDropdown extends StatelessWidget {
  const _MinutesDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowOff = false,
  });

  final String label;
  final int value;
  final bool enabled;
  final bool allowOff;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = allowOff
        ? [0, 1, 2, 3, 5, 10, 15, 30, 60]
        : [1, 2, 3, 5, 10, 15, 30, 60];
    return DropdownButtonFormField<int>(
      value: options.contains(value) ? value : options.first,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map(
            (m) => DropdownMenuItem(
              value: m,
              child: Text(
                allowOff && m == 0 ? 'Uit' : '$m min',
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? (v) => v != null ? onChanged(v) : null : null,
    );
  }
}

class _SpotifySection extends ConsumerWidget {
  const _SpotifySection();

  Future<void> _connect(BuildContext ctx, WidgetRef ref) async {
    final api = ref.read(mediaApiProvider);
    final messenger = ScaffoldMessenger.of(ctx);
    try {
      final url = await api.spotifyLoginUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.danger,
          shape: const StadiumBorder(),
          content: Text('Spotify verbinden niet mogelijk: $e'),
        ),
      );
      return;
    }
    if (!ctx.mounted) return;
    // The login happens in the browser; after returning the user confirms so
    // we re-check the status.
    await showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Spotify verbinden'),
        content: const Text(
          'Log in het geopende venster in bij Spotify. '
          'Tik daarna op Gereed om de koppeling te controleren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('Gereed'),
          ),
        ],
      ),
    );
    ref.invalidate(spotifyStatusProvider);
  }

  Future<void> _disconnect(BuildContext ctx, WidgetRef ref) async {
    await ref.read(mediaApiProvider).spotifyDisconnect();
    ref.invalidate(spotifyStatusProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(spotifyStatusProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        radius: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_music_outlined,
                    color: LuxeColors.ink, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SPOTIFY',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Verbind je Spotify-account om in de spelers te zoeken en af te spelen.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            statusAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Text(
                'Status kon niet geladen worden: $e',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              data: (status) => _statusBody(context, ref, status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBody(BuildContext context, WidgetRef ref, SpotifyStatus status) {
    if (!status.configured) {
      return _SpotifyCredentialsForm(
        suggestedRedirectUri: status.suggestedRedirectUri,
      );
    }
    if (status.connected) {
      return Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: LuxeColors.brassDeep, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.account != null && status.account!.isNotEmpty
                  ? 'Verbonden als ${status.account}'
                  : 'Verbonden',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => _disconnect(context, ref),
            child: const Text('Ontkoppelen'),
          ),
        ],
      );
    }
    final redirect = status.redirectUri ?? status.suggestedRedirectUri ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (redirect.isNotEmpty) ...[
          Text('Redirect URI (zet deze in je Spotify-app):',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          _RedirectUriBox(redirect),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _connect(context, ref),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Verbind Spotify'),
          ),
        ),
      ],
    );
  }
}

/// Read-only, copyable box showing a redirect URI to paste into Spotify.
class _RedirectUriBox extends StatelessWidget {
  const _RedirectUriBox(this.uri);
  final String uri;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LuxeColors.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LuxeColors.lineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              uri,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: 'Kopieer',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uri));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Redirect URI gekopieerd')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Form to enter the Spotify OAuth app credentials directly in the app, so the
/// user can test with their own account without editing server config.
class _SpotifyCredentialsForm extends ConsumerStatefulWidget {
  const _SpotifyCredentialsForm({this.suggestedRedirectUri});
  final String? suggestedRedirectUri;

  @override
  ConsumerState<_SpotifyCredentialsForm> createState() =>
      _SpotifyCredentialsFormState();
}

class _SpotifyCredentialsFormState
    extends ConsumerState<_SpotifyCredentialsForm> {
  final _idCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(mediaApiProvider).spotifyConfigure(
            clientId: _idCtrl.text.trim(),
            clientSecret: _secretCtrl.text.trim(),
            redirectUri: widget.suggestedRedirectUri,
          );
      ref.invalidate(spotifyStatusProvider);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.danger,
          shape: const StadiumBorder(),
          content: Text('Opslaan mislukt: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final redirect = widget.suggestedRedirectUri ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maak eenmalig een gratis Spotify-app aan op developer.spotify.com, '
          'en plak hieronder de Client ID en Client Secret.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: LuxeColors.inkSoft,
              ),
        ),
        if (redirect.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Redirect URI (zet deze in je Spotify-app):',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          _RedirectUriBox(redirect),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _idCtrl,
          decoration: const InputDecoration(
            labelText: 'Client ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _secretCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Client Secret',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Opslaan'),
          ),
        ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.schedule,
    required this.config,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
    this.onRun,
    this.locked = false,
  });
  final Schedule schedule;
  final HouseConfig config;
  final bool canEdit;
  final bool locked;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: canEdit ? onEdit : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: LuxeColors.surface.withValues(alpha: 0.72),
            border: Border.all(color: LuxeColors.lineSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: LuxeColors.brass.withValues(alpha: 0.15),
                  border: Border.all(
                    color: LuxeColors.brass.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(_triggerIcon(s.trigger),
                    color: LuxeColors.brassDeep, size: 18),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (locked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock_outline,
                              size: 14, color: LuxeColors.inkSoft),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${describeTrigger(s.trigger)}  ·  ${describeAction(s.action, config)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onRun != null)
                IconButton(
                  tooltip: canEdit
                      ? 'Nu uitvoeren'
                      : 'Alleen zichtbaar — geen rechten',
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    color: canEdit ? LuxeColors.ink : LuxeColors.inkSoft,
                  ),
                  onPressed: canEdit ? onRun : null,
                ),
              Switch.adaptive(
                value: s.enabled,
                onChanged: canEdit ? onToggle : null,
                activeThumbColor: LuxeColors.brass,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _triggerIcon(ScheduleTrigger t) => switch (t) {
      TimeTrigger() => Icons.access_time_rounded,
      AstroTrigger(event: AstroEvent.sunrise) => Icons.wb_twilight,
      AstroTrigger(event: AstroEvent.sunset) => Icons.nightlight_round,
    };

const _kWeekdayShort = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

String describeTrigger(ScheduleTrigger t) {
  String days(WeekdayMask m) {
    if (m.every((x) => x)) return 'elke dag';
    if (!m[5] && !m[6] && m.take(5).every((x) => x)) return 'doordeweeks';
    if (m[5] && m[6] && m.take(5).every((x) => !x)) return 'weekend';
    return [
      for (int i = 0; i < 7; i++)
        if (m[i]) _kWeekdayShort[i],
    ].join(', ');
  }

  if (t is TimeTrigger) {
    return '${t.time}  ·  ${days(t.days)}';
  }
  t as AstroTrigger;
  final off = t.offsetMin;
  final offStr = off == 0
      ? ''
      : off > 0
          ? ' +${off}m'
          : ' ${off}m';
  return '${t.event.label}$offStr  ·  ${days(t.days)}';
}

String describeAction(ScheduleAction a, HouseConfig cfg) {
  if (a is ScheduleThemeAction) {
    return a.toLight ? 'Weergave: licht' : 'Weergave: donker';
  }
  if (a is ScheduleSceneAction) {
    // Look up scene name across global + room scenes.
    final global = cfg.scenes.where((s) => s.id == a.sceneId).toList();
    if (global.isNotEmpty) return 'Scene: ${global.first.name}';
    for (final f in cfg.floors) {
      for (final r in f.rooms) {
        for (final s in r.scenes) {
          if (s.id == a.sceneId) return 'Scene: ${s.name}  (${r.name})';
        }
      }
    }
    return 'Scene: (verwijderd)';
  }
  a as ScheduleActionsAction;
  return '${a.actions.length} apparaten';
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final tabletHint = isWallTabletThemeTarget
        ? 'Op de wandtablet volgt Auto het weergave-schema onder '
            'Tijdschema\'s (standaard astro aan/uit).'
        : 'Op de telefoon volgt Auto het systeem.';
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        radius: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: LuxeColors.ink, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WEERGAVE',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Licht, donker, of automatisch. $tabletHint',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Licht'),
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Donker'),
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_outlined, size: 18),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (set) {
                  ref.read(themeModeProvider.notifier).setMode(set.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerUpdateSection extends StatelessWidget {
  const _ServerUpdateSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: AdminServerUpdateCard(),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Center(
        child: Text(
          'versie $kAppVersion',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: LuxeColors.inkSoft.withValues(alpha: 0.45),
                fontSize: 11,
              ),
        ),
      ),
    );
  }
}

class _GlassBack extends StatelessWidget {
  const _GlassBack({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
        child: LuxeRimBox(
          width: 48,
          height: 48,
          radius: 14,
          rimWidth: 1,
          rimColor: LuxeColors.glassRim,
          fillColor: LuxeColors.surface.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.92
                : LuxeChipChrome.lightFill(),
          ),
          shadows: LuxeShadows.soft,
          child: Icon(Icons.arrow_back_ios_new,
              size: 16, color: LuxeColors.ink),
        ),
    );
  }
}
