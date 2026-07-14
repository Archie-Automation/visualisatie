import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../fireplace_virtual.dart';
import '../media_api.dart';
import '../models.dart';
import '../room_control_category.dart';
import '../satel_api.dart';
import '../theme.dart';
import '../user_favorite_shortcuts.dart';
import 'responsive.dart';
import 'widgets/glass_card.dart';
import 'widgets/room_category_strip.dart';
import 'widgets/luxe_backdrop.dart';
import 'widgets/scene_strip.dart';
import '../floor_order.dart';
import '../room_order.dart';
import '../scene_order.dart';
import '../system_order.dart';
import '../system_category.dart';
import 'installer_nav.dart';

/// Combined alarm state used for auto-navigation and chip display.
/// Null when the Satel integration is disabled.
final _alarmStateProvider = Provider<SatelPartitionState?>((ref) {
  final enabled = ref.watch(satelEnabledProvider).value ?? false;
  if (!enabled) return null;
  return ref.watch(satelStatusProvider).worstState;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfgAsync = ref.watch(configProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LuxeBackdrop(
        child: SafeArea(
          child: cfgAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Kan huis niet laden:\n$e',
                    textAlign: TextAlign.center),
              ),
            ),
            data: (cfg) => _DashboardBody(key: ValueKey(cfg.projectName), cfg: cfg),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({super.key, required this.cfg});
  final HouseConfig cfg;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  int _floorIndex = 0;

  @override
  void didUpdateWidget(covariant _DashboardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.cfg.floors.length;
    if (n > 0 && _floorIndex >= n) {
      setState(() => _floorIndex = n - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-open alarm screen when entry delay starts (on any device).
    ref.listen<SatelPartitionState?>(
      _alarmStateProvider,
      (prev, next) {
        if (next == SatelPartitionState.entryDelay &&
            prev != SatelPartitionState.entryDelay) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.push('/alarm');
          });
        }
      },
    );

    final cfg = widget.cfg;
    final auth = ref.watch(authProvider);
    final canEdit = canEditScenesInApp(auth, cfg);
    final floorOrder = ref.watch(floorOrderProvider);
    final floors = applyFloorOrder(
      floorOrder,
      [...cfg.floors]..sort((a, b) => a.order.compareTo(b.order)),
    );
    final safeIndex =
        floors.isEmpty ? 0 : _floorIndex.clamp(0, floors.length - 1);
    final selectedFloor = floors.isEmpty ? null : floors[safeIndex];

    return CustomScrollView(
      physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: _header(context, cfg, auth, ref)),
        SliverToBoxAdapter(child: _scenes(context, cfg, canEdit, ref)),
        SliverToBoxAdapter(child: _Systemen(cfg: cfg)),
        if (floors.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              // Bottom space here mirrors the gap below the floor buttons
              // (tab margin) down to the line above the rooms, so the floor
              // buttons sit symmetrically between both lines.
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                height: 0.5,
                color: LuxeColors.line.withValues(alpha: 0.22),
              ),
            ),
          ),
        if (floors.isNotEmpty)
          SliverToBoxAdapter(
            child: _FloorTabBar(
              floors: floors,
              selectedIndex: safeIndex,
              onSelect: (i) => setState(() => _floorIndex = i),
            ),
          ),
        if (selectedFloor != null)
          SliverToBoxAdapter(
            child: _FloorRoomsBlock(
              floor: selectedFloor,
              onOpenRoom: (room) =>
                  context.push('/floor/${selectedFloor.id}/room/${room.id}'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 64)),
      ],
    );
  }
}

