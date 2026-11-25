import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../android_apk_updater.dart';
import '../../software_update_controller.dart';
import '../../theme.dart';
import '../responsive.dart';

/// Android: uitroepteken naast de statusicoontjes zodra er iets bij te werken
/// valt. Aanraken opent de vraag om bij te werken.
class SoftwareUpdateIndicator extends ConsumerWidget {
  const SoftwareUpdateIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supportsAndroidApkUpdate) return const SizedBox.shrink();
    final offer = ref.watch(softwareUpdateOfferProvider);
    final busy = ref.watch(softwareUpdateControllerProvider.select((s) => s.busy));
    if (!offer.any && !busy) return const SizedBox.shrink();

    final phone = context.isPhone;
    final size = phone ? 48.0 : 52.0;
    final accent = LuxeColors.brassOnCanvas;
    return Padding(
      padding: EdgeInsets.only(right: phone ? 8 : 10),
      child: Semantics(
        button: true,
        label: 'Update beschikbaar',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showSoftwareUpdateDialog(context),
          child: LuxeRimBox(
            width: size,
            height: size,
            radius: phone ? 14 : 15,
            rimWidth: 1.4,
            rimColor: accent,
            fillColor: LuxeChipChrome.tileFill(context, pressed: false),
            shadows: LuxeShadows.soft,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: accent,
                      ),
                    )
                  : Icon(Icons.priority_high_rounded, color: accent, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSoftwareUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SoftwareUpdateDialog(),
  );
}

class _SoftwareUpdateDialog extends ConsumerWidget {
  const _SoftwareUpdateDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(softwareUpdateOfferProvider);
    final s = ref.watch(softwareUpdateControllerProvider);
    final ctrl = ref.read(softwareUpdateControllerProvider.notifier);
    final theme = Theme.of(context);

    Future<void> run(Future<bool> Function() action) async {
      final ok = await action();
      if (ok && context.mounted) Navigator.of(context).pop();
    }

    final Widget body;
    if (s.serverUpdating) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.serverProgress ?? 'Server bijwerken…'),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      );
    } else if (s.installing) {
      final mb = (s.received / (1024 * 1024)).toStringAsFixed(1);
      final p = s.progress;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.received > 0
                ? 'App downloaden… $mb MB. Bevestig daarna Installeren op het tablet.'
                : 'De server haalt de app op.',
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: p != null && p > 0 && p < 1 ? p : null),
        ],
      );
    } else {
      final lines = <String>[
        if (s.error != null) s.error!,
        if (s.error == null && offer.app)
          offer.appVersion.isEmpty
              ? 'Er is een nieuwe versie van de app. Wil je de app nu bijwerken?'
              : 'Er is een nieuwe versie van de app (${offer.appVersion}). '
                  'Wil je de app nu bijwerken?',
        if (s.error == null && offer.server)
          offer.serverVersion.isEmpty
              ? 'Er is nieuwe serversoftware. Bijwerken duurt meestal 1–3 minuten.'
              : 'Er is nieuwe serversoftware (${offer.serverVersion}). '
                  'Bijwerken duurt meestal 1–3 minuten.',
        if (s.error == null && !offer.any) 'Alles is bijgewerkt.',
      ];
      body = Text(lines.join('\n\n'));
    }

    return AlertDialog(
      title: const Text('Update'),
      content: DefaultTextStyle.merge(
        style: theme.textTheme.bodyMedium,
        child: body,
      ),
      actions: s.busy
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Verbergen'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(offer.any ? 'Later' : 'Sluiten'),
              ),
              if (offer.server)
                TextButton(
                  onPressed: () => run(ctrl.updateServerThenApp),
                  child: const Text('Server bijwerken'),
                ),
              if (offer.app)
                FilledButton(
                  onPressed: () => run(() => ctrl.installApk(offer.apk)),
                  child: const Text('App bijwerken'),
                ),
            ],
    );
  }
}
