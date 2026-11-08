import 'package:flutter/foundation.dart';

/// Korte naam voor de sessielijst. Maximaal 64 tekens (server knipt daar).
String deviceLabel() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android-app',
    TargetPlatform.iOS => 'iOS-app',
    TargetPlatform.windows => 'Windows-app',
    TargetPlatform.macOS => 'Mac-app',
    TargetPlatform.linux => 'Linux-app',
    _ => 'App',
  };
}
