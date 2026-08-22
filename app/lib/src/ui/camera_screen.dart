import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera_api.dart';
import '../theme.dart';
import 'app_nav.dart';
import 'widgets/camera_stream_body.dart';
import 'widgets/function_screen_header.dart';
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
              child: Center(
                child: info.when(
                  loading: () =>
                      CircularProgressIndicator(color: LuxeColors.brass),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'Kan camera niet laden:\n$e',
                      style: TextStyle(color: LuxeColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  data: (i) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Hero(
                      tag: 'cam-${i.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: CameraLivePlayer(info: i, fit: BoxFit.contain),
                      ),
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
