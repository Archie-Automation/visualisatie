import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../media_api.dart';
import '../../models.dart';
import '../../theme.dart';
import '../app_nav.dart';
import '../responsive.dart';
import 'device_control_panel.dart';
import 'device_tile_shell.dart';
import 'media_search_sheet.dart';

const _metadataRevealDelay = Duration(milliseconds: 2500);

/// Houdt trackinfo even verborgen na start/overschakelen â€” RDS komt later binnen.
class _MediaMetadataGate extends StatefulWidget {
  const _MediaMetadataGate({
    required this.state,
    required this.builder,
  });

  final MediaState state;
  final Widget Function(BuildContext context, bool revealMetadata) builder;

  @override
  State<_MediaMetadataGate> createState() => _MediaMetadataGateState();
}

class _MediaMetadataGateState extends State<_MediaMetadataGate> {
  Timer? _timer;
  bool _reveal = false;
  bool _wasActive = false;
  String? _lastUri;

  @override
  void initState() {
    super.initState();
    _wasActive = widget.state.transport.isActive;
    _lastUri = widget.state.currentUri;
    // Al speelend bij openen â€” geen kunstmatige vertraging.
    _reveal = _wasActive;
  }

  @override
  void didUpdateWidget(_MediaMetadataGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(widget.state);
  }

  void _sync(MediaState state) {
    final active = state.transport.isActive;
    final uri = state.currentUri;

    if (!active) {
      _cancelDelay();
      if (_reveal) setState(() => _reveal = false);
    } else if (!_wasActive || uri != _lastUri) {
      _startDelay();
    }

    _wasActive = active;
    _lastUri = uri;
  }

  void _startDelay() {
    _cancelDelay();
    if (_reveal) setState(() => _reveal = false);
    _timer = Timer(_metadataRevealDelay, () {
      if (mounted) setState(() => _reveal = true);
    });
  }

  void _cancelDelay() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelDelay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _reveal);
}

