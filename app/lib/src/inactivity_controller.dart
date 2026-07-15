import 'package:flutter_riverpod/flutter_riverpod.dart';

class InactivityState {
  const InactivityState({
    required this.lastActivity,
    this.screensaverVisible = false,
    this.homeReturnedThisIdle = false,
  });

  final DateTime lastActivity;
  final bool screensaverVisible;
  final bool homeReturnedThisIdle;

  InactivityState copyWith({
    DateTime? lastActivity,
    bool? screensaverVisible,
    bool? homeReturnedThisIdle,
  }) =>
      InactivityState(
        lastActivity: lastActivity ?? this.lastActivity,
        screensaverVisible: screensaverVisible ?? this.screensaverVisible,
        homeReturnedThisIdle:
            homeReturnedThisIdle ?? this.homeReturnedThisIdle,
      );
}

class InactivityController extends Notifier<InactivityState> {
  @override
  InactivityState build() => InactivityState(lastActivity: DateTime.now());

  void registerActivity() {
    final wasScreensaver = state.screensaverVisible;
    state = InactivityState(lastActivity: DateTime.now());
    if (wasScreensaver) {
      state = state.copyWith(screensaverVisible: false);
    }
  }

  void showScreensaver() {
    if (!state.screensaverVisible) {
      state = state.copyWith(screensaverVisible: true);
    }
  }

  void hideScreensaver() {
    if (state.screensaverVisible) {
      state = state.copyWith(screensaverVisible: false);
    }
  }

  void markHomeReturned() {
    if (!state.homeReturnedThisIdle) {
      state = state.copyWith(homeReturnedThisIdle: true);
    }
  }
}

final inactivityControllerProvider =
    NotifierProvider<InactivityController, InactivityState>(
  InactivityController.new,
);
