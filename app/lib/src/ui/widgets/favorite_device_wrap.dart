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
                    color: isFav
                        ? LuxeColors.brass.withValues(alpha: 0.12)
                        : LuxeColors.ink.withValues(alpha: 0.04),
                    border: Border.all(
                      color: isFav
                          ? LuxeColors.brass.withValues(alpha: 0.45)
                          : LuxeColors.ink.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 22,
                      color: isFav ? LuxeColors.brass : LuxeColors.inkSoft,
                    ),
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
