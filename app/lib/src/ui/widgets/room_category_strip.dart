import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../room_control_category.dart';
import '../../theme.dart';
import '../responsive.dart';

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
    const accent = LuxeColors.brass;

    final fillColor =
        LuxeColors.surface.withValues(alpha: _pressed ? 0.95 : 0.82);
    final borderColor =
        _pressed ? accent.withValues(alpha: 0.55) : LuxeColors.glassRim;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 118,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: fillColor,
            border: Border.all(color: borderColor, width: _pressed ? 1.3 : 1),
            boxShadow: LuxeShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: accent.withValues(alpha: 0.15),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Icon(widget.segment.icon, size: 18, color: accent),
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
                      style: const TextStyle(
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
