import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../inactivity_controller.dart';
import '../../melding_alert_sound.dart';
import '../../melding_nav.dart';
import '../../proximity_wake.dart';

/// App-wide listener: urgent meldingen ring even if the tile is off-screen.
class MeldingAlertSoundLayer extends ConsumerStatefulWidget {
  const MeldingAlertSoundLayer({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MeldingAlertSoundLayer> createState() =>
      _MeldingAlertSoundLayerState();
}

class _MeldingAlertSoundLayerState
    extends ConsumerState<MeldingAlertSoundLayer> {
  var _playing = false;
  var _seenSnapshot = false;
  Set<String> _notifyKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void dispose() {
    MeldingAlertSound.stop();
    super.dispose();
  }

  void _openMeldingen() {
    ProximityWake.wakeScreen();
    ref.read(inactivityControllerProvider.notifier).hideScreensaver();
    ref.read(inactivityControllerProvider.notifier).registerActivity();
    MeldingNav.request();
  }

  void _sync() {
    if (!mounted) return;
    final cfg = ref.read(configProvider).value;
    final bus = ref.read(busProvider);
    final silenced = ref.read(meldingAlertSilenceProvider);
    final active = collectActiveUrgentMeldingKeys(cfg, bus.values);
    ref.read(meldingAlertSilenceProvider.notifier).retainOnly(active);
    _apply(active.any((k) => !silenced.contains(k)));
    if (bus.snapshotEpoch == 0) return;
    final notify = collectActiveNotifyMeldingKeys(cfg, bus.values);
    if (!_seenSnapshot) {
      _seenSnapshot = true;
      _notifyKeys = notify;
      return;
    }
    final fresh = notify.difference(_notifyKeys);
    _notifyKeys = notify;
    if (fresh.isNotEmpty) _openMeldingen();
  }

  void _apply(bool shouldPlay) {
    if (shouldPlay == _playing) return;
    _playing = shouldPlay;
    if (shouldPlay) {
      HapticFeedback.heavyImpact();
      ProximityWake.wakeScreen();
      ref.read(inactivityControllerProvider.notifier).registerActivity();
      MeldingAlertSound.start();
    } else {
      MeldingAlertSound.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (_, __) => _sync());
    ref.listen(busProvider, (_, __) => _sync());
    ref.listen(meldingAlertSilenceProvider, (_, __) => _sync());
    return widget.child;
  }
}
