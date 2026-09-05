import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../user_favorite_shortcuts.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/back_pill.dart';
import 'widgets/device_widgets.dart';
import 'widgets/favorite_device_wrap.dart';
import 'widgets/honeycomb_pattern.dart';
import 'widgets/luxe_backdrop.dart';
import 'widgets/satel_room_sensors.dart';
import 'widgets/scene_strip.dart';

class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key, required this.floorId, required this.roomId});

  final String floorId;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfgAsync = ref.watch(configProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: cfgAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text('$e')),
          data: (cfg) {
            final floor = cfg.floors.firstWhere((f) => f.id == floorId);
            final room = floor.rooms.firstWhere((r) => r.id == roomId);
            return _buildRoom(context, ref, cfg, floor, room);
          },
        ),
      ),
    );
  }

  Widget _buildRoom(
    BuildContext context,
    WidgetRef ref,
    HouseConfig cfg,
    Floor floor,
    Room room,
  ) {
    final canEdit = canEditScenesInApp(ref.watch(authProvider), cfg);
    final hp = context.hPad;

    return CustomScrollView(
      physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── Sticky header ──────────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _RoomStickyHeader(
            floor: floor,
            room: room,
            cfg: cfg,
            headerHeight: context.roomStickyHeaderH,
            onBack: () => appBack(context),
          ),
        ),

        // ── Scenes ────────────────────────────────────────────────────────
        if (room.scenes.isNotEmpty || canEdit)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
                    child: Text('SCENES',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  SceneStrip(
                    scenes: room.scenes,
                    canEdit: canEdit,
                    roomId: room.id,
                    onEdited: (_) => ref.invalidate(configProvider),
                  ),
                ],
              ),
            ),
          ),

        // ── Satel sensors for this room ───────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                context.isPhone ? 14 : 28, 0, context.isPhone ? 14 : 28, 0),
            child: SatelRoomSensors(roomId: room.id),
          ),
        ),

        // ── Device tiles ──────────────────────────────────────────────────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              context.isPhone ? 14 : 28, 8, context.isPhone ? 14 : 28, 64),
          sliver: SliverList.separated(
            itemCount: room.devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 18),
            itemBuilder: (_, i) {
              final device = room.devices[i];
              return FavoriteDeviceWrap(
                device: device,
                cfg: cfg,
                child: deviceWidget(device),
              );
            },
          ),
        ),
      ],
    );
  }
}

/* ─────────────────────────────────────────────────────────────────────────
   Sticky room header — vaste hoogte, cover + honingraat-profiel
   ───────────────────────────────────────────────────────────────────────── */

class _RoomStickyHeader extends SliverPersistentHeaderDelegate {
  _RoomStickyHeader({
    required this.floor,
    required this.room,
    required this.cfg,
    required this.headerHeight,
    required this.onBack,
  });

  final Floor floor;
  final Room room;
  final HouseConfig cfg;
  final double headerHeight;
  final VoidCallback onBack;

  @override
  double get minExtent => headerHeight;
  @override
  double get maxExtent => headerHeight;

  @override
  bool shouldRebuild(_RoomStickyHeader old) =>
      old.floor != floor ||
      old.room != room ||
      old.headerHeight != headerHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isPhone = context.isPhone;
    final backSize = isPhone ? 44.0 : 48.0;
    final roomFont = isPhone ? 18.0 : 20.0;

    return StickyHeaderSurface(
      height: headerHeight,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(isPhone ? 8 : 12, 0, isPhone ? 8 : 12, 10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: HeaderIconButton.size + 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        floor.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isPhone ? 10 : 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9,
                          color: LuxeColors.inkSoft,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: roomFont,
                          fontWeight: FontWeight.w700,
                          color: LuxeColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Consumer(
                builder: (context, ref, _) {
                  final fav = ref.watch(userFavoriteShortcutsProvider);
                  final on = userHasRoomFavorite(fav, floor.id, room.id);
                  return IconButton(
                    tooltip: on
                        ? 'Verwijder kamer uit favorieten'
                        : 'Voeg kamer toe aan favorieten',
                    iconSize: isPhone ? 24 : 26,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: backSize,
                      minHeight: backSize,
                    ),
                    icon: Icon(
                      on
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: on ? LuxeColors.brass : LuxeColors.inkSoft,
                    ),
                    onPressed: () async {
                      final was = on;
                      await toggleUserFavoriteRoom(
                          ref, cfg, floor.id, room.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            was
                                ? 'Kamer verwijderd uit favorieten.'
                                : 'Kamer toegevoegd aan favorieten.',
                          ),
                        ),
                      );
                    },
                  );
                },
                ),
              ),
              // Last = top for hit-testing — first tap must register.
              Align(
                alignment: Alignment.centerLeft,
                child: BackPill(onTap: onBack),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
