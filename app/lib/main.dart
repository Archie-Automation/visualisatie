import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/api.dart';
import 'src/app.dart';
import 'src/app_bootstrap.dart';
import 'src/kiosk_system_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────────────
  // Prevent a single broken widget from bricking the wall panel.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) {
    if (kDebugMode) return ErrorWidget(details.exception);
    return const SizedBox.shrink();
  };

  await applyAndroidKioskSystemUi();
  await loadApiBaseOverride();
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
