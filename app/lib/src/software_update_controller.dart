import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_apk_updater.dart';
import 'api.dart';
import 'full_app_restart.dart';
import 'server_update.dart';
import 'software_version.dart';

const _keep = Object();

/// Lopende app- of serverupdate. Gedeeld door de webbalk en het
/// update-icoon op Android, zodat een gesloten popup de download niet stopt.
class SoftwareUpdateState {
  const SoftwareUpdateState({
    this.installing = false,
    this.serverUpdating = false,
    this.progress,
    this.received = 0,
    this.error,
    this.serverProgress,
    this.rejectedApkKey,
  });

  final bool installing;
  final bool serverUpdating;
  final double? progress;
  final int received;
  final String? error;
  final String? serverProgress;

  /// GitHub-APK die Android weigerde (`apk_not_newer`). Niet opnieuw aanbieden
  /// tot naam/grootte/versie verandert — anders blijft Installeren dezelfde
  /// oude binary downloaden terwijl de server al verder is.
  final String? rejectedApkKey;

  bool get busy => installing || serverUpdating;

  SoftwareUpdateState copyWith({
    bool? installing,
    bool? serverUpdating,
    Object? progress = _keep,
    int? received,
    Object? error = _keep,
    Object? serverProgress = _keep,
    Object? rejectedApkKey = _keep,
  }) {
    return SoftwareUpdateState(
      installing: installing ?? this.installing,
      serverUpdating: serverUpdating ?? this.serverUpdating,
      progress: identical(progress, _keep) ? this.progress : progress as double?,
      received: received ?? this.received,
      error: identical(error, _keep) ? this.error : error as String?,
      serverProgress: identical(serverProgress, _keep)
          ? this.serverProgress
          : serverProgress as String?,
      rejectedApkKey: identical(rejectedApkKey, _keep)
          ? this.rejectedApkKey
          : rejectedApkKey as String?,
    );
  }
}

String apkIdentity(GithubAndroidApkInfo? apk) {
  if (apk == null) return '';
  return '${apk.version ?? ''}|${apk.sizeBytes}|${apk.name}';
}

class SoftwareUpdateController extends Notifier<SoftwareUpdateState> {
  @override
  SoftwareUpdateState build() => const SoftwareUpdateState();

  /// Na een poll: een nieuw bestand op de server wist de oude foutmelding.
  void apkChanged(String previous, String next) {
    if (next != previous && next != state.rejectedApkKey) {
      state = state.copyWith(error: null);
    }
  }

  Future<SoftwareVersionStatus?> _refreshStatus() async {
    ref.invalidate(softwareVersionStatusProvider);
    return ref.read(softwareVersionStatusProvider.future);
  }

  /// True zodra Android de installatievraag toont.
  Future<bool> installApk(GithubAndroidApkInfo? apk) async {
    if (state.installing) return false;
    state = state.copyWith(
      installing: true,
      progress: 0,
      received: 0,
      error: null,
    );
    final result = await downloadAndInstallAndroidApk(
      token: ref.read(authProvider).token,
      fileName: apk?.name,
      onProgress: (p) => state = state.copyWith(progress: p),
      onBytes: (got, _) => state = state.copyWith(received: got),
    );
    if (result.error == 'apk_not_newer') {
      state = state.copyWith(
        installing: false,
        progress: null,
        rejectedApkKey: apkIdentity(apk),
        error: apkInstallErrorMessage(result.error),
      );
      ref.invalidate(softwareVersionStatusProvider);
      return false;
    }
    state = state.copyWith(
      installing: false,
      progress: result.ok ? 1.0 : null,
      error: result.ok ? null : apkInstallErrorMessage(result.error),
    );
    if (result.ok ||
        result.error == 'install_aborted' ||
        result.error == 'busy') {
      ref.invalidate(softwareVersionStatusProvider);
    }
    return result.ok;
  }

  /// Alleen een installer-account: de server weigert anderen ook.
  /// True als de server klaar is en de app (indien nodig) volgt.
  Future<bool> updateServerThenApp() async {
    if (state.busy) return false;
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null || !auth.isInstaller) return false;
    state = state.copyWith(
      serverUpdating: true,
      serverProgress: 'Update starten…',
      error: null,
    );
    try {
      await postServerUpdate(token);
      final result = await waitForServerUpdate(
        token: token,
        onMessage: (m) => state = state.copyWith(serverProgress: m),
      );
      if (result.isError) {
        throw StateError(
          result.message.isEmpty ? 'Update mislukt.' : result.message,
        );
      }
      await waitForBackendOnline(timeout: const Duration(minutes: 3));
      state = state.copyWith(
        serverProgress: 'Server klaar. App-update controleren…',
      );
      var status = await _refreshStatus();
      if (supportsAndroidApkUpdate) {
        for (var i = 0; i < 45; i++) {
          status = await _refreshStatus();
          if (status?.androidApkUpdateAvailable == true) break;
          if (status != null &&
              !status.clientStale &&
              !status.androidApkPending) {
            break;
          }
          state = state.copyWith(
            serverProgress: 'App-update wordt klaargezet…',
          );
          await Future<void>.delayed(const Duration(seconds: 8));
        }
      }
      state = state.copyWith(serverUpdating: false, serverProgress: null);
      final apkVer = status?.latest?.androidApk?.asVersion;
      if (supportsAndroidApkUpdate &&
          status?.androidApkUpdateAvailable == true &&
          apkVer != null &&
          status!.running.compareTo(apkVer) >= 0) {
        return installApk(status.latest?.androidApk);
      }
      if (kIsWeb) {
        await fullAppRemountOrReload();
      }
      return true;
    } catch (e) {
      state = state.copyWith(
        serverUpdating: false,
        serverProgress: null,
        error: e.toString().replaceFirst('Bad state: ', ''),
      );
      return false;
    }
  }
}

