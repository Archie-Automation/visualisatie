import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/api.dart';
import 'src/app.dart';
import 'src/app_bootstrap.dart';
import 'src/kiosk_system_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyAndroidKioskSystemUi();
  await loadApiBaseOverride();
  runApp(
    ValueListenableBuilder<int>(
      valueListenable: appBootEpoch,
      builder: (context, epoch, _) {
        return ProviderScope(
          key: ValueKey<int>(epoch),
          child: const LuxeKnxApp(),
        );
      },
    ),
  );
}
