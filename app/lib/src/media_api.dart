import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// Transport state as published by the backend's `MediaManager`.
enum MediaTransport {
  playing,
  paused,
  stopped,
  buffering;

  static MediaTransport fromJson(String? v) => switch (v) {
        'playing' => playing,
        'paused' => paused,
        'buffering' => buffering,
        _ => stopped,
      };

  bool get isActive => this == playing || this == buffering;

  /// Dutch status when there is no track title — no technical terms like
  /// "buffering" / "transitioning" for end users.
  String get customerStatusLine => switch (this) {
        stopped => 'Gestopt',
        paused => 'Gepauzeerd',
        buffering => 'Starten…',
        playing => 'Starten…',
      };
}

/// Raw stream URLs / Sonos placeholders — hide until RDS metadata is ready.
bool isTechnicalMediaMetadata(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return false;
  if (RegExp(r'\.(aac|mp3|m4a|flac|wav|opus)(\?|#|$)', caseSensitive: false)
      .hasMatch(t)) {
    return true;
  }
  if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(t)) {
    return true;
  }
  if (RegExp(r'TLPSTR|SID=|\bsid=', caseSensitive: false).hasMatch(t)) {
    return true;
  }
  if (t.contains('?') && t.length < 80 && t.contains(RegExp(r'[=&]'))) {
    return true;
  }
  return false;
}

extension MediaStateDisplay on MediaState {
  String? get cleanTitle {
    final t = title?.trim();
    if (t == null || t.isEmpty || isTechnicalMediaMetadata(t)) return null;
    return t;
  }

  String? get cleanArtist {
    final a = artist?.trim();
    if (a == null || a.isEmpty || isTechnicalMediaMetadata(a)) return null;
    return a;
  }

  String headline({required bool revealMetadata}) {
    if (!online) return 'Offline';
    if (revealMetadata) {
      final t = cleanTitle;
      if (t != null) return t;
    }
    if (transport.isActive) return 'Starten…';
    return transport.customerStatusLine;
  }

  String metaLine({required bool revealMetadata}) {
    if (!online || !revealMetadata || cleanTitle == null) return '';
    return [cleanArtist, album?.trim()]
        .where((s) => s != null && s.isNotEmpty && !isTechnicalMediaMetadata(s))
        .join(' — ');
  }

  /// Eén regel voor compacte tegels (titel + artiest).
  String compactLine({required bool revealMetadata}) {
    if (!online) return 'Offline';
    if (!revealMetadata) {
      return transport.isActive ? 'Starten…' : transport.customerStatusLine;
    }
    final t = cleanTitle;
    if (t == null) {
      return transport.isActive ? 'Starten…' : transport.customerStatusLine;
    }
    final a = cleanArtist;
    if (a != null) return '$t — $a';
    return t;
  }
}

enum MediaGroupRole {
  standalone,
  coordinator,
  member;

  static MediaGroupRole fromJson(String? v) => switch (v) {
        'coordinator' => coordinator,
        'member' => member,
        _ => standalone,
      };

  bool get isGrouped => this == coordinator || this == member;
}

/// Coordinator first, then members. Works from a member tile via the coordinator state.
List<String> mediaGroupDeviceIds(
  MediaState state,
  String deviceId, [
  Map<String, MediaState>? all,
]) {
  if (state.groupRole == MediaGroupRole.coordinator) {
    return [deviceId, ...state.groupMemberIds];
  }
  if (state.groupRole == MediaGroupRole.member) {
    final coordId = state.groupCoordinatorId;
    if (coordId == null) return [deviceId];
    final coord = all?[coordId];
    if (coord != null && coord.groupMemberIds.isNotEmpty) {
      return [coordId, ...coord.groupMemberIds];
    }
    return [coordId, deviceId];
  }
  return [deviceId];
}

enum MediaBrand {
  sonos,
  bluesound;

  static MediaBrand fromJson(String? v) => switch (v) {
        'bluesound' => bluesound,
        _ => sonos,
      };

  String get label => switch (this) {
        MediaBrand.sonos => 'Sonos',
        MediaBrand.bluesound => 'Bluesound',
      };
}

class MediaPreset {
  final String id;
  final String name;
  final String? image;
  final String? uri;
  const MediaPreset({required this.id, required this.name, this.image, this.uri});

  factory MediaPreset.fromJson(Map<String, dynamic> j) => MediaPreset(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        image: j['image'] as String?,
        uri: j['uri'] as String?,
      );
}

