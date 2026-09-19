import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../theme.dart';
import '../../user_favorite_shortcuts.dart';

/// Star under a device tile so it can sit on the dashboard Favorieten chip.
class FavoriteDeviceWrap extends ConsumerWidget {
  const FavoriteDeviceWrap({
    super.key,
    required this.device,
    required this.cfg,
    required this.child,
  });

  final Device device;
  final HouseConfig cfg;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favOverrides = ref.watch(userFavoriteDevicesProvider);
    final isFav = effectiveDeviceFav(favOverrides, device);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final wasFav = isFav;
              await toggleUserFavoriteDevice(ref, cfg, device.id, wasFav);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    wasFav
                        ? '${device.name} van het beginscherm gehaald.'
                        : '${device.name} op het beginscherm gezet.',
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 2),
              child: Semantics(
                button: true,
                label: isFav
                    ? 'Haal van het beginscherm'
                    : 'Zet op het beginscherm',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: LuxeColors.ink.withValues(alpha: 0.04),
                    border: Border.all(
                      color: LuxeColors.ink.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Center(
                    child: _FavoriteStar(active: isFav, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Goud alleen in de ster. Ring en sterrand blijven antraciet (light: goud
/// op goud was onleesbaar).
class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({required this.active, this.size = 22});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return Icon(
        Icons.star_outline_rounded,
        size: size,
        color: LuxeColors.inkSoft,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.star_rounded,
            size: size,
            color: LuxeColors.brass,
          ),
          Icon(
            Icons.star_outline_rounded,
            size: size,
            color: LuxeColors.ink,
          ),
        ],
      ),
    );
  }
}
