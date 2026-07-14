import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/installer/installer_app.dart';

void main() {
  runApp(const ProviderScope(child: LuxeKnxInstallerApp()));
}
