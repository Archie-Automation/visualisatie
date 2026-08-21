import 'dart:async';

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
import 'widgets/confirm_dialog.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';
import 'installer_nav.dart';

enum _SettingsTopic { appearance, schedules, tablet, spotify }

/// Customer-facing settings: menu first, then one function at a time.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsTopic? _topic;

  ThemeData _settingsTheme(ThemeData base) {
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        bodyLarge: t.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
        bodyMedium: t.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
        bodySmall: t.bodySmall?.copyWith(fontWeight: FontWeight.w400),
        labelLarge: t.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 1.05,
        ),
        labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(isDense: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final schedAsync = ref.watch(schedulesProvider);
    final auth = ref.watch(authProvider);

    return PopScope(
      canPop: _topic == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _topic = null);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LuxeBackdrop(
          child: cfgAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (cfg) {
              return Theme(
                data: _settingsTheme(Theme.of(context)),
                child: _topic == null
                    ? _menu(auth)
                    : _detail(cfg, schedAsync, auth),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _menu(AuthState auth) {
    return SafeArea(
      child: ListView(
        physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          _header(auth),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: GlassCard(
              radius: 16,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingsMenuTile(
                    icon: Icons.palette_outlined,
                    title: 'Weergave',
                    subtitle: 'Licht, donker of automatisch',
                    onTap: () =>
                        setState(() => _topic = _SettingsTopic.appearance),
                  ),
                  Divider(height: 1, indent: 50, color: LuxeColors.lineSoft),
                  _SettingsMenuTile(
                    icon: Icons.schedule_outlined,
                    title: 'Tijdschema\'s',
                    subtitle: 'Scenes en apparaten op tijd',
                    onTap: () =>
                        setState(() => _topic = _SettingsTopic.schedules),
                  ),
                  Divider(height: 1, indent: 50, color: LuxeColors.lineSoft),
                  _SettingsMenuTile(
                    icon: Icons.tablet_android_outlined,
                    title: 'Wandtablet',
                    subtitle: 'Alleen voor het wandtablet',
                    onTap: () =>
                        setState(() => _topic = _SettingsTopic.tablet),
                  ),
                  Divider(height: 1, indent: 50, color: LuxeColors.lineSoft),
                  _SettingsMenuTile(
                    icon: Icons.library_music_outlined,
                    title: 'Spotify',
                    subtitle: 'Account voor dit huis',
                    onTap: () =>
                        setState(() => _topic = _SettingsTopic.spotify),
                  ),
                ],
              ),
            ),
          ),
          if (auth.isAuthed && auth.restoreComplete)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  'Ingelogd als ${auth.username ?? '—'} · ${auth.effectiveRole ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LuxeColors.inkSoft.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          const _VersionFooter(),
        ],
      ),
    );
  }

  Widget _detail(
    HouseConfig cfg,
    AsyncValue<List<Schedule>> schedAsync,
    AuthState auth,
  ) {
    final topic = _topic!;
    final canEditSchedules = canEditScenesInApp(auth, cfg);
    final themeMode = ref.watch(themeModeProvider);
    final showThemeSchedules = showThemeAutoSchedules(themeMode);

    final title = switch (topic) {
      _SettingsTopic.appearance => 'Weergave',
      _SettingsTopic.schedules => 'Tijdschema\'s',
      _SettingsTopic.tablet => 'Wandtablet',
      _SettingsTopic.spotify => 'Spotify',
    };
    final infoTitle = title;
    final infoBody = switch (topic) {
      _SettingsTopic.appearance =>
        'Kies licht, donker of automatisch.\n\n${showThemeSchedules ? 'Auto volgt het licht/donker-schema onder Tijdschema\'s.' : 'Licht of donker blijft vast tot je Auto kiest.'}',
      _SettingsTopic.schedules => [
          'Laat scenes of apparaten automatisch lopen op een tijdstip, of bij zonsopkomst en zonsondergang.',
          if (showThemeSchedules)
            'In Auto staan hier ook de licht- en donkerweergave.',
          if (!canEditSchedules)
            'Met dit account mag u geen tijdschema\'s wijzigen. Vraag een beheerder.',
        ].join('\n\n'),
      _SettingsTopic.tablet =>
        'Alleen voor het wandtablet (Android-app). Na inactiviteit gaat dit scherm '
            'terug naar home, daarna een screensaver met klok.\n\n'
            'Koppel de ruimte waar het tablet hangt. Optioneel toont '
            'de screensaver de temperatuur van een ruimte of KNX-groepadres. '
            'Zet screensaver uit als de muziekspeler van die ruimte fullscreen open staat.',
      _SettingsTopic.spotify =>
        'Eén keer inloggen voor dit huis — daarna werkt Spotify op elk paneel.\n\n'
            'Maak eenmalig een gratis app op developer.spotify.com. '
            'Plak Client ID en Client Secret hier, en de Redirect URI exact in die Spotify-app.\n\n'
            'Eerste keer toont de browser een certificaatwaarschuwing. '
            'Kies Geavanceerd → Doorgaan tot je “Certificaat OK” ziet, '
            'daarna Verbind Spotify.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FunctionScreenHeader(
          onBack: () => setState(() => _topic = null),
          title: title,
          subtitle: topic == _SettingsTopic.tablet
              ? 'Alleen voor het wandtablet'
              : null,
          trailing: LuxeInfoIconButton(title: infoTitle, body: infoBody),
        ),
        Expanded(
          child: ListView(
            physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.only(bottom: 36),
            children: [
              switch (topic) {
                _SettingsTopic.appearance =>
                  const _AppearanceSection(showTitle: false),
                _SettingsTopic.schedules => _schedulesSection(
                    context,
                    ref,
                    cfg,
                    schedAsync,
                    canEditSchedules: canEditSchedules,
                    showTitle: false,
                  ),
                _SettingsTopic.tablet =>
                  const _DisplayPanelSection(showTitle: false),
                _SettingsTopic.spotify =>
                  const _SpotifySection(showTitle: false),
              },
            ],
          ),
        ),
      ],
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

  Widget _header(AuthState auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 22, 8),
      child: Row(
        children: [
          _GlassBack(onTap: () => _popSettings(context)),
          const SizedBox(width: 14),
          Text(
            'Instellingen',
            style: Theme.of(context).textTheme.headlineMedium,
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
    bool showTitle = true,
  }) {
    final themeMode = ref.watch(themeModeProvider);
    final showThemeSchedules = showThemeAutoSchedules(themeMode);
    final themeSched = ref.watch(themeAutoScheduleProvider);
    final themeRows =
        showThemeSchedules ? themeSched.asSchedules() : const <Schedule>[];

    return _SettingsCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle)
              _SettingsSectionTitle(
                icon: Icons.schedule_outlined,
                title: 'TIJDSCHEMA\'S',
                infoTitle: 'Tijdschema\'s',
                infoBody: [
                  'Laat scenes of apparaten automatisch lopen op een tijdstip, of bij zonsopkomst en zonsondergang.',
                  if (showThemeSchedules)
                    'In Auto staan hier ook de licht- en donkerweergave.',
                  if (!canEditSchedules)
                    'Met dit account mag u geen tijdschema\'s wijzigen. Vraag een beheerder.',
                ].join('\n\n'),
              ),
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
                final addRow = canEditSchedules
                    ? _AddScheduleRow(
                        onTap: () => _openEditor(
                          ctx,
                          ref,
                          cfg,
                          canEditHouse: true,
                          createNew: true,
                        ),
                      )
                    : null;
                if (display.isEmpty && addRow == null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Text(
                      'Nog geen tijdschema\'s',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final s in display) ...[
                      if (s != display.first)
                        Divider(height: 1, color: LuxeColors.lineSoft),
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
                    if (addRow != null) ...[
                      if (display.isNotEmpty)
                        Divider(height: 1, color: LuxeColors.lineSoft),
                      addRow,
                    ],
                  ],
                );
              },
            ),
          ],
        ),
    );
  }

  Future<void> _openEditor(
    BuildContext ctx,
    WidgetRef ref,
    HouseConfig cfg, {
    Schedule? initial,
    bool canEditHouse = true,
    bool createNew = false,
  }) async {
    final existing =
        canEditHouse ? (ref.read(schedulesProvider).value ?? []) : <Schedule>[];
    final themeMode = ref.read(themeModeProvider);
    final includeTheme = showThemeAutoSchedules(themeMode);
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
        createNew: createNew,
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
  const _DisplayPanelSection({this.showTitle = true});

  final bool showTitle;

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

    return _SettingsCard(
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
                if (widget.showTitle) ...[
                _SettingsSectionTitle(
                  icon: Icons.tablet_android_outlined,
                  title: 'WANDTABLET',
                  subtitle: 'Alleen voor het wandtablet',
                  infoTitle: 'Wandtablet',
                  infoBody:
                      'Alleen op de Android-app. Na inactiviteit gaat dit scherm '
                      'terug naar home, daarna een screensaver met klok.\n\n'
                      'Koppel de ruimte waar het tablet hangt. Optioneel toont '
                      'de screensaver de temperatuur van een ruimte of KNX-groepadres. '
                      'Zet screensaver uit als de muziekspeler van die ruimte fullscreen open staat.',
                  trailing: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                ] else if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: const Text('Inactiviteit & screensaver'),
                  value: settings.enabled,
                  onChanged: _saving
                      ? null
                      : (v) => _save(settings.copyWith(enabled: v)),
                ),
                const SizedBox(height: 8),
                _LabeledBox(
                  label: 'Ruimte van dit scherm',
                  child: DropdownButtonFormField<String>(
                  value: settings.panelRoomId != null &&
                          rooms.any((r) => r.id == settings.panelRoomId)
                      ? settings.panelRoomId
                      : null,
                  decoration: _kSettingsBox,
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
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: const Text('Geen screensaver bij open media-speler'),
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
                  _LabeledBox(
                    label: 'Ruimte',
                    child: DropdownButtonFormField<String>(
                    value: settings.temperatureRoomId != null &&
                            rooms.any((r) => r.id == settings.temperatureRoomId)
                        ? settings.temperatureRoomId
                        : null,
                    decoration: _kSettingsBox,
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
    return _LabeledBox(
      label: 'Groepadres temperatuur',
      child: TextField(
      enabled: widget.enabled,
      controller: _ctrl,
      decoration: _kSettingsBox.copyWith(hintText: 'bijv. 4/1/10'),
      onSubmitted: widget.enabled ? widget.onSave : null,
    ),
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
    return _LabeledBox(
      label: label,
      child: DropdownButtonFormField<int>(
      value: options.contains(value) ? value : options.first,
      decoration: _kSettingsBox,
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
    ),
    );
  }
}

class _SpotifySection extends ConsumerStatefulWidget {
  const _SpotifySection({this.showTitle = true});

  final bool showTitle;

  @override
  ConsumerState<_SpotifySection> createState() => _SpotifySectionState();
}

class _SpotifySectionState extends ConsumerState<_SpotifySection> {
  /// When true, show the credentials form even if keys were already saved
  /// (wrong Client ID/Secret must remain editable).
  bool _editingCredentials = false;

  Future<void> _connect(BuildContext ctx) async {
    final api = ref.read(mediaApiProvider);
    final messenger = ScaffoldMessenger.of(ctx);
    final tlsCheck = ref.read(spotifyStatusProvider).value?.tlsCheckUrl;
    try {
      if (tlsCheck != null && tlsCheck.isNotEmpty) {
        await launchUrl(Uri.parse(tlsCheck), mode: LaunchMode.externalApplication);
        if (!ctx.mounted) return;
        final proceed = await showDialog<bool>(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text('Certificaat toestaan'),
            content: const Text(
              'Chrome toont een waarschuwing (zelf-getekend certificaat). '
              'Kies Geavanceerd → Doorgaan tot je “Certificaat OK” ziet. '
              'Daarna tik je hier op Verder.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(false),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dctx).pop(true),
                child: const Text('Verder'),
              ),
            ],
          ),
        );
        if (proceed != true || !ctx.mounted) return;
      }
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
    await showDialog<void>(
      context: ctx,
      builder: (dctx) => _SpotifyConnectDialog(
        onFinishUrl: (pasted) => api.spotifyFinish(callbackUrl: pasted),
        pollConnected: () async {
          ref.invalidate(spotifyStatusProvider);
          final next = await ref.read(spotifyStatusProvider.future);
          return next.connected;
        },
      ),
    );
    ref.invalidate(spotifyStatusProvider);
  }

  Future<void> _disconnect() async {
    await ref.read(mediaApiProvider).spotifyDisconnect();
    ref.invalidate(spotifyStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(spotifyStatusProvider);
    return _SettingsCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle) ...[
            _SettingsSectionTitle(
              icon: Icons.library_music_outlined,
              title: 'SPOTIFY',
              infoTitle: 'Spotify',
              infoBody:
                  'Eén keer inloggen voor dit huis — daarna werkt Spotify op elk paneel.\n\n'
                  'Maak eenmalig een gratis app op developer.spotify.com. '
                  'Plak Client ID en Client Secret hier, en de Redirect URI exact in die Spotify-app.\n\n'
                  'Eerste keer toont de browser een certificaatwaarschuwing. '
                  'Kies Geavanceerd → Doorgaan tot je “Certificaat OK” ziet, '
                  'daarna Verbind Spotify.',
            ),
            const SizedBox(height: 10),
            ],
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
              data: (status) => _statusBody(status),
            ),
          ],
        ),
    );
  }

  Widget _statusBody(SpotifyStatus status) {
    if (!status.configured || _editingCredentials) {
      return _SpotifyCredentialsForm(
        suggestedRedirectUri:
            status.suggestedRedirectUri ?? status.redirectUri,
        tlsCheckUrl: status.tlsCheckUrl,
        initialClientId: status.clientId,
        onCancel: status.configured
            ? () => setState(() => _editingCredentials = false)
            : null,
        onSaved: () => setState(() => _editingCredentials = false),
      );
    }
    if (status.connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                onPressed: _disconnect,
                child: const Text('Ontkoppelen'),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _editingCredentials = true),
              child: const Text('Gegevens wijzigen'),
            ),
          ),
        ],
      );
    }
    final redirect = status.suggestedRedirectUri ?? status.redirectUri ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (redirect.isNotEmpty) ...[
          _RedirectUriBox(redirect),
          if (status.tlsCheckUrl != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(status.tlsCheckUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.security_rounded),
              label: const Text('Certificaat toestaan'),
            ),
          ],
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _connect(context),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Verbind Spotify'),
            ),
            TextButton(
              onPressed: () => setState(() => _editingCredentials = true),
              child: const Text('Gegevens wijzigen'),
            ),
          ],
        ),
      ],
    );
  }
}

