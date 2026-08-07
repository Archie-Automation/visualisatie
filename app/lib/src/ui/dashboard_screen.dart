import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../fireplace_status.dart';
import '../fireplace_virtual.dart';
import '../idle_reset.dart';
import '../media_api.dart';
import '../models.dart';
import '../room_control_category.dart';
import '../satel_api.dart';
import '../theme.dart';
import '../user_favorite_shortcuts.dart';
import 'responsive.dart';
import 'widgets/back_pill.dart';
import 'widgets/device_tile_shell.dart';
import 'widgets/glass_card.dart';
import 'widgets/heater_icon.dart';
import 'widgets/honeycomb_pattern.dart';
import 'widgets/light_status_icon.dart';
import 'widgets/split_unit_icon.dart';
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
  /// Tablet/desktop: false = startscherm (geen kamers); true = verdieping open.
  bool _floorBrowsing = false;
  late final ScrollController _mainScroll;
  late final ScrollController _floorScroll;
  late final ScrollController _systemScroll;
  late final ScrollController _sceneScroll;
  late final ScrollController _roomsScroll;

  @override
  void initState() {
    super.initState();
    _mainScroll = ScrollController();
    _floorScroll = ScrollController();
    _systemScroll = ScrollController();
    _sceneScroll = ScrollController();
    _roomsScroll = ScrollController();
  }

  @override
  void dispose() {
    _mainScroll.dispose();
    _floorScroll.dispose();
    _systemScroll.dispose();
    _sceneScroll.dispose();
    _roomsScroll.dispose();
    super.dispose();
  }

  void _resetIdleScrollState() {
    if (_mainScroll.hasClients) _mainScroll.jumpTo(0);
    if (_floorScroll.hasClients) _floorScroll.jumpTo(0);
    if (_systemScroll.hasClients) _systemScroll.jumpTo(0);
    if (_sceneScroll.hasClients) _sceneScroll.jumpTo(0);
    if (_roomsScroll.hasClients) _roomsScroll.jumpTo(0);
    if (_floorIndex != 0 || _floorBrowsing) {
      setState(() {
        _floorIndex = 0;
        _floorBrowsing = false;
      });
    }
  }

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
    ref.listen<int>(idleResetSignalProvider, (prev, next) {
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resetIdleScrollState();
        });
      }
    });

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
    final isPanel = !context.isPhone;

    // Wall tablet / desktop: floor drill-down — header als systemen (hoogte + honeycomb).
    if (isPanel && _floorBrowsing && selectedFloor != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FloorBrowseHeader(
            floors: floors,
            selectedIndex: safeIndex,
            scrollController: _floorScroll,
            onBack: () => setState(() => _floorBrowsing = false),
            onSelect: (i) => setState(() {
              _floorIndex = i;
              if (_roomsScroll.hasClients) _roomsScroll.jumpTo(0);
            }),
          ),
          Expanded(
            child: ListView(
              controller: _roomsScroll,
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                _FloorRoomsBlock(
                  floor: selectedFloor,
                  showTopBorder: false,
                  onOpenRoom: (room) => context
                      .push('/floor/${selectedFloor.id}/room/${room.id}'),
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _mainScroll,
      physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: _header(context, cfg, auth, ref)),
        SliverToBoxAdapter(
            child: _scenes(context, cfg, canEdit, ref,
                scrollController: _sceneScroll)),
        SliverToBoxAdapter(
            child: _Systemen(cfg: cfg, scrollController: _systemScroll)),
        if (floors.isNotEmpty && isPanel)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _FloorsHomeBand(
              floors: floors,
              scrollController: _floorScroll,
              onSelect: (i) => setState(() {
                _floorIndex = i;
                _floorBrowsing = true;
              }),
            ),
          )
        else if (floors.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _FloorTabBar(
              floors: floors,
              selectedIndex: safeIndex,
              scrollController: _floorScroll,
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
      ],
    );
  }
}

