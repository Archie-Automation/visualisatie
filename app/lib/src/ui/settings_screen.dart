import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:go_router/go_router.dart';

import '../api.dart';
import '../media_api.dart';
import '../models.dart';
import '../schedule_api.dart';
import '../theme.dart';
import 'schedule_editor_sheet.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';
import 'installer_nav.dart';

/// App version embedded at build time via --dart-define=APP_VERSION=x.y.z+N.
/// Falls back to 'dev' when running without a production build (flutter run).
const _kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

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
                  SliverToBoxAdapter(
                    child: _schedulesSection(
                      context,
                      ref,
                      cfg,
                      schedAsync,
                      canEditSchedules: canEditSchedules,
                    ),
                  ),
                  const SliverToBoxAdapter(child: _SpotifySection()),
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
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
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
                const SizedBox(width: 10),
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
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Widget _header(BuildContext ctx, AuthState auth) {
    final uname = auth.username ?? '—';
    final rol = auth.effectiveRole ?? (auth.isAuthed ? 'onbekend' : '—');
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
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
                  const Icon(Icons.schedule_outlined,
                      color: LuxeColors.ink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TIJDSCHEMA\'S',
                            style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 2),
                        Text('Laat scenes of apparaten automatisch lopen.',
                            style: Theme.of(ctx).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: canEditSchedules
                        ? 'Tijdschema toevoegen'
                        : 'Geen rechten om te wijzigen',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: canEditSchedules
                        ? () => _openEditor(ctx, ref, cfg)
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
                if (list.isEmpty) {
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
                    for (final s in list)
                      _ScheduleRow(
                        schedule: s,
                        config: cfg,
                        canEdit: canEditSchedules,
                        onEdit: canEditSchedules
                            ? () =>
                                _openEditor(ctx, ref, cfg, initial: s)
                            : () {},
                        onToggle: (enabled) async {
                          final next = [
                            for (final x in list)
                              x.id == s.id ? x.copyWith(enabled: enabled) : x
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
                        onRun: () async {
                          try {
                            await ref.read(scheduleApiProvider).runNow(s.id);
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
  }) async {
    final existing = ref.read(schedulesProvider).value ?? const [];
    final saved = await showModalBottomSheet<List<Schedule>>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScheduleEditorSheet(
        schedules: existing,
        config: cfg,
        initiallySelectedId: initial?.id,
      ),
    );
    if (saved != null) {
      ref.invalidate(schedulesProvider);
    }
  }
}

/// Lets the customer connect their own Spotify account (one-time OAuth).
/// Search/play then works inside the player popups via Spotify Connect.
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
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        radius: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.library_music_outlined,
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
          const Icon(Icons.check_circle_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    required this.onRun,
  });
  final Schedule schedule;
  final HouseConfig config;
  final bool canEdit;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: Theme.of(context).textTheme.titleMedium,
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
              IconButton(
                tooltip:
                    canEdit ? 'Nu uitvoeren' : 'Alleen zichtbaar — geen rechten',
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

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(
        child: Text(
          'versie $_kAppVersion',
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
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: LuxeShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: LuxeColors.surface.withValues(alpha: 0.7),
                border: Border.all(color: LuxeColors.glassRim),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 16, color: LuxeColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
