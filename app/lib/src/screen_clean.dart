import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_panel_config.dart';
import 'theme.dart';

const screenCleanDuration = Duration(seconds: 20);

/// Einde van de schoonmaakperiode, of null als het scherm normaal reageert.
class ScreenCleanController extends Notifier<DateTime?> {
  Timer? _timer;

  @override
  DateTime? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void start() {
    _timer?.cancel();
    state = DateTime.now().add(screenCleanDuration);
    _timer = Timer(screenCleanDuration, () {
      _timer = null;
      state = null;
    });
  }
}

final screenCleanProvider =
    NotifierProvider<ScreenCleanController, DateTime?>(
  ScreenCleanController.new,
);

/// Android: volledig scherm dat aanrakingen negeert tot [screenCleanProvider] leeg is.
class ScreenCleanLayer extends ConsumerWidget {
  const ScreenCleanLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!wallTabletDeviceSettingsApply) return child;
    final endsAt = ref.watch(screenCleanProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (endsAt != null)
          Positioned.fill(child: _ScreenCleanBarrier(endsAt: endsAt)),
      ],
    );
  }
}

class _ScreenCleanBarrier extends StatefulWidget {
  const _ScreenCleanBarrier({required this.endsAt});

  final DateTime endsAt;

  @override
  State<_ScreenCleanBarrier> createState() => _ScreenCleanBarrierState();
}

class _ScreenCleanBarrierState extends State<_ScreenCleanBarrier> {
  Timer? _tick;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = _left();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = _left();
      if (!mounted || left == _seconds) return;
      setState(() => _seconds = left);
    });
  }

  @override
  void didUpdateWidget(_ScreenCleanBarrier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      setState(() => _seconds = _left());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int _left() {
    final ms = widget.endsAt.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BackButtonListener(
      onBackButtonPressed: () async => true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(
            dismissible: false,
            color: theme.scaffoldBackgroundColor,
          ),
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_seconds',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: LuxeColors.ink,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Scherm schoonmaken',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: LuxeColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aanraken doet niets',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: LuxeColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
