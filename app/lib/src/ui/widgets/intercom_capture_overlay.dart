import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api.dart';
import '../../camera_api.dart';
import '../../theme.dart';

/// Shutter + recent stills, pinned to the live intercom frame (top-right).
class IntercomCaptureOverlay extends ConsumerStatefulWidget {
  const IntercomCaptureOverlay({super.key, required this.intercomId});

  final String intercomId;

  @override
  ConsumerState<IntercomCaptureOverlay> createState() =>
      _IntercomCaptureOverlayState();
}

class _IntercomCaptureOverlayState
    extends ConsumerState<IntercomCaptureOverlay> {
  bool _busy = false;
  bool _flash = false;

  Future<void> _shutter() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await takeIntercomCapture(
        intercomId: widget.intercomId,
        token: ref.read(authProvider).token,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _flash = true);
      ref.invalidate(intercomCapturesProvider(widget.intercomId));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (mounted) setState(() => _flash = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Foto maken mislukt.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openGallery() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CaptureGallerySheet(intercomId: widget.intercomId),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(intercomRingProvider, (prev, next) {
      if (next == null || next.intercomId != widget.intercomId) return;
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        ref.invalidate(intercomCapturesProvider(widget.intercomId));
      });
    });
    final captures = ref.watch(intercomCapturesProvider(widget.intercomId));
    final count = captures.value?.length ?? 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: _flash ? 0.72 : 0,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FrameIconButton(
                tooltip: 'Recente foto’s',
                icon: Icons.photo_library_outlined,
                badge: count > 0 ? (count > 9 ? '10' : '$count') : null,
                onTap: _openGallery,
              ),
              const SizedBox(width: 8),
              _FrameIconButton(
                tooltip: 'Foto maken',
                icon: Icons.photo_camera_outlined,
                loading: _busy,
                onTap: _shutter,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrameIconButton extends StatelessWidget {
  const _FrameIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.loading = false,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool loading;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xE61A1A18) : const Color(0xF2F4EFE6);
    final rim = LuxeBorders.solid(
      LuxeColors.ink.withValues(alpha: dark ? 0.35 : 0.22),
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fill,
        shape: CircleBorder(side: BorderSide(color: rim)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: loading ? null : onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LuxeColors.brass,
                    ),
                  )
                else
                  Icon(icon, size: 22, color: LuxeColors.ink),
                if (badge != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: LuxeColors.brass,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1914),
                          height: 1.1,
                        ),
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

class _CaptureGallerySheet extends ConsumerWidget {
  const _CaptureGallerySheet({required this.intercomId});
  final String intercomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final captures = ref.watch(intercomCapturesProvider(intercomId));
    final fmt = DateFormat('d MMM yyyy  HH:mm:ss');

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scroll) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1B18) : LuxeColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(
                color: LuxeBorders.solid(
                  LuxeColors.ink.withValues(alpha: dark ? 0.28 : 0.14),
                ),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LuxeColors.ink.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Laatste foto’s',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: LuxeColors.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'max. 10',
                      style: TextStyle(
                        fontSize: 12,
                        color: LuxeColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: captures.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: LuxeColors.brass),
                  ),
                  error: (e, _) => Center(
                    child: Text(
                      'Kan foto’s niet laden.',
                      style: TextStyle(color: LuxeColors.inkSoft),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          'Nog geen foto’s.\nBij aanbellen wordt automatisch een still bewaard.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: LuxeColors.inkSoft,
                            height: 1.4,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        final cap = list[i];
                        final ring = cap.source == 'ring';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: _AuthJpeg(
                                    url: cap.imageUrl,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              fmt.format(cap.at.toLocal()),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: LuxeColors.ink,
                              ),
                            ),
                            Text(
                              ring ? 'Bij aanbellen' : 'Handmatig',
                              style: TextStyle(
                                fontSize: 11,
                                color: LuxeColors.inkSoft,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AuthJpeg extends ConsumerStatefulWidget {
  const _AuthJpeg({required this.url, this.fit = BoxFit.contain});
  final String url;
  final BoxFit fit;

  @override
  ConsumerState<_AuthJpeg> createState() => _AuthJpegState();
}

class _AuthJpegState extends ConsumerState<_AuthJpeg> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AuthJpeg old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await fetchIntercomCaptureJpeg(
        url: widget.url,
        token: ref.read(authProvider).token,
      );
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      /* keep empty */
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LuxeColors.brass,
          ),
        ),
      );
    }
    return Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
  }
}
