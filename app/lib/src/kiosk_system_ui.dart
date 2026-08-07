import 'dart:io' show Platform;
import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Wall-tablet / PoE panel: hide Android status + nav bars permanently.
bool get isAndroidKioskTarget => !kIsWeb && Platform.isAndroid;

Future<void> applyAndroidKioskSystemUi() async {
  if (!isAndroidKioskTarget) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}
