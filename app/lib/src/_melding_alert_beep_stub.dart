import 'package:flutter/services.dart';

/// Non-web fallback (iOS / desktop). Android uses the native channel.
void playMeldingAlertBeep() {
  SystemSound.play(SystemSoundType.alert);
}
