import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Spraak van de intercom op het mediavolume van de tablet.
///
/// Het bel-volume (STREAM_VOICE_CALL) heeft op Android maar een paar standen.
/// De eerste stand boven nul is op de luidspreker al hard, daaronder is het
/// zacht. Het mediavolume heeft die tussenstanden wel. Dit moet vóór de eerste
/// WebRTC-sessie, omdat de audio-route daarna vaststaat.
Future<void> configurePanelSpeechAudio() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final config = AndroidAudioConfiguration(
    manageAudioFocus: true,
    androidAudioMode: AndroidAudioMode.normal,
    androidAudioFocusMode: AndroidAudioFocusMode.gain,
    androidAudioStreamType: AndroidAudioStreamType.music,
    androidAudioAttributesUsageType: AndroidAudioAttributesUsageType.media,
    androidAudioAttributesContentType: AndroidAudioAttributesContentType.speech,
    forceHandleAudioRouting: true,
  );
  try {
    await WebRTC.initialize(options: {
      'androidAudioConfiguration': config.toMap(),
      // Hardware-echo-onderdrukking werkt alleen in de bel-modus. Die modus
      // koppelt het volume aan het grove bel-volume, dus die laten we uit.
      'androidUseHardwareAudioProcessing': false,
    });
    await Helper.setAndroidAudioConfiguration(config);
    await Helper.setSpeakerphoneOn(true);
  } catch (e) {
    debugPrint('[speech] audio-route mislukt: $e');
  }
}
