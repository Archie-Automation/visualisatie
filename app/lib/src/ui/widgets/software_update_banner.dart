import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../software_version.dart';
import '../../theme.dart';
import 'reload_app_stub.dart'
    if (dart.library.html) 'reload_app_web.dart' as reload;

/// Banner: stale PWA (reload) and/or newer release on GitHub (update server).
class SoftwareUpdateBanner extends ConsumerWidget {
  const SoftwareUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outdated = ref.watch(softwareUpdateAvailableProvider);
    if (!outdated) return const SizedBox.shrink();

    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    if (status == null) return const SizedBox.shrink();

    // Prefer reload when the page itself is stale; else GitHub update notice.
    if (status.clientStale) {
      return _Banner(
        message: status.running.version.isEmpty
            ? 'Nieuwe softwarestand beschikbaar. Vernieuw de app.'
            : 'Nieuwe softwarestand beschikbaar (${status.running.version}). Vernieuw de app.',
        actionLabel: kIsWeb ? 'Vernieuwen' : null,
        onAction: kIsWeb ? reload.reloadApp : null,
      );
    }

    final latest = status.latest;
    final ver = latest?.tag ?? latest?.version ?? '';
    return _Banner(
      message: ver.isEmpty
          ? 'Er is een nieuwere versie op GitHub. Update de server (./installeer.sh).'
          : 'Nieuwe versie op GitHub ($ver). Update de server met ./installeer.sh.',
      actionLabel: latest?.htmlUrl != null ? 'Bekijken' : null,
      onAction: latest?.htmlUrl != null
          ? () => openReleasePage(latest!.htmlUrl)
          : null,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFF3D3428),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                color: LuxeColors.brass,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: LuxeColors.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      color: LuxeColors.brass,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
