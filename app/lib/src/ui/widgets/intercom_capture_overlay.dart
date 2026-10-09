import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api.dart';
import '../../camera_api.dart';
import '../../theme.dart';

/// Foto-flits op het beeld; de knoppen zelf horen in de belbalk.
class IntercomCaptureHandle {
  const IntercomCaptureHandle({
    required this.busy,
    required this.flash,
    required this.takePhoto,
    required this.openPhotos,
  });

  final bool busy;
  final Widget flash;
  final VoidCallback takePhoto;
  final VoidCallback openPhotos;
}

class IntercomCaptureScope extends ConsumerStatefulWidget {
  const IntercomCaptureScope({
    super.key,
    required this.intercomId,
    required this.builder,
  });

  final String intercomId;
  final Widget Function(BuildContext context, IntercomCaptureHandle handle)
      builder;

  @override
  ConsumerState<IntercomCaptureScope> createState() =>
      _IntercomCaptureScopeState();
}

class _IntercomCaptureScopeState extends ConsumerState<IntercomCaptureScope> {
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
    return widget.builder(
      context,
      IntercomCaptureHandle(
        busy: _busy,
        takePhoto: _shutter,
        openPhotos: _openGallery,
        flash: Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: _flash ? 0.72 : 0,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _deleteCapture(
  BuildContext context,
  WidgetRef ref, {
  required String intercomId,
  required IntercomCapture capture,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Foto wissen'),
      content: const Text('Deze foto wordt verwijderd.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Wissen'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await deleteIntercomCapture(
      intercomId: intercomId,
      captureId: capture.id,
      token: ref.read(authProvider).token,
    );
    ref.invalidate(intercomCapturesProvider(intercomId));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Foto wissen mislukt.'),
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
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
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Foto wissen',
                                  onPressed: () => _deleteCapture(
                                    context,
                                    ref,
                                    intercomId: intercomId,
                                    capture: cap,
                                  ),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: LuxeColors.inkSoft,
                                  ),
                                ),
                              ],
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
