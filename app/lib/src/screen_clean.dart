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
    if (!wallTabletDeviceSettingsApply) return child;
    final seconds = ref.watch(screenCleanProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (seconds != null)
          const Positioned.fill(child: _ScreenCleanBarrier()),
      ],
    );
  }
}

class _ScreenCleanBarrier extends ConsumerWidget {
  const _ScreenCleanBarrier();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(screenCleanProvider) ?? 0;
    return BackButtonListener(
      onBackButtonPressed: () async => true,
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$seconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Scherm schoonmaken',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
