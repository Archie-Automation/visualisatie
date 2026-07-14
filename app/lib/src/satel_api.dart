/// Satel INTEGRA alarm integration — data models, polling provider, and
/// arm/disarm commands.
///
/// The Satel Python FastAPI service runs separately (default port 8001).
/// Set SATEL_BASE at build time to point to a different address:
///   flutter build web --dart-define=SATEL_BASE=https://myhome.local:8001
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart'; // authProvider

// ---------------------------------------------------------------------------
// Base URL
// ---------------------------------------------------------------------------

String get satelBase {
  if (kIsWeb && kReleaseMode) {
    final origin = Uri.base.origin;
    return origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  }
  return const String.fromEnvironment('SATEL_BASE',
      defaultValue: 'http://localhost:8001');
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SatelZone {
  const SatelZone({
    required this.zoneNumber,
    required this.name,
    required this.room,
    required this.roomId,
    required this.deviceType,
    required this.violated,
    this.bypassed = false,
  });

  final int zoneNumber;
  final String name;
  final String room;
  final String? roomId;
  final String deviceType;
  final bool violated;
  final bool bypassed;

  factory SatelZone.fromJson(Map<String, dynamic> j) => SatelZone(
        zoneNumber: (j['zone_number'] as num).toInt(),
        name: j['name'] as String,
        room: (j['room'] as String?) ?? '',
        roomId: j['room_id'] as String?,
        deviceType: j['device_type'] as String,
        violated: j['violated'] == true,
        bypassed: j['bypassed'] == true,
      );
}

/// Allowed Satel sensor device types (must match the Python DeviceType enum).
const satelDeviceTypes = <String>[
  'magneetcontact',
  'pir_beweging',
  'trilcontact',
  'glasbreuk',
  'rookmelder',
  'watermelder',
  'gasmelder',
  'paniekknop',
];

/// Human-readable label for a Satel device type (for dropdowns).
String satelDeviceTypeLabel(String type) => switch (type) {
      'magneetcontact' => 'Deur- / raamcontact',
      'pir_beweging'   => 'Bewegingsmelder',
      'trilcontact'    => 'Trilcontact',
      'glasbreuk'      => 'Glasbreukdetector',
      'rookmelder'     => 'Rookmelder',
      'watermelder'    => 'Watermelder',
      'gasmelder'      => 'Gasdetector',
      'paniekknop'     => 'Paniekknop',
      _                => type,
    };

/// Installer-configured mapping of a Satel zone to a sensor + room.
class SatelZoneMapping {
  const SatelZoneMapping({
    required this.zoneNumber,
    required this.name,
    required this.deviceType,
    this.roomId,
    this.roomName = '',
  });

  final int zoneNumber;
  final String name;
  final String deviceType;
  final String? roomId;
  final String roomName;

  SatelZoneMapping copyWith({
    int? zoneNumber,
    String? name,
    String? deviceType,
    String? roomId,
    String? roomName,
    bool clearRoom = false,
  }) =>
      SatelZoneMapping(
        zoneNumber: zoneNumber ?? this.zoneNumber,
        name: name ?? this.name,
        deviceType: deviceType ?? this.deviceType,
        roomId: clearRoom ? null : (roomId ?? this.roomId),
        roomName: clearRoom ? '' : (roomName ?? this.roomName),
      );

  factory SatelZoneMapping.fromJson(Map<String, dynamic> j) => SatelZoneMapping(
        zoneNumber: (j['zone_number'] as num).toInt(),
        name: j['name'] as String? ?? '',
        deviceType: j['device_type'] as String? ?? 'magneetcontact',
        roomId: j['room_id'] as String?,
        roomName: j['room'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'zone_number': zoneNumber,
        'name': name,
        'room': roomName,
        'room_id': roomId,
        'device_type': deviceType,
      };
}

class SatelRoom {
  const SatelRoom({
    required this.room,
    required this.violated,
    required this.sensors,
  });

  final String room;
  final bool violated;
  final List<SatelZone> sensors;

  factory SatelRoom.fromJson(Map<String, dynamic> j) => SatelRoom(
        room: j['room'] as String,
        violated: j['violated'] == true,
        sensors: ((j['sensors'] as List?) ?? [])
            .map((e) => SatelZone.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Partition states returned by the Python backend.
enum SatelPartitionState {
  disarmed,
  armed,
  exitDelay,
  entryDelay;

  static SatelPartitionState parse(String? s) => switch (s) {
        'Armed'       => SatelPartitionState.armed,
        'Exit_Delay'  => SatelPartitionState.exitDelay,
        'Entry_Delay' => SatelPartitionState.entryDelay,
        _             => SatelPartitionState.disarmed,
      };
}

/// State of a single INTEGRA partition.
class SatelPartitionInfo {
  const SatelPartitionInfo({
    required this.number,
    required this.name,
    required this.state,
  });

  final int number;
  final String name;
  final SatelPartitionState state;

  bool get isDisarmed   => state == SatelPartitionState.disarmed;
  bool get isArmed      => state == SatelPartitionState.armed;
  bool get isEntryDelay => state == SatelPartitionState.entryDelay;
  bool get isExitDelay  => state == SatelPartitionState.exitDelay;

  factory SatelPartitionInfo.fromJson(Map<String, dynamic> j) =>
      SatelPartitionInfo(
        number: (j['number'] as num).toInt(),
        name:   j['name'] as String,
        state:  SatelPartitionState.parse(j['state'] as String?),
      );
}

/// A single arm mode (Satel mode 0-3) with an installer-chosen label.
class SatelArmMode {
  const SatelArmMode({required this.mode, required this.name});
  final int mode;
  final String name;

  factory SatelArmMode.fromJson(Map<String, dynamic> j) => SatelArmMode(
        mode: (j['mode'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? 'Volledig',
      );

  Map<String, dynamic> toJson() => {'mode': mode, 'name': name};
}

/// Partition definition used by the Satel service config.
class SatelPartitionConfig {
  const SatelPartitionConfig({
    required this.number,
    required this.name,
    this.armModes = const [SatelArmMode(mode: 0, name: 'Volledig')],
  });
  final int number;
  final String name;
  final List<SatelArmMode> armModes;

  SatelPartitionConfig copyWith({
    int? number,
    String? name,
    List<SatelArmMode>? armModes,
  }) =>
      SatelPartitionConfig(
        number: number ?? this.number,
        name: name ?? this.name,
        armModes: armModes ?? this.armModes,
      );

  factory SatelPartitionConfig.fromJson(Map<String, dynamic> j) {
    final modes = ((j['arm_modes'] as List?) ?? [])
        .map((e) => SatelArmMode.fromJson((e as Map).cast()))
        .toList();
    return SatelPartitionConfig(
      number: (j['number'] as num).toInt(),
      name:   j['name'] as String,
      armModes: modes.isEmpty
          ? const [SatelArmMode(mode: 0, name: 'Volledig')]
          : modes,
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'name': name,
        'arm_modes': armModes.map((m) => m.toJson()).toList(),
      };
}

/// Result of GET /satel/config — includes has_pin flag (actual PIN never returned).
class SatelServiceConfig {
  const SatelServiceConfig({
    required this.host,
    required this.port,
    required this.partitions,
    required this.hasPin,
    this.hasEncryption = false,
    this.zoneMappings = const [],
  });

  final String host;
  final int port;
  final List<SatelPartitionConfig> partitions;
  final bool hasPin;
  final bool hasEncryption;
  final List<SatelZoneMapping> zoneMappings;

  factory SatelServiceConfig.fromJson(Map<String, dynamic> j) =>
      SatelServiceConfig(
        host:       j['host'] as String? ?? '',
        port:       (j['port'] as num?)?.toInt() ?? 7094,
        partitions: ((j['partitions'] as List?) ?? [])
            .map((e) => SatelPartitionConfig.fromJson((e as Map).cast()))
            .toList(),
        hasPin:     j['has_pin'] as bool? ?? false,
        hasEncryption: j['has_encryption'] as bool? ?? false,
        zoneMappings: ((j['zone_mapping'] as List?) ?? [])
            .map((e) => SatelZoneMapping.fromJson((e as Map).cast()))
            .toList(),
      );
}

class SatelStatus {
  const SatelStatus({
    required this.connected,
    required this.partitions,
    required this.rooms,
    required this.allZones,
  });

  final bool connected;
  final List<SatelPartitionInfo> partitions;
  final List<SatelRoom> rooms;
  final List<SatelZone> allZones;

  /// Worst state across all partitions (for the dashboard chip animation).
  SatelPartitionState get worstState {
    SatelPartitionState w = SatelPartitionState.disarmed;
    for (final p in partitions) {
      if (p.state == SatelPartitionState.entryDelay) return SatelPartitionState.entryDelay;
      if (p.state == SatelPartitionState.armed      && w != SatelPartitionState.entryDelay) w = SatelPartitionState.armed;
      if (p.state == SatelPartitionState.exitDelay  && w == SatelPartitionState.disarmed)   w = SatelPartitionState.exitDelay;
    }
    return w;
  }

  // Convenience getters derived from worstState.
  bool get isEntryDelay => worstState == SatelPartitionState.entryDelay;
  bool get isExitDelay  => worstState == SatelPartitionState.exitDelay;
  bool get isArmed      => worstState == SatelPartitionState.armed;
  bool get isDisarmed   => worstState == SatelPartitionState.disarmed;

  /// Zones coupled to a room, matched on the stable app room id.
  List<SatelZone> zonesForRoomId(String roomId) =>
      allZones.where((z) => z.roomId == roomId).toList();

  factory SatelStatus.fromJson(Map<String, dynamic> j) => SatelStatus(
        connected: j['connected'] == true,
        partitions: ((j['partitions'] as List?) ?? [])
            .map((e) => SatelPartitionInfo.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
        rooms: ((j['rooms'] as List?) ?? [])
            .map((e) => SatelRoom.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        allZones: ((j['all_zones'] as List?) ?? [])
            .map((e) => SatelZone.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// Empty placeholder used before the first successful poll.
  static const empty = SatelStatus(
    connected: false,
    partitions: [],
    rooms: [],
    allZones: [],
  );
}

// ---------------------------------------------------------------------------
// Main-backend satel config (enabled + partitions) — server-side, all devices
// ---------------------------------------------------------------------------

class _SatelMainConfig {
  const _SatelMainConfig({required this.enabled, required this.partitions});
  final bool enabled;
  final List<SatelPartitionConfig> partitions;

  factory _SatelMainConfig.fromJson(Map<String, dynamic> j) => _SatelMainConfig(
        enabled: j['enabled'] as bool? ?? false,
        partitions: ((j['partitions'] as List?) ?? [])
            .map((e) => SatelPartitionConfig.fromJson((e as Map).cast()))
            .toList(),
      );
}

/// Fetches satel config (enabled + partitions) from the MAIN backend.
/// Public endpoint — no auth required.
final satelMainConfigProvider = FutureProvider<_SatelMainConfig>((ref) async {
  try {
    final res = await http
        .get(Uri.parse('$apiBase/api/satel-config'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      return _SatelMainConfig.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
  } catch (_) {}
  return const _SatelMainConfig(enabled: false, partitions: []);
});

Future<void> _patchSatelMainConfig({
  bool? enabled,
  List<SatelPartitionConfig>? partitions,
  String? token,
}) async {
  try {
    final headers = <String, String>{'content-type': 'application/json'};
    if (token != null) headers['authorization'] = 'Bearer $token';
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (partitions != null) {
      // house.json only stores number + name; arm modes live in the Satel service.
      body['partitions'] =
          partitions.map((p) => {'number': p.number, 'name': p.name}).toList();
    }
    await http
        .post(Uri.parse('$apiBase/api/satel-config'),
            headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 6));
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Enable/disable toggle (persisted in SharedPreferences)
// ---------------------------------------------------------------------------

/// Whether the Satel integration is enabled.
/// Reads from the main backend (house.json) so all devices share the same setting.
final satelEnabledProvider =
    AsyncNotifierProvider<SatelEnabledNotifier, bool>(SatelEnabledNotifier.new);

class SatelEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // Fetch from server on first load — no watch dependency to avoid reset loops.
    try {
      final res = await http
          .get(Uri.parse('$apiBase/api/satel-config'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['enabled'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> setEnabled(bool value) async {
    // Optimistic update — UI reacts instantly.
    state = AsyncValue.data(value);
    // Persist to backend and refresh the shared config cache.
    await _patchSatelMainConfig(
        enabled: value, token: ref.read(authProvider).token);
    ref.invalidate(satelMainConfigProvider);
    // Keep optimistic state — do NOT call invalidateSelf() to avoid reset.
  }
}

// ---------------------------------------------------------------------------
// Status provider — never loading, always holds the last known value.
// ---------------------------------------------------------------------------

/// Live [SatelStatus]. Unlike a StreamProvider this never enters a "loading"
/// state: toggling enabled updates the value synchronously so the UI reacts
/// immediately. Polls the Satel service while the integration is enabled.
final satelStatusProvider =
    NotifierProvider<_SatelStatusNotifier, SatelStatus>(
        _SatelStatusNotifier.new);

class _SatelStatusNotifier extends Notifier<SatelStatus> {
  Timer? _pollTimer;

  @override
  SatelStatus build() {
    final enabled = ref.watch(satelEnabledProvider).value ?? false;
    final token   = ref.watch(authProvider).token;

    // Cancel any running poll immediately (before deciding whether to restart).
    _pollTimer?.cancel();
    _pollTimer = null;
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });

    // ── Disabled: stop polling. ──────────────────────────────────────────
    if (!enabled) return SatelStatus.empty;

    // ── Live: start periodic polling. ───────────────────────────────────
    _poll(token);
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _poll(token),
    );

    // Return last known value so there is no loading-flash on rebuild.
    try {
      return state;
    } catch (_) {
      return SatelStatus.empty; // first call: state not yet set
    }
  }

  Future<void> _poll(String? token) async {
    try {
      final headers = <String, String>{};
      if (token != null) headers['authorization'] = 'Bearer $token';
      final res = await http
          .get(Uri.parse('$satelBase/satel/status'), headers: headers)
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        state = SatelStatus.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {
      // Keep last good value on transient errors.
    }
  }
}

// ---------------------------------------------------------------------------
// Arm / Disarm commands
// ---------------------------------------------------------------------------

/// [pin] is the user's arm/disarm code entered on screen.
/// If omitted, the backend falls back to the server-side stored PIN.
Future<({bool ok, String? error})> satelArm(
    int partition, {int mode = 0, String? pin, String? token}) async {
  return _satelAction('/satel/arm', partition,
      mode: mode, pin: pin, token: token);
}

Future<({bool ok, String? error})> satelDisarm(
    int partition, {String? pin, String? token}) async {
  return _satelAction('/satel/disarm', partition, pin: pin, token: token);
}

Future<({bool ok, String? error})> _satelAction(
  String path,
  int partition, {
  int? mode,
  String? pin,
  String? token,
}) async {
  try {
    final headers = <String, String>{'content-type': 'application/json'};
    if (token != null) headers['authorization'] = 'Bearer $token';
    final body = <String, dynamic>{'partition': partition};
    if (mode != null) body['mode'] = mode;
    if (pin != null && pin.isNotEmpty) body['pin'] = pin;
    final res = await http
        .post(
          Uri.parse('$satelBase$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 204) return (ok: true, error: null);
    final resBody = res.body;
    final msg = resBody.isNotEmpty
        ? ((jsonDecode(resBody) as Map<String, dynamic>)['detail'] as String?)
        : null;
    return (ok: false, error: msg ?? 'HTTP ${res.statusCode}');
  } catch (e) {
    return (ok: false, error: e.toString());
  }
}

/// Bypass (or unbypass) one or more zones on the panel.
Future<({bool ok, String? error})> satelBypass(
    List<int> zones, {required bool bypass, String? pin, String? token}) async {
  try {
    final headers = <String, String>{'content-type': 'application/json'};
    if (token != null) headers['authorization'] = 'Bearer $token';
    final body = <String, dynamic>{'zones': zones, 'bypass': bypass};
    if (pin != null && pin.isNotEmpty) body['pin'] = pin;
    final res = await http
        .post(
          Uri.parse('$satelBase/satel/bypass'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 204) return (ok: true, error: null);
    final resBody = res.body;
    final msg = resBody.isNotEmpty
        ? ((jsonDecode(resBody) as Map<String, dynamic>)['detail'] as String?)
        : null;
    return (ok: false, error: msg ?? 'HTTP ${res.statusCode}');
  } catch (e) {
    return (ok: false, error: e.toString());
  }
}

// ---------------------------------------------------------------------------
// Service config provider (/satel/config)
// ---------------------------------------------------------------------------

const _kCachedPartitionsKey = 'satel_partitions_v1';

/// Fetches partition list + has_pin flag.
/// Priority: (1) Satel Python service  (2) main backend house.json  (3) local cache.
final satelServiceConfigProvider =
    FutureProvider<SatelServiceConfig?>((ref) async {
  // Always load main-backend partitions — these are shared across all devices.
  final mainCfg = await ref.watch(satelMainConfigProvider.future);

  try {
    // Try the Satel Python service for live has_pin + host info.
    final res = await http
        .get(Uri.parse('$satelBase/satel/config'))
        .timeout(const Duration(seconds: 3));
    if (res.statusCode == 200) {
      final cfg = SatelServiceConfig.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
      // Merge: use main-backend partitions when Python service has none.
      final parts = cfg.partitions.isNotEmpty
          ? cfg.partitions
          : mainCfg.partitions;
      return SatelServiceConfig(
        host: cfg.host,
        port: cfg.port,
        partitions: parts,
        hasPin: cfg.hasPin,
      );
    }
  } catch (_) {}

  // Satel Python service offline — return main-backend config.
  if (mainCfg.partitions.isNotEmpty) {
    return SatelServiceConfig(
      host: '', port: 7094,
      partitions: mainCfg.partitions,
      hasPin: false,
    );
  }

  // Final fallback: device-local cache (legacy).
  return await _loadCachedConfig();
});

/// Load the last-known partition list from SharedPreferences.
Future<SatelServiceConfig?> _loadCachedConfig() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kCachedPartitionsKey);
    if (raw == null) return null;
    final parts = (jsonDecode(raw) as List)
        .map((e) => SatelPartitionConfig.fromJson((e as Map).cast()))
        .toList();
    return SatelServiceConfig(
      host: '', port: 7094, partitions: parts, hasPin: false);
  } catch (_) {
    return null;
  }
}


/// Save updated partition list to BOTH the main backend (house.json) AND
/// optionally the Satel Python service. Main backend is source of truth for all devices.
Future<({bool ok, String? error})> saveSatelPartitions(
    List<SatelPartitionConfig> partitions, {String? token}) async {
  // 1. Save to main backend — this is shared across all devices.
  await _patchSatelMainConfig(partitions: partitions, token: token);

  // 2. Also try the Satel Python service (best-effort, may not be running).
  try {
    await http
        .post(
          Uri.parse('$satelBase/satel/config'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'host': 'keep',
            'partitions': partitions.map((p) => p.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 4));
  } catch (_) {}

  return (ok: true, error: null);
}

/// Save the zone → sensor → room mapping to the Satel service.
/// Sends `host: 'keep'` so the service preserves host/partitions/PIN.
Future<({bool ok, String? error})> saveSatelZones(
    List<SatelZoneMapping> zones) async {
  try {
    final res = await http
        .post(
          Uri.parse('$satelBase/satel/config'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'host': 'keep',
            'zone_mapping': zones.map((z) => z.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 204) return (ok: true, error: null);
    final body = res.body;
    final msg = body.isNotEmpty
        ? ((jsonDecode(body) as Map<String, dynamic>)['detail'] as String?)
        : null;
    return (ok: false, error: msg ?? 'HTTP ${res.statusCode}');
  } catch (e) {
    return (ok: false, error: e.toString());
  }
}

/// Set or clear the AES integration key on the Satel service.
/// Pass an empty string to disable encryption (plain-text connection).
/// The key is write-only: the server never returns it via the API.
Future<({bool ok, String? error})> saveSatelEncryptionKey(String key) async {
  try {
    final res = await http
        .post(
          Uri.parse('$satelBase/satel/config'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'host': 'keep', 'integration_key': key}),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 204) return (ok: true, error: null);
    final body = res.body;
    final msg = body.isNotEmpty
        ? ((jsonDecode(body) as Map<String, dynamic>)['detail'] as String?)
        : null;
    return (ok: false, error: msg ?? 'HTTP ${res.statusCode}');
  } catch (e) {
    return (ok: false, error: e.toString());
  }
}

/// Set or overwrite the stored arm/disarm PIN on the server.
/// The PIN is write-only: the server never returns it via the API.
Future<({bool ok, String? error})> saveSatelPin(String pin) async {
  try {
    final res = await http
        .post(
          Uri.parse('$satelBase/satel/pin'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'pin': pin}),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 204) return (ok: true, error: null);
    final body = res.body;
    final msg = body.isNotEmpty
        ? ((jsonDecode(body) as Map<String, dynamic>)['detail'] as String?)
        : null;
    return (ok: false, error: msg ?? 'HTTP ${res.statusCode}');
  } catch (e) {
    return (ok: false, error: e.toString());
  }
}

