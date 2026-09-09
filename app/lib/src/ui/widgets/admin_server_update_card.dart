import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api.dart';
import '../../full_app_restart.dart';
import '../../server_update.dart';
import '../../software_version.dart';
import '../../theme.dart';
import 'glass_card.dart';

/// Admin: pull GitHub + rebuild Docker via the host update-agent.
class AdminServerUpdateCard extends ConsumerStatefulWidget {
  const AdminServerUpdateCard({super.key});

  @override
  ConsumerState<AdminServerUpdateCard> createState() =>
      _AdminServerUpdateCardState();
}

class _AdminServerUpdateCardState extends ConsumerState<AdminServerUpdateCard> {
  bool _busy = false;
  String? _progress;
  String? _error;
  bool _togglingAutoUpdate = false;

  Future<void> _confirmAndUpdate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server bijwerken?'),
        content: const Text(
          'De server haalt de nieuwste software op en installeert die opnieuw. '
          'Meestal 1–3 minuten. Het huis blijft werken tot een korte herstart aan het eind. '
          'Huisconfiguratie en wachtwoorden blijven bewaard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bijwerken'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Update starten…';
    });
    try {
      await postServerUpdate(token);
      final result = await waitForServerUpdate(
        token: token,
        onMessage: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      if (result.isError) {
        throw StateError(
          result.message.isEmpty ? 'Update mislukt.' : result.message,
        );
      }
      await waitForBackendOnline(timeout: const Duration(minutes: 3));
      ref.invalidate(softwareVersionStatusProvider);
      if (!mounted) return;
      if (kIsWeb) {
        await fullAppRemountOrReload();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = 'Klaar.';
      });
    }
  }

  Future<void> _toggleAutoUpdate(bool enabled) async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() => _togglingAutoUpdate = true);
    try {
      final res = await http
          .put(
            Uri.parse('$apiBase/api/admin/auto-update'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw StateError('Instelling opslaan mislukt (${res.statusCode})');
      }
      ref.invalidate(softwareVersionStatusProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _togglingAutoUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    final su = status?.serverUpdate;
    final agentReady = su?.agentReady == true;
    final newer = status?.updateAvailable == true;
    final latest = status?.latest?.tag ?? status?.latest?.version;
    final running = status?.running.version;
    final autoUpdate = status?.autoUpdateEnabled ?? true;

    String body;
    if (_error != null) {
      body = _error!;
    } else if (_busy) {
      body = _progress ?? 'Bezig…';
    } else if (!agentReady) {
      body =
          'Nog niet beschikbaar. Eenmalig op de NUC: sudo bash docker/install.sh. '
          'Daarna kun je vanaf deze app bijwerken.';
    } else if (newer) {
      body = latest == null
          ? 'Er is een nieuwere versie beschikbaar.'
          : 'Er is een nieuwere versie ($latest).';
    } else {
      body = 'Dit is de laatste versie.';
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_download_outlined,
                  color: LuxeColors.brassDeep, size: 22),
              const SizedBox(width: 10),
              Text(
                'SERVER BIJWERKEN',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('SERVERVERSIE', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            running == null || running.isEmpty ? '…' : running,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (newer && latest != null && latest.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('NIEUWE VERSIE', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              latest,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: LuxeColors.brassDeep,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: LuxeColors.ink,
                foregroundColor: LuxeColors.onInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    )
                  : const Icon(Icons.system_update_alt_rounded),
              label: Text(
                _busy
                    ? 'Bezig…'
                    : (newer ? 'Server bijwerken' : 'Opnieuw bouwen'),
              ),
              onPressed: _busy || !agentReady ? null : _confirmAndUpdate,
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTOMATISCHE UPDATES',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      autoUpdate
                          ? 'De app toont een melding wanneer er een nieuwe versie is.'
                          : 'Automatische updatemelding is uitgeschakeld.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _togglingAutoUpdate
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: autoUpdate,
                      activeThumbColor: LuxeColors.brassDeep,
                      onChanged: (v) => _toggleAutoUpdate(v),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