/// Horizontale verdieping-kiezer (tabs). Lang indrukken opent de volgorde-popup.
class _FloorTabBar extends ConsumerWidget {
  const _FloorTabBar({
    required this.floors,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<Floor> floors;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  void _openReorderSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FloorReorderSheet(floors: floors, ref: ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const double vPad = 8;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 48 + vPad * 2,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          primary: false,
          clipBehavior: Clip.none,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(context.hPad, vPad, context.hPad, vPad),
          itemCount: floors.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final floor = floors[i];
            final selected = i == selectedIndex;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(i),
                onLongPress: () => _openReorderSheet(context, ref),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: selected
                        ? LuxeColors.surface.withValues(alpha: 0.94)
                        : LuxeColors.surface.withValues(alpha: 0.55),
                    border: Border.all(
                      color: selected
                          ? LuxeColors.brass.withValues(alpha: 0.75)
                          : LuxeColors.glassRim,
                      width: selected ? 1.25 : 1,
                    ),
                    boxShadow: selected ? LuxeShadows.soft : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    floor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: true,
                      applyHeightToLastDescent: true,
                    ),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          height: 1.2,
                          color:
                              selected ? LuxeColors.ink : LuxeColors.inkSoft,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Verdieping volgorde-popup
// ---------------------------------------------------------------------------

class _FloorReorderSheet extends ConsumerStatefulWidget {
  const _FloorReorderSheet({required this.floors, required this.ref});
  final List<Floor> floors;
  final WidgetRef ref;

  @override
  ConsumerState<_FloorReorderSheet> createState() => _FloorReorderSheetState();
}

class _FloorReorderSheetState extends ConsumerState<_FloorReorderSheet> {
  late List<Floor> _floors;

  @override
  void initState() {
    super.initState();
    _floors = List.of(widget.floors);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined,
                      size: 20, color: LuxeColors.brass),
                  const SizedBox(width: 10),
                  Text('Verdiepingen rangschikken',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
              child: Text(
                'Houd de handgreep vast en sleep om de volgorde te wijzigen.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: LuxeColors.inkSoft),
              ),
            ),
            SizedBox(
              height: (_floors.length * 64.0).clamp(0, 360),
              child: ReorderableListView.builder(
                itemCount: _floors.length,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    final item = _floors.removeAt(oldIndex);
                    _floors.insert(newIndex, item);
                  });
                  ref
                      .read(floorOrderProvider.notifier)
                      .reorder(_floors.map((f) => f.id).toList());
                },
                itemBuilder: (_, i) {
                  final floor = _floors[i];
                  return ListTile(
                    key: ValueKey(floor.id),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: LuxeColors.inkSoft),
                      ),
                    ),
                    title: Text(floor.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: LuxeColors.ink)),
                    subtitle: Text(
                        '${floor.rooms.length} kamer${floor.rooms.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12, color: LuxeColors.inkSoft)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Klaar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle() => _sheetHandle();
}

// ---------------------------------------------------------------------------
//  Scene reorder sheet
// ---------------------------------------------------------------------------

class _SceneReorderSheet extends StatefulWidget {
  const _SceneReorderSheet({
    required this.scenes,
    required this.onReordered,
  });
  final List<Scene> scenes;
  final ValueChanged<List<String>> onReordered;

  @override
  State<_SceneReorderSheet> createState() => _SceneReorderSheetState();
}

class _SceneReorderSheetState extends State<_SceneReorderSheet> {
  late List<Scene> _scenes;

  @override
  void initState() {
    super.initState();
    _scenes = List.of(widget.scenes);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded,
                      size: 20, color: LuxeColors.brass),
                  const SizedBox(width: 10),
                  Text('Scenes rangschikken',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
              child: Text(
                'Houd de handgreep vast en sleep om de volgorde te wijzigen.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: LuxeColors.inkSoft),
              ),
            ),
            SizedBox(
              height: (_scenes.length * 60.0).clamp(0.0, 380.0),
              child: ReorderableListView.builder(
                itemCount: _scenes.length,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    final item = _scenes.removeAt(oldIndex);
                    _scenes.insert(newIndex, item);
                  });
                  widget.onReordered(_scenes.map((s) => s.id).toList());
                },
                itemBuilder: (_, i) {
                  final scene = _scenes[i];
                  return ListTile(
                    key: ValueKey(scene.id),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: LuxeColors.inkSoft),
                      ),
                    ),
                    title: Text(scene.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: LuxeColors.ink)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Klaar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared drag-handle pip for bottom sheets.
Widget _sheetHandle() => Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: LuxeColors.ink.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );

class _FloorRoomsBlock extends ConsumerWidget {
  const _FloorRoomsBlock({
    required this.floor,
    required this.onOpenRoom,
  });

  final Floor floor;
  final void Function(Room room) onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (floor.rooms.isEmpty) return const SizedBox.shrink();

    final orderMap = ref.watch(roomOrderProvider);
    final rooms = applyRoomOrder(orderMap, floor);

