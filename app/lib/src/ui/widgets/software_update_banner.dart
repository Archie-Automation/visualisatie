import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../android_apk_updater.dart';
import '../../api.dart';
import '../../software_update_controller.dart';
import '../../software_version.dart';
import 'reload_app_stub.dart'
    if (dart.library.html) 'reload_app_web.dart' as reload;

/// Web: balk voor serverupdate (installer) of een verouderde PWA.
/// Android toont geen balk maar het update-icoon in de kopregel; deze widget
/// blijft daar wel de versie pollen, ook buiten het dashboard.
class SoftwareUpdateBanner extends ConsumerStatefulWidget {
  const SoftwareUpdateBanner({super.key});

  @override
  ConsumerState<SoftwareUpdateBanner> createState() =>
      _SoftwareUpdateBannerState();
}

class _SoftwareUpdateBannerState extends ConsumerState<SoftwareUpdateBanner> {
  Timer? _poll;
  int? _pollSeconds;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _setPoll(int? seconds) {
    if (seconds == null) {
      _poll?.cancel();
      _poll = null;
      _pollSeconds = null;
      return;
    }
    if (_poll != null && _pollSeconds == seconds) return;
    _poll?.cancel();
    _pollSeconds = seconds;
    _poll = Timer.periodic(Duration(seconds: seconds), (_) async {
      if (!mounted) return;
      final prev = apkIdentity(
        ref.read(softwareVersionStatusProvider).asData?.value?.latest?.androidApk,
      );
      ref.invalidate(softwareVersionStatusProvider);
      final next = await ref.read(softwareVersionStatusProvider.future);
      if (!mounted) return;
      ref
          .read(softwareUpdateControllerProvider.notifier)
          .apkChanged(prev, apkIdentity(next?.latest?.androidApk));
    });
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(authProvider).isInstaller;
    final status = ref.watch(softwareVersionStatusProvider).asData?.value;
    final update = ref.watch(softwareUpdateControllerProvider);
    final offer = ref.watch(softwareUpdateOfferProvider);

    if (supportsAndroidApkUpdate) {
      final apkWaiting = status?.androidApkPending == true ||
          status?.clientStale == true ||
          (status?.androidApkUpdateAvailable == true &&
              !offer.app &&
              !offer.appWaitsForServer);
      // Ook zonder melding pollen. Anders blijft een tablet op de eerste
      // controle staan tot de app even weg is. Vaker zolang de APK nog komt.
      _setPoll(update.busy ? null : (offer.app || apkWaiting) ? 8 : 45);
      return const SizedBox.shrink();
    }
    _setPoll(null);

    if (update.serverUpdating) {
      return _Banner(
        message: update.serverProgress ?? 'Server bijwerken…',
        progress: 0,
      );
    }
    if (status == null || !status.autoUpdateEnabled) {
      return const SizedBox.shrink();
    }

    if (admin && status.updateAvailable) {
      final latest = status.latest;
      final ver = latest?.version ?? latest?.tag ?? '';
      if (status.serverUpdate?.agentReady == true) {
        return _Banner(
          message: update.error ??
              (ver.isEmpty
                  ? 'Nieuwe software. Eén tik werkt de server bij.'
                  : 'Nieuwe software ($ver). Eén tik werkt de server bij.'),
          actionLabel: 'Bijwerken',
          onAction: () => ref
              .read(softwareUpdateControllerProvider.notifier)
              .updateServerThenApp(),
        );
      }
      return _Banner(
        message: ver.isEmpty
            ? 'Nieuwe versie. Eenmalig op de NUC: sudo bash docker/install.sh. Daarna vanaf de app.'
            : 'Nieuwe versie ($ver). Eenmalig op de NUC: sudo bash docker/install.sh. Daarna vanaf de app.',
        actionLabel: latest?.htmlUrl != null ? 'Bekijken' : null,
        onAction: latest?.htmlUrl != null
            ? () => openReleasePage(latest!.htmlUrl)
            : null,
      );
    }

    if (admin && status.clientStale && kIsWeb) {
      return _Banner(
        message: status.running.version.isEmpty
            ? 'Nieuwe softwarestand beschikbaar. Vernieuw de app.'
            : 'Nieuwe softwarestand beschikbaar (${status.running.version}). Vernieuw de app.',
        actionLabel: 'Vernieuwen',
        onAction: reload.reloadApp,
      );
    }

    return const SizedBox.shrink();
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
