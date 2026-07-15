import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented when the wandtablet idle timer resets navigation/scroll state.
class IdleResetSignal extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final idleResetSignalProvider =
    NotifierProvider<IdleResetSignal, int>(IdleResetSignal.new);
