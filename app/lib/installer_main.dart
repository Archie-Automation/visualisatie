import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/installer/installer_app.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  try {
    await preloadLuxeFonts();
  } catch (e) {
    if (kDebugMode) debugPrint('Font preload mislukt: $e');
  }
  runApp(const ProviderScope(child: ArchieOsInstallerApp()));
}
