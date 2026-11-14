import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../camera_api.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'widgets/camera_stream_body.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/live_video_stage.dart';
import 'widgets/luxe_backdrop.dart';

/// Surveillance camera view. View-only, no microphone.
class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key, required this.cameraId});
  final String cameraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    final title = cfg.maybeWhen(
      data: (c) => c.deviceById(cameraId)?.name ?? 'Camera',
      orElse: () => 'Camera',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FunctionScreenHeader(
              onBack: () => appBack(context),
              title: title,
              subtitle: "Camera's",
            ),
            Expanded(
              child: cfg.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: LuxeColors.brass),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'Kan camera niet laden:\n$e',
                      style: TextStyle(color: LuxeColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (c) {
                  final device = c.deviceById(cameraId);
                  if (device == null) {
                    return Center(
                      child: Text(
                        'Camera niet gevonden.',
                        style: TextStyle(color: LuxeColors.inkSoft),
                      ),
                    );
                  }
                  final info = CameraInfo.fromDevice(device);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    child: LiveVideoHuggingStage(
                      identity: info.id,
                      fallbackAspect: info.aspectRatio,
                      heroTag: 'cam-${info.id}',
                      builder: (onAspect) => CameraLivePlayer(
                        info: info,
                        fit: BoxFit.contain,
                        expand: true,
                        onIntrinsicAspect: onAspect,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
