import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../media_api.dart';
import '../models.dart';
import '../room_control_category.dart';
import '../system_category.dart';
import '../theme.dart';
import '../user_favorite_shortcuts.dart';
import 'responsive.dart';
import 'widgets/device_widgets.dart';
import 'widgets/function_screen_header.dart';
import 'widgets/glass_card.dart';
import 'widgets/luxe_backdrop.dart';

class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key, required this.slug});

  final String slug;

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
            if (slug == kFavorietenSlug) {
              return _FavorietenBody(cfg: cfg, onBack: () => context.pop());
            }
            final system = houseSystemBySlug(slug);
            if (system == null) {
              return _InvalidBody(onBack: () => context.pop());
            }
            final devices = devicesForHouseSystem(cfg, system);
            return _SystemDevicesBody(
              cfg: cfg,
              slug: slug,
              title: system.name,
              icon: system.icon,
              devices: devices,
              onBack: () => context.pop(),
            );
          },
        ),
      ),
    );
  }
}

class _InvalidBody extends StatelessWidget {
  const _InvalidBody({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FunctionScreenHeader(onBack: onBack, title: 'Pagina niet gevonden'),
        Expanded(
          child: Center(
            child: Text(
              'Dit systeem bestaat niet (meer).',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemDevicesBody extends ConsumerWidget {
  const _SystemDevicesBody({
    required this.cfg,
    required this.slug,
    required this.title,
    required this.icon,
    required this.devices,
    required this.onBack,
  });

  final HouseConfig cfg;
  final String slug;
  final String title;
  final IconData icon;
  final List<Device> devices;
  final VoidCallback onBack;

  String _headerSubtitle(WidgetRef ref) {
    if (slug == 'meldingen') {
      var items = 0;
      var active = 0;
      final busValues = ref.watch(busProvider).values;
      for (final d in devices) {
        final configured = MeldingTile.configuredItems(d);
        items += configured.length;
        active += MeldingTile.activeItemCount(d, busValues);
      }
      if (items == 0) return 'Geen meldingen geconfigureerd';
      if (active > 0) {
        return active == 1
            ? '1 actief · $items geconfigureerd'
            : '$active actief · $items geconfigureerd';
      }
      return items == 1 ? '1 melding' : '$items meldingen';
    }
    final n = devices.length;
    if (n == 1) return '1 apparaat';
    return '$n apparaten';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaStates = ref.watch(mediaStateProvider);
    final floorGroups = _groupByFloorRoom(cfg, devices);
    final placedIds = {
      for (final fg in floorGroups)
        for (final re in fg.rooms)
          for (final d in re.devices) d.id,
    };
    final unplaced = devices.where((d) => !placedIds.contains(d.id)).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FunctionScreenHeader(
            onBack: onBack,
            title: title,
            subtitle: _headerSubtitle(ref),
          ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Text(
                      'Geen apparaten in dit systeem.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: LuxeColors.inkSoft,
                          ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      context.isPhone ? 14 : 28,
                      8,
                      context.isPhone ? 14 : 28,
                      48,
                    ),
                    children: [
                      _AudioGroupSummary(devices: devices, mediaStates: mediaStates),
                      for (final fg in floorGroups) ...[
                        _SectionLabel(
                          icon: Icons.layers_outlined,
                          label: fg.floor.name.toUpperCase(),
                          brass: true,
                        ),
                        for (final re in fg.rooms) ...[
                          _SectionLabel(label: re.room.name.toUpperCase()),
                          for (var i = 0; i < re.devices.length; i++) ...[
                            if (i > 0) const SizedBox(height: 18),
                            deviceWidget(re.devices[i]),
                          ],
                          const SizedBox(height: 22),
                        ],
                      ],
                      if (unplaced.isNotEmpty) ...[
                        const _SectionLabel(label: 'OVERIGE'),
                        for (var i = 0; i < unplaced.length; i++) ...[
                          if (i > 0) const SizedBox(height: 18),
                          deviceWidget(unplaced[i]),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FavorietenBody extends ConsumerWidget {
  const _FavorietenBody({required this.cfg, required this.onBack});

  final HouseConfig cfg;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDevFavsAsync = ref.watch(userFavoriteDevicesProvider);
    final shortcutsAsync = ref.watch(userFavoriteShortcutsProvider);
    final shortcuts = shortcutsAsync.value ?? const <FavoriteShortcut>[];

    final seenFavIds = <String>{};
    final favDevices = <Device>[];
    for (final d in [...cfg.allDevices, ...cfg.cameras]) {
      if (effectiveDeviceFav(userDevFavsAsync, d)) {
        if (seenFavIds.add(d.id)) favDevices.add(d);
      }
    }

    final validShortcuts = <FavoriteShortcut>[];
    for (final s in shortcuts) {
      Floor? fl;
      for (final f in cfg.floors) {
        if (f.id == s.floorId) {
          fl = f;
          break;
        }
      }
      if (fl == null) continue;
      Room? rm;
      for (final r in fl.rooms) {
        if (r.id == s.roomId) {
          rm = r;
          break;
        }
      }
      if (rm == null) continue;
      if (!s.isRoomOnly &&
          RoomControlCategory.tryParseSlug(s.categorySlug!) == null) {
        continue;
      }
      validShortcuts.add(s);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FunctionScreenHeader(
            onBack: onBack,
            title: 'Favorieten',
            subtitle: 'Snelkoppelingen en apparaten',
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.isPhone ? 14 : 28,
                8,
                context.isPhone ? 14 : 28,
                48,
              ),
              children: [
                if (validShortcuts.isNotEmpty) ...[
                  const _SectionLabel(label: 'SNELKOPPELINGEN'),
                  for (var i = 0; i < validShortcuts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _FavoriteShortcutRow(cfg: cfg, shortcut: validShortcuts[i]),
                  ],
                  const SizedBox(height: 24),
                ],
                if (favDevices.isNotEmpty) ...[
                  const _SectionLabel(label: 'APPARATEN'),
                  for (var i = 0; i < favDevices.length; i++) ...[
                    if (i > 0) SizedBox(height: 18),
                    _FavoriteDeviceBlock(
                      device: favDevices[i],
                      roomName: cfg.roomForDevice(favDevices[i].id)?.name,
                    ),
                  ],
                ],
                if (validShortcuts.isEmpty && favDevices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Center(
                      child: Text(
                        'Nog geen favorieten.\nSter een apparaat of functiegroep in een kamer.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: LuxeColors.inkSoft,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteShortcutRow extends StatelessWidget {
  const _FavoriteShortcutRow({required this.cfg, required this.shortcut});

  final HouseConfig cfg;
  final FavoriteShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final floor = cfg.floors.firstWhere((f) => f.id == shortcut.floorId);
    final room = floor.rooms.firstWhere((r) => r.id == shortcut.roomId);
    final category = shortcut.isRoomOnly
        ? null
        : RoomControlCategory.tryParseSlug(shortcut.categorySlug!);
    final path = category == null
        ? '/floor/${floor.id}/room/${room.id}'
        : '/floor/${floor.id}/room/${room.id}/category/${category.name}';
    final title =
        category == null ? room.name : category.labelTitle;
    final subtitle = category == null
        ? '${floor.name} · kamer'
        : '${room.name} · ${floor.name}';

    return GlassCard(
      radius: 20,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => context.push(path),
      child: Row(
        children: [
          Icon(
            category == null ? Icons.meeting_room_outlined : category.icon,
            color: LuxeColors.brass,
            size: 22,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: LuxeColors.inkSoft,
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: LuxeColors.inkSoft),
        ],
      ),
    );
  }
}

class _FavoriteDeviceBlock extends StatelessWidget {
  const _FavoriteDeviceBlock({required this.device, this.roomName});

  final Device device;
  final String? roomName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (roomName != null)
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              roomName!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: LuxeColors.inkSoft,
                    letterSpacing: 1.1,
                  ),
            ),
          ),
        deviceWidget(device),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    this.icon,
    this.brass = false,
  });

  final String label;
  final IconData? icon;
  final bool brass;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Verdiepingen (brass): groter; light = ink (leesbaar), dark = brass.
    final color = brass
        ? (isDark ? LuxeColors.brass : LuxeColors.ink)
        : LuxeColors.inkSoft;
    final style = brass
        ? Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              fontSize: context.isPhone ? 15 : 17,
              height: 1.2,
            )
        : Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              letterSpacing: 1.15,
              fontWeight: FontWeight.w600,
              fontSize: context.isPhone ? 13 : 15,
              height: 1.2,
            );

    return Padding(
      padding: EdgeInsets.fromLTRB(4, brass ? 20 : 18, 4, brass ? 12 : 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: brass ? 18 : 15, color: color),
            SizedBox(width: 6),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}

class _AudioGroupSummary extends StatelessWidget {
  const _AudioGroupSummary({
    required this.devices,
    required this.mediaStates,
  });

  final List<Device> devices;
  final Map<String, MediaState> mediaStates;

  @override
  Widget build(BuildContext context) {
    final audioDeviceIds = devices
        .where((d) =>
            d.type == DeviceType.mediaSonos ||
            d.type == DeviceType.mediaBluesound)
        .map((d) => d.id)
        .toSet();
    if (audioDeviceIds.length < 2) return const SizedBox.shrink();

    final groups = <String, List<String>>{};
    for (final id in audioDeviceIds) {
      final s = mediaStates[id];
      if (s == null) continue;
      if (s.groupRole == MediaGroupRole.coordinator &&
          s.groupMemberIds.isNotEmpty) {
        groups[id] = s.groupMemberIds
            .where((m) => audioDeviceIds.contains(m))
            .toList();
      }
    }
    if (groups.isEmpty) return const SizedBox.shrink();

    String name(String id) {
      for (final d in devices) {
        if (d.id == id) return d.name;
      }
      return id;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: groups.entries.map((entry) {
          final allIds = [entry.key, ...entry.value];
          return Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: LuxeColors.brass.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuxeColors.brass.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 15, color: LuxeColors.brass),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: allIds.map((id) {
                      final isCoord = id == entry.key;
                      return Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCoord
                              ? LuxeColors.brass.withValues(alpha: 0.15)
                              : LuxeColors.ink.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isCoord
                                ? LuxeColors.brass.withValues(alpha: 0.4)
                                : LuxeColors.ink.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text(
                          name(id),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isCoord
                                ? LuxeColors.brass
                                : LuxeColors.ink.withValues(alpha: 0.7),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

List<({Floor floor, List<({Room room, List<Device> devices})> rooms})>
    _groupByFloorRoom(HouseConfig cfg, List<Device> devices) {
  final floorGroups =
      <({Floor floor, List<({Room room, List<Device> devices})> rooms})>[];
  for (final floor in cfg.floors) {
    final roomEntries = <({Room room, List<Device> devices})>[];
    for (final room in floor.rooms) {
      final roomDevs = devices
          .where((d) => room.devices.any((rd) => rd.id == d.id))
          .toList();
      if (roomDevs.isNotEmpty) {
        roomEntries.add((room: room, devices: roomDevs));
      }
    }
    if (roomEntries.isNotEmpty) {
      floorGroups.add((floor: floor, rooms: roomEntries));
    }
  }
  return floorGroups;
}