    return Padding(
      // Only bottom spacing; cards go edge-to-edge horizontally.
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full-width container housing all room rows.
          Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: LuxeColors.line.withValues(alpha: 0.22),
                  width: 0.5,
                ),
              ),
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 0,
                child: child,
              ),
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final reordered = List.of(rooms);
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                ref
                    .read(roomOrderProvider.notifier)
                    .reorder(floor.id, reordered.map((r) => r.id).toList());
              },
              itemCount: rooms.length,
              itemBuilder: (context, i) {
                final room = rooms[i];
                final isLast = i == rooms.length - 1;
                return _RoomDashboardRow(
                  key: ValueKey(room.id),
                  floor: floor,
                  room: room,
                  index: i,
                  showDivider: !isLast,
                  onOpenRoom: () => onOpenRoom(room),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDashboardRow extends ConsumerWidget {
  const _RoomDashboardRow({
    super.key,
    required this.floor,
    required this.room,
    required this.index,
    required this.showDivider,
    required this.onOpenRoom,
  });

  final Floor floor;
  final Room room;
  final int index;
  final bool showDivider;
  final VoidCallback onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = roomControlSegments(room.devices);
    final hp = context.hPad;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // â”€â”€ Room header row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Only the name text + chevron are tappable for room navigation.
        // Activity badges have their own tap targets for system sheets.
        Padding(
          padding: EdgeInsets.fromLTRB(hp, 16, hp, segments.isEmpty ? 16 : 10),
          child: Row(
            children: [
              // Drag handle for reordering â€” direct slepen vanaf de handgreep.
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 12, 6),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 22,
                      color: LuxeColors.inkSoft.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              // Name + chevron together form the tap target for room navigation.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenRoom,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: LuxeColors.inkSoft.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _RoomActivityBadges(room: room),
            ],
          ),
        ),
        // â”€â”€ Category chips (edge-to-edge, scrollable) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (segments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RoomCategoryStrip(
              floorId: floor.id,
              roomId: room.id,
              segments: segments,
            ),
          )
        else if (room.devices.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 14),
            child: Text(
              'Geen apparaten.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: LuxeColors.inkSoft),
            ),
          ),
        // â”€â”€ Row divider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            indent: context.hPad + 34,
            color: LuxeColors.line.withValues(alpha: 0.25),
          ),
      ],
      ),
    );
  }
}

String _timeGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 5) return 'Goedenacht';
  if (hour < 12) return 'Goedemorgen';
  if (hour < 18) return 'Goedemiddag';
  if (hour < 23) return 'Goedenavond';
  return 'Goedenacht';
}

Widget _header(
  BuildContext context,
  HouseConfig cfg,
  AuthState auth,
  WidgetRef ref,
) {
  final hp = context.hPad;
  final phone = context.isPhone;
  return Padding(
    padding: EdgeInsets.fromLTRB(hp, phone ? 28 : 40, hp, 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_timeGreeting().toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              Text(
                cfg.projectName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: context.displayLargeFontSize,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // On narrow phones collapse installer icon into a single menu
        if (auth.isAdmin) ...[
          _GlassIconButton(
            icon: Icons.construction_outlined,
            tooltip: 'Technische configuratie',
            onTap: () => openTechnischeConfiguratie(context, auth),
          ),
          SizedBox(width: phone ? 8 : 10),
        ],
        _GlassIconButton(
          icon: Icons.settings_outlined,
          onTap: () => context.push('/settings'),
        ),
        SizedBox(width: phone ? 8 : 10),
        _GlassIconButton(
          icon: Icons.logout_outlined,
          onTap: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
        ),
      ],
    ),
  );
}

Widget _scenes(
  BuildContext context,
  HouseConfig cfg,
  bool canEdit,
  WidgetRef ref,
) {
  if (cfg.scenes.isEmpty && !canEdit) return const SizedBox.shrink();
  final hp = context.hPad;
  final order = ref.watch(sceneOrderProvider);
  final ordered = applySceneOrder(order, cfg.scenes);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(hp, 0, hp, 14),
        child: Row(
          children: [
            Text('SCENES', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [LuxeColors.line, Colors.transparent],
                  ),
                ),
              ),
            ),
            if (cfg.scenes.length > 1)
              IconButton(
                icon: const Icon(Icons.sort_rounded, size: 22),
                tooltip: 'Volgorde aanpassen',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _SceneReorderSheet(
                    scenes: ordered,
                    onReordered: (ids) =>
                        ref.read(sceneOrderProvider.notifier).reorder(ids),
                  ),
                ),
              ),
          ],
        ),
      ),
      SceneStrip(
        scenes: ordered,
        canEdit: canEdit,
        onEdited: (_) => ref.invalidate(configProvider),
      ),
      const SizedBox(height: 24),
    ],
  );
}

// ---------------------------------------------------------------------------
//  _Systemen widget
// ---------------------------------------------------------------------------

class _Systemen extends ConsumerWidget {
  const _Systemen({required this.cfg});
  final HouseConfig cfg;

