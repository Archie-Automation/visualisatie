import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../camera_api.dart';
import '../kiosk_system_ui.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets/camera_snapshot.dart';
import 'widgets/camera_stream_body.dart';
import 'widgets/luxe_backdrop.dart';

void _restoreSystemUi() {
  if (isAndroidKioskTarget) {
    applyAndroidKioskSystemUi();
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

/// All surveillance cameras: one main live stream and a thumbnail strip.
class CamerasOverviewScreen extends ConsumerStatefulWidget {
  const CamerasOverviewScreen({super.key, this.initialCameraId});

  /// Deep-link from favourite tile; must match a configured camera id.
  final String? initialCameraId;

  @override
  ConsumerState<CamerasOverviewScreen> createState() =>
      _CamerasOverviewScreenState();
}

class _CamerasOverviewScreenState extends ConsumerState<CamerasOverviewScreen> {
  String? _selectedId;

  String _resolveSelectedId(List<Device> cameras) {
    final pick = _selectedId;
    if (pick != null && cameras.any((d) => d.id == pick)) return pick;
    final want = widget.initialCameraId;
    if (want != null && cameras.any((d) => d.id == want)) {
      _selectedId = want;
      return want;
    }
    final first = cameras.first.id;
    _selectedId = first;
    return first;
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  }

  @override
  void dispose() {
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);

    return cfg.when(
      loading: () => Scaffold(
        body: Center(child: CircularProgressIndicator(color: LuxeColors.brass)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text("Camera's")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Configuratie laden mislukt:\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: LuxeColors.inkSoft)),
          ),
        ),
      ),
      data: (c) {
        final cameras = List<Device>.from(c.cameras);
        if (cameras.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Camera's")),
            body: const Center(child: Text("Geen camera's in dit project.")),
          );
        }

        final selId = _resolveSelectedId(cameras);
        final selectedDevice =
            cameras.firstWhere((d) => d.id == selId, orElse: () => cameras.first);

        return OrientationBuilder(
          builder: (context, orientation) {
            final size = MediaQuery.of(context).size;
            // Only use the fullscreen landscape mode on phones (narrow screens).
            // On tablets and desktop the shortest side is >= 600dp, so we always
            // use the normal portrait layout there regardless of orientation.
            final isPhone = size.shortestSide < 600;
            final isLandscape =
                isPhone && orientation == Orientation.landscape;

            // Hide / restore system bars based on orientation (phones only)
            if (isLandscape) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            } else {
              _restoreSystemUi();
            }

            if (isLandscape) {
              return _FullscreenCameraView(
                selId: selId,
                deviceName: selectedDevice.name,
                onBack: () {
                  _restoreSystemUi();
                  context.pop();
                },
              );
            }

            // ── Portrait layout ────────────────────────────────────────────
            final info = ref.watch(cameraInfoProvider(selId));
            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.pop(),
                ),
                title: Text(
                  selectedDevice.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w400, letterSpacing: 0.5),
                ),
              ),
              body: LuxeBackdrop(
                child: Column(
                  children: [
                    const SizedBox(height: kToolbarHeight + 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: info.when(
                          loading: () => Center(
                            child: CircularProgressIndicator(
                                color: LuxeColors.brass),
                          ),
                          error: (e, _) => Center(
                            child: Text('Kan stream niet laden:\n$e',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: LuxeColors.inkSoft)),
                          ),
                          data: (i) => LayoutBuilder(
                            builder: (context, constraints) => Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: constraints.maxHeight,
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: CameraLivePlayer(
                                      info: i, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(8, 12, 8, 20),
                      decoration: BoxDecoration(
                        color: LuxeColors.cream.withValues(alpha: 0.85),
                        border: Border(
                            top: BorderSide(color: LuxeColors.line)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          height: 118,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: cameras.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final d = cameras[index];
                              final active = d.id == selId;
                              return _ThumbStripItem(
                                device: d,
                                selected: active,
                                onTap: () {
                                  if (_selectedId == d.id) return;
                                  setState(() => _selectedId = d.id);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Volledig scherm camera-weergave voor landscape modus.
class _FullscreenCameraView extends ConsumerWidget {
  const _FullscreenCameraView({
    required this.selId,
    required this.deviceName,
    required this.onBack,
  });

  final String selId;
  final String deviceName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(cameraInfoProvider(selId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera stream vult het hele scherm
          info.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: LuxeColors.brass)),
            error: (e, _) => Center(
              child: Text('Kan stream niet laden:\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
            ),
            data: (i) => CameraLivePlayer(info: i, fit: BoxFit.contain),
          ),
          // Terugknop linksonder
          Positioned(
            bottom: 16,
            left: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black.withValues(alpha: 0.5),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
          // Cameranaam rechtsonder
          Positioned(
            bottom: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: Text(
                  deviceName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbStripItem extends StatelessWidget {
  const _ThumbStripItem({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final Device device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? LuxeColors.brass : LuxeColors.line,
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: LuxeColors.brass.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraSnapshot(
                    cameraId: device.id,
                    aspectRatio: 16 / 9,
                    fit: BoxFit.cover,
                    refresh: Duration(milliseconds: 1500),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? LuxeColors.brass : LuxeColors.inkSoft,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