/// Compact media player tile shown in room & room-of-rooms views. Tapping
/// anywhere on the tile (outside the controls) navigates to the luxurious
/// full-screen player at `/media/:id`.
class MediaTile extends ConsumerWidget {
  const MediaTile({super.key, required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaStateProvider)[device.id] ??
        MediaState.offline(device.id);
    final api = ref.read(mediaApiProvider);
    final active = state.online && state.transport.isActive;
    final cfg = ref.watch(configProvider).value;

    // Collect same-brand zones (excluding this device).
    final sameZones = cfg == null
        ? <Device>[]
        : cfg.allDevices
            .where((d) =>
                d.id != device.id &&
                (d.type == DeviceType.mediaSonos ||
                    d.type == DeviceType.mediaBluesound) &&
                d.type == device.type)
            .toList();

    return DeviceTileShell(
        glow: active,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DeviceTileLayout.headerRow(
              context: context,
              leading: GestureDetector(
                onTap: () => appOpen(context, '/media/${device.id}'),
                behavior: HitTestBehavior.opaque,
                child: _Artwork(
                  state: state,
                  active: active,
                ),
              ),
              content: GestureDetector(
                onTap: () => appOpen(context, '/media/${device.id}'),
                behavior: HitTestBehavior.opaque,
                child: _MediaMetadataGate(
                  state: state,
                  builder: (ctx, reveal) => _NowPlaying(
                    device: device,
                    state: state,
                    revealMetadata: reveal,
                  ),
                ),
              ),
              trailing: (active || state.groupRole.isGrouped) &&
                      sameZones.isNotEmpty
                  ? DeviceTileLayout.statusIconSlot(
                      context,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _GroupButton(
                          device: device,
                          state: state,
                          allSameZones: sameZones,
                          api: api,
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(height: DeviceControlBar.sectionSpacing(context)),
            DeviceCardBody(
              child: LayoutBuilder(
              builder: (context, constraints) {
                // Tablet: stapel transport + volume â€” horizontale rij past niet goed
                // en veroorzaakt overflow op grotere touch-displays.
                final stacked = DeviceControlBar.useFullWidthRows(
                      context,
                      constraints.maxWidth,
                    ) ||
                    context.isTablet;

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Row(
                          children: [
                            Expanded(
                              child: _ControlButton(
                                icon: DeviceControlIcons.skipPrevious,
                                expand: true,
                                onTap: state.online
                                    ? () => api.previous(device.id)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: DeviceControlBar.gap),
                            Expanded(
                              child: _PlayPauseButton(
                                active: active,
                                state: state,
                                expand: true,
                                onPlay: () => api.play(device.id),
                                onPause: () => api.pause(device.id),
                              ),
                            ),
                            const SizedBox(width: DeviceControlBar.gap),
                            Expanded(
                              child: _ControlButton(
                                icon: DeviceControlIcons.skipNext,
                                expand: true,
                                onTap: state.online
                                    ? () => api.next(device.id)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _VolumeSlider(
                          value: (state.volume ?? 0).toDouble(),
                          muted: state.muted ?? false,
                          roomy: true,
                          onChanged: state.online
                              ? (v) => api.setVolume(device.id, v.round())
                              : null,
                          onToggleMute: state.online
                              ? () => api.setMuted(
                                    device.id,
                                    !(state.muted ?? false),
                                  )
                              : null,
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    _ControlButton(
                      icon: DeviceControlIcons.skipPrevious,
                      onTap:
                          state.online ? () => api.previous(device.id) : null,
                    ),
                    const SizedBox(width: 6),
                    _PlayPauseButton(
                      active: active,
                      state: state,
                      onPlay: () => api.play(device.id),
                      onPause: () => api.pause(device.id),
                    ),
                    const SizedBox(width: 6),
                    _ControlButton(
                      icon: DeviceControlIcons.skipNext,
                      onTap: state.online ? () => api.next(device.id) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _VolumeSlider(
                        value: (state.volume ?? 0).toDouble(),
                        muted: state.muted ?? false,
                        onChanged: state.online
                            ? (v) => api.setVolume(device.id, v.round())
                            : null,
                        onToggleMute: state.online
                            ? () => api.setMuted(
                                  device.id,
                                  !(state.muted ?? false),
                                )
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            ),
          ],
        ),
      );
  }
}

/* --------------------------------------------------------------------- */
/*  Full-screen player                                                   */
/* --------------------------------------------------------------------- */

class MediaPlayerScreen extends ConsumerWidget {
  const MediaPlayerScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaStateProvider)[deviceId] ??
        MediaState.offline(deviceId);
    final api = ref.read(mediaApiProvider);
    final active = state.online && state.transport.isActive;
    final cfg = ref.watch(configProvider).value;

    final sameZones = cfg == null
        ? <Device>[]
        : cfg.allDevices
            .where((d) =>
                d.id != deviceId &&
                (d.type == DeviceType.mediaSonos ||
                    d.type == DeviceType.mediaBluesound))
            .toList();

    // Find the device object for this screen.
    Device? thisDevice;
    if (cfg != null) {
      for (final d in cfg.allDevices) {
        if (d.id == deviceId) { thisDevice = d; break; }
      }
    }

    return Scaffold(
      backgroundColor: LuxeColors.surfaceDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white),
        title: Text(
          thisDevice?.name ?? state.brand.label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
        ),
        actions: [
          // Zoekknop â€” bij Bluesound (BluOS stelt de gekoppelde diensten lokaal
          // beschikbaar) of zodra Spotify verbonden is (dan kan ook Sonos via
          // Spotify Connect doorzocht/afgespeeld worden). Sonos zonder Spotify
          // heeft alleen favorieten, dus daar blijft de knop weg.
          if (thisDevice != null &&
              (thisDevice.type == DeviceType.mediaBluesound ||
                  (ref.watch(spotifyStatusProvider).value?.connected ?? false)))
            IconButton(
              icon: const Icon(Icons.search_rounded),
              iconSize: context.isPhone ? 24 : 30,
              tooltip: 'Zoek muziek',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => MediaSearchSheet(
                  deviceId: deviceId,
                  deviceName: thisDevice!.name,
                  api: api,
                  isSonos: thisDevice.type == DeviceType.mediaSonos,
                ),
              ),
            ),
          // Koppelknop in de AppBar â€” ook zichtbaar bij gestopte speler
          if (sameZones.isNotEmpty && thisDevice != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _AudioGroupSheet(
                    coordinator: thisDevice!,
                    allSameZones: sameZones,
                    api: api,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: state.groupRole.isGrouped
                        ? LuxeColors.brass.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: state.groupRole.isGrouped
                          ? LuxeColors.brass.withValues(alpha: 0.5)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.groupRole.isGrouped
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        size: context.isPhone ? 16 : 21,
                        color: state.groupRole.isGrouped
                            ? LuxeColors.brass
                            : Colors.white60,
                      ),
                      if (state.groupRole == MediaGroupRole.coordinator &&
                          state.groupMemberIds.isNotEmpty) ...[
                        SizedBox(width: 4),
                        Text(
                          '+${state.groupMemberIds.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: LuxeColors.brass,
                            height: 1,
                          ),
                        ),
                      ] else if (state.groupRole == MediaGroupRole.member) ...[
                        SizedBox(width: 4),
                        Text(
                          '+1',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: LuxeColors.brass,
                            height: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final height = c.maxHeight;
            final width = c.maxWidth;
            final artByWidth = (width * 0.75).clamp(180.0, 380.0);
            final artByHeight = (height * 0.30).clamp(150.0, 380.0);
            final artSize = math.min(artByWidth, artByHeight);
            final tight = height < 760;
            final sectionGap = tight ? 16.0 : 28.0;
            final titleGap = tight ? 20.0 : 32.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Artwork(state: state, size: artSize, hero: true),
                    SizedBox(height: titleGap),
                    _MediaMetadataGate(
                      state: state,
                      builder: (ctx, reveal) => Column(
                        children: [
                          Text(
                            state.headline(revealMetadata: reveal),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            state.metaLine(revealMetadata: reveal),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.white60,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    if (state.groupRole.isGrouped && cfg != null)
                      _GroupStatusBar(
                        state: state,
                        cfg: cfg,
                        deviceId: deviceId,
                      ),
                    SizedBox(height: sectionGap),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DarkCtl(
                          icon: DeviceControlIcons.skipPrevious,
                          size: 60,
                          onTap: state.online
                              ? () => api.previous(deviceId)
                              : null,
                        ),
                        const SizedBox(width: 20),
                        _BigPlayPause(
                          active: active,
                          state: state,
                          onPlay: () => api.play(deviceId),
                          onPause: () => api.pause(deviceId),
                        ),
                        const SizedBox(width: 20),
                        _DarkCtl(
                          icon: DeviceControlIcons.skipNext,
                          size: 60,
                          onTap:
                              state.online ? () => api.next(deviceId) : null,
                        ),
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    _VolumeSlider.dark(
                      value: (state.volume ?? 0).toDouble(),
                      muted: state.muted ?? false,
                      onChanged: state.online
                          ? (v) => api.setVolume(deviceId, v.round())
                          : null,
                      onToggleMute: state.online
                          ? () => api.setMuted(
                                deviceId,
                                !(state.muted ?? false),
                              )
                          : null,
                    ),
                    if (state.presets.isNotEmpty) ...[
                      SizedBox(height: sectionGap),
                      _Presets(
                        presets: state.presets,
                        onTap: (p) => api.playPreset(deviceId, p),
                      ),
                    ],
                    SizedBox(height: sectionGap),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shows the current group as a row of zone-name chips below the track info.
class _GroupStatusBar extends StatelessWidget {
  const _GroupStatusBar({
    required this.state,
    required this.cfg,
    required this.deviceId,
  });
  final MediaState state;
  final HouseConfig cfg;
  final String deviceId;

  String _nameFor(String id) {
    for (final d in cfg.allDevices) {
      if (d.id == id) return d.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    // Collect all IDs that are in the group (coordinator + members).
    final groupIds = <String>[];
    if (state.groupRole == MediaGroupRole.coordinator) {
      groupIds.add(deviceId);
      groupIds.addAll(state.groupMemberIds);
    } else if (state.groupRole == MediaGroupRole.member) {
      if (state.groupCoordinatorId != null) {
        groupIds.add(state.groupCoordinatorId!);
      }
      groupIds.add(deviceId);
    }

    if (groupIds.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_rounded,
                  size: 14, color: LuxeColors.brass.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                'Gekoppeld met',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: groupIds.map((id) {
              final isThis = id == deviceId;
              return Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isThis
                      ? LuxeColors.brass.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isThis
                        ? LuxeColors.brass.withValues(alpha: 0.5)
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  _nameFor(id),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isThis ? LuxeColors.brass : Colors.white70,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------------- */
/*  Bits                                                                 */
/* --------------------------------------------------------------------- */

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.state,
    this.size,
    this.hero = false,
    this.active = false,
  });
  final MediaState state;
  final double? size;
  final bool hero;
  final bool active;

  Widget _placeholder() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              state.brand == MediaBrand.sonos
                  ? Color(0xFF2A2A33)
                  : const Color(0xFF1F2A3A),
              Colors.black,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            state.brand == MediaBrand.sonos
                ? Icons.speaker_rounded
                : Icons.music_note_rounded,
            color: active ? LuxeColors.brass : Colors.white24,
            size: DeviceControlBar.tileGlyphSize,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tileSize = size ?? DeviceControlBar.tileIconSize;
    final radius = hero ? 28.0 : DeviceControlBar.tileIconRadius;
    final borderRadius = BorderRadius.circular(radius);
    final art = state.effectiveArt;

    Widget child;
    if (art != null && art.isNotEmpty) {
      child = Image.network(
        art,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }

    if (hero) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: tileSize,
          height: tileSize,
          child: child,
        ),
      );
    }

    const rim = 1.5;
    final outerR = radius;
    final innerR = (outerR - rim).clamp(0.0, outerR);
    final rimColor = active ? LuxeColors.brass : LuxeColors.line;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = active
        ? LuxeColors.brass.withValues(alpha: 0.14)
        : LuxeColors.surfaceDim.withValues(alpha: isDark ? 0.7 : 0.45);

    return SizedBox(
      width: tileSize,
      height: tileSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerR),
          color: rimColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(rim),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerR),
            child: ColoredBox(
              color: fillColor,
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.device,
    required this.state,
    this.revealMetadata = true,
  });
  final Device device;
  final MediaState state;
  final bool revealMetadata;

  @override
  Widget build(BuildContext context) {
    final statusLine = state.compactLine(revealMetadata: revealMetadata);

    final hideZoneName = device.name.trim().toLowerCase() ==
        state.brand.label.toLowerCase();

    if (hideZoneName) {
      final meta = state.metaLine(revealMetadata: revealMetadata);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            statusLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: DeviceTileLayout.titleStatusGap),
          Text(
            meta.isEmpty ? ' ' : meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: meta.isEmpty ? Colors.transparent : null,
                ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (statusLine.isNotEmpty) ...[
          const SizedBox(height: DeviceTileLayout.titleStatusGap),
          Text(
            statusLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.expand = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) => DeviceControlIconButton(
        icon: icon,
        onTap: onTap,
        expand: expand,
      );
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.active,
    required this.state,
    required this.onPlay,
    required this.onPause,
    this.expand = false,
  });
  final bool active;
  final MediaState state;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final icon = active ? Icons.pause_rounded : Icons.play_arrow_rounded;
    return GestureDetector(
      onTap: !state.online ? null : (active ? onPause : onPlay),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        width: expand ? double.infinity : DeviceControlBar.buttonSize,
        height: DeviceControlBar.buttonSize,
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(DeviceControlBar.buttonRadius),
          color: active ? LuxeColors.ink : LuxeColors.brass,
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: active ? LuxeColors.onInk : Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({
    required this.value,
    required this.muted,
    required this.onChanged,
    required this.onToggleMute,
    this.roomy = false,
    this.dark = false,
  });

  const _VolumeSlider.dark({
    required this.value,
    required this.muted,
    required this.onChanged,
    required this.onToggleMute,
  })  : roomy = false,
        dark = true;

  final double value;
  final bool muted;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onToggleMute;
  final bool roomy;
  final bool dark;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  static const _throttle = Duration(milliseconds: 100);

  bool _dragging = false;
  double _localSlider = 0;
  Timer? _volumeThrottle;
  DateTime? _lastSendAt;
  int? _lastSentVolume;

  @override
  void initState() {
    super.initState();
    _localSlider = widget.value.clamp(0.0, 100.0);
  }

  @override
  void dispose() {
    _volumeThrottle?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_VolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _localSlider = widget.value.clamp(0.0, 100.0);
    }
  }

  double get _displayValue =>
      widget.muted ? 0.0 : _localSlider.clamp(0.0, 100.0);

  void _emitDeviceVolume(double sliderPos) {
    final device = sliderPos.round().clamp(0, 100);
    if (_lastSentVolume == device) return;
    _lastSentVolume = device;
    _lastSendAt = DateTime.now();
    widget.onChanged?.call(device.toDouble());
  }

  void _scheduleSend(double sliderPos) {
    final now = DateTime.now();
    if (_lastSendAt == null ||
        now.difference(_lastSendAt!) >= _throttle) {
      _emitDeviceVolume(sliderPos);
      return;
    }
    _volumeThrottle?.cancel();
    final wait = _throttle - now.difference(_lastSendAt!);
    _volumeThrottle = Timer(wait, () => _emitDeviceVolume(_localSlider));
  }

  void _onDragStart(double sliderPos) {
    _lastSentVolume = null;
    setState(() {
      _dragging = true;
      _localSlider = sliderPos;
    });
    _emitDeviceVolume(sliderPos);
  }

  void _onDragUpdate(double sliderPos) {
    setState(() => _localSlider = sliderPos);
    _scheduleSend(sliderPos);
  }

  void _onDragEnd(double sliderPos) {
    _volumeThrottle?.cancel();
    _emitDeviceVolume(sliderPos);
    setState(() {
      _dragging = false;
      _localSlider = sliderPos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    // Slightly larger volume glyphs on the web/desktop layout.
    final bigDark = widget.dark && !context.isPhone;
    final muteIcon = widget.dark
        ? (widget.muted
            ? Icons.volume_off_rounded
            : Icons.volume_down_rounded)
        : (widget.muted
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded);

    final thumbRadius = widget.roomy ? 10.0 : 8.0;

    final sliderTheme = widget.dark
        ? SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: LuxeColors.brassGlow,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayShape: RoundSliderOverlayShape(overlayRadius: thumbRadius + 8),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
          )
        : SliderTheme.of(context).copyWith(
            trackHeight: widget.roomy ? 4 : 3,
            activeTrackColor: LuxeColors.brass,
            inactiveTrackColor: LuxeColors.line,
            thumbColor: LuxeColors.brass,
            overlayShape: RoundSliderOverlayShape(overlayRadius: thumbRadius + 8),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
          );

    return Row(
      children: [
        GestureDetector(
          onTap: widget.onToggleMute,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              muteIcon,
              color: widget.dark
                  ? Colors.white70
                  : (enabled ? LuxeColors.inkSoft : LuxeColors.inkFaint),
              size: bigDark ? 32 : (widget.dark ? 26 : (widget.roomy ? 24 : 22)),
            ),
          ),
        ),
        SizedBox(width: widget.dark ? 10 : (widget.roomy ? 4 : 6)),
        Expanded(
          child: SizedBox(
            height: widget.roomy ? 44 : 40,
            child: Center(
              child: SliderTheme(
                data: sliderTheme,
                child: Slider(
                  value: _displayValue,
                  min: 0,
                  max: 100,
                  onChangeStart: enabled ? _onDragStart : null,
                  onChanged: enabled ? _onDragUpdate : null,
                  onChangeEnd: enabled ? _onDragEnd : null,
                ),
              ),
            ),
          ),
        ),
        if (widget.dark) ...[
          const SizedBox(width: 10),
          Icon(Icons.volume_up_rounded,
              color: Colors.white70, size: bigDark ? 28 : 22),
        ],
      ],
    );
  }
}

/* ---------------------- Dark-mode full-screen bits -------------------- */

class _DarkCtl extends StatelessWidget {
  const _DarkCtl({required this.icon, required this.onTap, required this.size});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            color: LuxeColors.surfaceDarkElev,
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(
            icon,
            color: onTap == null ? Colors.white24 : Colors.white,
            size: size * 0.44,
          ),
        ),
      );
}

class _BigPlayPause extends StatelessWidget {
  const _BigPlayPause({
    required this.active,
    required this.state,
    required this.onPlay,
    required this.onPause,
  });
  final bool active;
  final MediaState state;
  final VoidCallback onPlay;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final icon = active ? Icons.pause_rounded : Icons.play_arrow_rounded;
    return GestureDetector(
      onTap: !state.online ? null : (active ? onPause : onPlay),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          color: LuxeColors.brass,
          boxShadow: LuxeShadows.brassGlow,
        ),
        child: Icon(icon, color: Colors.white, size: 42),
      ),
    );
  }
}

class _Presets extends StatelessWidget {
  const _Presets({required this.presets, required this.onTap});
  final List<MediaPreset> presets;
  final ValueChanged<MediaPreset> onTap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FAVORIETEN',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white60,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _PresetCard(
                preset: presets[i],
                onTap: () => onTap(presets[i]),
              ),
            ),
          ),
        ],
      );
}

class _PresetCard extends StatefulWidget {
  const _PresetCard({required this.preset, required this.onTap});
  final MediaPreset preset;
  final VoidCallback onTap;

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool _pressed = false;

  /// Guess the content type from the URI for a meaningful fallback icon.
  IconData get _fallbackIcon {
    final u = widget.preset.uri ?? '';
    if (u.contains('radio') || u.contains('stream') || u.contains('x-sonosapi-stream')) {
      return Icons.radio_rounded;
    }
    if (u.contains('spotify') || u.contains('x-sonos-spotify')) {
      return Icons.music_note_rounded;
    }
    return Icons.star_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final rawImg = widget.preset.image;
    // Resolve relative proxy paths (e.g. /api/media-art?u=...) to absolute URLs.
    final img = (rawImg != null && rawImg.startsWith('/'))
        ? '$apiBase$rawImg'
        : rawImg;
    final Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: img != null && img.isNotEmpty
          ? Image.network(
              img,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => _placeholder,
            )
          : _placeholder,
    );

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 180,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _pressed
                ? LuxeColors.brass.withValues(alpha: 0.18)
                : LuxeColors.surfaceDarkElev,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? LuxeColors.brass.withValues(alpha: 0.55)
                  : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              artwork,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.preset.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _placeholder => Container(
        width: 52,
        height: 52,
        color: Colors.white10,
        child: Icon(_fallbackIcon, color: Colors.white38, size: 24),
      );
}

/* --------------------------------------------------------------------- */
/*  Zone group button + sheet                                            */
/* --------------------------------------------------------------------- */

class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.device,
    required this.state,
    required this.allSameZones,
    required this.api,
  });
  final Device device;
  final MediaState state;
  final List<Device> allSameZones;
  final MediaApi api;

  @override
  Widget build(BuildContext context) {
    final grouped = state.groupRole.isGrouped;
    // Number of OTHER zones in the group (same for coordinator and member).
    final memberCount = state.groupRole == MediaGroupRole.coordinator
        ? state.groupMemberIds.length
        : (state.groupRole == MediaGroupRole.member ? 1 : 0);
    final showCount = grouped && memberCount > 0;

    void openSheet() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AudioGroupSheet(
            coordinator: device,
            allSameZones: allSameZones,
            api: api,
          ),
        );

    if (!showCount) {
      return DeviceControlSquare.icon(
        icon: grouped ? Icons.link_rounded : Icons.link_off_rounded,
        active: grouped,
        onTap: openSheet,
      );
    }

    return DeviceControlSquare(
      active: grouped,
      onTap: openSheet,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_rounded,
            size: DeviceControlIcons.size,
            color: LuxeColors.brass,
          ),
          SizedBox(height: 2),
          Text(
            '+$memberCount',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: LuxeColors.brass,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet that lets the user manage which zones play in sync with [coordinator].
/// The coordinator is always the currently PLAYING zone whose koppelen-button
/// was tapped.  All other same-brand zones (playing or not) appear as
/// checkboxes.  Checking adds them to the group; unchecking removes them.
///
/// Special case â€” "coordinator handoff":
/// If the coordinator itself is unchecked while other zones are still checked,
/// the first remaining checked zone becomes the new coordinator so music
/// doesn't stop.
class _AudioGroupSheet extends ConsumerStatefulWidget {
  const _AudioGroupSheet({
    required this.coordinator,
    required this.allSameZones,
    required this.api,
  });
  final Device coordinator;
  final List<Device> allSameZones;
  final MediaApi api;

  @override
  ConsumerState<_AudioGroupSheet> createState() => _AudioGroupSheetState();
}

class _AudioGroupSheetState extends ConsumerState<_AudioGroupSheet> {
  /// Tracks which zone IDs are currently checked (in the group).
  /// Initialised from current MediaState on first build.
  Set<String>? _checked; // null = not yet initialised

  Set<String> _initChecked(Map<String, MediaState> mediaStates) {
    final myState = mediaStates[widget.coordinator.id];
    final checked = <String>{widget.coordinator.id}; // coordinator itself always ON
    if (myState == null) return checked;
    // Add existing members
    for (final id in myState.groupMemberIds) {
      checked.add(id);
    }
    // Also check if this zone is a member (someone else is coordinator)
    if (myState.groupRole == MediaGroupRole.member &&
        myState.groupCoordinatorId != null) {
      checked.add(myState.groupCoordinatorId!);
    }
    return checked;
  }

  Future<void> _toggle(String zoneId, bool nowChecked) async {
    final mediaStates = ref.read(mediaStateProvider);
    final currentChecked = Set<String>.from(_checked!);

    if (nowChecked) {
      // Add zone to group: zone joins the coordinator's group.
      currentChecked.add(zoneId);
      setState(() => _checked = currentChecked);
      await widget.api.groupJoin(zoneId, widget.coordinator.id);
    } else {
      // Remove zone from group.
      currentChecked.remove(zoneId);

      // Special case: coordinator itself is being unchecked.
      if (zoneId == widget.coordinator.id) {
        setState(() => _checked = currentChecked);
        // Coordinator leaves â€” Sonos hardware automatically promotes the first
        // remaining member. We only need to call groupLeave on the coordinator;
        // the backend/hardware handles the remaining zones.
        await widget.api.groupLeave(widget.coordinator.id);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      setState(() => _checked = currentChecked);
      await widget.api.groupLeave(zoneId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaStates = ref.watch(mediaStateProvider);

    // Initialise on first build.
    _checked ??= _initChecked(mediaStates);

    // All zones in the sheet: coordinator first, then the rest.
    final allZones = [
      widget.coordinator,
      ...widget.allSameZones.where((z) => z.id != widget.coordinator.id),
    ];

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: LuxeColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: LuxeColors.ink.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: LuxeColors.ink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 10),
            child: Row(
              children: [
                Icon(Icons.link_rounded, color: LuxeColors.brass, size: 20),
                SizedBox(width: 10),
                Text(
                  'Zones koppelen',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: LuxeColors.ink.withValues(alpha: 0.08)),
          ...allZones.map((zone) {
            final zState = mediaStates[zone.id];
            final isPlaying = zState != null && zState.transport.isActive;
            final checked = _checked!.contains(zone.id);

            return CheckboxListTile(
              value: checked,
              onChanged: (v) => _toggle(zone.id, v ?? false),
              activeColor: LuxeColors.brass,
              checkColor: Colors.white,
              side: BorderSide(
                  color: LuxeColors.ink.withValues(alpha: 0.25), width: 1.5),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      zone.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (isPlaying) ...[
                    SizedBox(width: 8),
                    Icon(Icons.play_arrow_rounded,
                        size: 16, color: LuxeColors.brass),
                  ],
                ],
              ),
              subtitle: zState != null && zState.cleanTitle != null
                  ? Text(
                      zState.cleanTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: LuxeColors.inkSoft,
                          ),
                    )
                  : null,
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