/// Sticky header bij kamer-browse: zelfde hoogte als systemen, terug + verdiepingen.
class _FloorBrowseHeader extends StatelessWidget {
  const _FloorBrowseHeader({
    required this.floors,
    required this.selectedIndex,
    required this.onSelect,
    required this.onBack,
    this.scrollController,
  });

  final List<Floor> floors;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return StickyHeaderSurface(
      height: context.roomStickyHeaderH,
      child: Padding(
        padding: EdgeInsets.fromLTRB(context.hPad - 4, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            HeaderIconButton(
              icon: Icons.arrow_back_ios_new,
              onTap: onBack,
              tooltip: 'Terug',
            ),
            Expanded(
              child: _FloorTabBar(
                floors: floors,
                selectedIndex: selectedIndex,
                scrollController: scrollController,
                onSelect: onSelect,
                bottomPadding: 0,
                listPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontale verdieping-kiezer (tabs). Lang indrukken opent de volgorde-popup.
class _FloorTabBar extends ConsumerWidget {
  const _FloorTabBar({
    required this.floors,
    required this.selectedIndex,
    required this.onSelect,
    this.scrollController,
    this.bottomPadding = 14,
    this.listPadding,
  });

  final List<Floor> floors;
  /// Use `-1` when no floor should appear selected (tablet home).
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ScrollController? scrollController;
  final double bottomPadding;
  final EdgeInsetsGeometry? listPadding;

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
    const chipH = HeaderIconButton.size;
    final pad = listPadding ??
        EdgeInsets.fromLTRB(context.hPad, 8, context.hPad, 8);
    final vPadTotal = pad is EdgeInsets ? pad.vertical : 16.0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SizedBox(
        height: chipH + vPadTotal,
        child: ListView.separated(
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          primary: false,
          clipBehavior: Clip.none,
          physics: const ClampingScrollPhysics(),
          padding: pad,
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
                borderRadius: BorderRadius.circular(12),
                child: LuxeRimBox(
                  height: chipH,
                  radius: 12,
                  rimWidth: selected ? 2 : 1,
                  rimColor: selected
                      ? LuxeBorders.solid(LuxeColors.brass)
                      : LuxeColors.glassRim,
                  fillColor: LuxeChipChrome.fill(
                    context,
                    pressed: selected,
                  ),
                  shadows: selected ? LuxeShadows.soft : null,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Center(
                    child: Text(
                      floor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                        applyHeightToLastDescent: false,
                      ),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            height: 1.0,
                            color: selected
                                ? LuxeColors.ink
                                : LuxeColors.inkSoft,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
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

/// Tablet startscherm: verdiepingen verticaal gecentreerd (geen lijn onder systemen).
class _FloorsHomeBand extends StatelessWidget {
  const _FloorsHomeBand({
    required this.floors,
    required this.onSelect,
    this.scrollController,
  });

  final List<Floor> floors;
  final ValueChanged<int> onSelect;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _FloorTabBar(
        floors: floors,
        selectedIndex: -1,
        scrollController: scrollController,
        onSelect: onSelect,
        bottomPadding: 0,
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            Padding(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  Icon(Icons.layers_outlined,
                      size: 20, color: LuxeColors.brass),
                  SizedBox(width: 10),
                  Text('Verdiepingen rangschikken',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
              child: Text(
                'Houd de handgreep even ingedrukt en sleep om de volgorde te wijzigen.',
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
                        EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDelayedDragStartListener(
                      index: i,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: LuxeColors.inkSoft),
                      ),
                    ),
                    title: Text(floor.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: LuxeColors.ink)),
                    subtitle: Text(
                        '${floor.rooms.length} kamer${floor.rooms.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12, color: LuxeColors.inkSoft)),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            Padding(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  Icon(Icons.sort_rounded,
                      size: 20, color: LuxeColors.brass),
                  SizedBox(width: 10),
                  Text('Scenes rangschikken',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 12),
              child: Text(
                'Houd de handgreep even ingedrukt en sleep om de volgorde te wijzigen.',
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
                        EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDelayedDragStartListener(
                      index: i,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: LuxeColors.inkSoft),
                      ),
                    ),
                    title: Text(scene.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: LuxeColors.ink)),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
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
        padding: EdgeInsets.only(top: 12, bottom: 4),
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
    this.showTopBorder = true,
  });

  final Floor floor;
  final void Function(Room room) onOpenRoom;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (floor.rooms.isEmpty) return const SizedBox.shrink();

    final orderMap = ref.watch(roomOrderProvider);
    final rooms = applyRoomOrder(orderMap, floor);

    return Padding(
      // Only bottom spacing; cards go edge-to-edge horizontally.
      padding: EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full-width room list (geen top/bottom banen).
          ReorderableListView.builder(
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
                return _RoomDashboardRow(
                  key: ValueKey(room.id),
                  floor: floor,
                  room: room,
                  index: i,
                  showDivider: false,
                  onOpenRoom: () => onOpenRoom(room),
                );
              },
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // â”€â”€ Room header row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // Only the name text + chevron are tappable for room navigation.
        // Activity badges have their own tap targets for system sheets.
        Padding(
          padding: EdgeInsets.fromLTRB(hp, 16, hp, segments.isEmpty ? 16 : 10),
          child: Row(
            children: [
              // Drag handle — long-press first so horizontal swipes don't reorder.
              ReorderableDelayedDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(2, 6, 12, 6),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 22,
                      color: LuxeColors.inkSoft.withValues(alpha: 0.75),
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
                        room.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Same family as scenes/systems; slightly larger for
                        // list-row context (chips read bigger inside their tile).
                        style: TextStyle(
                          color: LuxeColors.ink,
                          fontSize: 12,
                          height: 1.35,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: LuxeColors.inkSoft.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
              Spacer(),
              _RoomActivityBadges(floor: floor, room: room),
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
        _HouseActivityHeaderButtons(cfg: cfg),
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
  WidgetRef ref, {
  ScrollController? scrollController,
}) {
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
            if (cfg.scenes.length > 1) ...[
              const Spacer(),
              GestureDetector(
                onTap: () => showModalBottomSheet<void>(
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
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.sort_rounded,
                    size: 22,
                    color: LuxeColors.inkSoft.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      SceneStrip(
        scenes: ordered,
        canEdit: canEdit,
        scrollController: scrollController,
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
  const _Systemen({required this.cfg, this.scrollController});
  final HouseConfig cfg;
  final ScrollController? scrollController;

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
      padding: EdgeInsets.fromLTRB(0, 16, 0, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(context.hPad, 0, context.hPad, 16),
            child: Row(
              children: [
                Text('SYSTEMEN',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                GestureDetector(
                  onTap: () => _openManageSheet(context, ref, allOrderedChips, sysHidden),
                  child: Padding(
                    padding: EdgeInsets.only(left: 8),
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
              scrollController: scrollController,
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        color: LuxeColors.cream,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            Padding(
              padding: EdgeInsets.fromLTRB(22, 10, 22, 4),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded,
                      size: 20, color: LuxeColors.brass),
                  SizedBox(width: 10),
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
                        EdgeInsets.symmetric(horizontal: 8),
                    leading: ReorderableDelayedDragStartListener(
                      index: i,
                      child: Padding(
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
                        SizedBox(width: 10),
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
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
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

    final fillColor = LuxeChipChrome.fill(context, pressed: _pressed);
    final borderColor = hasAlert
        ? LuxeBorders.solid(accent.withValues(alpha: 0.7))
        : LuxeChipChrome.border(
            context,
            pressed: _pressed,
            accent: defaultAccent,
          );

    final iconBox = context.chipIconBox;
    final iconSize = context.chipIconSize;
    final iconRadius = context.chipIconRadius;

    // The icon for the alarm chip needs animated transforms.
    Widget iconWidget = Icon(widget.data.icon, size: iconSize, color: accent);
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
            final blinkBorder = LuxeBorders.solid(
              (isAlarm && alarmIsActive)
                  ? accent.withValues(
                      alpha: 0.30 + 0.50 * _blinkAnim.value)
                  : borderColor,
            );
            final blinkWidth = (isAlarm && alarmIsActive)
                ? 1.0 + 0.8 * _blinkAnim.value
                : (_pressed || hasAlert ? 1.3 : 1.0);
            return LuxeRimBox(
              width: 118,
              radius: 22,
              rimWidth: blinkWidth,
              rimColor: blinkBorder,
              fillColor: fillColor,
              shadows: LuxeShadows.chip(context),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: child!,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  LuxeAccentIconWell(
                    size: iconBox,
                    radius: iconRadius,
                    accent: accent,
                    child: iconWidget,
                  ),
                  if (hasAlert)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(3),
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

  static const double size = 48;
  static const double iconSize = 20;
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: LuxeRimBox(
        width: size,
        height: size,
        radius: radius,
        rimWidth: 1,
        rimColor: LuxeColors.glassRim,
        fillColor: LuxeChipChrome.fill(context, pressed: false),
        shadows: LuxeShadows.soft,
        child: Center(
          child: Icon(icon, color: LuxeColors.ink, size: iconSize),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Same shell as [_GlassIconButton] — neutrale chrome, brass blijft op het glyph.
class _GlassStatusButton extends StatelessWidget {
  const _GlassStatusButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LuxeRimBox(
          width: _GlassIconButton.size,
          height: _GlassIconButton.size,
          radius: _GlassIconButton.radius,
          rimWidth: 1,
          rimColor: LuxeColors.glassRim,
          fillColor: LuxeChipChrome.fill(context, pressed: false),
          shadows: LuxeShadows.soft,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// House-wide activity: lights / heater / fireplace / ac / music → system pages.
class _HouseActivityHeaderButtons extends ConsumerWidget {
  const _HouseActivityHeaderButtons({required this.cfg});
  final HouseConfig cfg;

  static const _glyph = 24.0;

  void _openSystem(BuildContext context, String sysName) {
    final sys = houseSystemByName(sysName);
    final route = sys?.routePath;
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Header status cluster is tablet/desktop only — phone keeps a clean header.
    if (context.isPhone) return const SizedBox.shrink();

    final bus = ref.watch(busProvider);
    final mediaStates = ref.watch(mediaStateProvider);
    final fireplaceVirtual = ref.watch(fireplaceVirtualProvider);
    final gap = 10.0;

    var lightsOn = false;
    var heaterOn = false;
    var fireplaceOn = false;
    var acOn = false;
    var mediaPlaying = false;

    for (final d in cfg.allDevices) {
      if (!lightsOn && _RoomActivityBadges._isLightOn(d, bus)) lightsOn = true;
      if (!heaterOn && _RoomActivityBadges._isHeaterActive(d, bus)) {
        heaterOn = true;
      }
      if (!fireplaceOn &&
          _RoomActivityBadges._isFireplaceOn(d, bus, fireplaceVirtual)) {
        fireplaceOn = true;
      }
      if (!acOn && _RoomActivityBadges._isAcOn(d, bus)) acOn = true;
      if (!mediaPlaying && d.type.isMedia) {
        final ms = mediaStates[d.id];
        if (ms != null && ms.transport.isActive) mediaPlaying = true;
      }
      if (lightsOn && heaterOn && fireplaceOn && acOn && mediaPlaying) break;
    }

    final buttons = <Widget>[
      if (lightsOn)
        _GlassStatusButton(
          tooltip: 'Verlichting aan',
          onTap: () => _openSystem(context, 'Verlichting'),
          child: LightStatusIcon(size: _glyph, color: LuxeColors.ink),
        ),
      if (heaterOn)
        _GlassStatusButton(
          tooltip: 'Heater aan',
          onTap: () => _openSystem(context, 'Diverse'),
          child: _HeaterBadge(size: _glyph, color: LuxeColors.ink),
        ),
      if (fireplaceOn)
        _GlassStatusButton(
          tooltip: 'Openhaard aan',
          onTap: () => _openSystem(context, 'Openhaard'),
          child: _FireBadge(size: _glyph, color: LuxeColors.ink),
        ),
      if (acOn)
        _GlassStatusButton(
          tooltip: 'Airco aan',
          onTap: () => _openSystem(context, 'Klimaat'),
          child: SplitUnitIcon(size: _glyph, color: LuxeColors.ink),
        ),
      if (mediaPlaying)
        _GlassStatusButton(
          tooltip: 'Muziek speelt',
          onTap: () => _openSystem(context, 'Audio'),
          child: _EqualizerBadge(size: _glyph, color: LuxeColors.ink),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            buttons[i],
          ],
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Room activity badges                                                */
/* ------------------------------------------------------------------ */

class _RoomActivityBadges extends ConsumerWidget {
  const _RoomActivityBadges({required this.floor, required this.room});
  final Floor floor;
  final Room room;

  /// Baseline for equalizer scale math.
  static const _badgeSize = 22.0;
  static const _glyphSize = 18.0;
  static const _slotHeight = 36.0;

  void _openCategory(BuildContext context, String categorySlug) {
    context.push(
      '/floor/${floor.id}/room/${room.id}/category/$categorySlug',
    );
  }

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

  static bool _isHeaterActive(Device d, BusState bus) {
    if (d.type != DeviceType.universal) return false;
    final cfg = d.raw['universal'] as Map<String, dynamic>?;
    if (cfg == null) return false;
    if ((cfg['icon'] as String?) != 'heater') return false;
    final buttons =
        (cfg['buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final b in buttons) {
      final ga = b['statusGa'] as String?;
      if (ga == null) continue;
      final v = bus.values[ga];
      if (v == true || v == 1) return true;
    }
    return false;
  }

  static bool _isFireplaceOn(
    Device d,
    BusState bus,
    Map<String, bool> fireplaceVirtual,
  ) {
    if (d.type != DeviceType.fireplace) return false;
    final cfg = d.raw['fireplace'] as Map<String, dynamic>?;
    if (cfg == null) return false;
    final workingOn = fireplaceWorkingOn(cfg, bus.values);
    if (workingOn != null) return workingOn;
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

  static bool _isAcOn(Device d, BusState bus) {
    if (d.type != DeviceType.ac) return false;
    final cfg = d.raw['ac'] as Map<String, dynamic>?;
    if (cfg == null) return false;
    final onOff = cfg['onOff'];
    if (onOff is! Map) return false;
    final ga = (onOff['statusGa'] ?? onOff['ga']) as String?;
    if (ga == null) return false;
    final v = bus.values[ga];
    return v == true || v == 1;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bus = ref.watch(busProvider);
    final mediaStates = ref.watch(mediaStateProvider);
    final fireplaceVirtual = ref.watch(fireplaceVirtualProvider);

    bool lightsOn = false;
    bool mediaPlaying = false;
    bool fireplaceOn = false;
    Device? activeHeater;
    Device? activeAc;
    Device? meldingWindow;
    Device? meldingDoor;
    Device? meldingGarage;

    for (final d in room.devices) {
      if (!lightsOn && _isLightOn(d, bus)) lightsOn = true;
      if (!fireplaceOn && _isFireplaceOn(d, bus, fireplaceVirtual)) {
        fireplaceOn = true;
      }
      if (activeHeater == null && _isHeaterActive(d, bus)) activeHeater = d;
      if (activeAc == null && _isAcOn(d, bus)) activeAc = d;
      if (!mediaPlaying && d.type.isMedia) {
        final ms = mediaStates[d.id];
        if (ms != null && ms.transport.isActive) mediaPlaying = true;
      }
      if (d.type == DeviceType.melding) {
        final o = _openings(d, bus);
        if (o.window && meldingWindow == null) meldingWindow = d;
        if (o.door && meldingDoor == null) meldingDoor = d;
        if (o.garageDoor && meldingGarage == null) meldingGarage = d;
      }
    }

    final heaterOn = activeHeater != null;
    final acOn = activeAc != null;
    final windowOpen = meldingWindow != null;
    final doorOpen = meldingDoor != null;
    final garageDoorOpen = meldingGarage != null;

    final any = lightsOn ||
        mediaPlaying ||
        fireplaceOn ||
        heaterOn ||
        acOn ||
        windowOpen ||
        doorOpen ||
        garageDoorOpen;

    if (!any) return const SizedBox.shrink();

    // Kale glyphs — geen glass/wells.
    // Phone: brass. Tablet: ink (zwart light / wit dark), gelijk aan header.
    final phone = context.isPhone;
    final glyph = phone ? _glyphSize : 22.0;
    final slot = phone ? _slotHeight : 40.0;
    final badge = phone ? _badgeSize : 26.0;
    final color = phone ? LuxeColors.brass : LuxeColors.ink;

    Widget tap(Widget child, String categorySlug) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openCategory(context, categorySlug),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: SizedBox(
              width: badge,
              height: badge,
              child: Center(child: child),
            ),
          ),
        );

    return SizedBox(
      height: slot,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (lightsOn)
            tap(
              Icon(Icons.lightbulb_outline_rounded, size: glyph, color: color),
              'lighting',
            ),
          if (fireplaceOn)
            tap(_FireBadge(size: glyph + 2, color: color), 'fireplace'),
          if (heaterOn)
            tap(
              _HeaterBadge(size: glyph + 1, color: color),
              'universal__${activeHeater.id}',
            ),
          if (acOn)
            tap(
              SplitUnitIcon(size: glyph, color: color),
              'climate',
            ),
          if (windowOpen)
            tap(
              Icon(Icons.sensor_window_outlined, size: glyph, color: color),
              'melding__${meldingWindow.id}',
            ),
          if (doorOpen)
            tap(
              Icon(Icons.door_front_door_outlined, size: glyph, color: color),
              'melding__${meldingDoor.id}',
            ),
          if (garageDoorOpen)
            tap(
              Icon(Icons.garage_outlined, size: glyph, color: color),
              'melding__${meldingGarage.id}',
            ),
          if (mediaPlaying)
            tap(_EqualizerBadge(size: badge, color: color), 'audio'),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Animated fire badge                                                 */
/* ------------------------------------------------------------------ */

class _FireBadge extends StatefulWidget {
  const _FireBadge({
    this.size = _RoomActivityBadges._glyphSize + 2,
    this.color,
  });
  final double size;
  final Color? color;

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
      duration: const Duration(milliseconds: 1750),
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
              size: widget.size,
              color: widget.color ?? LuxeColors.brass,
            ),
          );
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Animated heater badge                                               */
/* ------------------------------------------------------------------ */

class _HeaterBadge extends StatelessWidget {
  const _HeaterBadge({
    this.size = _RoomActivityBadges._glyphSize + 1,
    this.color,
  });
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return HeaterIcon(
      size: size,
      color: color ?? LuxeColors.brass,
      animate: true,
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Animated equalizer icon                                             */
/* ------------------------------------------------------------------ */

class _EqualizerBadge extends StatefulWidget {
  const _EqualizerBadge({
    this.size = _RoomActivityBadges._badgeSize,
    this.color,
  });
  final double size;
  final Color? color;

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
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.size / _RoomActivityBadges._badgeSize;
    final maxH = 17.0 * scale;
    final bottomInset = 3.0 * scale;
    final barW = 3.5 * scale;
    final gap = 2.0 * scale;
    final color = widget.color ?? LuxeColors.brass;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value * 2 * pi;
        // Three bars with different phase offsets
        final h1 = (0.35 + 0.65 * ((sin(t) + 1) / 2)).clamp(0.15, 1.0);
        final h2 = (0.35 + 0.65 * ((sin(t + 2.1) + 1) / 2)).clamp(0.15, 1.0);
        final h3 = (0.35 + 0.65 * ((sin(t + 4.2) + 1) / 2)).clamp(0.15, 1.0);
        return SizedBox(
          width: barW * 3 + gap * 2,
          height: widget.size,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(barW, maxH * h1, color),
                SizedBox(width: gap),
                _bar(barW, maxH * h2, color),
                SizedBox(width: gap),
                _bar(barW, maxH * h3, color),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double w, double h, Color color) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
}
