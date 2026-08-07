import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera_api.dart';
import '../theme.dart';
import 'widgets/camera_stream_body.dart';
import 'widgets/luxe_backdrop.dart';

/// Surveillance camera view. View-only, no microphone.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, required this.cameraId});
  final String cameraId;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(cameraInfoProvider(widget.cameraId));

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: info.maybeWhen(
          data: (i) => Text(i.name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.5,
              )),
          orElse: () => const SizedBox.shrink(),
        ),
      ),
      body: LuxeBackdrop(
        dark: true,
        child: Center(
          child: info.when(
            loading: () =>
                CircularProgressIndicator(color: LuxeColors.brass),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(40),
              child: Text('Kan camera niet laden:\n$e',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
            ),
            data: (i) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
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
    );
  }
}