final softwareUpdateControllerProvider =
    NotifierProvider<SoftwareUpdateController, SoftwareUpdateState>(
  SoftwareUpdateController.new,
);

/// Wat deze gebruiker nu kan bijwerken.
class SoftwareUpdateOffer {
  const SoftwareUpdateOffer({
    this.app = false,
    this.appWaitsForServer = false,
    this.server = false,
    this.apk,
    this.appVersion = '',
    this.serverVersion = '',
  });

  /// APK nieuwer dan deze tablet. Elk account mag installeren.
  final bool app;

  /// APK is nieuwer dan deze tablet, maar de server loopt nog achter.
  final bool appWaitsForServer;

  /// Nieuwere serversoftware. Alleen voor een installer-account.
  final bool server;
  final GithubAndroidApkInfo? apk;
  final String appVersion;
  final String serverVersion;

  bool get any => app || server;
}

final softwareUpdateOfferProvider =
    Provider.autoDispose<SoftwareUpdateOffer>((ref) {
  final status = ref.watch(softwareVersionStatusProvider).asData?.value;
  final admin = ref.watch(authProvider).isInstaller;
  final rejected = ref.watch(
    softwareUpdateControllerProvider.select((s) => s.rejectedApkKey),
  );
  if (status == null || !status.autoUpdateEnabled) {
    return const SoftwareUpdateOffer();
  }
  final apk = status.latest?.androidApk;
  final apkNewer = supportsAndroidApkUpdate &&
      status.androidApkUpdateAvailable &&
      apkIdentity(apk) != rejected;
  // Eerst de server, dan de app: een app nieuwer dan de backend kan een API
  // verwachten die de server nog niet heeft.
  final apkVer = apk?.asVersion;
  final serverReady = apkVer != null && status.running.compareTo(apkVer) >= 0;
  final server = admin &&
      status.updateAvailable &&
      status.serverUpdate?.agentReady == true;
  return SoftwareUpdateOffer(
    app: apkNewer && serverReady,
    appWaitsForServer: apkNewer && !serverReady,
    server: server,
    apk: apk,
    appVersion: apk?.version ?? '',
    serverVersion: status.latest?.version ?? status.latest?.tag ?? '',
  );
});

String apkInstallErrorMessage(String? code) {
  switch (code) {
    case 'install_permission_denied':
      return 'Sta “apps uit onbekende bronnen” toe voor Archie OS en tik opnieuw op Installeren.';
    case 'apk_too_small':
    case 'apk_missing':
      return 'De gedownloade app is ongeldig. Probeer het later opnieuw.';
    case 'download_stalled':
      return 'De download bleef stil. Tik Server bijwerken, wacht tot die klaar is, en tik dan opnieuw op Installeren.';
    case 'apk_invalid':
      return 'Het gedownloade bestand is geen geldige app. Probeer het later opnieuw.';
    case 'apk_not_newer':
      return 'Het installatiebestand is niet nieuwer dan deze app. '
          'Installeren heeft niets veranderd. Wacht tot er een nieuwere APK klaarstaat.';
    case 'install_aborted':
      return 'Installatie afgebroken. Tik opnieuw op Installeren en bevestig op het tablet.';
    case 'install_blocked':
      return 'Android blokkeert de installatie. Controleer ouderlijk toezicht of zakelijke beperkingen.';
    case 'install_conflict':
      return 'Android weigert de update (andere handtekening). Verwijder Archie OS eenmalig en installeer opnieuw.';
    case 'install_incompatible':
      return 'Deze app-versie past niet op dit tablet.';
    case 'install_storage':
      return 'Te weinig opslagruimte om de app te installeren.';
    case 'install_intent_failed':
    case 'install_failed':
    case 'busy':
      return 'Installatie mislukt. Tik opnieuw op Installeren.';
    default:
      if (code != null && code.startsWith('download_http_401')) {
        return 'Niet ingelogd of sessie verlopen. Log opnieuw in en probeer de update opnieuw.';
      }
      if (code != null && code.startsWith('download_http_403')) {
        return 'Download geweigerd. Controleer de serverinstellingen op de NUC.';
      }
      if (code != null && code.startsWith('download_http_404')) {
        return 'De app-update is nog niet beschikbaar. Probeer het later opnieuw.';
      }
      if (code != null && code.startsWith('download_http_504')) {
        return 'De NUC kreeg de app-update niet op tijd. Controleer het netwerk en probeer opnieuw.';
      }
      if (code != null && code.startsWith('download_http_')) {
        return 'Download mislukt ($code). Probeer het later opnieuw.';
      }
      if (code != null &&
          (code.contains('Connection closed before full header') ||
              code.contains('ClientException'))) {
        return 'Verbinding met de NUC viel weg tijdens de download. '
            'Update eerst de server, daarna opnieuw Installeren.';
      }
      return 'Update mislukt${code == null || code.isEmpty ? '.' : ': $code'}';
  }
}
