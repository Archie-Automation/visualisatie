import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../android_apk_updater.dart';
import '../../api.dart';
import '../../full_app_restart.dart';
import '../../server_update.dart';
import '../../software_version.dart';
import '../../theme.dart';
import 'reload_app_stub.dart'
    if (dart.library.html) 'reload_app_web.dart' as reload;

/// Banner: stale PWA (reload), Android APK install, or newer GitHub release.
class SoftwareUpdateBanner extends ConsumerStatefulWidget {
  const SoftwareUpdateBanner({super.key});

  @override
  ConsumerState<SoftwareUpdateBanner> createState() =>
      _SoftwareUpdateBannerState();
}

class _SoftwareUpdateBannerState extends ConsumerState<SoftwareUpdateBanner> {
  bool _installing = false;
  bool _serverUpdating = false;
  double? _progress;
  String? _error;
  String? _serverProgress;

  Future<void> _installApk(GithubAndroidApkInfo? apk) async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _progress = 0;
      _error = null;
    });
    final result = await downloadAndInstallAndroidApk(
      fileName: apk?.name,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _installing = false;
      _progress = result.ok ? 1 : null;
      _error = result.ok ? null : _apkInstallErrorMessage(result.error);
    });
  }

  Future<void> _updateServer() async {
    if (_serverUpdating) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() {
      _serverUpdating = true;
      _serverProgress = 'Update starten…';
      _error = null;
    });
    try {
      await postServerUpdate(token);
      final result = await waitForServerUpdate(
        token: token,
        onMessage: (m) {
          if (mounted) setState(() => _serverProgress = m);
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
      if (!mounted) return;
      setState(() {
        _serverUpdating = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
      return;
    }
    if (mounted) setState(() => _serverUpdating = false);
  }

  @override
  Widget build(BuildContext context) {
    final outdated = ref.watch(softwareUpdateAvailableProvider);
    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    final admin = ref.watch(authProvider).isAdmin;

    if (_serverUpdating) {
      return _Banner(
        message: _serverProgress ?? 'Server bijwerken…',
        progress: 0,
      );
    }

    if (!outdated) return const SizedBox.shrink();
    if (status == null) return const SizedBox.shrink();

    // Native tablet: APK install beats the web-only "Vernieuwen" path.
    if (status.androidApkUpdateAvailable) {
      final latest = status.latest;
      final ver = latest?.tag ?? latest?.version ?? '';
      final message = _error ??
          (_installing
              ? 'App-update downloaden… Bevestig daarna de installatie.'
              : (ver.isEmpty
                  ? 'Nieuwe app-versie beschikbaar.'
                  : 'Nieuwe app-versie ($ver) beschikbaar.'));
      return _Banner(
        message: message,
        actionLabel: _installing ? null : 'Installeren',
        onAction:
            _installing ? null : () => _installApk(latest?.androidApk),
        progress: _installing ? (_progress ?? 0) : null,
      );
    }

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
    final agentReady = status.serverUpdate?.agentReady == true;
    if (admin && agentReady) {
      return _Banner(
        message: _error ??
            (ver.isEmpty
                ? 'Nieuwe serverversie op GitHub. Bijwerken duurt 10–20 minuten.'
                : 'Nieuwe serverversie ($ver). Bijwerken duurt 10–20 minuten.'),
        actionLabel: 'Server bijwerken',
        onAction: _updateServer,
      );
    }
    if (admin) {
      return _Banner(
        message: ver.isEmpty
            ? 'Nieuwe versie op GitHub. Eenmalig op de NUC: sudo bash docker/install.sh. Daarna vanaf de tablet.'
            : 'Nieuwe versie ($ver). Eenmalig op de NUC: sudo bash docker/install.sh. Daarna vanaf de tablet.',
        actionLabel: latest?.htmlUrl != null ? 'Bekijken' : null,
        onAction: latest?.htmlUrl != null
            ? () => openReleasePage(latest!.htmlUrl)
            : null,
      );
    }
    return _Banner(
      message: ver.isEmpty
          ? 'Er is een nieuwere versie op GitHub. Vraag de beheerder de server bij te werken.'
          : 'Nieuwe versie op GitHub ($ver). Vraag de beheerder de server bij te werken.',
      actionLabel: latest?.htmlUrl != null ? 'Bekijken' : null,
      onAction: latest?.htmlUrl != null
          ? () => openReleasePage(latest!.htmlUrl)
          : null,
    );
  }
}

String _apkInstallErrorMessage(String? code) {
  switch (code) {
    case 'install_permission_denied':
      return 'Sta “apps uit onbekende bronnen” toe voor Archie OS en tik opnieuw op Installeren.';
    case 'apk_too_small':
    case 'apk_missing':
      return 'De gedownloade APK is ongeldig. Controleer of de GitHub Release een .apk heeft.';
    case 'install_intent_failed':
    case 'install_failed':
      return 'Android kon de installatie niet starten.';
    default:
      if (code != null && code.startsWith('download_http_')) {
        return 'Download mislukt ($code). Staat er een .apk op de GitHub Release?';
      }
      return 'Update mislukt${code == null || code.isEmpty ? '.' : ': $code'}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.progress,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFF3D3428),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              if (progress != null) ...[
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress! > 0 && progress! < 1 ? progress : null,
                    minHeight: 3,
                    color: LuxeColors.brass,
                    backgroundColor: LuxeColors.lineSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