/// Mirror of the backend's `MediaState` broadcast shape.
class MediaState {
  final String deviceId;
  final MediaBrand brand;
  final bool online;
  final MediaTransport transport;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArt;
  final String? source;
  final int? volume;
  final bool? muted;
  final int? position;
  final int? duration;
  final List<MediaPreset> presets;
  final MediaGroupRole groupRole;
  final List<String> groupMemberIds;
  final String? groupCoordinatorId;
  final int? groupVolume;
  final String? currentUri;

  const MediaState({
    required this.deviceId,
    required this.brand,
    required this.online,
    required this.transport,
    this.title,
    this.artist,
    this.album,
    this.albumArt,
    this.source,
    this.volume,
    this.muted,
    this.position,
    this.duration,
    this.presets = const [],
    this.groupRole = MediaGroupRole.standalone,
    this.groupMemberIds = const [],
    this.groupCoordinatorId,
    this.groupVolume,
    this.currentUri,
  });

  /// Returns the best available artwork URL, resolving relative proxy paths.
  /// Falls back to a matching preset image when the track has no art
  /// (common for internet radio stations).
  ///
  /// Sonos `/getaa` URLs stay identical while the pixels change; append a
  /// cache-buster from the current track identity so [Image.network] reloads.
  String? get effectiveArt {
    final art = _resolveArtUrl(albumArt) ?? _presetFallbackArt;
    if (art == null || art.isEmpty) return null;
    if (!art.contains('getaa')) return art;
    final tag = '${title ?? ''}|${artist ?? ''}|${currentUri ?? ''}';
    final sep = art.contains('?') ? '&' : '?';
    return '$art${sep}v=${tag.hashCode}';
  }

  String? get _presetFallbackArt {
    if (presets.isEmpty) return null;
    final uri = currentUri ?? '';

    // 1. Exact URI match — works for TuneIn/Sonos API stations.
    for (final p in presets) {
      if (p.image == null) continue;
      if (p.uri != null && p.uri!.isNotEmpty && p.uri == uri) {
        return _resolveArtUrl(p.image);
      }
    }

    // 2. Source match — station name reported by Sonos (stationName field).
    //    E.g. source = "NPO Radio 2", preset.name = "NPO Radio 2".
    if (source != null && source!.isNotEmpty) {
      final sLower = source!.toLowerCase();
      for (final p in presets) {
        if (p.image == null) continue;
        if (p.name.isNotEmpty && sLower.contains(p.name.toLowerCase())) {
          return _resolveArtUrl(p.image);
        }
      }
    }

    // 3. Exact title match — ICY metadata sometimes *is* the station name.
    if (title != null && title!.isNotEmpty) {
      final tLower = title!.toLowerCase().trim();
      for (final p in presets) {
        if (p.image == null) continue;
        if (p.name.isNotEmpty && tLower == p.name.toLowerCase().trim()) {
          return _resolveArtUrl(p.image);
        }
      }
    }

    return null;
  }

  /// Turns a backend-relative proxy path like `/api/media-art?u=...`
  /// into an absolute URL using the configured API base.
  static String? _resolveArtUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('/')) return '$apiBase$url';
    return url;
  }

  factory MediaState.fromJson(Map<String, dynamic> j) => MediaState(
        deviceId: (j['deviceId'] as String?) ?? '',
        brand: MediaBrand.fromJson(j['brand'] as String?),
        online: (j['online'] as bool?) ?? false,
        transport: MediaTransport.fromJson(j['transport'] as String?),
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        album: j['album'] as String?,
        albumArt: j['albumArt'] as String?,
        source: j['source'] as String?,
        volume: (j['volume'] as num?)?.toInt(),
        muted: j['muted'] as bool?,
        position: (j['position'] as num?)?.toInt(),
        duration: (j['duration'] as num?)?.toInt(),
        presets: ((j['presets'] as List?) ?? const [])
            .map((e) => MediaPreset.fromJson(e as Map<String, dynamic>))
            .toList(),
        groupRole: MediaGroupRole.fromJson(j['groupRole'] as String?),
        groupMemberIds: ((j['groupMemberIds'] as List?) ?? const [])
            .cast<String>(),
        groupCoordinatorId: j['groupCoordinatorId'] as String?,
        groupVolume: (j['groupVolume'] as num?)?.toInt(),
        currentUri: j['currentUri'] as String?,
      );

  /// Offline placeholder shown while we wait for the first snapshot.
  factory MediaState.offline(String id) => MediaState(
        deviceId: id,
        brand: MediaBrand.sonos,
        online: false,
        transport: MediaTransport.stopped,
      );

  MediaState copyWith({int? volume, bool? muted, int? groupVolume}) => MediaState(
        deviceId: deviceId,
        brand: brand,
        online: online,
        transport: transport,
        title: title,
        artist: artist,
        album: album,
        albumArt: albumArt,
        source: source,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        position: position,
        duration: duration,
        presets: presets,
        groupRole: groupRole,
        groupMemberIds: groupMemberIds,
        groupCoordinatorId: groupCoordinatorId,
        groupVolume: groupVolume ?? this.groupVolume,
        currentUri: currentUri,
      );
}

