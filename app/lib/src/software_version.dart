import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// App version embedded at build time via --dart-define=APP_VERSION=x.y.z+N.
const kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

class SoftwareVersionInfo {
  const SoftwareVersionInfo({
    required this.version,
    required this.semver,
    required this.build,
  });

  final String version;
  final String semver;
  final int? build;

  factory SoftwareVersionInfo.parse(String raw) {
    final v = raw.trim().isEmpty ? '0.0.0' : raw.trim();
    final plus = v.indexOf('+');
    if (plus < 0) {
      return SoftwareVersionInfo(version: v, semver: v, build: null);
    }
    final semver = v.substring(0, plus);
    final buildRaw = v.substring(plus + 1);
    final build = int.tryParse(buildRaw);
    return SoftwareVersionInfo(version: v, semver: semver, build: build);
  }

  factory SoftwareVersionInfo.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] as String?)?.trim() ?? '0.0.0';
    final parsed = SoftwareVersionInfo.parse(version);
    final build =
        j['build'] is num ? (j['build'] as num).toInt() : parsed.build;
    final semver = (j['semver'] as String?)?.trim() ?? parsed.semver;
    return SoftwareVersionInfo(
      version: version,
      semver: semver,
      build: build,
    );
  }

  /// Positive if [other] is newer than this.
  int compareTo(SoftwareVersionInfo other) {
    final a = _semverParts(semver);
    final b = _semverParts(other.semver);
    for (var i = 0; i < 3; i++) {
      final d = a[i].compareTo(b[i]);
      if (d != 0) return d;
    }
    final ab = build ?? 0;
    final bb = other.build ?? 0;
    return ab.compareTo(bb);
  }

  static List<int> _semverParts(String s) {
    final bits = s.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < bits.length ? (int.tryParse(bits[i]) ?? 0) : 0,
    ];
  }
}

class GithubLatestInfo {
  const GithubLatestInfo({
    required this.version,
    required this.semver,
    required this.build,
    required this.tag,
    required this.htmlUrl,
  });

  final String version;
  final String semver;
  final int? build;
  final String tag;
  final String? htmlUrl;

  SoftwareVersionInfo get asVersion => SoftwareVersionInfo(
        version: version,
        semver: semver,
        build: build,
      );

  factory GithubLatestInfo.fromJson(Map<String, dynamic> j) {
    final base = SoftwareVersionInfo.fromJson(j);
    return GithubLatestInfo(
      version: base.version,
      semver: base.semver,
      build: base.build,
      tag: (j['tag'] as String?)?.trim() ?? base.version,
      htmlUrl: (j['htmlUrl'] as String?)?.trim(),
    );
  }
}

/// Full payload from GET /api/version.
class SoftwareVersionStatus {
  const SoftwareVersionStatus({
    required this.running,
    required this.latest,
    required this.updateAvailable,
    required this.clientStale,
  });

  final SoftwareVersionInfo running;
  final GithubLatestInfo? latest;
  final bool updateAvailable;
  /// Client build older than what this server is serving (stale PWA cache).
  final bool clientStale;
}

/// Server software version status (null while loading / on error).
final softwareVersionStatusProvider =
    FutureProvider.autoDispose<SoftwareVersionStatus?>((ref) async {
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), link.close);
  try {
    final res = await http
        .get(Uri.parse('$apiBase/api/version'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    final running = SoftwareVersionInfo.fromJson(body);
    GithubLatestInfo? latest;
    final rawLatest = body['latest'];
    if (rawLatest is Map<String, dynamic>) {
      latest = GithubLatestInfo.fromJson(rawLatest);
    }
    final updateAvailable = body['updateAvailable'] == true;
    final client = SoftwareVersionInfo.parse(kAppVersion);
    final clientStale =
        kAppVersion != 'dev' && client.compareTo(running) < 0;
    return SoftwareVersionStatus(
      running: running,
      latest: latest,
      updateAvailable: updateAvailable,
      clientStale: clientStale,
    );
  } catch (_) {
    return null;
  }
});

/// @deprecated Prefer [softwareVersionStatusProvider].
final serverVersionProvider =
    FutureProvider.autoDispose<SoftwareVersionInfo?>((ref) async {
  final s = await ref.watch(softwareVersionStatusProvider.future);
  return s?.running;
});

/// True when the user should see an update banner (stale PWA or newer on GitHub).
final softwareUpdateAvailableProvider = Provider.autoDispose<bool>((ref) {
  final async = ref.watch(softwareVersionStatusProvider);
  final s = async.asData?.value;
  if (s == null) return false;
  return s.clientStale || s.updateAvailable;
});

Future<void> openReleasePage(String? htmlUrl) async {
  if (htmlUrl == null || htmlUrl.isEmpty) return;
  final uri = Uri.tryParse(htmlUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