/// After the browser login, the user either lands on the backend callback
/// (SSH tunnel / loopback) or pastes the 127.0.0.1 URL that failed to load.
class _SpotifyConnectDialog extends StatefulWidget {
  const _SpotifyConnectDialog({
    required this.onFinishUrl,
    required this.pollConnected,
  });
  final Future<void> Function(String url) onFinishUrl;
  final Future<bool> Function() pollConnected;

  @override
  State<_SpotifyConnectDialog> createState() => _SpotifyConnectDialogState();
}

class _SpotifyConnectDialogState extends State<_SpotifyConnectDialog> {
  final _urlCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _waiting = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    _check();
  }

  Future<void> _check() async {
    try {
      final ok = await widget.pollConnected();
      if (ok && mounted) Navigator.of(context).pop();
    } catch (_) {
      /* keep waiting */
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _urlCtrl.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onFinishUrl(raw);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spotify verbinden'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log in bij Spotify in het geopende venster. '
              'Dit is eenmalig voor het hele huis — daarna werken alle panelen. '
              'Deze dialoog sluit vanzelf als de koppeling lukt.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_waiting) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _LabeledBox(
              label: 'Callback-URL (als de pagina niet laadt)',
              child: TextField(
              controller: _urlCtrl,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              decoration: _kSettingsBox.copyWith(
                hintText:
                    'https://192.168.x.x:4443/api/media/spotify/callback?code=…',
              ),
            ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: LuxeColors.danger,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Gereed'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('URL versturen'),
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
  const _SpotifyCredentialsForm({
    this.suggestedRedirectUri,
    this.tlsCheckUrl,
    this.initialClientId,
    this.onCancel,
    this.onSaved,
  });
  final String? suggestedRedirectUri;
  final String? tlsCheckUrl;
  final String? initialClientId;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;

  @override
  ConsumerState<_SpotifyCredentialsForm> createState() =>
      _SpotifyCredentialsFormState();
}

class _SpotifyCredentialsFormState
    extends ConsumerState<_SpotifyCredentialsForm> {
  late final TextEditingController _idCtrl;
  final _secretCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.initialClientId ?? '');
  }

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
      widget.onSaved?.call();
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
        if (redirect.isNotEmpty) ...[
          _RedirectUriBox(redirect),
          if (widget.tlsCheckUrl != null)
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(widget.tlsCheckUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.security_rounded),
              label: const Text('Certificaat toestaan'),
            ),
          const SizedBox(height: 12),
        ],
        _LabeledBox(
          label: 'Client ID',
          child: TextField(
          controller: _idCtrl,
          decoration: _kSettingsBox,
        ),
        ),
        const SizedBox(height: 10),
        _LabeledBox(
          label: 'Client Secret',
          child: TextField(
          controller: _secretCtrl,
          obscureText: true,
          decoration: _kSettingsBox,
        ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
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
            if (widget.onCancel != null)
              TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('Annuleren'),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddScheduleRow extends StatelessWidget {
  const _AddScheduleRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Row(
          children: [
            Icon(
              Icons.add_rounded,
              size: 20,
              color: LuxeColors.brassDeep,
            ),
            const SizedBox(width: 10),
            Text(
              'Tijdschema toevoegen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
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
    final meta = '${describeTrigger(s.trigger)} · ${describeAction(s.action, config)}';
    return InkWell(
      onTap: canEdit ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Row(
          children: [
            Icon(
              _triggerIcon(s.trigger),
              size: 18,
              color: LuxeColors.brassDeep,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    meta,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (locked)
              LuxeInfoIconButton(
                title: 'Weergave',
                body:
                    'Hier kun je alleen het tijdstip aanpassen. '
                    'Naam en actie (licht of donker) staan vast.',
              ),
            if (onRun != null)
              IconButton(
                tooltip: canEdit ? 'Nu uitvoeren' : 'Geen rechten',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
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
  const _AppearanceSection({this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final autoHint = showThemeAutoSchedules(mode)
        ? 'Auto volgt het licht/donker-schema onder Tijdschema\'s.'
        : 'Licht of donker blijft vast tot je Auto kiest.';
    return _SettingsCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              _SettingsSectionTitle(
                icon: Icons.palette_outlined,
                title: 'WEERGAVE',
                infoTitle: 'Weergave',
                infoBody: 'Kies licht, donker of automatisch.\n\n$autoHint',
              ),
              const SizedBox(height: 10),
            ],
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
    );
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    final server = status?.running.version;
    final app = status?.clientVersion?.version ?? kAppVersion;
    final line = auth.isAdmin && server != null && server.isNotEmpty
        ? 'app $app · server $server'
        : 'versie $app';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(
        child: Text(
          line,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: LuxeColors.inkSoft.withValues(alpha: 0.45),
                fontSize: 11,
              ),
        ),
      ),
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Icon(icon, color: LuxeColors.ink, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 9),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        radius: 18,
        child: child,
      ),
    );
  }
}

const _kSettingsBox = InputDecoration(
  floatingLabelBehavior: FloatingLabelBehavior.never,
  border: OutlineInputBorder(),
);

class _LabeledBox extends StatelessWidget {
  const _LabeledBox({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        child,
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.icon,
    required this.title,
    required this.infoTitle,
    required this.infoBody,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String infoTitle;
  final String infoBody;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: LuxeColors.ink, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: LuxeColors.inkSoft,
                      ),
                ),
              ],
            ],
          ),
        ),
        LuxeInfoIconButton(title: infoTitle, body: infoBody),
        if (trailing != null) trailing!,
      ],
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
