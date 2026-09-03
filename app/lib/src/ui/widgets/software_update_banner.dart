import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../android_apk_updater.dart';
import '../../api.dart';
import '../../full_app_restart.dart';
import '../../server_update.dart';
import '../../software_version.dart';
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
    final admin = ref.watch(authProvider).isInstaller;

    if (_serverUpdating) {
      return _Banner(
        message: _serverProgress ?? 'Server bijwerken…',
        progress: 0,
      );
    }

    if (!outdated) return const SizedBox.shrink();
    if (status == null) return const SizedBox.shrink();

    // Native tablet: tap anywhere on the strip to install. FilledButton/InkWell
    // often eats the first touch on PoE wall panels.
    final canInstallApk = supportsAndroidApkUpdate &&
        status.latest?.androidApk?.available == true &&
        (status.androidApkUpdateAvailable || status.clientStale);
    if (canInstallApk) {
      final latest = status.latest;
      final ver = latest?.tag ??
          latest?.version ??
          status.running.version;
      final message = _error ??
          (_installing
              ? 'App-update downloaden… Bevestig daarna de installatie.'
              : (ver.isEmpty
                  ? 'Nieuwe app-versie beschikbaar. Tik om te installeren.'
                  : 'Nieuwe app-versie ($ver) beschikbaar. Tik om te installeren.'));
      return _Banner(
        message: message,
        actionLabel: _installing ? null : 'Installeren',
        onAction:
            _installing ? null : () => _installApk(latest?.androidApk),
        progress: _installing ? (_progress ?? 0) : null,
      );
    }

    if (supportsAndroidApkUpdate && status.clientStale) {
      return _Banner(
        message: status.running.version.isEmpty
            ? 'Nieuwe software op de server. Tablet-APK ontbreekt nog op GitHub (release android-latest).'
            : 'Nieuwe software (${status.running.version}) op de server. Tablet-APK ontbreekt nog op GitHub (release android-latest).',
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
      if (code != null && code.startsWith('download_http_401')) {
        return 'GitHub token verlopen of ongeldig. '
            'Controleer GITHUB_TOKEN in docker/.env op de NUC.';
      }
      if (code != null && code.startsWith('download_http_403')) {
        return 'GitHub toegang geweigerd (403). '
            'Controleer GITHUB_TOKEN in docker/.env op de NUC.';
      }
      if (code != null && code.startsWith('download_http_404')) {
        return 'APK niet gevonden op GitHub. Staat er een release "android-latest" met .apk?';
      }
      if (code != null && code.startsWith('download_http_')) {
        return 'Download mislukt ($code). Staat er een .apk op de GitHub Release?';
      }
      return 'Update mislukt${code == null || code.isEmpty ? '.' : ': $code'}';
  }
}

/// High-contrast strip. Do not use [LuxeColors.ink] — those invert with theme
/// and produce dark-on-dark (Licht) or a bar that vanishes into the canvas (Donker).
class _BannerTone {
  const _BannerTone({
    required this.bg,
    required this.fg,
    required this.accent,
    required this.buttonBg,
    required this.buttonFg,
    required this.track,
    required this.statusIconBrightness,
  });

  final Color bg;
  final Color fg;
  final Color accent;
  final Color buttonBg;
  final Color buttonFg;
  final Color track;
  final Brightness statusIconBrightness;

  static _BannerTone of(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.light) {
      return const _BannerTone(
        bg: Color(0xFF1A1814),
        fg: Color(0xFFF7F6F2),
        accent: Color(0xFFE2C88A),
        buttonBg: Color(0xFFE8D5A8),
        buttonFg: Color(0xFF1A1814),
        track: Color(0x33F7F6F2),
        statusIconBrightness: Brightness.light,
      );
    }
    return const _BannerTone(
      bg: Color(0xFFE8E4DC),
      fg: Color(0xFF12110F),
      accent: Color(0xFF5E4722),
      buttonBg: Color(0xFF1A1814),
      buttonFg: Color(0xFFF7F6F2),
      track: Color(0x3312110F),
      statusIconBrightness: Brightness.dark,
    );
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
    final tone = _BannerTone.of(context);
    final tappable = onAction != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: tone.bg,
        statusBarIconBrightness: tone.statusIconBrightness,
        statusBarBrightness: tone.statusIconBrightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Material(
        color: tone.bg,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: tappable ? (_) => onAction!() : null,
          child: SafeArea(
            bottom: false,
            child: DefaultTextStyle(
              style: TextStyle(
                color: tone.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              child: IconTheme(
                data: IconThemeData(color: tone.accent, size: 20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.system_update_alt_rounded,
                              color: tone.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(color: tone.fg),
                            ),
                          ),
                          if (actionLabel != null)
                            IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                constraints: const BoxConstraints(minHeight: 44),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: tappable
                                      ? tone.buttonBg
                                      : tone.buttonBg.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Text(
                                  actionLabel!,
                                  style: TextStyle(
                                    color: tappable
                                        ? tone.buttonFg
                                        : tone.buttonFg.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress! > 0 && progress! < 1
                                ? progress
                                : null,
                            minHeight: 3,
                            color: tone.accent,
                            backgroundColor: tone.track,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