/* --------------------------------------------------------------------- */
/*  Live state feed                                                      */
/* --------------------------------------------------------------------- */

/// A `Map<deviceId, MediaState>` that the websocket in `api.dart` keeps
/// up to date. Widgets watch this provider to react to now-playing pushes
/// without having to poll the backend themselves.
class MediaStateStore extends Notifier<Map<String, MediaState>> {
  static const _volumeHoldDuration = Duration(milliseconds: 1200);

  final Map<String, ({int volume, DateTime until})> _volumeHolds = {};

  @override
  Map<String, MediaState> build() => const {};

  void snapshot(List<MediaState> states) {
    state = {for (final s in states) s.deviceId: s};
  }

  void patchVolume(String deviceId, int volume) {
    final cur = state[deviceId];
    if (cur == null) return;
    final v = volume.clamp(0, 100);
    _volumeHolds[deviceId] = (
      volume: v,
      until: DateTime.now().add(_volumeHoldDuration),
    );
    final patched = cur.copyWith(volume: v);
    final next = {...state, deviceId: patched};
    _stampGroupVolume(next, deviceId);
    state = next;
  }

  void patchGroupVolumes(Map<String, int> volumes, int groupVolume) {
    if (volumes.isEmpty) return;
    final next = {...state};
    final until = DateTime.now().add(_volumeHoldDuration);
    for (final e in volumes.entries) {
      final cur = next[e.key];
      if (cur == null) continue;
      final v = e.value.clamp(0, 100);
      _volumeHolds[e.key] = (volume: v, until: until);
      next[e.key] = cur.copyWith(volume: v, groupVolume: groupVolume);
    }
    state = next;
  }

  void _stampGroupVolume(Map<String, MediaState> map, String deviceId) {
    final cur = map[deviceId];
    if (cur == null || !cur.groupRole.isGrouped) return;
    final ids = mediaGroupDeviceIds(cur, deviceId, map);
    var max = 0;
    for (final id in ids) {
      final v = map[id]?.volume ?? 0;
      if (v > max) max = v;
    }
    for (final id in ids) {
      final s = map[id];
      if (s == null || s.groupVolume == max) continue;
      map[id] = s.copyWith(groupVolume: max);
    }
  }

  void update(MediaState s) {
    final hold = _volumeHolds[s.deviceId];
    var next = s;
    if (hold != null) {
      if (DateTime.now().isBefore(hold.until)) {
        final incoming = s.volume;
        if (incoming != null && (incoming - hold.volume).abs() > 2) {
          next = s.copyWith(volume: hold.volume);
        } else {
          _volumeHolds.remove(s.deviceId);
        }
      } else {
        _volumeHolds.remove(s.deviceId);
      }
    }
    state = {...state, next.deviceId: next};
    final map = {...state};
    _stampGroupVolume(map, next.deviceId);
    state = map;
  }

  MediaState? get(String id) => state[id];
}

final mediaStateProvider =
    NotifierProvider<MediaStateStore, Map<String, MediaState>>(
  MediaStateStore.new,
);

/// Hydrates the state store once with an HTTP fetch. The WS push takes
/// over from there, but an initial REST call avoids the "flash of empty
/// tile" when a user navigates to a room before any state change has
/// been observed.
Future<void> primeMediaStates(Ref ref) async {
  final auth = ref.read(authProvider);
  if (!auth.isAuthed) return;
  try {
    final res = await http.get(
      Uri.parse('$apiBase/api/media'),
      headers: {'authorization': 'Bearer ${auth.token}'},
    );
    if (res.statusCode != 200) return;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = ((data['states'] as List?) ?? const [])
        .map((e) => MediaState.fromJson(e as Map<String, dynamic>))
        .toList();
    ref.read(mediaStateProvider.notifier).snapshot(list);
  } catch (_) {
    /* offline at boot is fine — WS will fill us in */
  }
}

/* --------------------------------------------------------------------- */
/*  Commands                                                             */
/* --------------------------------------------------------------------- */

final mediaApiProvider = Provider<MediaApi>((ref) => MediaApi(ref));

/// One playable hit returned by the search endpoint.
class MediaSearchResult {
  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String? image;
  final String playRef;

  const MediaSearchResult({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.image,
    required this.playRef,
  });

