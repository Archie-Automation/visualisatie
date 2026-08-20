import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _confirmAndUpdate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server bijwerken?'),
        content: const Text(
          'De NUC haalt de nieuwste versie van GitHub en bouwt de software opnieuw. '
          'Dat duurt 10–20 minuten. Het huis blijft werken tot een korte herstart aan het eind. '
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
      await fullAppRemountOrReload();
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

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    final su = status?.serverUpdate;
    final agentReady = su?.agentReady == true;
    final newer = status?.updateAvailable == true;
    final latest = status?.latest?.tag ?? status?.latest?.version;
    final running = status?.running.version ?? kAppVersion;

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
          ? 'Er staat een nieuwere versie op GitHub. Nu draait $running.'
          : 'GitHub heeft $latest. Deze server draait $running.';
    } else {
      body =
          'Deze server draait $running en is gelijk met GitHub. '
          'Je kunt toch opnieuw bouwen als iets vastzit.';
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
              SizedBox(width: 10),
              Text(
                'BEHEERDER: SERVER BIJWERKEN',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                    : (newer ? 'Server bijwerken van GitHub' : 'Opnieuw bouwen'),
              ),
              onPressed: _busy || !agentReady ? null : _confirmAndUpdate,
            ),
          ),
        ],
      ),
    );
  }
}
