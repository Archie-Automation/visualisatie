import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../room_control_category.dart';
import '../../theme.dart';
import '../responsive.dart';
import 'device_tile_shell.dart';
import 'heater_icon.dart';

/// Horizontale chips (scene-stijl) per bedieningssegment; navigeert naar
/// `/floor/:floorId/room/:roomId/category/:slug`.
class RoomCategoryStrip extends StatelessWidget {
  const RoomCategoryStrip({
    super.key,
    required this.floorId,
    required this.roomId,
    required this.segments,
  });

  final String floorId;
  final String roomId;
  final List<RoomSegment> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    // Extra vertical room so chip box-shadows are not clipped.
    const double vPad = 10;
    const double chipH = 118;

    final hPad = context.hPad;
    return SizedBox(
      height: chipH + vPad * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        primary: false,
        clipBehavior: Clip.none,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
        itemCount: segments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final s = segments[i];
          return _SegmentChip(
            segment: s,
            onTap: () => context.push(
              '/floor/$floorId/room/$roomId/category/${s.slug}',
            ),
          );
        },
      ),
    );
  }
}

class _SegmentChip extends StatefulWidget {
  const _SegmentChip({required this.segment, required this.onTap});

  final RoomSegment segment;
  final VoidCallback onTap;

  @override
  State<_SegmentChip> createState() => _SegmentChipState();
}

class _SegmentChipState extends State<_SegmentChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = LuxeColors.brass;
    final fillColor = LuxeChipChrome.fill(context, pressed: _pressed);
    final borderColor =
        LuxeChipChrome.border(context, pressed: _pressed, accent: accent);
    final iconBox = context.chipIconBox;
    final iconSize = context.chipIconSize;
    final iconRadius = context.chipIconRadius;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: LuxeRimBox(
          width: 118,
          radius: 22,
          rimWidth: _pressed ? 1.3 : 1.0,
          rimColor: borderColor,
          fillColor: fillColor,
          shadows: LuxeShadows.chip(context),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LuxeAccentIconWell(
                size: iconBox,
                radius: iconRadius,
                accent: accent,
                child: iconWidgetForData(
                      widget.segment.icon,
                      size: iconSize,
                      color: accent,
                    ) ??
                    Icon(widget.segment.icon, size: iconSize, color: accent),
              ),
              SizedBox(
                width: 118 - 24,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      widget.segment.labelUpper,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: LuxeColors.ink,
                        fontSize: 11,
                        height: 1.35,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
