import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import '../../media_api.dart';
import '../../theme.dart';

/// Bottom sheet that searches the services linked on a single player
/// (Sonos favourites/library, Bluesound's linked BluOS services) and plays
/// a result with one tap. Opened from the full-screen player.
class MediaSearchSheet extends ConsumerStatefulWidget {
  const MediaSearchSheet({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.api,
    this.isSonos = false,
  });

  final String deviceId;
  final String deviceName;
  final MediaApi api;
  /// Sonos can only search Spotify + its favourites/library (not every linked
  /// service), so the placeholder copy differs per brand.
  final bool isSonos;

  @override
  ConsumerState<MediaSearchSheet> createState() => _MediaSearchSheetState();
}

class _MediaSearchSheetState extends ConsumerState<MediaSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  bool _needsSpotifyAuth = false;
  List<MediaSearchSection> _sections = const [];

  /// Guards against out-of-order responses overwriting newer results.
  int _reqSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // refresh the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value));
  }

  Future<void> _run(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _sections = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final seq = ++_reqSeq;
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.searchMedia(widget.deviceId, q);
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _sections = result.sections;
        _needsSpotifyAuth = result.needsSpotifyAuth;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _error = 'Zoeken mislukt. Probeer het opnieuw.';
        _loading = false;
      });
    }
  }

  Future<void> _reconnectSpotify() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await widget.api.spotifyLoginUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      ref.invalidate(spotifyStatusProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kon Spotify-login niet openen')),
      );
    }
  }

  Future<void> _play(MediaSearchResult item) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.api.playItem(widget.deviceId, item);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Speelt: ${item.title}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(_friendlyError(e)),
        ),
      );
    }
  }

  /// Strip the Dart "Exception: " prefix so the backend message reads cleanly.
  String _friendlyError(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: height,
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: LuxeColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: LuxeColors.ink.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: LuxeColors.ink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: LuxeColors.brass, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Zoeken op ${widget.deviceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: _run,
                    decoration: InputDecoration(
                      hintText: 'Artiest, nummer, album of playlist…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _controller.clear();
                                _run('');
                                setState(() {});
                              },
                            ),
                      filled: true,
                      fillColor: LuxeColors.ink.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: LuxeColors.ink.withValues(alpha: 0.08)),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final content = _contentBody();
    if (!_needsSpotifyAuth) return content;
    return Column(
      children: [
        _spotifyReconnectBanner(),
        Expanded(child: content),
      ],
    );
  }

  Widget _spotifyReconnectBanner() => Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: LuxeColors.brass.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: LuxeColors.brass.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.link_off_rounded,
                color: LuxeColors.brassDeep, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'De Spotify-koppeling is verlopen. Verbind opnieuw om in Spotify te zoeken.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: LuxeColors.ink,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _reconnectSpotify,
              child: const Text('Verbind opnieuw'),
            ),
          ],
        ),
      );

  Widget _contentBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centered(Icons.error_outline_rounded, _error!);
    }
    if (_query.isEmpty) {
      return _centered(
        Icons.library_music_outlined,
        widget.isSonos
            ? 'Zoek in Spotify, je favorieten\nen de bibliotheek van deze speler.'
            : 'Zoek in Spotify en de gekoppelde\nmuziekdiensten van deze speler.',
      );
    }
    if (_sections.isEmpty) {
      return _centered(
        Icons.search_off_rounded,
        'Geen resultaten voor "$_query".',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _sections.length,
      itemBuilder: (_, i) {
        final section = _sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
              child: Text(
                section.title.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: LuxeColors.inkSoft,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
            ...section.results.map(
              (r) => _ResultRow(result: r, onTap: () => _play(r)),
            ),
          ],
        );
      },
    );
  }

  Widget _centered(IconData icon, String text) => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: LuxeColors.ink.withValues(alpha: 0.25)),
              SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: LuxeColors.inkSoft,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.onTap});

  final MediaSearchResult result;
  final VoidCallback onTap;

  IconData get _fallbackIcon => switch (result.kind) {
        'album' => Icons.album_rounded,
        'artist' => Icons.person_rounded,
        'playlist' => Icons.queue_music_rounded,
        'radio' => Icons.radio_rounded,
        'favorite' => Icons.star_rounded,
        _ => Icons.music_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final rawImg = result.image;
    final img = (rawImg != null && rawImg.startsWith('/'))
        ? '$apiBase$rawImg'
        : rawImg;

    final Widget art = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: img != null && img.isNotEmpty
          ? Image.network(
              img,
              width: 46,
              height: 46,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              cacheWidth: 128,
              errorBuilder: (_, __, ___) => _placeholder,
            )
          : _placeholder,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              art,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (result.subtitle != null &&
                        result.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: LuxeColors.inkSoft,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.play_arrow_rounded,
                  color: LuxeColors.brass, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _placeholder => Container(
        width: 46,
        height: 46,
        color: LuxeColors.ink.withValues(alpha: 0.06),
        child: Icon(_fallbackIcon,
            color: LuxeColors.ink.withValues(alpha: 0.3), size: 22),
      );
}
