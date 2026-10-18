import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/api.dart';
import 'src/app.dart';
import 'src/app_bootstrap.dart';
import 'src/intercom/panel_speech_audio.dart';
import 'src/kiosk_system_ui.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────────────
  // Prevent a single broken widget from bricking the wall panel.
  // Ook in release naar logcat: een leeg paneel is anders niet te diagnosticeren.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) {
    if (kDebugMode) return ErrorWidget(details.exception);
    return const SizedBox.shrink();
  };

  debugPrint('[boot] kiosk-ui');
  await applyAndroidKioskSystemUi();
  // Vóór de eerste camera of intercom, anders blijft spraak op het bel-volume.
  await configurePanelSpeechAudio();
  debugPrint('[boot] api-base');
  await loadApiBaseOverride();
  debugPrint('[boot] server-route');
  // LAN of cloud? Max ~1,5 s, thuis <200 ms. Splash pingt daarna de keuze.
  await chooseServerRoute();
  debugPrint('[boot] fonts');
  try {
    await preloadLuxeFonts();
  } catch (e) {
    debugPrint('Font preload mislukt: $e');
  }
  debugPrint('[boot] runApp');
  runApp(
    ValueListenableBuilder<int>(
      valueListenable: appBootEpoch,
      builder: (context, epoch, _) {
        return ProviderScope(
          key: ValueKey<int>(epoch),
          child: const ArchieOsApp(),
        );
      },
    ),
  );
}
