import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../full_app_restart.dart';
import '../../theme.dart';
import 'glass_card.dart';

/// Volledige backend + app herstart (alleen voor ingelogde admin met token).
class AdminFullRestartCard extends ConsumerStatefulWidget {
  const AdminFullRestartCard({super.key});

  @override
  ConsumerState<AdminFullRestartCard> createState() =>
      _AdminFullRestartCardState();
}

class _AdminFullRestartCardState extends ConsumerState<AdminFullRestartCard> {
  bool _busy = false;

  Future<void> _confirmAndRestart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alles herstarten?'),
        content: const Text(
          'De server-api wordt kort herstart (inclusief camera-streaming). '
          'De app laadt daarna opnieuw zodra de server weer bereikbaar is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Herstarten'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await postAdminFullRestart(token);
      await waitForBackendOnline();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: LuxeColors.danger,
            shape: const StadiumBorder(),
            content: Text('Kon server niet herstarten: $e'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await fullAppRemountOrReload();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.fromLTRB(24, 22, 20, 22),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  color: LuxeColors.brassDeep, size: 22),
              SizedBox(width: 10),
              Text(
                'BEHEERDER: HERSTART',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Herstart de backend op de server en laad deze app opnieuw. '
            'Gebruik bij vastlopende streams of na grote configuratiewijzigingen.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
                  : const Icon(Icons.restart_alt),
              label: Text(_busy ? 'Even geduld…' : 'Herstart backend en app'),
              onPressed: _busy ? null : _confirmAndRestart,
            ),
          ),
        ],
      ),
    );
  }
}
