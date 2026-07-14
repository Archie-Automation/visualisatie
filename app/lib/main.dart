import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/app_bootstrap.dart';

void main() {
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
