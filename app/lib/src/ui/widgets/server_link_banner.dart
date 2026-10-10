import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';

/// Blijft staan zolang de huisserver niet bereikbaar is. De bus zelf
/// probeert op de achtergrond opnieuw te verbinden.
class ServerLinkBanner extends ConsumerWidget {
  const ServerLinkBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authProvider.select((a) => a.isAuthed));
    final link = ref.watch(serverLinkProvider);
    if (!authed || link != ServerLink.offline) {
      return const SizedBox.shrink();
    }

    final light = Theme.of(context).brightness == Brightness.light;
    final bg = light ? const Color(0xFF3A1818) : const Color(0xFFF3D4D4);
    final fg = light ? const Color(0xFFFFF7F6) : const Color(0xFF3A1212);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: bg,
        statusBarIconBrightness: light ? Brightness.light : Brightness.dark,
        statusBarBrightness: light ? Brightness.dark : Brightness.light,
      ),
      child: Material(
        color: bg,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: fg, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Geen verbinding met de server. Opnieuw verbinden…',
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