  void _openManageSheet(
    BuildContext context,
    WidgetRef ref,
    List<_SystemChipData> allChips,
    Set<String> hidden,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SystemManageSheet(
        allChips: allChips,
        hidden: hidden,
        ref: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDevFavsAsync = ref.watch(userFavoriteDevicesProvider);
    final shortcutsAsync = ref.watch(userFavoriteShortcutsProvider);
    final shortcuts = shortcutsAsync.value ?? const <FavoriteShortcut>[];

    // Verzamel alle devices over alle verdiepingen/kamers.
    final allDevices = cfg.allDevices;
    final allCameras = cfg.cameras;

    // Bouw lijst van zichtbare systemen (alleen als er devices zijn).
    final chips = <_SystemChipData>[];

    // Favorieten chip â€” alleen als er favoriete devices of shortcuts zijn.
    final seenFavIds = <String>{};
    final favDevices = <Device>[];
    for (final d in [...allDevices, ...allCameras]) {
      if (effectiveDeviceFav(userDevFavsAsync, d)) {
        if (seenFavIds.add(d.id)) favDevices.add(d);
      }
    }
    final validShortcuts = <FavoriteShortcut>[];
    for (final s in shortcuts) {
      Floor? fl;
      for (final f in cfg.floors) {
        if (f.id == s.floorId) { fl = f; break; }
      }
      if (fl == null) continue;
      Room? rm;
      for (final r in fl.rooms) {
        if (r.id == s.roomId) { rm = r; break; }
      }
      if (rm == null) continue;
      if (!s.isRoomOnly && RoomControlCategory.tryParseSlug(s.categorySlug!) == null) continue;
      validShortcuts.add(s);
    }
    if (favDevices.isNotEmpty || validShortcuts.isNotEmpty) {
      chips.add(_SystemChipData(
        name: 'Favorieten',
        icon: Icons.star_rounded,
        accent: LuxeColors.brass,
        devices: favDevices,
        shortcuts: validShortcuts,
      ));
    }

    // Overige systemen.
    for (final sys in kHouseSystems) {
      final devices = allDevices
          .where((d) => sys.types.contains(d.type))
          .toList();
      // Camera's staan los in cfg.cameras.
      if (sys.types.contains(DeviceType.camera)) {
        devices.addAll(allCameras);
      }
      if (devices.isEmpty) continue;
      chips.add(_SystemChipData(
        name: sys.name,
        icon: sys.icon,
        devices: devices,
      ));
    }

    // Alarm chip â€” tonen zodra de Satel-koppeling is ingeschakeld.
    final satelEnabled = ref.watch(satelEnabledProvider).value ?? false;
    if (satelEnabled) {
      chips.add(_SystemChipData(
        name: 'Alarm',
        icon: Icons.security_outlined,
        devices: const [],
        alarmState: ref.watch(_alarmStateProvider),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    // Pas volgorde en zichtbaarheid toe.
    final sysOrder = ref.watch(systemOrderProvider);
    final sysHidden = ref.watch(systemHiddenProvider);
    final allOrderedChips = applySystemOrder(sysOrder, chips, (c) => c.name);
    final orderedChips =
        allOrderedChips.where((c) => !sysHidden.contains(c.name)).toList();

    const double vPad = 10;
    const double chipH = 118;

    return Padding(
      // Bottom gap (chip vPad + this) matches the gap between the scene
      // buttons and the "Systemen" line above (~54px) for a consistent rhythm.
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(context.hPad, 0, context.hPad, 16),
            child: Row(
              children: [
                Text('SYSTEMEN',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [LuxeColors.line, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openManageSheet(context, ref, allOrderedChips, sysHidden),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: LuxeColors.inkSoft.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: chipH + vPad * 2,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              primary: false,
              buildDefaultDragHandles: false,
              clipBehavior: Clip.none,
              padding: EdgeInsets.fromLTRB(
                  context.hPad, vPad, context.hPad, vPad),
              proxyDecorator: (child, _, animation) => ScaleTransition(
                scale: animation.drive(
                  Tween(begin: 1.0, end: 1.06).chain(
                    CurveTween(curve: Curves.easeOutCubic),
                  ),
                ),
                child: Material(color: Colors.transparent, child: child),
              ),
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final reordered = List.of(orderedChips);
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                ref
                    .read(systemOrderProvider.notifier)
                    .reorder(reordered.map((c) => c.name).toList());
              },
              itemCount: orderedChips.length,
              itemBuilder: (ctx, i) {
                final chip = orderedChips[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(chip.name),
                  index: i,
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: i < orderedChips.length - 1 ? 14 : 0),
                    child: _SystemChip(data: chip, cfg: cfg),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Systemen beheer-popup (volgorde + aan/uit)
// ---------------------------------------------------------------------------

class _SystemManageSheet extends ConsumerStatefulWidget {
  const _SystemManageSheet({
    required this.allChips,
    required this.hidden,
    required this.ref,
  });
  final List<_SystemChipData> allChips;
  final Set<String> hidden;
  final WidgetRef ref;

  @override
  ConsumerState<_SystemManageSheet> createState() => _SystemManageSheetState();
}

class _SystemManageSheetState extends ConsumerState<_SystemManageSheet> {
  late List<_SystemChipData> _chips;
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _chips = List.of(widget.allChips);
    _hidden = Set.of(widget.hidden);
  }

  void _save() {
    ref
        .read(systemOrderProvider.notifier)
        .reorder(_chips.map((c) => c.name).toList());
    ref.read(systemHiddenProvider.notifier).setHidden(_hidden);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 20, color: LuxeColors.brass),
                  const SizedBox(width: 10),
                  Text('Systemen beheren',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
              child: Text(
                'Sleep om te rangschikken Â· Vinkje om te tonen of verbergen.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: LuxeColors.inkSoft),
              ),
            ),
            SizedBox(
              height: (_chips.length * 64.0).clamp(0.0, 420.0),
              child: ReorderableListView.builder(
                itemCount: _chips.length,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    final item = _chips.removeAt(oldIndex);
                    _chips.insert(newIndex, item);
                  });
                },
                itemBuilder: (_, i) {
                  final chip = _chips[i];
                  final visible = !_hidden.contains(chip.name);
                  return ListTile(
                    key: ValueKey(chip.name),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: LuxeColors.inkSoft),
                      ),
                    ),
                    title: Row(
                      children: [
                        Icon(chip.icon,
                            size: 18,
                            color: visible
                                ? (chip.accent ?? LuxeColors.brass)
                                : LuxeColors.inkSoft.withValues(alpha: 0.4)),
                        const SizedBox(width: 10),
                        Text(
                          chip.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: visible
                                ? LuxeColors.ink
                                : LuxeColors.inkSoft
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                    trailing: Switch.adaptive(
                      value: visible,
                      activeColor: LuxeColors.brass,
                      onChanged: (on) {
                        setState(() {
                          if (on) {
                            _hidden.remove(chip.name);
                          } else {
                            _hidden.add(chip.name);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.ink,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                onPressed: _save,
                child: const Text('Opslaan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle() => _sheetHandle();
}

class _SystemChipData {
  const _SystemChipData({
    required this.name,
    required this.icon,
    required this.devices,
    this.accent,
    this.shortcuts = const [],
    this.alarmState,
  });
  final String name;
  final IconData icon;
  final List<Device> devices;
  final Color? accent;
  final List<FavoriteShortcut> shortcuts;
  /// Pre-computed alarm state (only used for the Alarm chip).
  final SatelPartitionState? alarmState;
}

class _SystemChip extends ConsumerStatefulWidget {
  const _SystemChip({required this.data, required this.cfg});
  final _SystemChipData data;
  final HouseConfig cfg;

  @override
  ConsumerState<_SystemChip> createState() => _SystemChipState();
}

class _SystemChipState extends ConsumerState<_SystemChip>
    with TickerProviderStateMixin {
  bool _pressed = false;

  // Slow continuous rotation for "Armed".
  late final AnimationController _rotCtrl;
  late final Animation<double> _rotAnim;

  // Rapid shake for "Entry_Delay".
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // Blink for "Entry_Delay" border.
  late final AnimationController _blinkCtrl;
  late final Animation<double> _blinkAnim;

  SatelPartitionState? _lastState;

  @override
  void initState() {
    super.initState();

    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _rotAnim = Tween<double>(begin: 0, end: 1).animate(_rotCtrl);

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5, end: -3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.linear));

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _blinkAnim = CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _shakeCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  void _syncAnimations(SatelPartitionState? state) {
    if (state == _lastState) return;
    _lastState = state;

    switch (state) {
      case SatelPartitionState.armed:
        _rotCtrl.repeat();
        _shakeCtrl.stop();
        _blinkCtrl.stop();
      case SatelPartitionState.entryDelay:
        _rotCtrl.stop();
        _shakeCtrl.repeat();
        _blinkCtrl.repeat(reverse: true);
      case SatelPartitionState.exitDelay:
        _rotCtrl.stop();
        _shakeCtrl.stop();
        _blinkCtrl.repeat(reverse: true);
      default:
        _rotCtrl.stop();
        _rotCtrl.reset();
        _shakeCtrl.stop();
        _shakeCtrl.reset();
        _blinkCtrl.stop();
        _blinkCtrl.reset();
    }
  }

  void _open(BuildContext context) {
    final data = widget.data;
    if (data.name == 'Favorieten') {
      context.push('/system/$kFavorietenSlug');
      return;
    }
    if (data.name == 'Alarm') {
      context.push('/alarm');
      return;
    }
    final sys = houseSystemByName(data.name);
    final route = sys?.routePath;
    if (route != null) context.push(route);
  }

  /// Returns the count + worst urgency for active melding alerts.
  (int count, String? urgency) _meldingAlertInfo() {
    final bus = ref.watch(busProvider);
    int urgent = 0, belangrijk = 0, minder = 0;
    for (final d in widget.data.devices) {
      if (d.type != DeviceType.melding) continue;
      final cfg = d.raw['melding'] as Map<String, dynamic>? ?? {};
      final items = (cfg['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final item in items) {
        final ga = item['ga'] as String? ?? '';
        final dpt = item['dpt'] as String? ?? '1.001';
        final busVal = bus.values[ga];
        if (!_meldingIsActive(dpt, busVal, item)) continue;
        switch (item['urgency'] as String? ?? 'minder_belangrijk') {
          case 'urgent':
            urgent++;
          case 'belangrijk':
            belangrijk++;
          default:
            minder++;
        }
      }
    }
    final total = urgent + belangrijk + minder;
    if (total == 0) return (0, null);
    final worst = urgent > 0
        ? 'urgent'
        : belangrijk > 0
            ? 'belangrijk'
            : 'minder_belangrijk';
    return (total, worst);
  }

  static bool _meldingIsActive(
      String dpt, dynamic busVal, Map<String, dynamic> item) {
    if (busVal == null) return false;
    final activeVal = item['activeValue'];
    if (dpt.startsWith('1.')) {
      final target = activeVal ?? 1;
      if (busVal is bool) return busVal == (target == 1 || target == true);
      final n = num.tryParse(busVal.toString());
      return n != null &&
          n == (activeVal != null ? num.tryParse(activeVal.toString()) : 1);
    }
    if (activeVal != null) {
      final n = num.tryParse(busVal.toString());
      final t = num.tryParse(activeVal.toString());
      return n != null && t != null && n == t;
    }
    final n = num.tryParse(busVal.toString());
    return n != null && n != 0;
  }

  @override
  Widget build(BuildContext context) {
    final isMelding = widget.data.name == 'Meldingen';
    final isAlarm  = widget.data.name == 'Alarm';
    final (alertCount, worstUrgency) =
        isMelding ? _meldingAlertInfo() : (0, null);
    final hasAlert = alertCount > 0;

    // Watch the live alarm state directly so the chip rebuilds the moment
    // the status changes â€” no prop-passing needed.
    final SatelPartitionState? alarmState =
        isAlarm ? ref.watch(_alarmStateProvider) : null;

    if (isAlarm) _syncAnimations(alarmState);

    final alarmIsActive = alarmState != null &&
        alarmState != SatelPartitionState.disarmed;
    // Only colour the chip when armed / in delay â€” disarmed = brass (normal).
    final alarmAccent = switch (alarmState) {
      SatelPartitionState.armed      => const Color(0xFFD64545),
      SatelPartitionState.entryDelay => const Color(0xFFD64545),
      SatelPartitionState.exitDelay  => const Color(0xFFE07A3F),
      _                              => LuxeColors.brass,
    };
    final alarmLabel = switch (alarmState) {
      SatelPartitionState.armed      => 'Aan',
      SatelPartitionState.entryDelay => 'Inloop!',
      SatelPartitionState.exitDelay  => 'Uitloop',
      _                              => null, // no sub-label when disarmed
    };

    // Override accent to alert color when there are active meldingen.
    final defaultAccent = isAlarm
        ? alarmAccent
        : widget.data.accent ?? LuxeColors.brass;
    final accent = hasAlert
        ? (worstUrgency == 'urgent'
            ? const Color(0xFFD32F2F)
            : worstUrgency == 'belangrijk'
                ? const Color(0xFFD97706)
                : const Color(0xFFC08500))
        : defaultAccent;

    final fillColor =
        LuxeColors.surface.withValues(alpha: _pressed ? 0.95 : 0.82);
    final borderColor = hasAlert
        ? accent.withValues(alpha: 0.55)
        : _pressed
            ? defaultAccent.withValues(alpha: 0.55)
            : LuxeColors.glassRim;

    // The icon for the alarm chip needs animated transforms.
    Widget iconWidget = Icon(widget.data.icon, size: 18, color: accent);
    if (isAlarm) {
      if (alarmState == SatelPartitionState.armed) {
        // Slow continuous y-axis flip (simulate rotating on its axis).
        iconWidget = AnimatedBuilder(
          animation: _rotAnim,
          builder: (_, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(2 * pi * _rotAnim.value),
            child: child,
          ),
          child: iconWidget,
        );
      } else if (alarmState == SatelPartitionState.entryDelay) {
        // Rapid left-right shake.
        iconWidget = AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: iconWidget,
        );
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          // Rebuild the border when blinking (Entry/Exit delay).
          animation: _blinkAnim,
          builder: (_, child) {
            final blinkBorder = (isAlarm && alarmIsActive)
                ? accent.withValues(
                    alpha: 0.30 + 0.50 * _blinkAnim.value)
                : borderColor;
            final blinkWidth = (isAlarm && alarmIsActive)
                ? 1.0 + 0.8 * _blinkAnim.value
                : (_pressed || hasAlert ? 1.3 : 1.0);
            return Container(
              width: 118,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: fillColor,
                border: Border.all(color: blinkBorder, width: blinkWidth),
                boxShadow: LuxeShadows.soft,
              ),
              child: child,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: accent.withValues(alpha: 0.15),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: iconWidget,
                  ),
                  if (hasAlert)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(
                            minWidth: 17, minHeight: 17),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$alertCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(
                width: 118 - 24,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          widget.data.name.toUpperCase(),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: (hasAlert || (isAlarm && alarmIsActive)) ? accent : LuxeColors.ink,
                            fontSize: 11,
                            height: 1.35,
                            letterSpacing: 0.7,
                            fontWeight: (hasAlert || (isAlarm && alarmIsActive))
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isAlarm && alarmLabel != null)
                        Text(
                          alarmLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: alarmAccent,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small circular glass affordance used in the top-right of the header.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: LuxeShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: LuxeColors.surface.withValues(alpha: 0.7),
                border: Border.all(color: LuxeColors.glassRim),
              ),
              child: Icon(icon, color: LuxeColors.ink, size: 20),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/* ------------------------------------------------------------------ */
/*  Room activity badges                                                */
/* ------------------------------------------------------------------ */

class _RoomActivityBadges extends ConsumerWidget {
  const _RoomActivityBadges({required this.room});
  final Room room;

  /// Vaste hoogte zodat iconen (vlam, equalizer, â€¦) de kamerbalk niet laten verspringen.
  static const _badgeSize = 22.0;
  static const _glyphSize = 18.0;
  static const _slotHeight = 36.0;

  static bool _isLightOn(Device d, BusState bus) {
    switch (d.type) {
      case DeviceType.lightSwitch:
      case DeviceType.lightDimmer:
        final swGa = d.ga['switch_status'] ?? d.ga['switch'];
        if (swGa == null) return false;
        final v = bus.values[swGa];
        return v == true || v == 1;
      case DeviceType.rgbwWw:
        final ga = d.ga['on'];
        if (ga == null) return false;
        final v = bus.values[ga];
        return v == true || v == 1;
      default:
        return false;
    }
  }

  static bool _isFireplaceOn(
    Device d,
    BusState bus,
    Map<String, bool> fireplaceVirtual,
  ) {
    if (d.type != DeviceType.fireplace) return false;
    final cfg = d.raw['fireplace'] as Map<String, dynamic>?;
    if (cfg == null) return false;
    final onOff = cfg['onOff'];
    if (onOff is! Map) return false;
    final ga = (onOff['statusGa'] ?? onOff['ga']) as String?;
    if (ga == null) return false;
    final busOn = bus.values[ga] == true || bus.values[ga] == 1;
    final discreteMode =
        cfg['controlMode'] == 'discrete' && cfg['discreteLevel'] != null;
    return FireplaceVirtualStore.resolveOn(
      discreteMode: discreteMode,
      virtual: fireplaceVirtual,
      deviceId: d.id,
      busOn: busOn,
    );
  }

  /// Returns true/false/garage for open window or door melding-items.
  /// Melding-items with category 'window', 'door', or 'garage_door' trigger this.
  static ({bool window, bool door, bool garageDoor}) _openings(
      Device d, BusState bus) {
    if (d.type != DeviceType.melding) {
      return (window: false, door: false, garageDoor: false);
    }
    final cfg = d.raw['melding'] as Map<String, dynamic>? ?? {};
    final items = (cfg['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    bool win = false, door = false, garage = false;
    for (final item in items) {
      final cat = item['category'] as String? ?? '';
      if (cat != 'window' && cat != 'door' && cat != 'garage_door') continue;
      final ga = item['ga'] as String? ?? '';
      final busVal = bus.values[ga];
      if (busVal == null) continue;
      // active when 1/true (or custom activeValue)
      final activeVal = item['activeValue'];
      bool active;
      if (activeVal != null) {
        active = busVal.toString() == activeVal.toString();
      } else {
        active = busVal == true || busVal == 1;
      }
      if (!active) continue;
      if (cat == 'window') win = true;
      if (cat == 'door') door = true;
      if (cat == 'garage_door') garage = true;
    }
    return (window: win, door: door, garageDoor: garage);
  }

  void _openSystem(BuildContext context, HouseConfig cfg, String sysName) {
    final sys = houseSystemByName(sysName);
    final route = sys?.routePath;
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(busProvider);
    final mediaStates = ref.watch(mediaStateProvider);
    final fireplaceVirtual = ref.watch(fireplaceVirtualProvider);
    final cfg = ref.watch(configProvider).value;

    bool lightsOn = false;
    bool mediaPlaying = false;
    bool fireplaceOn = false;
    bool windowOpen = false;
    bool doorOpen = false;
    bool garageDoorOpen = false;

    for (final d in room.devices) {
      if (!lightsOn && _isLightOn(d, bus)) lightsOn = true;
      if (!fireplaceOn && _isFireplaceOn(d, bus, fireplaceVirtual)) {
        fireplaceOn = true;
      }
      if (!mediaPlaying && d.type.isMedia) {
        final ms = mediaStates[d.id];
        if (ms != null && ms.transport.isActive) mediaPlaying = true;
      }
      if (d.type == DeviceType.melding) {
        final o = _openings(d, bus);
        if (o.window) windowOpen = true;
        if (o.door) doorOpen = true;
        if (o.garageDoor) garageDoorOpen = true;
      }
    }

    final any = lightsOn || mediaPlaying || fireplaceOn ||
        windowOpen || doorOpen || garageDoorOpen;

    // Wrap an icon so its tap opens a system sheet without propagating to the
    // parent room InkWell. Vertical padding gives a taller touch target;
    // horizontal padding is kept small so the rest of the row stays navigable.
    Widget tap(Widget child, String sysName) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: cfg == null ? null : () => _openSystem(context, cfg, sysName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: SizedBox(
              width: _badgeSize,
              height: _badgeSize,
              child: Center(child: child),
            ),
          ),
        );

    return SizedBox(
      height: _slotHeight,
      child: any
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (lightsOn)
                  tap(
                    Icon(Icons.lightbulb_rounded,
                        size: _glyphSize,
                        color: LuxeColors.brass.withValues(alpha: 0.85)),
                    'Verlichting',
                  ),
                if (fireplaceOn)
                  tap(const _FireBadge(), 'Openhaard'),
                if (windowOpen)
                  tap(
                    Icon(Icons.sensor_window_outlined,
                        size: _glyphSize,
                        color: LuxeColors.brass.withValues(alpha: 0.85)),
                    'Meldingen',
                  ),
                if (doorOpen)
                  tap(
                    Icon(Icons.door_front_door_outlined,
                        size: _glyphSize,
                        color: LuxeColors.brass.withValues(alpha: 0.85)),
                    'Meldingen',
                  ),
                if (garageDoorOpen)
                  tap(
                    Icon(Icons.garage_outlined,
                        size: _glyphSize,
                        color: LuxeColors.brass.withValues(alpha: 0.85)),
                    'Meldingen',
                  ),
                if (mediaPlaying) tap(const _EqualizerBadge(), 'Audio'),
              ],
            )
          : null,
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Animated fire badge                                                 */
/* ------------------------------------------------------------------ */

class _FireBadge extends StatefulWidget {
  const _FireBadge();

  @override
  State<_FireBadge> createState() => _FireBadgeState();
}

class _FireBadgeState extends State<_FireBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value * 2 * pi;
          // Subtle scale flicker between 0.82 and 1.0
          final scale = 0.82 + 0.18 * ((sin(t * 1.7) + sin(t * 2.3) + 2) / 4);
          return Transform.scale(
            scale: scale,
            child: Icon(
              Icons.local_fire_department_rounded,
              size: _RoomActivityBadges._glyphSize + 2,
              color: LuxeColors.brass.withValues(alpha: 0.85),
            ),
          );
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Animated equalizer icon                                             */
/* ------------------------------------------------------------------ */

class _EqualizerBadge extends StatefulWidget {
  const _EqualizerBadge();

  @override
  State<_EqualizerBadge> createState() => _EqualizerBadgeState();
}

class _EqualizerBadgeState extends State<_EqualizerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * pi;
        // Three bars with different phase offsets
        final h1 = (0.35 + 0.65 * ((sin(t) + 1) / 2)).clamp(0.15, 1.0);
        final h2 = (0.35 + 0.65 * ((sin(t + 2.1) + 1) / 2)).clamp(0.15, 1.0);
        final h3 = (0.35 + 0.65 * ((sin(t + 4.2) + 1) / 2)).clamp(0.15, 1.0);
        // Balkjes optisch even hoog als de iconen, met dezelfde onderlijn:
        // een kleine bodem-inset tilt ze gelijk met lamp/vlam.
        const maxH = 17.0;
        const bottomInset = 3.0;
        const barW = 3.5;
        return SizedBox(
          width: barW * 3 + 2 * 2, // 3 bars + 2 gaps
          height: _RoomActivityBadges._badgeSize,
          child: Padding(
            padding: const EdgeInsets.only(bottom: bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(barW, maxH * h1),
                const SizedBox(width: 2),
                _bar(barW, maxH * h2),
                const SizedBox(width: 2),
                _bar(barW, maxH * h3),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: LuxeColors.brass.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
}