  factory MediaSearchResult.fromJson(Map<String, dynamic> j) => MediaSearchResult(
        id: j['id'] as String? ?? '',
        kind: j['kind'] as String? ?? 'track',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String?,
        image: j['image'] as String?,
        playRef: j['playRef'] as String? ?? '',
      );
}

/// A titled group of search results (e.g. "Favorieten", "Spotify").
class MediaSearchSection {
  final String title;
  final List<MediaSearchResult> results;

  const MediaSearchSection({required this.title, required this.results});

  factory MediaSearchSection.fromJson(Map<String, dynamic> j) => MediaSearchSection(
        title: j['title'] as String? ?? '',
        results: ((j['results'] as List?) ?? const [])
            .map((e) => MediaSearchResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Result of a media search: grouped sections plus a flag indicating the
/// Spotify link expired and the user should reconnect.
class MediaSearchResponse {
  final List<MediaSearchSection> sections;
  final bool needsSpotifyAuth;
  const MediaSearchResponse({
    required this.sections,
    this.needsSpotifyAuth = false,
  });
}

/// Spotify connection status for the household.
class SpotifyStatus {
  final bool configured;
  final bool connected;
  final String? account;
  /// Currently effective redirect URI (if any).
  final String? redirectUri;
  /// Suggested redirect URI to paste into the Spotify dashboard.
  final String? suggestedRedirectUri;
  /// HTTPS page to open once so the browser accepts the self-signed cert.
  final String? tlsCheckUrl;
  /// Public OAuth client id (never the secret), used to prefill the form.
  final String? clientId;
  const SpotifyStatus({
    required this.configured,
    required this.connected,
    this.account,
    this.redirectUri,
    this.suggestedRedirectUri,
    this.tlsCheckUrl,
    this.clientId,
  });

  factory SpotifyStatus.fromJson(Map<String, dynamic> j) => SpotifyStatus(
        configured: j['configured'] == true,
        connected: j['connected'] == true,
        account: j['account'] as String?,
        redirectUri: j['redirectUri'] as String?,
        suggestedRedirectUri: j['suggestedRedirectUri'] as String?,
        tlsCheckUrl: j['tlsCheckUrl'] as String?,
        clientId: j['clientId'] as String?,
      );
}

/// Spotify status. autoDispose so it is re-fetched whenever a screen that
/// needs it (player, settings) is reopened — this way connecting on one device
/// is reflected elsewhere without an app restart. Invalidate to refresh now.
final spotifyStatusProvider =
    FutureProvider.autoDispose<SpotifyStatus>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthed) {
    return const SpotifyStatus(configured: false, connected: false);
  }
  return ref.read(mediaApiProvider).spotifyStatus();
});

class MediaApi {
  MediaApi(this._ref);
  final Ref _ref;

  Future<void> _cmd(Map<String, dynamic> body) async {
    final bus = _ref.read(busProvider.notifier);
    await bus.send(body);
  }

  Future<void> play(String id) => _cmd({
        'kind': 'media.transport',
        'deviceId': id,
        'action': 'play',
      });

  Future<void> pause(String id) => _cmd({
        'kind': 'media.transport',
        'deviceId': id,
        'action': 'pause',
      });

  Future<void> stop(String id) => _cmd({
        'kind': 'media.transport',
        'deviceId': id,
        'action': 'stop',
      });

  Future<void> next(String id) => _cmd({
        'kind': 'media.transport',
        'deviceId': id,
        'action': 'next',
      });

  Future<void> previous(String id) => _cmd({
        'kind': 'media.transport',
        'deviceId': id,
        'action': 'previous',
      });

  Future<void> setVolume(String id, int percent) async {
    final v = percent.clamp(0, 100).round();
    _ref.read(mediaStateProvider.notifier).patchVolume(id, v);
    await _cmd({
        'kind': 'media.volume',
        'deviceId': id,
        'value': v,
      });
  }

  Future<void> setGroupVolume(String id, int percent) async {
    final target = percent.clamp(0, 100).round();
    final store = _ref.read(mediaStateProvider.notifier);
    final all = _ref.read(mediaStateProvider);
    final cur = all[id];
    if (cur != null && cur.groupRole.isGrouped) {
      final ids = mediaGroupDeviceIds(cur, id, all);
      final oldMax = ids.fold<int>(0, (m, gid) {
        final v = all[gid]?.volume ?? 0;
        return v > m ? v : m;
      });
      final next = <String, int>{};
      for (final gid in ids) {
        final vol = all[gid]?.volume ?? 0;
        if (oldMax <= 0) {
          next[gid] = target;
        } else if (vol == oldMax) {
          next[gid] = target;
        } else {
          next[gid] = ((vol * target) / oldMax).round().clamp(0, 100);
        }
      }
      store.patchGroupVolumes(next, target);
    } else {
      store.patchVolume(id, target);
    }
    await _cmd({
      'kind': 'media.group.volume',
      'deviceId': id,
      'value': target,
    });
  }

