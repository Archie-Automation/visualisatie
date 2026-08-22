import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../models.dart';
import '../../scene_api.dart';
import '../../theme.dart';
import '../responsive.dart';
import '../scene_editor_sheet.dart';
import 'device_tile_shell.dart';
import 'scene_icons.dart';

/// Horizontal strip of scene chips. Shown at the top of the dashboard
/// and every room screen. If [canEdit] is true, a trailing "+" chip
/// appears that opens the scene editor.
class SceneStrip extends ConsumerWidget {
  const SceneStrip({
    super.key,
    required this.scenes,
    required this.canEdit,
    required this.onEdited,
    this.roomId,
    this.dark = false,
    this.scrollController,
  });

  /// Current scenes to display.
  final List<Scene> scenes;

  /// True if the active user may create / edit / delete scenes.
  final bool canEdit;

  /// Called after the editor sheet has saved a new list. Parent refreshes.
  final ValueChanged<List<Scene>> onEdited;

  /// When non-null we're rendering room-scoped scenes – editor saves
  /// to `PUT /rooms/:id/scenes`. When null, the editor saves globally.
  final String? roomId;

  /// Use light foreground on dark ambient backgrounds (intercom etc.).
  final bool dark;

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = scenes.length + (canEdit ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();

    const double vPad = 10;
    final hPad = context.hPad;
    return SizedBox(
      height: 124 + vPad * 2,
      child: ListView.separated(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        primary: false,
        clipBehavior: Clip.none,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == scenes.length) {
            return _AddSceneChip(
              dark: dark,
              onTap: () => _openEditor(context, ref),
            );
          }
          final scene = scenes[i];
          return _SceneChip(
            scene: scene,
            dark: dark,
            onTap: () => _runScene(context, ref, scene),
            onLongPress:
                canEdit ? () => _openEditor(context, ref, initial: scene) : null,
          );
        },
      ),
    );
  }

  Future<void> _runScene(
      BuildContext context, WidgetRef ref, Scene scene) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(sceneApiProvider).run(scene.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.ink,
          shape: const StadiumBorder(),
          content: Text('${scene.name} gestart'),
        ),
      );
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: LuxeColors.danger,
          shape: const StadiumBorder(),
          content: Text('Scene mislukt: $err'),
        ),
      );
      rethrow;
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Scene? initial,
  }) async {
    // The editor needs the full HouseConfig to offer the device picker.
    final cfg = ref.read(configProvider).value;
    if (cfg == null) return;
    final next = await showModalBottomSheet<List<Scene>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SceneEditorSheet(
        scenes: scenes,
        config: cfg,
        initiallySelectedId: initial?.id,
        createNew: initial == null,
        scope: roomId == null ? SceneScope.global : SceneScope.room,
        roomId: roomId,
      ),
    );
    if (next != null) onEdited(next);
  }
}

class _SceneChip extends StatefulWidget {
  const _SceneChip({
    required this.scene,
    required this.onTap,
    required this.dark,
    this.onLongPress,
  });

  final Scene scene;

  /// Async-aware tap handler. Ignores re-taps while the scene call is in flight.
  final Future<void> Function() onTap;
  final VoidCallback? onLongPress;
  final bool dark;

  @override
  State<_SceneChip> createState() => _SceneChipState();
}

class _SceneChipState extends State<_SceneChip> {
  bool _pressed = false;
  bool _running = false;

  Future<void> _handleTap() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      await widget.onTap();
    } catch (_) {
      /* parent already surfaced the error */
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `dark` = forced light-on-dark for special overlays; otherwise follow theme.
    final forceDarkChrome = widget.dark;
    final fg = forceDarkChrome ? Colors.white : LuxeColors.ink;
    final accentHex = widget.scene.color;
    final accent = accentHex != null
        ? _parseHex(accentHex) ?? LuxeColors.brass
        : LuxeColors.brass;

    final fillColor = forceDarkChrome
        ? Colors.white.withValues(alpha: _pressed ? 0.12 : 0.06)
        : LuxeChipChrome.fill(context, pressed: _pressed);
    final borderColor = forceDarkChrome
        ? LuxeBorders.solid(
            _pressed
                ? accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.18),
            LuxeColors.cream,
          )
        : LuxeChipChrome.border(context, pressed: _pressed, accent: accent);
    final iconBox = context.chipIconBox;
    final iconSize = context.chipIconSize;
    final iconRadius = context.chipIconRadius;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: LuxeRimBox(
          width: 118,
          radius: 22,
          rimWidth: _pressed ? 1.3 : 1.0,
          rimColor: borderColor,
          fillColor: fillColor,
          shadows: forceDarkChrome
              ? LuxeShadows.darkLift
              : LuxeShadows.chip(context),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LuxeAccentIconWell(
                size: iconBox,
                radius: iconRadius,
                accent: accent,
                child: Icon(
                  sceneIconFor(widget.scene.icon),
                  size: iconSize,
                  color: accent,
                ),
              ),
              Text(
                widget.scene.name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  height: 1.35,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddSceneChip extends StatelessWidget {
  const _AddSceneChip({required this.onTap, required this.dark});
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final forceDark = dark;
    final fg = forceDark ? Colors.white70 : LuxeColors.inkSoft;
    final border = forceDark
        ? LuxeBorders.solid(
            Colors.white.withValues(alpha: 0.18),
            LuxeColors.cream,
          )
        : LuxeChipChrome.border(context, pressed: false);
    final fill = forceDark
        ? Colors.white.withValues(alpha: 0.04)
        : LuxeChipChrome.fill(context, pressed: false);
    return GestureDetector(
      onTap: onTap,
      child: LuxeRimBox(
        width: 88,
        radius: 22,
        rimWidth: 1,
        rimColor: border,
        fillColor: fill,
        shadows: forceDark ? null : LuxeShadows.chip(context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: fg, size: 22),
              const SizedBox(height: 6),
              Text(
                'SCENE',
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color? _parseHex(String s) {
  var v = s.replaceAll('#', '');
  if (v.length == 6) v = 'FF$v';
  final n = int.tryParse(v, radix: 16);
  return n == null ? null : Color(n);
}
