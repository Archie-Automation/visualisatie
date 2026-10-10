import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_panel_config.dart';

const screenCleanDuration = Duration(seconds: 20);

/// Seconden die nog lopen, of null als het scherm normaal reageert.
/// 0 blijft even staan zodat de aftelling zichtbaar eindigt.
class ScreenCleanController extends Notifier<int?> {
  Timer? _timer;

  @override
  int? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void start() {
    _timer?.cancel();
    var left = screenCleanDuration.inSeconds;
    state = left;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      left -= 1;
      if (left > 0) {
        state = left;
        return;
      }
      t.cancel();
      state = 0;
      _timer = Timer(const Duration(milliseconds: 700), () {
        _timer = null;
        state = null;
      });
    });
  }
}

final screenCleanProvider = NotifierProvider<ScreenCleanController, int?>(
  ScreenCleanController.new,
);

/// Android: volledig scherm dat aanrakingen negeert tot [screenCleanProvider] leeg is.
class ScreenCleanLayer extends ConsumerWidget {
  const ScreenCleanLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(screenCleanProvider);
    if (!wallTabletDeviceSettingsApply || seconds == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(child: ScreenCleanView(seconds: seconds)),
      ],
    );
  }
}

/// Opent het schoonmaakscherm als eigen route, boven instellingen.
void openScreenClean(BuildContext context, WidgetRef ref) {
  if (ref.read(screenCleanProvider) != null) return;
  ref.read(screenCleanProvider.notifier).start();
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const ScreenCleanPage(),
    ),
  );
}

class ScreenCleanPage extends ConsumerWidget {
  const ScreenCleanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int?>(screenCleanProvider, (prev, next) {
      if (next != null || prev == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      });
    });
    final seconds = ref.watch(screenCleanProvider) ?? 0;
    return ScreenCleanView(seconds: seconds);
  }
}

class ScreenCleanView extends StatelessWidget {
  const ScreenCleanView({super.key, required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    final fontSize = (side * 0.42).clamp(180.0, 420.0);
    return BackButtonListener(
      onBackButtonPressed: () async => true,
      child: AbsorbPointer(
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: SizedBox.expand(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$seconds',
                      style: TextStyle(
                        color: const Color(0xFFFFFFFF),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        height: 0.9,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Scherm schoonmaken',
                      style: TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
