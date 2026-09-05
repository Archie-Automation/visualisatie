import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final info = ref.watch(cameraInfoProvider(cameraId));
    final title = info.maybeWhen(
      data: (i) => i.name,
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
              child: info.when(
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
                data: (i) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  child: LiveVideoFittedStage(
                    aspectRatio: i.aspectRatio,
                    heroTag: 'cam-${i.id}',
                    child: CameraLivePlayer(
                      info: i,
                      fit: BoxFit.contain,
                      expand: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