  Future<void> setMuted(String id, bool muted) => _cmd({
        'kind': 'media.mute',
        'deviceId': id,
        'muted': muted,
      });

  Future<void> playPreset(String id, MediaPreset preset) => _cmd({
        'kind': 'media.preset',
        'deviceId': id,
        'presetId': preset.id,
        if (preset.uri != null) 'uri': preset.uri,
      });

  /// Join the group of [coordinatorId] (this device becomes a follower).
  Future<void> groupJoin(String id, String coordinatorId) => _cmd({
        'kind': 'media.group.join',
        'deviceId': id,
        'coordinatorId': coordinatorId,
      });

  /// Leave the current group — device becomes standalone again.
  Future<void> groupLeave(String id) => _cmd({
        'kind': 'media.group.leave',
        'deviceId': id,
      });

  /// Search the services linked on [deviceId] (plus Spotify when connected).
  Future<MediaSearchResponse> searchMedia(
    String deviceId,
    String query,
  ) async {
    final auth = _ref.read(authProvider);
    final res = await http.post(
      Uri.parse('$apiBase/api/media/search'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode({'deviceId': deviceId, 'query': query}),
    );
    if (res.statusCode != 200) {
      throw Exception('Zoeken mislukt (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return MediaSearchResponse(
      sections: ((data['sections'] as List?) ?? const [])
          .map((e) => MediaSearchSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      needsSpotifyAuth: data['needsSpotifyAuth'] == true,
    );
  }

  /// Current Spotify connection status for this household.
  Future<SpotifyStatus> spotifyStatus() async {
    final auth = _ref.read(authProvider);
    final res = await http.get(
      Uri.parse('$apiBase/api/media/spotify/status'),
      headers: {'authorization': 'Bearer ${auth.token}'},
    );
    if (res.statusCode != 200) {
      return const SpotifyStatus(configured: false, connected: false);
    }
    return SpotifyStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Save the Spotify OAuth app credentials (entered in the app).
  Future<SpotifyStatus> spotifyConfigure({
    required String clientId,
    required String clientSecret,
    String? redirectUri,
  }) async {
    final auth = _ref.read(authProvider);
    final res = await http.post(
      Uri.parse('$apiBase/api/media/spotify/config'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode({
        'clientId': clientId,
        'clientSecret': clientSecret,
        if (redirectUri != null && redirectUri.isNotEmpty)
          'redirectUri': redirectUri,
      }),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] as String? ?? 'Opslaan mislukt');
    }
    return SpotifyStatus.fromJson(data);
  }

  /// Fetch the Spotify authorize URL to open in the browser.
  Future<String> spotifyLoginUrl() async {
    final auth = _ref.read(authProvider);
    final res = await http.get(
      Uri.parse('$apiBase/api/media/spotify/login'),
      headers: {'authorization': 'Bearer ${auth.token}'},
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] as String? ?? 'Spotify-login niet beschikbaar');
    }
    return data['url'] as String;
  }

  /// Complete OAuth by pasting the callback URL (when 127.0.0.1 is unreachable).
  Future<SpotifyStatus> spotifyFinish({required String callbackUrl}) async {
    final auth = _ref.read(authProvider);
    final res = await http.post(
      Uri.parse('$apiBase/api/media/spotify/finish'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${auth.token}',
      },
      body: jsonEncode({'url': callbackUrl}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] as String? ?? 'Verbinden mislukt');
    }
    return SpotifyStatus.fromJson(data);
  }

  /// Disconnect the Spotify account.
  Future<void> spotifyDisconnect() async {
    final auth = _ref.read(authProvider);
    await http.post(
      Uri.parse('$apiBase/api/media/spotify/disconnect'),
      headers: {'authorization': 'Bearer ${auth.token}'},
    );
  }

  /// Play a search result on [deviceId] (clears the queue and starts it).
  /// Uses the checked send so playback failures surface their reason.
  Future<void> playItem(String deviceId, MediaSearchResult item) =>
      _ref.read(busProvider.notifier).sendChecked({
        'kind': 'media.playItem',
        'deviceId': deviceId,
        'ref': item.playRef,
        if (item.title.isNotEmpty) 'title': item.title,
        if (item.image != null) 'image': item.image,
      });
}
