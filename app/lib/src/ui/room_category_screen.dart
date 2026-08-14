import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../models.dart';
import '../room_control_category.dart';
import '../theme.dart';
import '../user_favorite_shortcuts.dart';
import 'app_nav.dart';
import 'responsive.dart';
import 'widgets/device_widgets.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/luxe_backdrop.dart';

class RoomCategoryScreen extends ConsumerWidget {
  const RoomCategoryScreen({
    super.key,
    required this.floorId,
    required this.roomId,
    required this.categorySlug,
  });

  final String floorId;
  final String roomId;
  final String categorySlug;

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
            Floor? foundFloor;
            for (final f in cfg.floors) {
              if (f.id == floorId) {
                foundFloor = f;
                break;
              }
            }
            Room? foundRoom;
            if (foundFloor != null) {
              for (final r in foundFloor.rooms) {
                if (r.id == roomId) {
                  foundRoom = r;
                  break;
                }
              }
            }
            void backToRoom() => appBack(
                  context,
                  fallback: '/floor/$floorId/room/$roomId',
                );

            if (foundFloor == null || foundRoom == null) {
              return _InvalidCategoryBody(onBack: backToRoom);
            }

            // Resolve slug: fixed category OR universal__<deviceId>.
            final category = RoomControlCategory.tryParseSlug(categorySlug);
            if (category != null) {
              final devices =
                  foundRoom.devices.where(category.matchesDevice).toList();
              return _CategoryBody(
                cfg: cfg,
                floor: foundFloor,
                room: foundRoom,
                segment: RoomSegment.fromCategory(category, devices),
                onBack: backToRoom,
              );
            }

            if (categorySlug.startsWith('universal__')) {
              final deviceId = categorySlug.substring('universal__'.length);
              final device = foundRoom.devices
                  .where((d) => d.id == deviceId)
                  .firstOrNull;
              if (device == null) {
                return _InvalidCategoryBody(onBack: backToRoom);
              }
              return _CategoryBody(
                cfg: cfg,
                floor: foundFloor,
                room: foundRoom,
                segment: RoomSegment.fromUniversal(device),
                onBack: backToRoom,
              );
            }

            if (categorySlug.startsWith('melding__')) {
              final deviceId = categorySlug.substring('melding__'.length);
              final device = foundRoom.devices
                  .where((d) => d.id == deviceId)
                  .firstOrNull;
              if (device == null) {
                return _InvalidCategoryBody(onBack: backToRoom);
              }
              return _CategoryBody(
                cfg: cfg,
                floor: foundFloor,
                room: foundRoom,
                segment: RoomSegment.fromMelding(device),
                onBack: backToRoom,
              );
            }

            return _InvalidCategoryBody(onBack: backToRoom);
          },
        ),
      ),
    );
  }
}

class _InvalidCategoryBody extends StatelessWidget {
  const _InvalidCategoryBody({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FunctionScreenHeader(
          onBack: onBack,
          title: 'Pagina niet gevonden',
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Deze pagina bestaat niet (meer).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryBody extends ConsumerWidget {
  const _CategoryBody({
    required this.cfg,
    required this.floor,
    required this.room,
    required this.segment,
    required this.onBack,
  });

  final HouseConfig cfg;
  final Floor floor;
  final Room room;
  final RoomSegment segment;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = segment.devices;
    final fav = ref.watch(userFavoriteShortcutsProvider);
    final isCatFav = userHasCategoryFavorite(
      fav,
      floor.id,
      room.id,
      segment.slug,
    );
    // Use the proper title casing: for fixed categories use labelTitle,
    // for universal segments the name is already set as the device name.
    final titleText = segment.category?.labelTitle ??
        segment.devices.firstOrNull?.name ??
        segment.labelUpper;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FunctionScreenHeader(
            onBack: onBack,
            title: titleText,
            subtitle: '${room.name} · ${floor.name}',
            trailing: IconButton(
              tooltip: isCatFav
                  ? 'Verwijder deze groep uit favorieten'
                  : 'Zet deze functiegroep op het dashboard',
              onPressed: () async {
                final was = isCatFav;
                await toggleUserFavoriteCategory(
                  ref,
                  cfg,
                  floor.id,
                  room.id,
                  segment.slug,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      was
                          ? 'Functiegroep verwijderd uit favorieten.'
                          : 'Functiegroep toegevoegd aan favorieten op het dashboard.',
                    ),
                  ),
                );
              },
              iconSize: context.isPhone ? 24 : 26,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: context.isPhone ? 44 : 48,
                minHeight: context.isPhone ? 44 : 48,
              ),
              icon: Icon(
                isCatFav ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isCatFav ? LuxeColors.brass : LuxeColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Geen apparaten in deze categorie.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: LuxeColors.inkSoft,
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        context.isPhone ? 14 : 28, 12,
                        context.isPhone ? 14 : 28, 48),
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (_, i) => deviceWidget(devices[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
