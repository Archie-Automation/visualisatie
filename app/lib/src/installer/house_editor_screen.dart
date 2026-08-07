import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../ac_mode_config.dart';
import '../api.dart';
import '../fireplace_step_ranges.dart';
import '../models.dart';
import '../satel_api.dart'
    show
        SatelArmMode,
        SatelPartitionConfig,
        SatelPartitionInfo,
        SatelPartitionState,
        SatelStatus,
        SatelZoneMapping,
        satelDeviceTypes,
        satelDeviceTypeLabel,
        satelEnabledProvider,
        satelMainConfigProvider,
        satelServiceConfigProvider,
        SatelServiceConfig,
        satelStatusProvider,
        saveSatelPartitions,
        saveSatelZones,
        saveSatelEncryptionKey,
        saveSatelPin;
import '../shading_subtype_glyph.dart';
import '../theme.dart';
import '../ui/widgets/admin_full_restart_card.dart';
import 'installer_api.dart';
import 'installer_auth.dart';
import 'installer_form_sections.dart';
import 'knx_ga_catalog.dart';

const _deviceTypesKnx = [
  'light_switch',
  'light_dimmer',
  'rgbw_ww',
  'shading',
  'position_actuator',
  'climate',
  'fireplace',
  'ac',
  'fan',
  'universal',
  'wtw',
  'melding',
];

const _deviceTypesAudio = [
  'media_sonos',
  'media_bluesound',
];

const _deviceTypesLutron = [
  'light_switch',
  'light_dimmer',
  'shading',
  'lutron_homeworks',
];

enum DeviceBusCategory { knx, lutron, audio }

const _deviceBusCategoryLabels = <DeviceBusCategory, String>{
  DeviceBusCategory.knx: 'KNX',
  DeviceBusCategory.lutron: 'Lutron',
  DeviceBusCategory.audio: 'Audio',
};

const _deviceBusCategoryHints = <DeviceBusCategory, String>{
  DeviceBusCategory.knx:
      'Licht, zonwering, klimaat, haard, knoppaneel, ?',
  DeviceBusCategory.lutron:
      'Lampen, gordijnen/jaloezie?n en keypad ? KNX',
  DeviceBusCategory.audio: 'Sonos en Bluesound in een kamer',
};

List<String> _deviceTypesForBus(DeviceBusCategory bus) {
  switch (bus) {
    case DeviceBusCategory.knx:
      return _deviceTypesKnx;
    case DeviceBusCategory.lutron:
      return _deviceTypesLutron;
    case DeviceBusCategory.audio:
      return _deviceTypesAudio;
  }
}

IconData _deviceBusCategoryIcon(DeviceBusCategory bus) {
  switch (bus) {
    case DeviceBusCategory.knx:
      return Icons.settings_input_component_outlined;
    case DeviceBusCategory.lutron:
      return Icons.lightbulb_outline;
    case DeviceBusCategory.audio:
      return Icons.speaker_outlined;
  }
}

/// Gekozen apparaattype + bus (voor standaard KNX- of Lutron-config).
class DeviceTypePick {
  const DeviceTypePick({required this.type, required this.bus});
  final String type;
  final DeviceBusCategory bus;
}

String _deviceTypeLabel(String dt, DeviceBusCategory bus) {
  if (bus == DeviceBusCategory.lutron) {
    switch (dt) {
      case 'light_switch':
        return 'Lamp / schakelcontact (aan/uit)';
      case 'light_dimmer':
        return 'Dimbare lamp';
      case 'shading':
        return 'Gordijn / jaloezie';
      case 'lutron_homeworks':
        return 'Keypad ? KNX (QSX/QS)';
    }
  }
  return _deviceTypeLabels[dt] ?? dt;
}

/// Twee stappen: eerst KNX / Lutron / Audio, daarna alleen passende types.
Future<DeviceTypePick?> showPickDeviceTypeSheet(BuildContext context) {
  return showModalBottomSheet<DeviceTypePick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _DeviceTypePickerSheet(),
  );
}

const _deviceTypeLabels = <String, String>{
  'light_switch': 'Licht (aan/uit)',
  'light_dimmer': 'Licht (dimmen)',
  'rgbw_ww': 'RGB / W / WW (KNX)',
  'shading': 'Zonwering / gordijn',
  'position_actuator': 'Positie-aansturing (klep / raam)',
  'climate': 'Thermostaat / klimaat',
  'media_sonos': 'Sonos',
  'media_bluesound': 'Bluesound',
  'camera': 'Camera (RTSP, IP)',
  'intercom': 'Intercom / deurbel',
  'fireplace': 'Haard',
  'ac': 'Airco',
  'fan': 'Ventilator',
  'universal': 'Universeel knoppaneel',
  'wtw': 'WTW / HRV ventilatie',
  'melding': 'Meldingen / Alarmen monitor',
  'lutron_homeworks': 'Lutron Homeworks ? KNX',
};

class _DeviceTypePickerSheet extends StatefulWidget {
  const _DeviceTypePickerSheet();

  @override
  State<_DeviceTypePickerSheet> createState() => _DeviceTypePickerSheetState();
}

class _DeviceTypePickerSheetState extends State<_DeviceTypePickerSheet> {
  DeviceBusCategory? _bus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (_bus == null) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Welke bus?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final bus in DeviceBusCategory.values)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Icon(_deviceBusCategoryIcon(bus)),
                title: Text(_deviceBusCategoryLabels[bus]!),
                subtitle: Text(
                  _deviceBusCategoryHints[bus]!,
                  style: theme.textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _bus = bus),
              ),
            SizedBox(height: 8 + bottom),
          ],
        ),
      );
    }

    final types = _deviceTypesForBus(_bus!);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _bus = null),
            ),
            title: Text(
              _deviceBusCategoryLabels[_bus!]!,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(
              'Kies apparaattype',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final dt in types)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(_deviceTypeLabel(dt, _bus!)),
              onTap: () => Navigator.pop(
                context,
                DeviceTypePick(type: dt, bus: _bus!),
              ),
            ),
          SizedBox(height: 8 + bottom),
        ],
      ),
    );
  }
}

/// Verwijzing naar een apparaat in [floors ? rooms ? devices] (installateur).
class _RoomDevRef {
  const _RoomDevRef({
    required this.fi,
    required this.ri,
    required this.di,
    required this.dev,
    required this.location,
  });
  final int fi;
  final int ri;
  final int di;
  final Map<String, dynamic> dev;
  final String location;
}

bool _deviceHasKnxGa(Map<String, dynamic> device) {
  final ga = device['ga'];
  if (ga is! Map) return false;
  for (final v in ga.values) {
    if (v != null && v.toString().trim().isNotEmpty) return true;
  }
  return false;
}

/// Diepe kopie van apparaat-JSON met nieuwe id(s) voor plakken in config.
Map<String, dynamic> _cloneDeviceJson(Map<String, dynamic> source, Uuid uuid) {
  final clone = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
  );

  String freshNestedId(String old) {
    if (RegExp(r'^\d+/\d+/\d+').hasMatch(old)) return old;
    final dash = old.indexOf('-');
    if (dash > 0) return '${old.substring(0, dash + 1)}${uuid.v4()}';
    return 'dev-${uuid.v4()}';
  }

  void walk(dynamic node, {required bool root}) {
    if (node is Map) {
      final map = node.cast<String, dynamic>();
      final id = map['id'];
      if (id is String && id.isNotEmpty) {
        map['id'] = root ? 'dev-${uuid.v4()}' : freshNestedId(id);
      }
      if (root) {
        final name = map['name'];
        if (name is String && name.isNotEmpty && !name.contains('(kopie)')) {
          map['name'] = '$name (kopie)';
        }
      }
      for (final v in map.values) {
        walk(v, root: false);
      }
    } else if (node is List) {
      for (final v in node) {
        walk(v, root: false);
      }
    }
  }

  walk(clone, root: true);
  return clone;
}

Map<String, dynamic> _ensureChildMap(Map<String, dynamic> parent, String key) {
  final x = parent[key];
  if (x is Map<String, dynamic>) return x;
  final m = <String, dynamic>{};
  parent[key] = m;
  return m;
}

enum _FocusKind {
  project,
  knx,
  lutron,
  cameras,
  cameraDetail,
  audio,
  intercoms,
  intercomDetail,
  users,
  user,
  logs,
  satel,
  floor,
  room,
  device,
  /// A device that is NOT placed in any room.
  globalDevice,
}

/// Payload carried during a device drag in the installer tree.
class _DeviceDragData {
  const _DeviceDragData({
    required this.device,
    required this.fi,
    required this.ri,
    required this.di,
  });
  /// The device JSON map being dragged.
  final Map<String, dynamic> device;
  /// Source floor index; -1 means the global (room-less) list.
  final int fi;
  /// Source room index; -1 for global devices.
  final int ri;
  /// Source device index within the source list.
  final int di;

  bool get isGlobal => fi < 0;
}

class _Focus {
  const _Focus.project()
      : kind = _FocusKind.project,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.knx()
      : kind = _FocusKind.knx,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.lutron()
      : kind = _FocusKind.lutron,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.cameras()
      : kind = _FocusKind.cameras,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.cameraDetail(int index)
      : kind = _FocusKind.cameraDetail,
        fi = -1,
        ri = -1,
        di = -1,
        ci = index;
  const _Focus.audio()
      : kind = _FocusKind.audio,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.intercoms()
      : kind = _FocusKind.intercoms,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.intercomDetail(int index)
      : kind = _FocusKind.intercomDetail,
        fi = -1,
        ri = -1,
        di = -1,
        ci = index;
  const _Focus.users()
      : kind = _FocusKind.users,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.logs()
      : kind = _FocusKind.logs,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.satel()
      : kind = _FocusKind.satel,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.user(this.fi)
      : kind = _FocusKind.user,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.floor(this.fi)
      : kind = _FocusKind.floor,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.room(this.fi, this.ri)
      : kind = _FocusKind.room,
        di = -1,
        ci = null;
  const _Focus.device(this.fi, this.ri, this.di)
      : kind = _FocusKind.device,
        ci = null;
  const _Focus.globalDevice(this.di)
      : kind = _FocusKind.globalDevice,
        fi = -1,
        ri = -1,
        ci = null;

  final _FocusKind kind;
  final int fi;
  final int ri;
  final int di;
  final int? ci;
}

class HouseEditorScreen extends ConsumerStatefulWidget {
  /// When true, uses [authProvider] (customer app admin session). When false,
  /// uses [installerAuthProvider] (standalone installateur-app).
  const HouseEditorScreen({
    super.key,
    this.useCustomerSession = false,
  });

  final bool useCustomerSession;

  @override
  ConsumerState<HouseEditorScreen> createState() => _HouseEditorScreenState();
}

class _HouseEditorScreenState extends ConsumerState<HouseEditorScreen> {
  static const _uuid = Uuid();
  Map<String, dynamic>? _house;
  /// `${fi}-${ri}` when that room [ExpansionTile] is expanded (edit icon in title).
  final Set<String> _expandedRoomKeys = {};
  _Focus _sel = const _Focus.project();
  Map<String, dynamic>? _copiedDevice;
  /// Whether the mobile detail panel is in view (vs. the menu list).
  bool _mobileShowDetail = false;
  bool _loading = true;
  bool _saving = false;
  bool _knxSyncExisting = false;
  String? _loadErr;
  ProviderSubscription<AuthState>? _customerAuthSub;

  void _selectFocus(_Focus focus) {
    setState(() {
      _sel = focus;
      if (MediaQuery.sizeOf(context).width < 900) {
        _mobileShowDetail = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.useCustomerSession) {
      _customerAuthSub = ref.listenManual<AuthState>(authProvider, (prev, next) {
        _onCustomerAuth(next);
      });
      _onCustomerAuth(ref.read(authProvider));
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _customerAuthSub?.close();
    super.dispose();
  }

  void _onCustomerAuth(AuthState auth) {
    if (!auth.restoreComplete) {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _loadErr = null;
      });
      return;
    }
    if (!auth.isAuthed) {
      if (!mounted) return;
      setState(() {
        _loadErr = 'Log in om technische configuratie te openen.';
        _loading = false;
      });
      return;
    }
    if (!auth.isAdmin) {
      if (!mounted) return;
      setState(() {
        _loadErr = 'Alleen beheerders maken technische configuratie aan.';
        _loading = false;
      });
      return;
    }
    _load();
  }

  Future<void> _load() async {
    String? token;
    if (widget.useCustomerSession) {
      final auth = ref.read(authProvider);
      if (!auth.restoreComplete || !auth.isAuthed || !auth.isAdmin) {
        return;
      }
      token = auth.token;
    } else {
      final auth = ref.read(installerAuthProvider);
      if (!auth.isAuthed) return;
      token = auth.token;
    }
    if (token == null) return;
    setState(() {
      _loading = true;
      _loadErr = null;
    });
    try {
      final h = await fetchInstallerHouse(token);
      await loadKnxGaCatalog(token);
      if (!mounted) return;
      setState(() {
        _house = h;
        _normalizeHouseIntercoms();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadErr = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    String? token;
    if (widget.useCustomerSession) {
      final auth = ref.read(authProvider);
      token = auth.token;
      if (token == null || !auth.isAdmin) return;
    } else {
      final auth = ref.read(installerAuthProvider);
      token = auth.token;
      if (token == null) return;
    }
    final house = _house;
    if (house == null) return;
    setState(() => _saving = true);
    try {
      _stripEmptyPasswordFields();
      _normalizeHouseIntercoms();
      await putInstallerHouse(token, house);
      if (!mounted) return;
      for (final u in _users()) {
        u.remove('password');
      }
      setState(() {});
      if (widget.useCustomerSession) {
        ref.invalidate(configProvider);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuratie opgeslagen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _ensureProject() {
    final h = _house!;
    final p = h['project'];
    if (p is Map<String, dynamic>) return p;
    final m = <String, dynamic>{'id': '', 'name': ''};
    h['project'] = m;
    return m;
  }

  Map<String, dynamic> _ensureKnx() {
    final h = _house!;
    final k = h['knx'];
    if (k is Map<String, dynamic>) return k;
    final m = <String, dynamic>{
      'enabled': true,
      'gateway': {'host': '', 'port': 3671, 'mode': 'tunneling'},
    };
    h['knx'] = m;
    return m;
  }

  Map<String, dynamic> _ensureLutron() {
    final h = _house!;
    final l = h['lutron'];
    if (l is Map<String, dynamic>) {
      _ensureLutronTelnet(l);
      return l;
    }
    final m = <String, dynamic>{
      'bridgeHost': '',
      'telnet': <String, dynamic>{
        'enabled': false,
        'host': '',
        'port': 23,
        'username': '',
        'password': '',
        'postLoginCommands': <String>['#MONITORING,3,1'],
      },
      'buttonToKnx': <Map<String, dynamic>>[],
    };
    h['lutron'] = m;
    return m;
  }

  void _ensureLutronTelnet(Map<String, dynamic> lutron) {
    final t = lutron['telnet'];
    if (t is Map<String, dynamic>) return;
    lutron['telnet'] = <String, dynamic>{
      'enabled': false,
      'host': '',
      'port': 23,
      'username': '',
      'password': '',
      'postLoginCommands': <String>['#MONITORING,3,1'],
    };
  }

  List<Map<String, dynamic>> _floors() {
    final h = _house!;
    final f = h['floors'];
    if (f is! List) {
      h['floors'] = <Map<String, dynamic>>[];
    }
    return (h['floors'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _users() {
    final h = _house!;
    final u = h['users'];
    if (u is! List) {
      h['users'] = <Map<String, dynamic>>[];
    }
    return (h['users'] as List).cast<Map<String, dynamic>>();
  }

  void _addUser() {
    _users().add({
      'id': 'usr-${_uuid.v4()}',
      'username': 'nieuw',
      'displayName': 'Nieuwe gebruiker',
      'role': 'user',
      'passwordHash': '',
      'access': {
        'floors': '*',
        'rooms': '*',
        'editScenes': true,
      },
    });
    setState(() => _sel = _Focus.user(_users().length - 1));
  }

  void _stripEmptyPasswordFields() {
    final h = _house;
    if (h == null) return;
    for (final u in _users()) {
      final p = u['password'];
      if (p is! String || p.isEmpty) {
        u.remove('password');
      }
    }
  }

  void _addFloor() {
    _floors().add({
      'id': 'fl-${_uuid.v4()}',
      'name': 'Nieuwe verdieping',
      'order': _floors().length,
      'rooms': <Map<String, dynamic>>[],
    });
    setState(() {});
  }

  void _addRoom(int fi) {
    final rooms = _roomList(fi);
    rooms.add({
      'id': 'rm-${_uuid.v4()}',
      'name': 'Nieuwe ruimte',
      'devices': <Map<String, dynamic>>[],
    });
    setState(() {});
  }

  String? _currentToken() {
    if (widget.useCustomerSession) {
      final auth = ref.read(authProvider);
      if (!auth.isAdmin) return null;
      return auth.token;
    }
    return ref.read(installerAuthProvider).token;
  }

  static const _knxImportInfo =
      'Importeer een KNX Group Address XML (ETS-export of de Archie '
      'Groepsadressentool). De hoofdfuncties (verlichting, dimmers, zonwering, '
      'klimaat) worden automatisch per verdieping en ruimte aangemaakt. Alle '
      'groepsadressen komen ook in de zoekfunctie bij de GA-velden.\n\n'
      'Gebruikt u de Archie Groepsadressentool? Zorg er dan voor dat u de XML '
      'exporteert MET volledige groepsadresnamen (verdieping.ruimte, ruimtenaam, '
      'devicenaam en objectnaam). Zonder volledige namen kunnen ruimtes en '
      'apparaten niet betrouwbaar worden herkend.';

  Future<void> _showKnxImportInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('KNX-import'),
        content: const SingleChildScrollView(child: Text(_knxImportInfo)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  Future<void> _importKnx() async {
    final token = _currentToken();
    if (token == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kon het bestand niet lezen.')),
      );
      return;
    }
    String xml;
    try {
      xml = utf8.decode(bytes);
    } catch (_) {
      xml = String.fromCharCodes(bytes);
    }
    setState(() => _saving = true);
    Map<String, dynamic> result;
    try {
      result = await importKnxXml(token, xml);
      // Refresh the searchable catalog with the freshly imported addresses.
      await loadKnxGaCatalog(token);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _knxSyncExisting = false;
    final confirmed = await _showKnxPreview(result);
    if (confirmed != true) return;
    final merged = _mergeKnxProposal(result, sync: _knxSyncExisting);
    setState(() {});
    if (merged.added > 0 || merged.updated > 0) {
      await _save();
      if (mounted) {
        final parts = <String>[
          if (merged.added > 0) '${merged.added} toegevoegd',
          if (merged.updated > 0) '${merged.updated} bijgewerkt',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KNX-import: ${parts.join(' · ')}.')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Niets toegevoegd (alles bestond al).'),
        ),
      );
    }
  }

  Future<bool?> _showKnxPreview(Map<String, dynamic> result) {
    final floors = (result['floors'] as List?) ?? const [];
    final stats = (result['stats'] as Map?) ?? const {};
    final warnings = (result['warnings'] as List?) ?? const [];
    final skipped = (result['skipped'] as List?) ?? const [];
    final review = (result['review'] as Map?) ?? const {};
    final manualDevices = (review['manualDevices'] as List?) ?? const [];
    final duplicateNames = (review['duplicateNames'] as List?) ?? const [];
    final singleDeviceRooms = (review['singleDeviceRooms'] as List?) ?? const [];
    final unclassified = (review['unclassified'] as List?) ?? const [];
    final rgbwGroups = (review['rgbwGroups'] as List?) ?? const [];
    final groupChannelDevices =
        (review['groupChannelDevices'] as List?) ?? const [];
    final acDevices = (review['acDevices'] as List?) ?? const [];

    List<Widget> reviewBlock(String title, List<dynamic> items, Color color) {
      if (items.isEmpty) return const [];
      return [
        const SizedBox(height: 8),
        Text('$title (${items.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        for (final it in items.take(12))
          Text(
            '• ${(it as Map)['name'] ?? it['address'] ?? ''}'
            '${it['reason'] != null ? '  —  ${it['reason']}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (items.length > 12)
          Text('  … en ${items.length - 12} meer',
              style: Theme.of(context).textTheme.bodySmall),
      ];
    }
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
        title: const Text('KNX-import voorbeeld'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${stats['addresses'] ?? 0} groepsadressen · '
                  '${stats['devices'] ?? 0} apparaten · '
                  '${stats['floors'] ?? 0} verdiepingen · '
                  '${stats['rooms'] ?? 0} ruimtes',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                for (final f in floors.cast<Map>()) ...[
                  Text(
                    f['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final r in ((f['rooms'] as List?) ?? const []).cast<Map>())
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r['name']} (${r['code']})',
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic)),
                          for (final d
                              in ((r['devices'] as List?) ?? const []).cast<Map>())
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                '• ${d['name']}  —  ${d['type']}',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Waarschuwingen (${warnings.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800)),
                  for (final w in warnings.take(10))
                    Text('• $w',
                        style: Theme.of(ctx).textTheme.bodySmall),
                ],
                const Divider(height: 20),
                Text('Nakijken',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                ...reviewBlock('Handmatig toevoegen (geen hoofdfunctie)',
                    manualDevices, Colors.blue.shade700),
                ...reviewBlock('Dubbele namen (automatisch onderscheiden)',
                    duplicateNames, Colors.purple.shade700),
                ...reviewBlock(
                    'RGB(W) samengevoegd', rgbwGroups, Colors.teal.shade700),
                ...reviewBlock('Groeps-GA (stuurt meerdere contacten)',
                    groupChannelDevices, Colors.indigo.shade700),
                ...reviewBlock('Airco — instellingen controleren', acDevices,
                    Colors.cyan.shade700),
                ...reviewBlock('Ruimtenaam uit één device',
                    singleDeviceRooms, Colors.orange.shade700),
                ...reviewBlock('Rol niet herkend', unclassified,
                    Colors.red.shade700),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${skipped.length} adressen niet als apparaat herkend '
                    '(wel doorzoekbaar bij de GA-velden).',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 20),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _knxSyncExisting,
                  onChanged: (v) =>
                      setLocal(() => _knxSyncExisting = v ?? false),
                  title: const Text('Bestaande apparaten bijwerken (sync)'),
                  subtitle: const Text(
                    'Werk de groepsadressen bij van apparaten die op een GA '
                    'matchen. Type en zelf aangepaste namen blijven behouden. '
                    'Zonder dit vinkje worden bestaande apparaten overgeslagen.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_knxSyncExisting ? 'Toevoegen + bijwerken' : 'Toevoegen'),
          ),
        ],
      ),
      ),
    );
  }

  /// Merge a parsed KNX proposal into `_house`, keeping floors/rooms unique on
  /// their KNX floor number / room code. Returns the number of devices added.
  ({int added, int updated}) _mergeKnxProposal(
    Map<String, dynamic> result, {
    bool sync = false,
  }) {
    final floors = (result['floors'] as List?)?.cast<Map>() ?? const [];
    var addedDevices = 0;
    var updatedDevices = 0;
    for (final pf in floors) {
      final floorNr = (pf['floor'] as num?)?.toInt();
      final floorName = pf['name']?.toString() ?? 'Verdieping';
      final floor = _findOrCreateFloor(floorNr, floorName);
      final rooms = (pf['rooms'] as List?)?.cast<Map>() ?? const [];
      for (final pr in rooms) {
        final code = pr['code']?.toString() ?? '';
        final roomName = pr['name']?.toString() ?? 'Ruimte';
        final room = _findOrCreateRoom(floor, code, roomName);
        final devices =
            (room['devices'] as List).cast<Map<String, dynamic>>();
        final proposed = (pr['devices'] as List?)?.cast<Map>() ?? const [];
        for (final pd in proposed) {
          final device = Map<String, dynamic>.from(pd);
          final existing = _findMatchingDevice(devices, device);
          if (existing != null) {
            // Sync only rewrites the group addresses of a matched device;
            // its id, type and any manual rename/options stay intact.
            if (sync && _syncDeviceGa(existing, device)) updatedDevices++;
            continue;
          }
          device['id'] = 'dev-${_uuid.v4()}';
          devices.add(device);
          addedDevices++;
        }
      }
    }
    return (added: addedDevices, updated: updatedDevices);
  }

  /// Overwrites the `ga` map of [existing] with the freshly imported addresses.
  /// Returns true when something actually changed.
  bool _syncDeviceGa(
    Map<String, dynamic> existing,
    Map<String, dynamic> proposed,
  ) {
    final newGa = proposed['ga'];
    if (newGa is! Map) return false;
    final oldGa = existing['ga'];
    if (oldGa is Map &&
        oldGa.length == newGa.length &&
        oldGa.entries.every((e) => '${newGa[e.key]}' == '${e.value}')) {
      return false;
    }
    existing['ga'] = Map<String, dynamic>.from(newGa);
    return true;
  }

  Map<String, dynamic> _findOrCreateFloor(int? floorNr, String name) {
    final floors = _floors();
    for (final f in floors) {
      if (floorNr != null && (f['knxFloor'] as num?)?.toInt() == floorNr) {
        return f;
      }
    }
    for (final f in floors) {
      if ((f['name'] as String?)?.toLowerCase() == name.toLowerCase()) {
        if (floorNr != null) f['knxFloor'] = floorNr;
        return f;
      }
    }
    final created = <String, dynamic>{
      'id': 'fl-${_uuid.v4()}',
      'name': name,
      'order': floors.length,
      if (floorNr != null) 'knxFloor': floorNr,
      'rooms': <Map<String, dynamic>>[],
    };
    floors.add(created);
    return created;
  }

  Map<String, dynamic> _findOrCreateRoom(
    Map<String, dynamic> floor,
    String code,
    String name,
  ) {
    final rooms = (floor['rooms'] as List).cast<Map<String, dynamic>>();
    for (final r in rooms) {
      if (code.isNotEmpty && r['knxRoom'] == code) return r;
    }
    for (final r in rooms) {
      // Don't hijack a room already claimed by a different KNX room code:
      // e.g. "1.01 Overloop" and "1.01p Overloop" share a name but are
      // physically distinct rooms (the ".p" wing) and must stay separate.
      final claimed = r['knxRoom'];
      if (claimed != null && claimed != code) continue;
      if ((r['name'] as String?)?.toLowerCase() == name.toLowerCase()) {
        if (code.isNotEmpty) r['knxRoom'] = code;
        return r;
      }
    }
    final created = <String, dynamic>{
      'id': 'rm-${_uuid.v4()}',
      'name': name,
      if (code.isNotEmpty) 'knxRoom': code,
      'devices': <Map<String, dynamic>>[],
    };
    rooms.add(created);
    return created;
  }

  /// Idempotency guard: returns the existing device in the room that shares at
  /// least one group address with [device], or null when it is new.
  Map<String, dynamic>? _findMatchingDevice(
    List<Map<String, dynamic>> existing,
    Map<String, dynamic> device,
  ) {
    final ga = device['ga'];
    if (ga is! Map || ga.isEmpty) return null;
    final addrs = ga.values.map((v) => '$v').toSet();
    for (final d in existing) {
      final dga = d['ga'];
      if (dga is Map) {
        for (final v in dga.values) {
          if (addrs.contains('$v')) return d;
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _roomList(int fi) {
    final floor = _floors()[fi];
    final r = floor['rooms'];
    if (r is! List) {
      floor['rooms'] = <Map<String, dynamic>>[];
    }
    return (floor['rooms'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _deviceList(int fi, int ri) {
    final room = _roomList(fi)[ri];
    final d = room['devices'];
    if (d is! List) {
      room['devices'] = <Map<String, dynamic>>[];
    }
    return (room['devices'] as List).cast<Map<String, dynamic>>();
  }

  /// Devices at the project root level ? NOT placed in any room.
  List<Map<String, dynamic>> _globalDeviceList() {
    final h = _house!;
    final d = h['devices'];
    if (d is! List) {
      h['devices'] = <dynamic>[];
    }
    return (h['devices'] as List).cast<Map<String, dynamic>>();
  }

  void _addGlobalDevice(DeviceTypePick pick) {
    final id = 'dev-${_uuid.v4()}';
    _globalDeviceList().add(_defaultDevice(pick.type, id, bus: pick.bus));
    _selectFocus(_Focus.globalDevice(_globalDeviceList().length - 1));
  }

  /// Moves a dragged device from its current location to a new target.
  /// Pass [targetFi] = -1 / [targetRi] = -1 to move to the global list.
  void _moveDevice(_DeviceDragData data,
      {required int targetFi, required int targetRi}) {
    // Prevent no-op drops on the same room.
    if (!data.isGlobal &&
        targetFi >= 0 &&
        data.fi == targetFi &&
        data.ri == targetRi) { return; }
    if (data.isGlobal && targetFi < 0) { return; }

    setState(() {
      final deviceCopy = Map<String, dynamic>.from(data.device);
      // Remove from source.
      if (data.isGlobal) {
        _globalDeviceList().removeAt(data.di);
      } else {
        _deviceList(data.fi, data.ri).removeAt(data.di);
      }
      // Insert in target and update selection.
      if (targetFi < 0) {
        _globalDeviceList().add(deviceCopy);
        _sel = _Focus.globalDevice(_globalDeviceList().length - 1);
        _mobileShowDetail = false;
      } else {
        _deviceList(targetFi, targetRi).add(deviceCopy);
        _sel = _Focus.device(
            targetFi, targetRi, _deviceList(targetFi, targetRi).length - 1);
        _mobileShowDetail = false;
      }
    });
  }

  /// Compact floating card shown while dragging a device.
  Widget _deviceDragFeedback(String name, String type) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_with_outlined, size: 16,
                color: Colors.grey),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(type,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _cameras() {
    final h = _house;
    if (h == null) return [];
    final c = h['cameras'];
    if (c is! List) {
      h['cameras'] = <Map<String, dynamic>>[];
    }
    return (h['cameras'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _intercoms() {
    final h = _house;
    if (h == null) return [];
    final c = h['intercoms'];
    if (c is! List) {
      h['intercoms'] = <Map<String, dynamic>>[];
    }
    return (h['intercoms'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _logsList() {
    final h = _house;
    if (h == null) return [];
    final c = h['logs'];
    if (c is! List) {
      h['logs'] = <Map<String, dynamic>>[];
    }
    return (h['logs'] as List).cast<Map<String, dynamic>>();
  }

  /// Verplaats intercoms uit kamers naar `intercoms` (zoals camera's).
  void _normalizeHouseIntercoms() {
    final h = _house;
    if (h == null) return;
    final list = _intercoms();
    final seen = list.map((c) => c['id'] as String).toSet();
    for (final floor in _floors()) {
      for (final room in (floor['rooms'] as List).cast<Map<String, dynamic>>()) {
        final devs = (room['devices'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
        final next = <Map<String, dynamic>>[];
        for (final d in devs) {
          if (d['type'] == 'intercom') {
            final id = d['id'] as String?;
            if (id != null && !seen.contains(id)) {
              list.add(d);
              seen.add(id);
            }
          } else {
            next.add(d);
          }
        }
        room['devices'] = next;
      }
    }
  }

  void _addCamera() {
    final map = _defaultDevice('camera', 'dev-cam-${_uuid.v4()}');
    _cameras().add(map);
    _selectFocus(_Focus.cameraDetail(_cameras().length - 1));
  }

  Widget _camerasInstallerPanel(BuildContext context) {
    final list = _cameras();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Camera\'s', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addCamera,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Camera toevoegen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Camera\'s horen bij het hele project, niet bij een kamer. '
          'Configureer hier RTSP, pad, aspect en opties.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          Text(
            'Nog geen camera. Klik op ?Camera toevoegen?.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        for (var i = 0; i < list.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(list[i]['name'] as String? ?? list[i]['id'] as String),
              subtitle: Text(list[i]['id'] as String? ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _selectFocus(_Focus.cameraDetail(i)),
            ),
          ),
      ],
    );
  }

  List<_RoomDevRef> _audioDevicesInRooms() {
    final out = <_RoomDevRef>[];
    for (var fi = 0; fi < _floors().length; fi++) {
      final floor = _floors()[fi];
      final fn = (floor['name'] as String?) ?? floor['id'].toString();
      for (var ri = 0; ri < _roomList(fi).length; ri++) {
        final room = _roomList(fi)[ri];
        final rn = (room['name'] as String?) ?? room['id'].toString();
        final devs = _deviceList(fi, ri);
        for (var di = 0; di < devs.length; di++) {
          final t = devs[di]['type'] as String?;
          if (t == 'media_sonos' || t == 'media_bluesound') {
            out.add(_RoomDevRef(
              fi: fi,
              ri: ri,
              di: di,
              dev: devs[di],
              location: '$fn ? $rn',
            ));
          }
        }
      }
    }
    return out;
  }

  void _addIntercom() {
    final map = _defaultDevice('intercom', 'dev-ic-${_uuid.v4()}');
    _intercoms().add(map);
    setState(() => _sel = _Focus.intercomDetail(_intercoms().length - 1));
  }

  Future<void> _pickRoomAndAddDevice(
      BuildContext context, DeviceTypePick pick) async {
    final fiList = <int>[];
    final riList = <int>[];
    final labels = <String>[];
    for (var fi = 0; fi < _floors().length; fi++) {
      final fn = (_floors()[fi]['name'] as String?) ?? '';
      for (var ri = 0; ri < _roomList(fi).length; ri++) {
        final rn = (_roomList(fi)[ri]['name'] as String?) ?? '';
        fiList.add(fi);
        riList.add(ri);
        labels.add('$fn ? $rn');
      }
    }
    if (labels.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Voeg eerst een verdieping en kamer toe.')),
      );
      return;
    }
    final idx = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Kies kamer')),
            for (var i = 0; i < labels.length; i++)
              ListTile(
                title: Text(labels[i]),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (idx == null || !context.mounted) return;
    final fi = fiList[idx];
    final ri = riList[idx];
    final id = 'dev-${_uuid.v4()}';
    _deviceList(fi, ri).add(_defaultDevice(pick.type, id, bus: pick.bus));
    final di = _deviceList(fi, ri).length - 1;
    _selectFocus(_Focus.device(fi, ri, di));
  }

  Widget _audioInstallerPanel(BuildContext context) {
    final rows = _audioDevicesInRooms();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Audio (Sonos / Bluesound)',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'Toevoegen in kamer',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () async {
                final pick = await showPickDeviceTypeSheet(context);
                if (pick != null && context.mounted) {
                  await _pickRoomAndAddDevice(context, pick);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Overzicht voor de installateur: de apparaten staan in de JSON onder '
          'de gekozen kamer (zelfde als in de boom links). Tik om te bewerken.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        if (rows.isEmpty)
          Text(
            'Nog geen Sonos/Bluesound in kamers. Gebruik + of voeg toe via een kamer.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        for (final row in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                row.dev['type'] == 'media_bluesound'
                    ? Icons.speaker_group_outlined
                    : Icons.speaker_outlined,
              ),
              title: Text(
                  row.dev['name'] as String? ?? row.dev['id'] as String),
              subtitle: Text('${row.location} ? ${row.dev['id']}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => setState(
                () => _sel = _Focus.device(row.fi, row.ri, row.di),
              ),
            ),
          ),
      ],
    );
  }

  Widget _intercomsInstallerPanel(BuildContext context) {
    final list = _intercoms();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Intercom', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addIntercom,
              icon: const Icon(Icons.doorbell_outlined),
              label: const Text('Intercom toevoegen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Intercom hoort bij het hele project, niet bij een kamer. '
          'Configureer hier type (DoorBird / 2N / SIP), stream en KNX voor deurbel en deur.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          Text(
            'Nog geen intercom. Klik op ?Intercom toevoegen?.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        for (var i = 0; i < list.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.doorbell_outlined),
              title: Text(list[i]['name'] as String? ?? list[i]['id'] as String),
              subtitle: Text(list[i]['id'] as String? ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _selectFocus(_Focus.intercomDetail(i)),
            ),
          ),
      ],
    );
  }

  Map<String, dynamic> _lutronLoadDevice({
    required String id,
    required String type,
    required String name,
    Map<String, dynamic>? extra,
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'control': 'lutron',
      'lutronIntegrationId': 1,
      if (extra != null) ...extra,
    };
  }

  Map<String, dynamic> _defaultDevice(
    String type,
    String id, {
    DeviceBusCategory bus = DeviceBusCategory.knx,
  }) {
    final lutronLoad = bus == DeviceBusCategory.lutron &&
        (type == 'light_switch' ||
            type == 'light_dimmer' ||
            type == 'shading');

    switch (type) {
      case 'light_switch':
        if (lutronLoad) {
          return _lutronLoadDevice(
            id: id,
            type: 'light_switch',
            name: 'Lutron lamp',
          );
        }
        return {
          'id': id,
          'name': 'Lamp',
          'type': 'light_switch',
          'ga': {'switch': '1/1/1'},
        };
      case 'light_dimmer':
        if (lutronLoad) {
          return _lutronLoadDevice(
            id: id,
            type: 'light_dimmer',
            name: 'Lutron dimlamp',
          );
        }
        return {
          'id': id,
          'name': 'Dimmer',
          'type': 'light_dimmer',
          'ga': {
            'switch': '1/1/1',
            'dim_value': '1/1/2',
          },
        };
      case 'rgbw_ww':
        return {
          'id': id,
          'name': 'RGBWW',
          'type': 'rgbw_ww',
          'rgbwWw': {'mode': 'channels'},
          'ga': {
            'r': '1/3/1',
            'g': '1/3/2',
            'b': '1/3/3',
            'w': '1/3/4',
            'ww': '1/3/5',
          },
        };
      case 'shading':
        if (lutronLoad) {
          return _lutronLoadDevice(
            id: id,
            type: 'shading',
            name: 'Lutron gordijn',
            extra: {'subtype': 'blind'},
          );
        }
        return {
          'id': id,
          'name': 'Zonwering',
          'type': 'shading',
          'subtype': 'blind',
          'ga': {
            'up_down': '2/1/1',
            'stop_step': '2/1/2',
            'position': '2/1/3',
            'position_status': '2/1/4',
          },
        };
      case 'position_actuator':
        return {
          'id': id,
          'name': 'Raam',
          'type': 'position_actuator',
          'ga': {
            'up_down': '2/2/1',
            'stop_step': '2/2/2',
            'position': '2/2/3',
            'position_status': '2/2/4',
          },
        };
      case 'climate':
        return {
          'id': id,
          'name': 'Thermostaat',
          'type': 'climate',
          'ga': {
            'actual_temp': '3/1/1',
            'setpoint': '3/1/2',
          },
          'climate': {
            'canHeat': true,
            'canCool': false,
            'userCanSwitchMode': false,
          },
        };
      case 'media_sonos':
        return {
          'id': id,
          'name': 'Sonos',
          'type': 'media_sonos',
          'sonos': {'host': '', 'port': 1400},
        };
      case 'media_bluesound':
        return {
          'id': id,
          'name': 'Bluesound',
          'type': 'media_bluesound',
          'bluesound': {'host': '192.168.1.50'},
        };
      case 'camera':
        return {
          'id': id,
          'name': 'Camera',
          'type': 'camera',
          'camera': {
            'rtsp':
                'rtsp://gebruiker:wachtwoord@192.168.1.10:554/stream',
          },
        };
      case 'intercom':
        return {
          'id': id,
          'name': 'Intercom',
          'type': 'intercom',
          'intercom': {
            'kind': 'doorbird',
            'rtsp': 'rtsp://192.168.1.102/live',
            'releaseMode': 'knx',
          },
        };
      case 'fireplace':
        return {
          'id': id,
          'name': 'Haard',
          'type': 'fireplace',
          'confirm': {
            'on': {
              'title': 'Weet u zeker dat u de haard aan wilt zetten?',
              'message':
                  'Let op: volg bij het gebruik van de haard altijd de '
                  'veiligheids- en bedieningsvoorschriften van de fabrikant.',
            },
          },
          'fireplace': {
            'controlMode': 'analog',
            'onOff': {'ga': '1/1/1', 'statusGa': '1/1/2'},
            'flame': {
              'ga': '1/2/1',
              'statusGa': '1/2/2',
              'levelDisplay': 'percent',
            },
          },
        };
      case 'ac':
        return {
          'id': id,
          'name': 'Airco',
          'type': 'ac',
          'ac': {
            'onOff': {'ga': '1/1/1'},
            'setpoint': {'ga': '1/1/2', 'min': 16, 'max': 30},
            'mode': {
              'ga': '1/1/4',
              'options': defaultAcModeOptions
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(),
            },
            'modeVisibility': Map<String, dynamic>.from(
              defaultAcModeVisibility,
            ),
          },
        };
      case 'fan':
        return {
          'id': id,
          'name': 'Ventilator',
          'type': 'fan',
          'fan': {
            'onOff': {'ga': '1/1/1'},
          },
        };
      case 'universal':
        return {
          'id': id,
          'name': 'Universeel paneel',
          'type': 'universal',
          'universal': {
            'icon': 'grid',
            'buttons': <Map<String, dynamic>>[],
          },
        };
      case 'lutron_homeworks':
        return {
          'id': id,
          'name': 'Lutron ? KNX',
          'type': 'lutron_homeworks',
          'lutronHomeworks': <String, dynamic>{
            'zoneAddress': '',
            'bridgeHost': '',
            'telnet': <String, dynamic>{
              'enabled': false,
              'host': '',
              'port': 23,
              'username': '',
              'password': '',
              'postLoginCommands': <String>['#MONITORING,3,1'],
            },
            'buttonToKnx': <Map<String, dynamic>>[
              {
                'id': 'demo-1',
                'label': 'Voorbeeld knop',
                'integrationId': 1,
                'componentNumber': 1,
                'actionNumber': 1,
                'knx': <String, dynamic>{
                  'ga': '1/1/1',
                  'role': 'switch',
                  'value': true,
                  'pulseMs': 250,
                },
              },
            ],
          },
        };
      default:
        return {'id': id, 'name': 'Apparaat', 'type': type};
    }
  }

  void _addDevice(int fi, int ri, DeviceTypePick pick) {
    final id = 'dev-${_uuid.v4()}';
    _deviceList(fi, ri).add(_defaultDevice(pick.type, id, bus: pick.bus));
    setState(() {
      _sel = _Focus.device(fi, ri, _deviceList(fi, ri).length - 1);
    });
  }

  Future<void> _copyDevice(Map<String, dynamic> device) async {
    _copiedDevice = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(device)) as Map<String, dynamic>,
    );
    await Clipboard.setData(ClipboardData(
      text: const JsonEncoder.withIndent('  ').convert(_copiedDevice),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${device['name'] ?? device['id']} gekopieerd',
        ),
      ),
    );
    setState(() {});
  }

  Future<bool> _loadPasteClipboard() async {
    if (_copiedDevice != null) return true;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _copiedDevice = decoded;
        return true;
      }
      if (decoded is Map) {
        _copiedDevice = Map<String, dynamic>.from(decoded);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _pasteDeviceIntoList(
    List<Map<String, dynamic>> list, {
    int? afterIndex,
    void Function(int newIndex)? onPasted,
  }) async {
    if (!await _loadPasteClipboard()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Niets om te plakken — kopieer eerst een apparaat'),
        ),
      );
      return;
    }
    final clone = _cloneDeviceJson(_copiedDevice!, _uuid);
    final insertAt =
        afterIndex == null ? list.length : (afterIndex + 1).clamp(0, list.length);
    list.insert(insertAt, clone);
    if (!mounted) return;
    if (onPasted != null) {
      onPasted(insertAt);
    } else {
      setState(() {});
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${clone['name'] ?? clone['id']} geplakt')),
    );
  }

  void _tryCopyFocusedDevice() {
    switch (_sel.kind) {
      case _FocusKind.device:
        _copyDevice(_deviceList(_sel.fi, _sel.ri)[_sel.di]);
      case _FocusKind.globalDevice:
        _copyDevice(_globalDeviceList()[_sel.di]);
      case _FocusKind.cameraDetail:
        _copyDevice(_cameras()[_sel.ci!]);
      case _FocusKind.intercomDetail:
        _copyDevice(_intercoms()[_sel.ci!]);
      default:
        break;
    }
  }

  Future<void> _tryPasteFocusedDevice() async {
    switch (_sel.kind) {
      case _FocusKind.device:
        await _pasteDeviceIntoList(
          _deviceList(_sel.fi, _sel.ri),
          afterIndex: _sel.di,
          onPasted: (i) => _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
        );
      case _FocusKind.globalDevice:
        await _pasteDeviceIntoList(
          _globalDeviceList(),
          afterIndex: _sel.di,
          onPasted: (i) => _selectFocus(_Focus.globalDevice(i)),
        );
      case _FocusKind.room:
        await _pasteDeviceIntoList(
          _deviceList(_sel.fi, _sel.ri),
          onPasted: (i) => _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
        );
      case _FocusKind.cameraDetail:
        await _pasteDeviceIntoList(
          _cameras(),
          afterIndex: _sel.ci,
          onPasted: (i) => _selectFocus(_Focus.cameraDetail(i)),
        );
      case _FocusKind.intercomDetail:
        await _pasteDeviceIntoList(
          _intercoms(),
          afterIndex: _sel.ci,
          onPasted: (i) => _selectFocus(_Focus.intercomDetail(i)),
        );
      default:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecteer een apparaat of kamer om te plakken'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadErr != null || _house == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadErr ?? 'Onbekende fout'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Opnieuw')),
              ],
            ),
          ),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 900;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _tryCopyFocusedDevice,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          _tryPasteFocusedDevice();
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
      // On mobile, intercepting the back gesture while detail is visible
      // navigates back to the menu instead of popping the route.
      canPop: wide || !_mobileShowDetail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _mobileShowDetail = false);
      },
      child: Scaffold(
        appBar: AppBar(
          // On mobile detail view, replace the route back button with a
          // menu-back button so the user can navigate the menu without leaving.
          leading: (!wide && _mobileShowDetail)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Terug naar menu',
                  onPressed: () => setState(() => _mobileShowDetail = false),
                )
              : null,
          title: Text(widget.useCustomerSession
              ? 'Technische configuratie'
              : 'Installateur ? huisconfiguratie'),
          actions: [
            if (wide || _mobileShowDetail) ...[
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Herladen van server',
                onPressed: _saving ? null : _load,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Opslaan'),
                ),
              ),
            ],
            TextButton(
              onPressed: () async {
                if (widget.useCustomerSession) {
                  if (context.mounted) context.pop();
                } else {
                  await ref.read(installerAuthProvider.notifier).logout();
                }
              },
              child: Text(widget.useCustomerSession ? 'Terug' : 'Uitloggen'),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (ctx, c) {
            final isWide = c.maxWidth >= 900;
            final tree = _buildTree(ctx);
            if (!isWide) {
              // Mobile: show either the menu list OR the detail full-screen.
              if (_mobileShowDetail) return _buildDetail(ctx);
              return tree;
            }
            // Desktop/tablet: side-by-side layout.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 340, child: tree),
                const VerticalDivider(width: 1),
                Expanded(child: _buildDetail(ctx)),
              ],
            );
          },
        ),
      ),
        ),
      ),
    );
  }

  /// Draggable list tile for a single device entry in the tree.
  Widget _buildDraggableDeviceTile({
    required BuildContext context,
    required Map<String, dynamic> device,
    required int fi,
    required int ri,
    required int di,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final name = (device['name'] as String?) ?? (device['id'] as String? ?? '');
    final type = (device['type'] as String?) ?? '';
    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 4, right: 0),
      leading: Icon(Icons.drag_handle, size: 18,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade400),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(type, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade500),
        padding: EdgeInsets.zero,
        tooltip: 'Kopiëren / plakken',
        onSelected: (action) {
          if (action == 'copy') {
            _copyDevice(device);
          } else if (action == 'paste') {
            if (fi < 0) {
              _pasteDeviceIntoList(
                _globalDeviceList(),
                afterIndex: di,
                onPasted: (i) => _selectFocus(_Focus.globalDevice(i)),
              );
            } else {
              _pasteDeviceIntoList(
                _deviceList(fi, ri),
                afterIndex: di,
                onPasted: (i) => _selectFocus(_Focus.device(fi, ri, i)),
              );
            }
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'copy', child: Text('Kopiëren')),
          PopupMenuItem(value: 'paste', child: Text('Plakken eronder')),
        ],
      ),
    );
    return LongPressDraggable<_DeviceDragData>(
      data: _DeviceDragData(device: device, fi: fi, ri: ri, di: di),
      delay: const Duration(milliseconds: 350),
      feedback: _deviceDragFeedback(name, type),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  /// Label widget used inside DragTarget for room/global section headers.
  Widget _dropTargetLabel(
    BuildContext context,
    String label,
    bool active, {
    bool bold = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      decoration: active
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              ),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.w500)
                  : null,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            Icon(Icons.arrow_downward_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
    );
  }

  Widget _buildTree(BuildContext context) {
    final floors = _floors();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ListTile(
          title: const Text('Project'),
          selected: _sel.kind == _FocusKind.project,
          leading: const Icon(Icons.home_work_outlined),
          onTap: () => _selectFocus(const _Focus.project()),
        ),
        ListTile(
          title: const Text('KNX-gateway'),
          selected: _sel.kind == _FocusKind.knx,
          leading: const Icon(Icons.hub_outlined),
          trailing: _IntegrationBadge(
              enabled: (_house?['knx']?['enabled'] as bool?) != false &&
                  _house?['knx'] != null),
          onTap: () => _selectFocus(const _Focus.knx()),
        ),
        ListTile(
          title: const Text('Lutron QSX/QS Processor'),
          selected: _sel.kind == _FocusKind.lutron,
          leading: const Icon(Icons.home_work_outlined),
          trailing: _IntegrationBadge(
              enabled: (_house?['lutron']?['telnet']?['enabled'] as bool?) ==
                  true),
          onTap: () => _selectFocus(const _Focus.lutron()),
        ),
        ListTile(
          title: const Text('Camera\'s'),
          selected: _sel.kind == _FocusKind.cameras ||
              _sel.kind == _FocusKind.cameraDetail,
          leading: const Icon(Icons.videocam_outlined),
          onTap: () => _selectFocus(const _Focus.cameras()),
        ),
        ListTile(
          title: const Text('Audio'),
          selected: _sel.kind == _FocusKind.audio,
          leading: const Icon(Icons.speaker_group_outlined),
          onTap: () => _selectFocus(const _Focus.audio()),
        ),
        ListTile(
          title: const Text('Intercom'),
          selected: _sel.kind == _FocusKind.intercoms ||
              _sel.kind == _FocusKind.intercomDetail,
          leading: const Icon(Icons.doorbell_outlined),
          onTap: () => _selectFocus(const _Focus.intercoms()),
        ),
        ListTile(
          title: const Text('Gebruikers'),
          selected: _sel.kind == _FocusKind.users ||
              (_sel.kind == _FocusKind.user),
          leading: const Icon(Icons.people_outline),
          onTap: () => _selectFocus(const _Focus.users()),
        ),
        ListTile(
          title: const Text('Logs / grafieken'),
          selected: _sel.kind == _FocusKind.logs,
          leading: const Icon(Icons.show_chart_outlined),
          onTap: () => _selectFocus(const _Focus.logs()),
        ),
        ListTile(
          title: const Text('Satel alarm'),
          selected: _sel.kind == _FocusKind.satel,
          leading: const Icon(Icons.security_outlined),
          onTap: () => _selectFocus(const _Focus.satel()),
        ),
        const Divider(),
        // ?? Global (room-less) devices ????????????????????????????????????
        ExpansionTile(
          key: const ValueKey('global-devices'),
          leading: const Icon(Icons.devices_other_outlined),
          title: DragTarget<_DeviceDragData>(
            onWillAcceptWithDetails: (d) => !d.data.isGlobal,
            onAcceptWithDetails: (d) =>
                _moveDevice(d.data, targetFi: -1, targetRi: -1),
            builder: (ctx, candidates, _) => _dropTargetLabel(
              context,
              'Apparaten (geen ruimte)',
              candidates.isNotEmpty,
            ),
          ),
          subtitle: Text(
            '${_globalDeviceList().length} apparaten',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var di = 0; di < _globalDeviceList().length; di++)
                    _buildDraggableDeviceTile(
                      context: context,
                      device: _globalDeviceList()[di],
                      fi: -1, ri: -1, di: di,
                      selected: _sel.kind == _FocusKind.globalDevice &&
                          _sel.di == di,
                      onTap: () => _selectFocus(_Focus.globalDevice(di)),
                    ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding:
                        const EdgeInsets.only(left: 0, right: 8),
                    leading:
                        const Icon(Icons.add_circle_outline, size: 18),
                    title: const Text('Apparaat toevoegen'),
                    onTap: () async {
                      final pick =
                          await showPickDeviceTypeSheet(context);
                      if (pick == null) return;
                      _addGlobalDevice(pick);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Verdieping toevoegen'),
          onTap: _addFloor,
        ),
        for (var fi = 0; fi < floors.length; fi++)
          ExpansionTile(
            key: ValueKey('f-$fi'),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    floors[fi]['name'] as String? ?? floors[fi]['id'] as String,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 22,
                    color: _sel.kind == _FocusKind.floor && _sel.fi == fi
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: 'Verdieping bewerken',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => _selectFocus(_Focus.floor(fi)),
                ),
              ],
            ),
            initiallyExpanded: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var ri = 0; ri < _roomList(fi).length; ri++)
                      ExpansionTile(
                        key: ValueKey('f${fi}r$ri'),
                        tilePadding: const EdgeInsets.only(left: 4, right: 8),
                        onExpansionChanged: (expanded) {
                          final k = '$fi-$ri';
                          setState(() {
                            if (expanded) {
                              _expandedRoomKeys.add(k);
                            } else {
                              _expandedRoomKeys.remove(k);
                            }
                          });
                        },
                        title: DragTarget<_DeviceDragData>(
                          onWillAcceptWithDetails: (d) =>
                              d.data.isGlobal ||
                              d.data.fi != fi ||
                              d.data.ri != ri,
                          onAcceptWithDetails: (d) =>
                              _moveDevice(d.data, targetFi: fi, targetRi: ri),
                          builder: (ctx, candidates, _) => Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _dropTargetLabel(
                                  context,
                                  _roomList(fi)[ri]['name'] as String? ??
                                      _roomList(fi)[ri]['id'] as String,
                                  candidates.isNotEmpty,
                                  bold: true,
                                ),
                              ),
                              if (_expandedRoomKeys.contains('$fi-$ri'))
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                    color: _sel.kind == _FocusKind.room &&
                                            _sel.fi == fi &&
                                            _sel.ri == ri
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : null,
                                  ),
                                  tooltip: 'Kamer bewerken',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: () => _selectFocus(_Focus.room(fi, ri)),
                                ),
                            ],
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var di = 0;
                                    di < _deviceList(fi, ri).length;
                                    di++)
                                  _buildDraggableDeviceTile(
                                    context: context,
                                    device: _deviceList(fi, ri)[di],
                                    fi: fi, ri: ri, di: di,
                                    selected: _sel.kind ==
                                            _FocusKind.device &&
                                        _sel.fi == fi &&
                                        _sel.ri == ri &&
                                        _sel.di == di,
                                    onTap: () => _selectFocus(
                                          _Focus.device(fi, ri, di),
                                        ),
                                  ),
                                ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding:
                                      const EdgeInsets.only(left: 0, right: 8),
                                  leading: const Icon(
                                      Icons.add_circle_outline,
                                      size: 18),
                                  title: const Text('Apparaat toevoegen'),
                                  onTap: () async {
                                    final pick =
                                        await showPickDeviceTypeSheet(context);
                                    if (!context.mounted) return;
                                    if (pick != null) {
                                      _addDevice(fi, ri, pick);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.only(left: 0, right: 8),
                      leading: const Icon(Icons.add_circle_outline, size: 18),
                      title: const Text('Kamer toevoegen'),
                      onTap: () => _addRoom(fi),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    switch (_sel.kind) {
      case _FocusKind.project:
        return _ProjectForm(
          project: _ensureProject(),
          onChanged: () => setState(() {}),
          showAdminRestart: widget.useCustomerSession,
        );
      case _FocusKind.knx:
        return _KnxInstallerSection(
          knx: _ensureKnx(),
          onChanged: () => setState(() {}),
          onImport: _importKnx,
          onImportInfo: _showKnxImportInfo,
          getToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      case _FocusKind.lutron:
        return _LutronInstallerSection(
          lutron: _ensureLutron(),
          onChanged: () => setState(() {}),
          getToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      case _FocusKind.cameras:
        return _camerasInstallerPanel(context);
      case _FocusKind.cameraDetail:
        return _DeviceForm(
          device: _cameras()[_sel.ci!],
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_cameras()[_sel.ci!]),
          onPaste: () => _pasteDeviceIntoList(
            _cameras(),
            afterIndex: _sel.ci,
            onPasted: (i) => _selectFocus(_Focus.cameraDetail(i)),
          ),
          onDelete: () {
            _cameras().removeAt(_sel.ci!);
            setState(() => _sel = const _Focus.cameras());
          },
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      case _FocusKind.audio:
        return _audioInstallerPanel(context);
      case _FocusKind.intercoms:
        return _intercomsInstallerPanel(context);
      case _FocusKind.intercomDetail:
        return _DeviceForm(
          device: _intercoms()[_sel.ci!],
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_intercoms()[_sel.ci!]),
          onPaste: () => _pasteDeviceIntoList(
            _intercoms(),
            afterIndex: _sel.ci,
            onPasted: (i) => _selectFocus(_Focus.intercomDetail(i)),
          ),
          onDelete: () {
            _intercoms().removeAt(_sel.ci!);
            setState(() => _sel = const _Focus.intercoms());
          },
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      case _FocusKind.users:
        return _usersPanel(context);
      case _FocusKind.user:
        return _userEditorPanel(context);
      case _FocusKind.logs:
        return _LogsInstallerPanel(
          logs: _logsList(),
          uuid: _uuid,
          onChanged: () => setState(() {}),
        );
      case _FocusKind.satel:
        return const _SatelInstallerPanel();
      case _FocusKind.floor:
        return _MapStringForm(
          title: 'Verdieping',
          values: _floors()[_sel.fi],
          keys: const ['id', 'name', 'order', 'icon'],
          numericKeys: const {'order'},
          onChanged: () => setState(() {}),
          onDelete: () {
            _floors().removeAt(_sel.fi);
            setState(() => _sel = const _Focus.project());
          },
        );
      case _FocusKind.room:
        return _MapStringForm(
          title: 'Kamer',
          values: _roomList(_sel.fi)[_sel.ri],
          keys: const ['id', 'name', 'icon', 'cover'],
          headerActions: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _pasteDeviceIntoList(
                _deviceList(_sel.fi, _sel.ri),
                onPasted: (i) =>
                    _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
              ),
              icon: const Icon(Icons.content_paste_outlined),
              label: const Text('Apparaat plakken'),
            ),
          ),
          onChanged: () => setState(() {}),
          onDelete: () {
            _roomList(_sel.fi).removeAt(_sel.ri);
            setState(() => _sel = _Focus.floor(_sel.fi));
          },
        );
      case _FocusKind.device:
        return _DeviceForm(
          device: _deviceList(_sel.fi, _sel.ri)[_sel.di],
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_deviceList(_sel.fi, _sel.ri)[_sel.di]),
          onPaste: () => _pasteDeviceIntoList(
            _deviceList(_sel.fi, _sel.ri),
            afterIndex: _sel.di,
            onPasted: (i) => _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
          ),
          onDelete: () {
            _deviceList(_sel.fi, _sel.ri).removeAt(_sel.di);
            setState(() => _sel = _Focus.room(_sel.fi, _sel.ri));
          },
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      case _FocusKind.globalDevice:
        return _DeviceForm(
          device: _globalDeviceList()[_sel.di],
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_globalDeviceList()[_sel.di]),
          onPaste: () => _pasteDeviceIntoList(
            _globalDeviceList(),
            afterIndex: _sel.di,
            onPasted: (i) => _selectFocus(_Focus.globalDevice(i)),
          ),
          onDelete: () {
            _globalDeviceList().removeAt(_sel.di);
            setState(() {
              _sel = const _Focus.project();
              _mobileShowDetail = false;
            });
          },
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
    }
  }

  Widget _usersPanel(BuildContext context) {
    final list = _users();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Gebruikers', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addUser,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Toevoegen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Nieuwe gebruikers: vul bij de gebruiker een wachtwoord in en kies Opslaan. '
          'Bestaande gebruikers: laat wachtwoord leeg om het huidige te behouden.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Text('Nog geen gebruikers. Maak er een aan.'),
        for (var i = 0; i < list.length; i++)
          ListTile(
            leading: Icon(
              list[i]['role'] == 'admin'
                  ? Icons.admin_panel_settings_outlined
                  : Icons.person_outline,
            ),
            title: Text(list[i]['username'] as String? ?? ''),
            subtitle: Text(
              '${list[i]['role']} ? ${list[i]['displayName'] ?? ''}',
            ),
            selected: _sel.kind == _FocusKind.user && _sel.fi == i,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectFocus(_Focus.user(i)),
          ),
      ],
    );
  }

  Widget _userEditorPanel(BuildContext context) {
    final list = _users();
    final i = _sel.fi;
    if (i < 0 || i >= list.length) {
      return const Center(child: Text('Selecteer een gebruiker.'));
    }
    return _InstallerUserForm(
      key: ValueKey(list[i]['id']),
      user: list[i],
      onChanged: () => setState(() {}),
      onDelete: () {
        list.removeAt(i);
        setState(() => _sel = const _Focus.users());
      },
    );
  }
}

class _InstallerUserForm extends StatefulWidget {
  const _InstallerUserForm({
    super.key,
    required this.user,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> user;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_InstallerUserForm> createState() => _InstallerUserFormState();
}

class _InstallerUserFormState extends State<_InstallerUserForm> {
  late TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Map<String, dynamic> _ensureAccess() {
    final a = widget.user['access'];
    if (a is Map<String, dynamic>) return a;
    final m = <String, dynamic>{
      'floors': '*',
      'rooms': '*',
      'editScenes': true,
    };
    widget.user['access'] = m;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final access = _ensureAccess();
    final editScenes = access['editScenes'] != false;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Gebruiker', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _BoundStrField('id', u, widget.onChanged),
        _BoundStrField('username', u, widget.onChanged),
        _BoundStrField('displayName', u, widget.onChanged),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: u['role'] as String? ?? 'user',
            decoration: const InputDecoration(
              labelText: 'Rol',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('Beheerder (admin)')),
              DropdownMenuItem(value: 'user', child: Text('Gebruiker (user)')),
            ],
            onChanged: (v) {
              if (v != null) {
                u['role'] = v;
                widget.onChanged();
              }
            },
          ),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Nieuw wachtwoord (leeg = ongewijzigd)',
            border: OutlineInputBorder(),
            helperText:
                'Voor een nieuw account is een wachtwoord verplicht v??r Opslaan.',
          ),
          onChanged: (s) {
            if (s.isEmpty) {
              u.remove('password');
            } else {
              u['password'] = s;
            }
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Scenes en tijdschema\'s mogen wijzigen'),
          value: editScenes,
          onChanged: (v) {
            access['editScenes'] = v;
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.onDelete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Gebruiker verwijderen'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }
}

class _ProjectForm extends ConsumerWidget {
  const _ProjectForm({
    required this.project,
    required this.onChanged,
    required this.showAdminRestart,
  });
  final Map<String, dynamic> project;
  final VoidCallback onChanged;
  final bool showAdminRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = project['location'];
    Map<String, dynamic> locMap;
    if (loc is Map<String, dynamic>) {
      locMap = loc;
    } else {
      locMap = <String, dynamic>{};
      project['location'] = locMap;
    }
    final auth = ref.watch(authProvider);
    final showRestart = showAdminRestart && auth.isAdmin;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Project', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _BoundStrField('id', project, onChanged),
        _BoundStrField('name', project, onChanged),
        _BoundStrField('timezone', project, onChanged),
        const SizedBox(height: 12),
        Text('Locatie (astro)', style: Theme.of(context).textTheme.titleSmall),
        _BoundStrField('lat', locMap, onChanged, number: true),
        _BoundStrField('lon', locMap, onChanged, number: true),
        if (showRestart) ...[
          const SizedBox(height: 28),
          const AdminFullRestartCard(),
        ],
      ],
    );
  }
}

class _KnxInstallerSection extends StatefulWidget {
  const _KnxInstallerSection({
    required this.knx,
    required this.onChanged,
    required this.getToken,
    required this.onImport,
    required this.onImportInfo,
  });

  final Map<String, dynamic> knx;
  final VoidCallback onChanged;
  final Future<String?> Function() getToken;
  final VoidCallback onImport;
  final VoidCallback onImportInfo;

  @override
  State<_KnxInstallerSection> createState() => _KnxInstallerSectionState();
}

class _KnxInstallerSectionState extends State<_KnxInstallerSection> {
  Timer? _poll;
  InstallerKnxStatus? _status;
  String? _statusErr;
  bool _reconnectBusy = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus(silent: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    final t = await widget.getToken();
    if (!mounted || t == null) return;
    try {
      final s = await fetchInstallerKnxStatus(t);
      if (!mounted) return;
      setState(() {
        _status = s;
        if (!silent) _statusErr = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() => _statusErr = '$e');
    }
  }

  Future<void> _reconnect() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = await widget.getToken();
    if (!context.mounted || t == null) return;
    setState(() => _reconnectBusy = true);
    try {
      await postInstallerKnxReconnect(t);
      if (!context.mounted) return;
      await _refreshStatus();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('KNX-gateway opnieuw verbonden.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      await _refreshStatus();
    } finally {
      if (mounted) setState(() => _reconnectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: _status == null
                          ? 'Status wordt geladen?'
                          : _status!.simulate
                              ? 'Simulatiemodus (KNX_SIMULATE=1): geen echte bus'
                              : (_status!.connected
                                  ? 'Tunnel actief naar gateway'
                                  : 'Geen verbinding met KNX-gateway'),
                      child: Icon(
                        Icons.circle,
                        size: 22,
                        color: _status == null
                            ? Colors.grey.shade400
                            : _status!.simulate
                                ? Colors.amber.shade700
                                : _status!.connected
                                    ? Colors.green.shade600
                                    : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gateway-verbinding',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _status == null
                                ? (_statusErr ?? 'Status laden?')
                                : _status!.simulate
                                    ? 'Simulatie actief (${_status!.host}:${_status!.port})'
                                    : _status!.connected
                                        ? 'Verbonden met ${_status!.host}:${_status!.port}'
                                        : 'Niet verbonden ? backend: ${_status!.host}:${_status!.port}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _reconnectBusy ? null : _reconnect,
                      icon: _reconnectBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync, size: 20),
                      label: const Text('Opnieuw verbinden'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Nieuw IP of poort? Eerst onderaan Opslaan (house.json), daarna opnieuw verbinden.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _KnxForm(
            knx: widget.knx,
            onChanged: widget.onChanged,
            onImport: widget.onImport,
            onImportInfo: widget.onImportInfo,
          ),
        ),
      ],
    );
  }
}

class _LutronInstallerSection extends StatefulWidget {
  const _LutronInstallerSection({
    required this.lutron,
    required this.onChanged,
    required this.getToken,
  });

  final Map<String, dynamic> lutron;
  final VoidCallback onChanged;
  final Future<String?> Function() getToken;

  @override
  State<_LutronInstallerSection> createState() => _LutronInstallerSectionState();
}

class _LutronInstallerSectionState extends State<_LutronInstallerSection> {
  Timer? _poll;
  InstallerLutronStatus? _status;
  String? _statusErr;
  bool _reconnectBusy = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus(silent: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    final t = await widget.getToken();
    if (!mounted || t == null) return;
    try {
      final s = await fetchInstallerLutronStatus(t);
      if (!mounted) return;
      setState(() {
        _status = s;
        if (!silent) _statusErr = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _statusErr = '$e');
    }
  }

  Future<void> _reconnect() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = await widget.getToken();
    if (!context.mounted || t == null) return;
    setState(() => _reconnectBusy = true);
    try {
      await postInstallerLutronReconnect(t);
      if (!context.mounted) return;
      await _refreshStatus();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Lutron opnieuw verbonden.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      await _refreshStatus();
    } finally {
      if (mounted) setState(() => _reconnectBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: _status == null
                          ? 'Status wordt geladen?'
                          : (_status!.connected && _status!.loggedIn
                              ? 'Telnet verbonden'
                              : 'Geen telnet-verbinding'),
                      child: Icon(
                        Icons.circle,
                        size: 22,
                        color: _status == null
                            ? Colors.grey.shade400
                            : (_status!.connected && _status!.loggedIn
                                ? Colors.green.shade600
                                : Colors.grey.shade500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Telnet-verbinding',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _status == null
                                ? (_statusErr ?? 'Status laden?')
                                : _status!.connected
                                    ? (_status!.loggedIn
                                        ? 'Verbonden met ${_status!.host}:${_status!.port}'
                                        : 'Verbonden, login? (${_status!.host})')
                                    : 'Niet verbonden ? ${_status!.host.isNotEmpty ? "${_status!.host}:${_status!.port}" : "host nog niet geconfigureerd"}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _reconnectBusy ? null : _reconnect,
                      icon: _reconnectBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sync, size: 20),
                      label: const Text('Opnieuw verbinden'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Zet telnet aan, vul IP-adres, username en password in. Bij lampen/zonwering kies je het zone-nummer uit het Lutron integration report.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _LutronForm(lutron: widget.lutron, onChanged: widget.onChanged),
        ),
      ],
    );
  }
}

class _LutronForm extends StatelessWidget {
  const _LutronForm({required this.lutron, required this.onChanged});

  final Map<String, dynamic> lutron;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final tel = lutron['telnet'];
    Map<String, dynamic> telm;
    if (tel is Map<String, dynamic>) {
      telm = tel;
    } else {
      telm = <String, dynamic>{
        'enabled': false,
        'host': '',
        'port': 23,
        'username': '',
        'password': '',
        'postLoginCommands': <String>['#MONITORING,3,1'],
      };
      lutron['telnet'] = telm;
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Lutron QSX/QS Processor', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Centrale koppeling voor alle Lutron-gestuurde lampen en zonwering. '
          'Vul het IP-adres van de QSX/QS processor in, username en password. '
          'Integration ID?s vul je per apparaat in de kamer in.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Telnet ingeschakeld'),
          value: telm['enabled'] == true,
          onChanged: (v) {
            telm['enabled'] = v;
            onChanged();
          },
        ),
        _BoundStrField(
          'host',
          telm,
          onChanged,
          labelOverride: 'IP-adres (verplicht)',
          hintText: 'bijv. 192.168.1.50 (IP van de QSX/QS processor)',
        ),
        _BoundStrField('port', telm, onChanged,
            number: true,
            labelOverride: 'Poort (standaard 23, optioneel)'),
        _BoundStrField('bridgeHost', lutron, onChanged,
            labelOverride: 'bridgeHost (fallback)',
            hintText: 'Optioneel als host leeg is',
            emptyMeansRemove: true),
        _BoundStrField('username', telm, onChanged, emptyMeansRemove: true),
        _BoundStrField(
          'password',
          telm,
          onChanged,
          labelOverride: 'Wachtwoord',
          hintText: 'Leeg laten = bestaande hash behouden bij opslaan',
          emptyMeansRemove: true,
        ),
        const SizedBox(height: 16),
        LutronButtonToKnxListEditor(
          parent: lutron,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _KnxForm extends StatelessWidget {
  const _KnxForm({
    required this.knx,
    required this.onChanged,
    required this.onImport,
    required this.onImportInfo,
  });
  final Map<String, dynamic> knx;
  final VoidCallback onChanged;
  final VoidCallback onImport;
  final VoidCallback onImportInfo;

  @override
  Widget build(BuildContext context) {
    final enabled = knx['enabled'] != false;
    final gw = knx['gateway'];
    Map<String, dynamic> gwm;
    if (gw is Map<String, dynamic>) {
      gwm = gw;
    } else {
      gwm = {};
      knx['gateway'] = gwm;
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('KNX', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        // ?? Enabled toggle ??????????????????????????????????????????
        SwitchListTile(
          title: const Text('KNX ingeschakeld'),
          subtitle: const Text(
            'Schakel uit als er geen KNX-bus aanwezig is. '
            'De app start dan direct op zonder verbindingspogingen.',
          ),
          value: enabled,
          onChanged: (v) {
            knx['enabled'] = v;
            onChanged();
          },
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(height: 24),
        if (enabled) ...[
          Text('Gateway', style: Theme.of(context).textTheme.titleSmall),
          _BoundStrField('host', gwm, onChanged),
          _BoundStrField('port', gwm, onChanged, number: true),
          _DropdownField(
            label: 'mode',
            value: gwm['mode'] as String? ?? 'tunneling',
            options: const ['tunneling', 'routing'],
            onChanged: (v) {
              gwm['mode'] = v;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          _BoundStrField('physicalAddress', knx, onChanged),
          const Divider(height: 32),
          Text('Import', style: Theme.of(context).textTheme.titleSmall),
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Importeer uit KNX (.xml)'),
              subtitle: const Text(
                'Maak verdiepingen, ruimtes en apparaten aan uit een '
                'Group Address XML (ETS-export of Archie Groepsadressentool).',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Uitleg KNX-import',
                onPressed: onImportInfo,
              ),
              onTap: onImport,
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: Colors.grey),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'KNX is uitgeschakeld. Schakel in om de gateway-instellingen te configureren.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MapStringForm extends StatelessWidget {
  const _MapStringForm({
    required this.title,
    required this.values,
    required this.keys,
    required this.onChanged,
    this.numericKeys = const {},
    this.onDelete,
    this.headerActions,
  });
  final String title;
  final Map<String, dynamic> values;
  final List<String> keys;
  final Set<String> numericKeys;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  final Widget? headerActions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (headerActions != null) ...[
          headerActions!,
          const SizedBox(height: 8),
        ],
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        for (final k in keys)
          if (values.containsKey(k) || k == 'icon' || k == 'cover' || k == 'order')
            _BoundStrField(
              k,
              values,
              onChanged,
              number: numericKeys.contains(k),
            ),
        if (onDelete != null) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text('$title verwijderen'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ],
    );
  }
}

class _BoundStrField extends StatefulWidget {
  const _BoundStrField(
    this.keyName,
    this.map,
    this.onNotify, {
    super.key,
    this.number = false,
    this.labelOverride,
    this.maxLines = 1,
    this.hintText,
    this.emptyMeansRemove = false,
    this.gaSearch = false,
    this.gaDptHint,
  });
  final String keyName;
  final Map<String, dynamic> map;
  final VoidCallback onNotify;
  final bool number;
  final String? labelOverride;
  final int maxLines;
  final String? hintText;
  /// Voor optionele tekstvelden: leeg wissen verwijdert de sleutel uit JSON.
  final bool emptyMeansRemove;
  /// Toont een zoekknop die het geïmporteerde GA-adres opzoekt op naam/adres,
  /// en toont de bijbehorende groepsadresnaam onder het veld.
  final bool gaSearch;
  /// DPT-hint (bv. "DPT1.001") waarmee passende adressen bovenaan komen.
  final String? gaDptHint;

  @override
  State<_BoundStrField> createState() => _BoundStrFieldState();
}

class _BoundStrFieldState extends State<_BoundStrField> {
  late TextEditingController _c;

  String _initialText() {
    final v = widget.map[widget.keyName];
    if (v == null) return '';
    if (widget.number && v is num) return '$v';
    return '$v';
  }

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _initialText());
  }

  @override
  void didUpdateWidget(_BoundStrField old) {
    super.didUpdateWidget(old);
    if (old.map[widget.keyName] != widget.map[widget.keyName]) {
      _c.text = _initialText();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Auto-detect GA fields (keyName `ga` or a "Groepsadres" label) so every
  /// device GA input gets the search picker, in addition to explicit gaSearch.
  bool get _gaSearchEnabled {
    if (widget.gaSearch) return true;
    if (widget.keyName == 'ga') return true;
    final l = widget.labelOverride?.toLowerCase() ?? '';
    return l.startsWith('groepsadres') || l.startsWith('groepadres');
  }

  Future<void> _pickGa() async {
    final addr = await showGaSearchDialog(context, dptHint: widget.gaDptHint);
    if (addr == null || !mounted) return;
    _c.text = addr;
    widget.map[widget.keyName] = addr;
    widget.onNotify();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final gaSearch = _gaSearchEnabled;
    final resolvedName = gaSearch && _c.text.trim().isNotEmpty
        ? KnxGaCatalog.instance.nameFor(_c.text)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c,
        decoration: InputDecoration(
          labelText: widget.labelOverride ?? widget.keyName,
          hintText: widget.hintText,
          helperText: resolvedName,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          alignLabelWithHint: widget.maxLines > 1,
          suffixIcon: gaSearch
              ? IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Groepsadres zoeken',
                  onPressed: _pickGa,
                )
              : null,
        ),
        keyboardType: widget.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (widget.maxLines > 1
                ? TextInputType.multiline
                : TextInputType.url),
        maxLines: widget.maxLines,
        inputFormatters: widget.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]'))]
            : null,
        onChanged: (s) {
          if (widget.number) {
            if (s.isEmpty) {
              widget.map.remove(widget.keyName);
            } else if (widget.keyName == 'order' ||
                widget.keyName == 'port' ||
                widget.keyName == 'pulseMs' ||
                widget.keyName == 'lutronIntegrationId' ||
                widget.keyName == 'lutronSlatIntegrationId') {
              widget.map[widget.keyName] =
                  int.tryParse(s) ?? widget.map[widget.keyName];
            } else {
              widget.map[widget.keyName] = double.tryParse(s) ?? widget.map[widget.keyName];
            }
          } else {
            if (widget.emptyMeansRemove && s.trim().isEmpty) {
              widget.map.remove(widget.keyName);
            } else {
              widget.map[widget.keyName] = s;
            }
          }
          widget.onNotify();
          if (gaSearch) setState(() {});
        },
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SonosProbeCard extends StatefulWidget {
  const _SonosProbeCard({required this.device, required this.getToken});

  final Map<String, dynamic> device;
  final Future<String?> Function() getToken;

  @override
  State<_SonosProbeCard> createState() => _SonosProbeCardState();
}

class _SonosProbeCardState extends State<_SonosProbeCard> {
  bool _busy = false;
  String? _lastResult;

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = await widget.getToken();
    if (!context.mounted || t == null) return;
    final sonos = widget.device['sonos'];
    String? host;
    var port = 1400;
    if (sonos is Map<String, dynamic>) {
      final h = sonos['host'];
      if (h is String) host = h;
      if (h != null && h is! String) host = '$h';
      final pr = sonos['port'];
      if (pr is int) {
        port = pr;
      } else if (pr != null) {
        port = int.tryParse('$pr') ?? 1400;
      }
    }
    if (host == null || host.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vul eerst het IP-adres (host) in.')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final r = await postInstallerSonosProbe(t, host: host.trim(), port: port);
      if (!context.mounted) return;
      final okMsg =
          'Sonos bereikbaar: ${r.zoneName ?? "zone"} ? ${r.state ?? "?"}';
      final failMsg = 'Sonos: ${r.error ?? "onbekende fout"}';
      setState(() {
        _lastResult = r.ok ? okMsg : failMsg;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(r.ok ? okMsg : failMsg),
          backgroundColor: r.ok ? null : Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        setState(() => _lastResult = '$e');
        messenger.showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verbinding', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speaker_outlined, size: 20),
            label: const Text('Test Sonos (UPnP / poort 1400)'),
          ),
          if (_lastResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _lastResult!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Tip: alleen het IP van deze Sonos-zone (of de coordinator van '
              'de groep). Firewall: TCP 1400 van deze server naar de speaker. '
              'Na IP-wijziging: Opslaan zodat de driver opnieuw wordt aangemaakt.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Installateur: type zonwering / icoon in klant-app.
class _ShadingSubtypeSection extends StatelessWidget {
  const _ShadingSubtypeSection({
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final current = ShadingSubtype.fromJson(device['subtype'] as String?);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type zonwering (icoon)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Bepaalt het icoon, de ondertitel en de bedieningsstijl '
            '(open/dicht vs. omhoog/omlaag) in de klant-app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final st in ShadingSubtype.values)
                _ShadingSubtypeChip(
                  subtype: st,
                  selected: st == current,
                  onTap: () {
                    device['subtype'] = st.configValue;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShadingSubtypeChip extends StatelessWidget {
  const _ShadingSubtypeChip({
    required this.subtype,
    required this.selected,
    required this.onTap,
  });

  final ShadingSubtype subtype;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadingSubtypeGlyph(
                subtype: subtype,
                size: 28,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                subtype.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? scheme.onPrimaryContainer : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Installateur: welke zonwering-bediening in de klant-app zichtbaar is.
class _ShadingUiSection extends StatelessWidget {
  const _ShadingUiSection({
    required this.device,
    required this.onChanged,
    this.title = 'Zichtbare bediening (klant-app)',
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;
  final String title;

  Map<String, dynamic> _uiMap() => Map<String, dynamic>.from(
        (device['shadingUi'] as Map?)?.cast<String, dynamic>() ?? {},
      );

  void _setBool(String key, bool value) {
    final m = _uiMap();
    m[key] = value;
    device['shadingUi'] = m;
    onChanged();
  }

  void _clearUi() {
    device.remove('shadingUi');
    onChanged();
  }

  bool _get(String key, bool def) {
    final m = device['shadingUi'] as Map?;
    if (m == null) return def;
    final v = m[key];
    if (v is bool) return v;
    return def;
  }

  @override
  Widget build(BuildContext context) {
    final ga = (device['ga'] as Map?)?.cast<String, dynamic>() ?? {};
    final hasPos = ga['position'] != null;
    final hasStop = ga['stop_step'] != null;
    final hasSlat = ga['slat'] != null;
    final subtype = device['subtype'] as String? ?? 'blind';
    final isPositionActuator = device['type'] == 'position_actuator';
    final preferSlider = (device['slider'] as bool?) ?? true;
    final showSlatsLegacy = hasSlat &&
        (isPositionActuator || subtype == 'jalousie' || ga['slat'] != null);
    final defPosSlider = hasPos && preferSlider;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Laat leeg voor standaard (alles wat de GA-set toelaat). '
            'Lamellen-stap: ?5 % op slat-GA.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (hasPos)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Positie-slider'),
              value: _get('showPositionSlider', defPosSlider),
              onChanged: (v) => _setBool('showPositionSlider', v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rij knoppen onder positie-slider (omhoog/stop/omlaag)'),
            subtitle: const Text('Alleen als de positie-slider aan staat'),
            value: _get('showMoveButtonsUnderSlider', defPosSlider && hasPos),
            onChanged: (hasPos && _get('showPositionSlider', defPosSlider))
                ? (v) => _setBool('showMoveButtonsUnderSlider', v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Knop omhoog / open'),
            value: _get('showMoveUp', true),
            onChanged: (v) => _setBool('showMoveUp', v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Knop stop'),
            subtitle: hasStop
                ? null
                : const Text('Geen stop_step-GA in config'),
            value: _get('showMoveStop', hasStop),
            onChanged: hasStop ? (v) => _setBool('showMoveStop', v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Knop omlaag / dicht'),
            value: _get('showMoveDown', true),
            onChanged: (v) => _setBool('showMoveDown', v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lamellen-slider'),
            value: _get('showSlatSlider', showSlatsLegacy),
            onChanged: showSlatsLegacy ? (v) => _setBool('showSlatSlider', v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lamellen stap (+ / ? 5 %)'),
            subtitle: hasSlat ? null : const Text('Geen slat-GA'),
            value: _get('showSlatStepButtons', false),
            onChanged: hasSlat ? (v) => _setBool('showSlatStepButtons', v) : null,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _clearUi,
              child: const Text('Herstel standaard (wis shadingUi)'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optioneel: vaste % banden per vlamstand (alleen zinvol bij weergave Percent).
class _FireplaceStepRangesSection extends StatelessWidget {
  const _FireplaceStepRangesSection({
    required this.flame,
    required this.onChanged,
  });

  final Map<String, dynamic> flame;
  final VoidCallback onChanged;

  List<Map<String, dynamic>> _mutableRanges() {
    final list = flame['stepRanges'];
    if (list is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map<String, dynamic>) {
        out.add(e);
      } else if (e is Map) {
        final c = Map<String, dynamic>.from(
            e.map((k, v) => MapEntry(k.toString(), v)));
        list[i] = c;
        out.add(c);
      }
    }
    return out;
  }

  void _setBandCount(int n) {
    var list = flame['stepRanges'];
    if (list is! List) {
      flame['stepRanges'] = <dynamic>[];
      list = flame['stepRanges'] as List;
    }
    while (list.length < n) {
      list.add(<String, dynamic>{'min': 0, 'max': 100});
    }
    while (list.length > n) {
      list.removeLast();
    }
    flame['steps'] = n;
  }

  @override
  Widget build(BuildContext context) {
    void touchSteps() {
      final r = flame['stepRanges'];
      if (r is List && r.length >= 2) {
        flame['steps'] = r.length;
      }
    }

    void notifyRows() {
      touchSteps();
      onChanged();
    }

    final parsed = parseFireplaceStepRanges(flame);
    final enabled = parsed != null && parsed.isNotEmpty;
    final rows = enabled ? _mutableRanges() : <Map<String, dynamic>>[];
    final err = enabled ? validateFireplaceStepRanges(rows) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Vlamstanden (percent)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Per stand: min?max % op de bus (terugmelding). Geen overlap: het '
          'maximum van stap n moet strikt kleiner zijn dan het minimum van stap n+1.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vaste percent-banden per stand'),
          subtitle: const Text('2?10 stappen; uit = ??n doorlopende schuifregelaar.'),
          value: enabled,
          onChanged: (v) {
            if (v) {
              flame['stepRanges'] = [
                <String, dynamic>{'min': 1, 'max': 33},
                <String, dynamic>{'min': 34, 'max': 66},
                <String, dynamic>{'min': 67, 'max': 100},
              ];
              flame['steps'] = 3;
            } else {
              flame.remove('stepRanges');
              flame.remove('steps');
            }
            onChanged();
          },
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Aantal stappen',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: rows.length.clamp(2, 10),
                items: [
                  for (var n = 2; n <= 10; n++)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) {
                  if (n == null) return;
                  _setBandCount(n);
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Percentage verbergen op knoppen'),
            subtitle: const Text(
                'Verberg het %-bereik als sublabel op de vlamstand-knoppen.'),
            value: flame['hideStepPercent'] == true,
            onChanged: (v) {
              if (v) {
                flame['hideStepPercent'] = true;
              } else {
                flame.remove('hideStepPercent');
              }
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            Text('Stap ${i + 1}', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            _BoundStrField(
              'label',
              rows[i],
              notifyRows,
              labelOverride: 'Naam van de stand (bijv. Laag)',
              emptyMeansRemove: true,
              key: ValueKey('fp-sr-lbl-$i-${rows.length}'),
            ),
            _BoundStrField(
              'min',
              rows[i],
              notifyRows,
              number: true,
              labelOverride: 'Minimum % (bus)',
              key: ValueKey('fp-sr-min-$i-${rows.length}'),
            ),
            _BoundStrField(
              'max',
              rows[i],
              notifyRows,
              number: true,
              labelOverride: 'Maximum % (bus)',
              key: ValueKey('fp-sr-max-$i-${rows.length}'),
            ),
            _BoundStrField(
              'write',
              rows[i],
              notifyRows,
              number: true,
              labelOverride: 'Schrijf-% (optioneel)',
              emptyMeansRemove: true,
              key: ValueKey('fp-sr-wr-$i-${rows.length}'),
            ),
            const SizedBox(height: 12),
          ],
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                err,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Openhaard: geen JSON — KNX-configurateur kiest werking en vult GA’s in.
enum _FireplaceOpMode {
  analogFlame,
  analogSwitchOnly,
  discretePulses,
  discretePulsesStatus,
}

_FireplaceOpMode _fireplaceReadMode(Map<String, dynamic> fp) {
  if (fp['controlMode'] == 'discrete') {
    if (fp['statusBits'] is Map) return _FireplaceOpMode.discretePulsesStatus;
    return _FireplaceOpMode.discretePulses;
  }
  if (fp['flame'] is Map) return _FireplaceOpMode.analogFlame;
  return _FireplaceOpMode.analogSwitchOnly;
}

void _fireplaceApplyMode(Map<String, dynamic> fp, _FireplaceOpMode mode) {
  switch (mode) {
    case _FireplaceOpMode.analogFlame:
      fp['controlMode'] = 'analog';
      fp.remove('discreteLevel');
      fp.remove('statusBits');
      final old = fp['flame'];
      final oldM = <String, dynamic>{};
      if (old is Map) {
        for (final e in old.entries) {
          oldM[e.key.toString()] = e.value;
        }
      }
      final flame = <String, dynamic>{
        'ga': '${oldM['ga'] ?? ''}'.trim(),
        'levelDisplay': (oldM['levelDisplay'] is String &&
                (oldM['levelDisplay'] as String).isNotEmpty)
            ? oldM['levelDisplay']
            : 'percent',
      };
      final st = oldM['statusGa'];
      if (st is String && st.trim().isNotEmpty) {
        flame['statusGa'] = st.trim();
      }
      final steps = oldM['steps'];
      if (steps is int && steps >= 2 && steps <= 10) {
        flame['steps'] = steps;
      } else if (steps is num && steps >= 2 && steps <= 10) {
        flame['steps'] = steps.round();
      }
      fp['flame'] = flame;
      break;
    case _FireplaceOpMode.analogSwitchOnly:
      fp['controlMode'] = 'analog';
      fp.remove('discreteLevel');
      fp.remove('statusBits');
      fp.remove('flame');
      break;
    case _FireplaceOpMode.discretePulses:
      fp['controlMode'] = 'discrete';
      fp.remove('flame');
      fp.remove('statusBits');
      fp['discreteLevel'] ??= <String, dynamic>{};
      break;
    case _FireplaceOpMode.discretePulsesStatus:
      fp['controlMode'] = 'discrete';
      fp.remove('flame');
      fp['discreteLevel'] ??= <String, dynamic>{};
      fp['statusBits'] ??= <String, dynamic>{};
      break;
  }
}

Map<String, dynamic> _ensureFireplaceMap(Map<String, dynamic> device) {
  final v = device['fireplace'];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    final c = Map<String, dynamic>.from(
        v.map((k, val) => MapEntry(k.toString(), val)));
    device['fireplace'] = c;
    return c;
  }
  final m = <String, dynamic>{
    'controlMode': 'analog',
    'onOff': <String, dynamic>{'ga': ''},
  };
  device['fireplace'] = m;
  return m;
}

Map<String, dynamic> _ensureOnOff(Map<String, dynamic> fp) {
  final o = fp['onOff'];
  if (o is Map<String, dynamic>) return o;
  if (o is Map) {
    final c = Map<String, dynamic>.from(
        o.map((k, val) => MapEntry(k.toString(), val)));
    fp['onOff'] = c;
    return c;
  }
  final m = <String, dynamic>{'ga': ''};
  fp['onOff'] = m;
  return m;
}

Map<String, dynamic> _ensureFlame(Map<String, dynamic> fp) {
  final f = fp['flame'];
  if (f is Map<String, dynamic>) return f;
  if (f is Map) {
    final c = Map<String, dynamic>.from(
        f.map((k, val) => MapEntry(k.toString(), val)));
    fp['flame'] = c;
    return c;
  }
  final m = <String, dynamic>{
    'ga': '',
    'levelDisplay': 'percent',
  };
  fp['flame'] = m;
  return m;
}

Map<String, dynamic> _ensureDiscreteLevel(Map<String, dynamic> fp) {
  final d = fp['discreteLevel'];
  if (d is Map<String, dynamic>) return d;
  if (d is Map) {
    final c = Map<String, dynamic>.from(
        d.map((k, val) => MapEntry(k.toString(), val)));
    fp['discreteLevel'] = c;
    return c;
  }
  final m = <String, dynamic>{};
  fp['discreteLevel'] = m;
  return m;
}

Map<String, dynamic> _ensurePulseChannel(
    Map<String, dynamic> discrete, String key) {
  final x = discrete[key];
  if (x is Map<String, dynamic>) return x;
  if (x is Map) {
    final c = Map<String, dynamic>.from(
        x.map((k, val) => MapEntry(k.toString(), val)));
    discrete[key] = c;
    return c;
  }
  final m = <String, dynamic>{'ga': ''};
  discrete[key] = m;
  return m;
}

Map<String, dynamic> _ensureStatusBits(Map<String, dynamic> fp) {
  final d = fp['statusBits'];
  if (d is Map<String, dynamic>) return d;
  if (d is Map) {
    final c = Map<String, dynamic>.from(
        d.map((k, val) => MapEntry(k.toString(), val)));
    fp['statusBits'] = c;
    return c;
  }
  final m = <String, dynamic>{};
  fp['statusBits'] = m;
  return m;
}

Map<String, dynamic> _ensureStatusBitGa(
    Map<String, dynamic> statusBits, String key) {
  final x = statusBits[key];
  if (x is Map<String, dynamic>) return x;
  if (x is Map) {
    final c = Map<String, dynamic>.from(
        x.map((k, val) => MapEntry(k.toString(), val)));
    statusBits[key] = c;
    return c;
  }
  final m = <String, dynamic>{'ga': ''};
  statusBits[key] = m;
  return m;
}

class _FireplaceInstallerSection extends StatelessWidget {
  const _FireplaceInstallerSection({
    super.key,
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fp = _ensureFireplaceMap(device);
    final mode = _fireplaceReadMode(fp);
    final onOff = _ensureOnOff(fp);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Openhaard (KNX)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Kies hoe de haard op de bus zit. Vul groepsadressen in (vorm x/y/z). '
            'Geen programmeerwerk ? alleen configureren.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_FireplaceOpMode>(
            key: ValueKey('fp-mode-${device['id']}-$mode'),
            decoration: const InputDecoration(
              labelText: 'Werking',
              border: OutlineInputBorder(),
            ),
            initialValue: mode,
            items: const [
              DropdownMenuItem(
                value: _FireplaceOpMode.analogFlame,
                child: Text('Bit + byte (aan/uit + vlam)'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.analogSwitchOnly,
                child: Text('Alleen bit (aan/uit)'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.discretePulses,
                child: Text('4× puls (start/stop/omhoog/omlaag)'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.discretePulsesStatus,
                child: Text('4× puls + status (8 GA’s)'),
              ),
            ],
            onChanged: (_FireplaceOpMode? next) {
              if (next == null) return;
              _fireplaceApplyMode(fp, next);
              onChanged();
            },
          ),
          if (mode == _FireplaceOpMode.discretePulsesStatus) ...[
            const SizedBox(height: 8),
            Text(
              'Acht bit-GA’s: 4× pulscommando (waarde 1) + 4× statuscontact. '
              'Combinaties: Error+Fuel = Bijvullen, Working+Ready = Wachten/Koelen.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          Text('Aan / uit', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            mode == _FireplaceOpMode.discretePulsesStatus
                ? 'Schema-veld (bit). Bij deze modus komt de app-status uit de '
                    '4 statuscontacten hieronder; Working = aan.'
                : 'Schrijf-Groepadres (bit). Optioneel status voor terugmelding in de app.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _BoundStrField(
            'ga',
            onOff,
            onChanged,
            labelOverride: 'Groepsadres schrijven (bit)',
            hintText: 'bijv. 6/1/1',
            key: ValueKey('fp-on-${device['id']}-ga'),
          ),
          _BoundStrField(
            'statusGa',
            onOff,
            onChanged,
            labelOverride: 'Groepsadres status (bit, optioneel)',
            hintText: 'leeg = zelfde als schrijven',
            emptyMeansRemove: true,
            key: ValueKey('fp-on-${device['id']}-st'),
          ),
          if (mode == _FireplaceOpMode.analogFlame) ...[
            const SizedBox(height: 20),
            Text('Vlamsterkte (byte 0?100 % op de bus)',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'DPT5 op het schrijfadres; in de app kunt u kiezen of de schaal '
              'als procent of geschat als 0?10 V / 0?3 V getoond wordt.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final flame = _ensureFlame(fp);
                final ld = (flame['levelDisplay'] as String?) ?? 'percent';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BoundStrField(
                      'ga',
                      flame,
                      onChanged,
                      labelOverride: 'Groepsadres schrijven (byte 0?100 %)',
                      hintText: 'bijv. 6/2/1',
                      key: ValueKey('fp-fl-${device['id']}-ga'),
                    ),
                    _BoundStrField(
                      'statusGa',
                      flame,
                      onChanged,
                      labelOverride: 'Groepsadres status (byte, aanbevolen)',
                      hintText: 'bijv. 6/2/2',
                      emptyMeansRemove: true,
                      key: ValueKey('fp-fl-${device['id']}-st'),
                    ),
                    Builder(
                      builder: (context) {
                        final ldVal =
                            const {'percent', 'volt_10', 'volt_3'}.contains(ld)
                                ? ld
                                : 'percent';
                        return DropdownButtonFormField<String>(
                          key: ValueKey(
                              'fp-ld-${device['id']}-$ldVal-${flame['ga']}'),
                          decoration: const InputDecoration(
                            labelText: 'Weergave in de app',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: ldVal,
                          items: const [
                            DropdownMenuItem(
                              value: 'percent',
                              child: Text('Percent (0?100 %)'),
                            ),
                            DropdownMenuItem(
                              value: 'volt_10',
                              child: Text(
                                  'Labels 0?10 V (bus blijft 0?100 %)'),
                            ),
                            DropdownMenuItem(
                              value: 'volt_3',
                              child: Text(
                                  'Labels 0?3 V (bus blijft 0?100 %)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            flame['levelDisplay'] = v;
                            if (v != 'percent') {
                              flame.remove('stepRanges');
                              flame.remove('steps');
                            }
                            onChanged();
                          },
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Op de KNX-bus blijft de vlam altijd 0?100 % (DPT5.001), '
                        'tenzij u elders stappen gebruikt. Alleen de teksten in de '
                        'klant-app volgen de gekozen weergave.',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ),
                    if (ld == 'percent')
                      _FireplaceStepRangesSection(
                        flame: flame,
                        onChanged: onChanged,
                      ),
                  ],
                );
              },
            ),
          ],
          if (mode == _FireplaceOpMode.discretePulses ||
              mode == _FireplaceOpMode.discretePulsesStatus) ...[
            const SizedBox(height: 16),
            Text(
              mode == _FireplaceOpMode.discretePulsesStatus
                  ? 'Commando’s — per functie één bit-GA; de app stuurt kort waarde 1, daarna 0. Pulsduur standaard 250 ms.'
                  : 'Pulscontacten — per functie één bit-GA; de app stuurt alleen kort aan (1), daarna 0. Pulsduur standaard 250 ms.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final dl = _ensureDiscreteLevel(fp);
                final withStatus =
                    mode == _FireplaceOpMode.discretePulsesStatus;
                Widget row(String key, String title) {
                  final ch = _ensurePulseChannel(dl, key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.labelLarge),
                        _BoundStrField(
                          'ga',
                          ch,
                          onChanged,
                          labelOverride: 'Groepsadres (puls 1)',
                          key: ValueKey('fp-dl-${device['id']}-$key-ga'),
                        ),
                        _BoundStrField(
                          'pulseMs',
                          ch,
                          onChanged,
                          number: true,
                          labelOverride: 'Pulsduur (ms, optioneel)',
                          emptyMeansRemove: true,
                          key: ValueKey('fp-dl-${device['id']}-$key-ms'),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    row('on', withStatus ? '1 · Start' : 'Aanzetten'),
                    row('off', withStatus ? '2 · Stop' : 'Uitzetten'),
                    row('up', withStatus ? '3 · Omhoog' : 'Vlam hoger'),
                    row('down', withStatus ? '4 · Omlaag' : 'Vlam lager'),
                  ],
                );
              },
            ),
          ],
          if (mode == _FireplaceOpMode.discretePulsesStatus) ...[
            const SizedBox(height: 8),
            Text('Statuscontacten (bit)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Vier status-GA’s. Combinaties: Error+Fuel = Bijvullen, '
              'Working+Ready = Wachten / Koelen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final sb = _ensureStatusBits(fp);
                Widget statusRow(String key, String title) {
                  final ch = _ensureStatusBitGa(sb, key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.labelLarge),
                        _BoundStrField(
                          'ga',
                          ch,
                          onChanged,
                          labelOverride: 'Groepsadres (bit)',
                          key: ValueKey('fp-sb-${device['id']}-$key-ga'),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statusRow('error', '1 · Error (fout)'),
                    statusRow('fuel', '2 · Fuel (geen brandstof)'),
                    statusRow('working', '3 · Working (bezig)'),
                    statusRow('ready', '4 · Ready (gereed)'),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          Text('Optioneel: veiligheidsslot', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Één bit-GA: als deze aan staat, kan de app de haard niet starten.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              Map<String, dynamic> lockMap;
              final rawLock = fp['safetyLockout'];
              if (rawLock is Map<String, dynamic>) {
                lockMap = rawLock;
              } else if (rawLock is Map) {
                lockMap = Map<String, dynamic>.from(
                    rawLock.map((k, v) => MapEntry(k.toString(), v)));
                fp['safetyLockout'] = lockMap;
              } else {
                lockMap = <String, dynamic>{};
                fp['safetyLockout'] = lockMap;
              }
              return _BoundStrField(
                'ga',
                lockMap,
                onChanged,
                labelOverride: 'Groepsadres veiligheidsslot (leeg = uit)',
                emptyMeansRemove: true,
                key: ValueKey('fp-lock-${device['id']}'),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// KNX of Lutron per lamp/zonwering; bij Lutron alleen integration ID.
class _DeviceBusControlSection extends StatelessWidget {
  const _DeviceBusControlSection({
    required this.device,
    required this.onChanged,
    this.lutronOnly = false,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;
  /// Geen KNX/Lutron-keuze ? alleen Lutron output-ID (apparaat uit Lutron-menu).
  final bool lutronOnly;

  bool get _isLutron => device['control'] == 'lutron' || lutronOnly;

  void _setBus(String bus) {
    if (bus == 'lutron') {
      device['control'] = 'lutron';
      device.remove('lutronOutput');
      device['lutronIntegrationId'] ??= 1;
    } else {
      device.remove('control');
      device.remove('lutronIntegrationId');
      device.remove('lutronOutput');
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lutronOnly ? 'Lutron' : 'Besturing',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!lutronOnly) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'knx', label: Text('KNX')),
                ButtonSegment(value: 'lutron', label: Text('Lutron')),
              ],
              selected: {_isLutron ? 'lutron' : 'knx'},
              onSelectionChanged: (s) => _setBus(s.first),
            ),
          ],
          if (_isLutron) ...[
            if (lutronOnly) const SizedBox(height: 8),
            const SizedBox(height: 16),
            Text(
              'Lutron Zone-nummer (integration ID uit Lutron-software / integration report). '
              'Telnet staat onder Lutron QSX/QS Processor in de boom.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _BoundStrField(
              'lutronIntegrationId',
              device,
              onChanged,
              labelOverride: 'Zone-nummer (integration ID)',
              number: true,
            ),
            if (device['type'] == 'shading') ...[
              const SizedBox(height: 4),
              Text(
                'Voor jalousie/lamellen: vul ook het aparte zone-nummer voor lamelhoek in.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _BoundStrField(
                'lutronSlatIntegrationId',
                device,
                onChanged,
                labelOverride: 'Lamellen zone-nummer (optioneel)',
                number: true,
                emptyMeansRemove: true,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DeviceForm extends StatelessWidget {
  const _DeviceForm({
    required this.device,
    required this.onChanged,
    required this.onDelete,
    this.onCopy,
    this.onPaste,
    this.getInstallerToken,
  });
  final Map<String, dynamic> device;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final Future<String?> Function()? getInstallerToken;

  @override
  Widget build(BuildContext context) {
    final type = device['type'] as String? ?? '';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Apparaat ($type)',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (onCopy != null)
              IconButton(
                tooltip: 'Kopiëren (Ctrl+C)',
                icon: const Icon(Icons.copy_outlined),
                onPressed: onCopy,
              ),
            IconButton(
              tooltip: 'Plakken eronder (Ctrl+V)',
              icon: const Icon(Icons.content_paste_outlined),
              onPressed: onPaste,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BoundStrField('id', device, onChanged),
        _BoundStrField('name', device, onChanged),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Toon als favoriet op het dashboard'),
          subtitle: const Text(
            'Standaard-instelling voor alle gebruikers. '
            'Gebruikers kunnen dit daarna zelf aanpassen met de ster-knop.',
          ),
          value: device['favorite'] as bool? ?? false,
          onChanged: (v) {
            device['favorite'] = v;
            onChanged();
          },
        ),
        if (type == 'light_switch' || type == 'light_dimmer' || type == 'shading')
          _DeviceBusControlSection(
            device: device,
            onChanged: onChanged,
            lutronOnly: device['control'] == 'lutron' && !_deviceHasKnxGa(device),
          ),
        if (type == 'position_actuator' ||
            (type == 'shading' && device['control'] != 'lutron'))
          _ShadingLikeGaSection(device: device, onChanged: onChanged)
        else if ((type == 'light_switch' ||
                type == 'light_dimmer' ||
                type == 'rgbw_ww') &&
            device['control'] != 'lutron')
          _GaSection(device: device, onChanged: onChanged),
        if (type == 'climate')
          ClimateInstallerSection(
            key: ValueKey('${device['id']}-climate'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'rgbw_ww')
          RgbwWwInstallerSection(
            key: ValueKey('${device['id']}-rgbwWw'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'shading') ...[
          _ShadingSubtypeSection(device: device, onChanged: onChanged),
          _ShadingUiSection(device: device, onChanged: onChanged),
        ],
        if (type == 'position_actuator')
          _ShadingUiSection(
            device: device,
            onChanged: onChanged,
            title: 'Bediening in klant-app',
          ),
        if (type == 'media_sonos') ...[
          _NestedStringFields(
            label: 'Sonos',
            jsonKey: 'sonos',
            device: device,
            fields: const ['host', 'room'],
            intFields: const {'port'},
            onChanged: onChanged,
          ),
          if (getInstallerToken != null)
            _SonosProbeCard(device: device, getToken: getInstallerToken!),
        ],
        if (type == 'media_bluesound')
          _NestedStringFields(
            label: 'Bluesound',
            jsonKey: 'bluesound',
            device: device,
            fields: const ['host'],
            intFields: const {'port'},
            onChanged: onChanged,
          ),
        if (type == 'camera') ...[
          _CameraInstallerSection(device: device, onChanged: onChanged),
          _RtspDeviceExtra(
            device: device,
            nestedKey: 'camera',
            includeRepublish: true,
            onChanged: onChanged,
          ),
        ],
        if (type == 'intercom') ...[
          _IntercomKnxExtras(device: device, onChanged: onChanged),
          _NestedStringFields(
            label: 'Intercom ? stream-URL?s',
            jsonKey: 'intercom',
            device: device,
            fields: const ['rtsp', 'path', 'aspect'],
            onChanged: onChanged,
          ),
          _RtspDeviceExtra(
            device: device,
            nestedKey: 'intercom',
            includeRepublish: false,
            onChanged: onChanged,
          ),
        ],
        if (type == 'fireplace')
          _FireplaceInstallerSection(
            key: ValueKey('${device['id']}-fireplace'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'ac')
          AcInstallerSection(
            key: ValueKey('${device['id']}-ac'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'fan')
          FanInstallerSection(
            key: ValueKey('${device['id']}-fan'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'universal')
          UniversalPanelInstallerSection(
            key: ValueKey('${device['id']}-universal'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'wtw')
          WtwInstallerSection(
            key: ValueKey('${device['id']}-wtw'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'melding')
          MeldingInstallerSection(
            key: ValueKey('${device['id']}-melding'),
            device: device,
            onChanged: onChanged,
          ),
        if (type == 'lutron_homeworks') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Telnet en de centrale Lutron-koppeling stel je in via Lutron QSX/QS Processor '
              'in de boom. Hier kun je optioneel extra keypad?KNX mappings zetten.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          LutronButtonToKnxListEditor(
            parent: _ensureChildMap(device, 'lutronHomeworks'),
            onChanged: onChanged,
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Apparaat verwijderen'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }
}

/// Camera: RTSP + optional preview stream; auto profile for live.
class _CameraInstallerSection extends ConsumerStatefulWidget {
  const _CameraInstallerSection({
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CameraInstallerSection> createState() =>
      _CameraInstallerSectionState();
}

class _CameraInstallerSectionState extends ConsumerState<_CameraInstallerSection> {
  Map<String, dynamic> get _m {
    final o = widget.device['camera'];
    if (o is Map<String, dynamic>) return o;
    final m = <String, dynamic>{};
    widget.device['camera'] = m;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Camera-stream',
            style: Theme.of(context).textTheme.titleSmall),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'RTSP van camera, recorder/NVR of Surveillance Station (deel stream-pad). '
            'Werkt hetzelfde als in VLC — plak de volledige url incl. login.',
            style: hintStyle,
          ),
        ),
        _BoundStrField(
          'rtsp',
          m,
          widget.onChanged,
          labelOverride: 'Live RTSP-URL (hoofdstream)',
          maxLines: 4,
          hintText: 'rtsp://syno:…@192.168.1.22:554/Sms=8.unicast',
        ),
        const SizedBox(height: 8),
        _BoundStrField(
          'previewRtsp',
          m,
          widget.onChanged,
          labelOverride: 'Preview RTSP (optioneel, snellere thumbnails)',
          maxLines: 3,
          hintText: 'Substream / lage kwaliteit — leeg = zelfde als live',
          emptyMeansRemove: true,
        ),
        const SizedBox(height: 8),
        _CameraStreamProbePanel(
          rtsp: (m['rtsp'] as String?) ?? '',
          previewRtsp: (m['previewRtsp'] as String?) ?? '',
          codec: (m['codec'] as String?) ?? '',
          token: _installerToken(),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              'Optioneel ? meestal leeg laten',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Text(
              'Path, beeldverhouding, directe HLS',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Path = korte naam voor de mediaserver (go2rtc), niet het '
                  'camera-pad uit uw RTSP-link. Leeg = automatisch op basis van '
                  'dit apparaat.\n\n'
                  'Aspect = bijv. 16:9. Leeg = 16:9 in de app.\n\n'
                  'Directe HLS = alleen als u al een werkende .m3u8-url heeft '
                  'zonder deze server.',
                  style: hintStyle,
                ),
              ),
              _BoundStrField(
                'path',
                m,
                widget.onChanged,
                labelOverride: 'Path (streamnaam server)',
                hintText: 'Leeg laten',
                emptyMeansRemove: true,
              ),
              _BoundStrField(
                'aspect',
                m,
                widget.onChanged,
                labelOverride: 'Aspect',
                hintText: '16:9',
                emptyMeansRemove: true,
              ),
              _BoundStrField(
                'directHls',
                m,
                widget.onChanged,
                labelOverride: 'Directe HLS-URL',
                maxLines: 2,
                emptyMeansRemove: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _installerToken() {
    final auth = ref.read(authProvider);
    if (auth.token != null && auth.isAdmin) return auth.token;
    return ref.read(installerAuthProvider).token;
  }
}

class _CameraStreamProbePanel extends StatefulWidget {
  const _CameraStreamProbePanel({
    required this.rtsp,
    required this.previewRtsp,
    required this.codec,
    required this.token,
  });

  final String rtsp;
  final String previewRtsp;
  final String codec;
  final String? token;

  @override
  State<_CameraStreamProbePanel> createState() =>
      _CameraStreamProbePanelState();
}

class _CameraStreamProbePanelState extends State<_CameraStreamProbePanel> {
  InstallerCameraProbeSummary? _result;
  String? _err;
  bool _busy = false;

  Future<void> _run() async {
    final token = widget.token;
    if (token == null) return;
    if (widget.rtsp.trim().isEmpty) {
      setState(() => _err = 'Vul eerst een live RTSP-URL in');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
      _result = null;
    });
    try {
      final r = await postInstallerCameraProbe(
        token,
        rtsp: widget.rtsp.trim(),
        previewRtsp: widget.previewRtsp.trim(),
        codec: widget.codec.trim(),
      );
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy || widget.token == null ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.videocam_outlined, size: 18),
          label: const Text('Stream testen'),
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_err!, style: TextStyle(color: Colors.red.shade700)),
          ),
        if (r != null) ...[
          const SizedBox(height: 8),
          _probeLine('Live', r.live),
          if (r.preview != null) _probeLine('Preview', r.preview!),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Aanbevolen: FFmpeg live=${r.recommended.go2rtcFfmpeg}, '
              'alleen video=${r.recommended.go2rtcVideoOnly}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _probeLine(String label, InstallerCameraProbeResult p) {
    final ok = p.ok;
    final res = p.width != null && p.height != null
        ? '${p.width}×${p.height}'
        : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: ${ok ? "OK" : "mislukt"} · ${p.latencyMs}ms · $res · '
        '${p.profileLabel}${p.error != null ? " — ${p.error}" : ""}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ok ? null : Colors.red.shade700,
            ),
      ),
    );
  }
}

class _RtspDeviceExtra extends StatelessWidget {
  const _RtspDeviceExtra({
    required this.device,
    required this.nestedKey,
    required this.includeRepublish,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final String nestedKey;
  final bool includeRepublish;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = device[nestedKey];
    if (o is! Map<String, dynamic>) return const SizedBox.shrink();
    final m = o;
    final codecVal = m['codec'];
    final codecStr = codecVal is String ? codecVal : '';
    final hasCodec = codecStr.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
            nestedKey == 'camera'
                ? 'Geavanceerd (meestal automatisch)'
                : 'Encoder & extra stream-opties',
            style: Theme.of(context).textTheme.titleSmall),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: hasCodec ? codecStr : '__auto__',
            decoration: const InputDecoration(
              labelText: 'Video codec',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: '__auto__',
                child: Text('Standaard'),
              ),
              DropdownMenuItem(value: 'h264', child: Text('H.264')),
              DropdownMenuItem(value: 'h265', child: Text('H.265')),
            ],
            onChanged: (v) {
              if (v == null || v == '__auto__') {
                m.remove('codec');
              } else {
                m['codec'] = v;
              }
              onChanged();
            },
          ),
        ),
        if (includeRepublish)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stream opnieuw publiceren (go2rtc)'),
            subtitle: const Text(
                'Standaard aan. Zet uit alleen als go2rtc deze stream niet mag opnemen.'),
            value: m['republish'] != false,
            onChanged: (v) {
              if (v) {
                m.remove('republish');
              } else {
                m['republish'] = false;
              }
              onChanged();
            },
          ),
        if (nestedKey == 'camera')
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Handmatige live-instellingen'),
              subtitle: const Text(
                  'Leeg = automatisch op basis van RTSP-url (Synology/NVR/camera)'),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Forceer FFmpeg voor live'),
                  subtitle: const Text(
                      'Transcodeert naar H.264 met korte GOP — vloeiender op tablets'),
                  value: m['go2rtcFfmpeg'] == true,
                  onChanged: (v) {
                    if (v) {
                      m['go2rtcFfmpeg'] = true;
                    } else {
                      m.remove('go2rtcFfmpeg');
                    }
                    onChanged();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Forceer: geen audio op RTSP'),
                  subtitle: const Text(
                      'Helpt als WebRTC geen beeld geeft door audio op de stream'),
                  value: m['go2rtcVideoOnly'] == true,
                  onChanged: (v) {
                    if (v) {
                      m['go2rtcVideoOnly'] = true;
                    } else {
                      m.remove('go2rtcVideoOnly');
                    }
                    onChanged();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('go2rtc: backchannel uit (#backchannel=0)'),
                  subtitle: const Text(
                      'Alleen bij glitchy NVR two-way-audio op RTSP'),
                  value: m['go2rtcBackchannel0'] == true,
                  onChanged: (v) {
                    if (v) {
                      m['go2rtcBackchannel0'] = true;
                    } else {
                      m.remove('go2rtcBackchannel0');
                    }
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        _SourcesCommaField(
          key: ValueKey('${device['id']}-$nestedKey-sources'),
          map: m,
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Tip: gebruikersnaam en wachtwoord voor RTSP kunnen in de URL: '
            'rtsp://gebruiker:wachtwoord@192.168.1.10/stream',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SourcesCommaField extends StatefulWidget {
  const _SourcesCommaField({super.key, required this.map, required this.onChanged});

  final Map<String, dynamic> map;
  final VoidCallback onChanged;

  @override
  State<_SourcesCommaField> createState() => _SourcesCommaFieldState();
}

class _SourcesCommaFieldState extends State<_SourcesCommaField> {
  late TextEditingController _c;

  @override
  void initState() {
    super.initState();
    final src = widget.map['sources'];
    final t = src is List ? src.map((e) => '$e').join(', ') : '';
    _c = TextEditingController(text: t);
  }

  @override
  void didUpdateWidget(_SourcesCommaField old) {
    super.didUpdateWidget(old);
    if (old.map != widget.map) {
      final src = widget.map['sources'];
      final t = src is List ? src.map((e) => '$e').join(', ') : '';
      if (_c.text != t) _c.text = t;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _commit(String s) {
    final parts = s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      widget.map.remove('sources');
    } else {
      widget.map['sources'] = parts;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      decoration: const InputDecoration(
        labelText: 'Extra bronnen (comma-gescheiden URL?s)',
        border: OutlineInputBorder(),
        helperText: 'Optioneel: alternatieve streams. Sluit af met Enter om op te slaan.',
      ),
      onSubmitted: _commit,
      onEditingComplete: () => _commit(_c.text),
    );
  }
}

class _IntercomKnxExtras extends StatelessWidget {
  const _IntercomKnxExtras({required this.device, required this.onChanged});

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = device['intercom'];
    if (o is! Map<String, dynamic>) return const SizedBox.shrink();
    final doorbell = _ensureChildMap(o, 'doorbell');
    final release = _ensureChildMap(o, 'release');
    final doorbird = _ensureChildMap(o, 'doorbird');
    final sip = _ensureChildMap(o, 'sip');
    final kind = (o['kind'] as String?) ?? 'doorbird';
    final isSip = kind == 'sip';
    final isTwoN = kind == 'twoN';
    final doorMode = (o['releaseMode'] as String?) ?? 'knx';
    final doorViaDoorbird = doorMode == 'doorbird';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          isSip
              ? 'SIP-intercom: audio en video lopen via uw PBX (Asterisk/FreePBX). '
                  'De app registreert op de WebSocket van de server en toont inkomende oproepen. '
                  'Deuropen kan nog steeds via KNX of DoorBird-API (zie onder).'
              : isTwoN
                  ? '2N: gebruik meestal een SIP-trunk naar uw centrale; vul hieronder SIP in '
                      'of laat de stream-URL?s staan voor beeld naast het gesprek.'
                  : 'DoorBird: livebeeld en terugspreken kunnen via RTSP/go2rtc (hieronder); '
                      'deuropen via KNX of DoorBird HTTP.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 16),
        Text('Intercom-type', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text('Bron van het gesprek', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'doorbird',
              label: Text('DoorBird'),
              icon: Icon(Icons.videocam_outlined, size: 18),
            ),
            ButtonSegment<String>(
              value: 'twoN',
              label: Text('2N'),
              icon: Icon(Icons.apartment_outlined, size: 18),
            ),
            ButtonSegment<String>(
              value: 'sip',
              label: Text('SIP'),
              icon: Icon(Icons.dialer_sip, size: 18),
            ),
          ],
          emptySelectionAllowed: false,
          showSelectedIcon: false,
          selected: {kind},
          onSelectionChanged: (Set<String> next) {
            if (next.isEmpty) return;
            o['kind'] = next.first;
            onChanged();
          },
        ),
        if (isSip) ...[
          const SizedBox(height: 16),
          Text('SIP-registratie (WebSocket)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _BoundStrField(
            'webSocketUrl',
            sip,
            onChanged,
            labelOverride: 'WebSocket-URL (wss://?)',
            key: ValueKey('sip-ws-${device['id']}'),
          ),
          _BoundStrField(
            'uri',
            sip,
            onChanged,
            labelOverride: 'SIP-URI (bijv. sip:1001@pbx.lan)',
            key: ValueKey('sip-uri-${device['id']}'),
          ),
          _BoundStrField(
            'authorizationUser',
            sip,
            onChanged,
            labelOverride: 'Auth-gebruiker (optioneel)',
            key: ValueKey('sip-auth-${device['id']}'),
          ),
          _BoundStrField(
            'password',
            sip,
            onChanged,
            labelOverride: 'SIP-wachtwoord',
            key: ValueKey('sip-pass-${device['id']}'),
          ),
          _BoundStrField(
            'displayName',
            sip,
            onChanged,
            labelOverride: 'Weergavenaam (optioneel)',
            key: ValueKey('sip-dn-${device['id']}'),
          ),
        ],
        const SizedBox(height: 20),
        Text('Deur / poort open (KNX is alleen hiervoor)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'knx',
              label: Text('KNX'),
              icon: Icon(Icons.hub_outlined, size: 18),
            ),
            ButtonSegment<String>(
              value: 'doorbird',
              label: Text('DoorBird API'),
              icon: Icon(Icons.lock_open, size: 18),
            ),
          ],
          emptySelectionAllowed: false,
          showSelectedIcon: false,
          selected: {doorMode},
          onSelectionChanged: (Set<String> next) {
            if (next.isEmpty) return;
            o['releaseMode'] = next.first;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        _BoundStrField(
          'ga',
          doorbell,
          onChanged,
          labelOverride: 'Deurbel KNX (optioneel, voor busmonitor)',
          key: ValueKey('db-${device['id']}'),
        ),
        if (!doorViaDoorbird) ...[
          _BoundStrField(
            'ga',
            release,
            onChanged,
            labelOverride: 'Deur open ? KNX schrijfadres',
            key: ValueKey('rel-ga-${device['id']}'),
          ),
          _BoundStrField(
            'pulseMs',
            release,
            onChanged,
            number: true,
            labelOverride: 'Deur open ? pulsduur (ms)',
            key: ValueKey('rel-pulse-${device['id']}'),
          ),
        ],
        if (doorViaDoorbird) ...[
          const SizedBox(height: 8),
          Text(
            'HTTP open-door (zelfde login als DoorBird-app indien van toepassing).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 8),
          _BoundStrField(
            'host',
            doorbird,
            onChanged,
            labelOverride: 'IP of hostname',
            key: ValueKey('dbird-host-${device['id']}'),
          ),
          _BoundStrField(
            'port',
            doorbird,
            onChanged,
            number: true,
            labelOverride: 'HTTP-poort (leeg = 80 of 443 bij TLS)',
            emptyMeansRemove: true,
            key: ValueKey('dbird-port-${device['id']}'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('HTTPS'),
            subtitle: const Text('Poort 443 standaard bij TLS.'),
            value: doorbird['useTls'] == true,
            onChanged: (v) {
              doorbird['useTls'] = v;
              onChanged();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zelfondertekend certificaat accepteren'),
            value: doorbird['insecureTls'] != false,
            onChanged: (v) {
              doorbird['insecureTls'] = v;
              onChanged();
            },
          ),
          _BoundStrField(
            'username',
            doorbird,
            onChanged,
            labelOverride: 'Gebruikersnaam',
            key: ValueKey('dbird-user-${device['id']}'),
          ),
          _BoundStrField(
            'password',
            doorbird,
            onChanged,
            labelOverride: 'Wachtwoord',
            key: ValueKey('dbird-pass-${device['id']}'),
          ),
          _BoundStrField(
            'relay',
            doorbird,
            onChanged,
            labelOverride: 'Relay r= (standaard 1)',
            key: ValueKey('dbird-relay-${device['id']}'),
          ),
        ],
        const SizedBox(height: 20),
        Text('Bel-webhook (DoorBird / 2N ring-notificatie)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configureer in DoorBird (Schedule ? HTTP(S)) of 2N (HTTP Automation):',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'http://<server>:4000/api/webhooks/ring/${device['id'] ?? '<id>'}?passcode=<code>',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Method: GET of POST. Gebruik dezelfde passcode als hieronder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _BoundStrField(
          'webhookPasscode',
          o,
          onChanged,
          labelOverride: 'Webhook passcode (optioneel)',
          hintText: 'Leeg = geen beveiliging (alleen voor intern LAN)',
          emptyMeansRemove: true,
          key: ValueKey('webhook-pc-${device['id']}'),
        ),
      ],
    );
  }
}

class _ShadingLikeGaSection extends StatelessWidget {
  const _ShadingLikeGaSection({
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  Map<String, dynamic> _gaMap() {
    final ga = device['ga'];
    if (ga is Map<String, dynamic>) return ga;
    final m = <String, dynamic>{};
    device['ga'] = m;
    return m;
  }

  static const _fields = <(String key, String label, bool optional)>[
    ('up_down', 'Omhoog / omlaag (schrijven)', false),
    ('stop_step', 'Stop / stap (schrijven)', true),
    ('position', 'Positie % (schrijven)', true),
    ('position_status', 'Positie % status (lezen)', true),
    ('slat', 'Lamellen / tilt (schrijven)', true),
    ('slat_status', 'Lamellen status (lezen)', true),
    ('moving', 'Beweging actief (lezen, DPT 1)', true),
  ];

  @override
  Widget build(BuildContext context) {
    final ga = _gaMap();
    final isPosition = device['type'] == 'position_actuator';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Groepadressen (jaloezie-object)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          isPosition
              ? 'Zelfde KNX-object als zonwering: percentage positie, '
                  'omhoog/omlaag/stop. Status-GA\'s zijn optioneel maar '
                  'aanbevolen voor live weergave in de app.'
              : 'KNX jaloezie / zonwering: schrijf- en leesadressen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final (fieldKey, label, optional) in _fields)
          _BoundStrField(
            fieldKey,
            ga,
            onChanged,
            key: ValueKey('ga-${device['id']}-$fieldKey'),
            labelOverride: optional ? '$label (optioneel)' : label,
            emptyMeansRemove: optional,
          ),
      ],
    );
  }
}

/// Expected DPT per ga role, used to float matching addresses to the top of
/// the GA search picker.
String? _gaDptHint(String role) {
  const m = {
    'switch': 'DPT1.001',
    'switch_status': 'DPT1.001',
    'dim_value': 'DPT5.001',
    'dim_status': 'DPT5.001',
    'up_down': 'DPT1.008',
    'stop_step': 'DPT1.007',
    'position': 'DPT5.001',
    'position_status': 'DPT5.001',
    'slat': 'DPT5.001',
    'slat_status': 'DPT5.001',
    'setpoint': 'DPT9.001',
    'setpoint_status': 'DPT9.001',
    'actual_temp': 'DPT9.001',
  };
  return m[role];
}

class _GaSection extends StatelessWidget {
  const _GaSection({required this.device, required this.onChanged});
  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ga = device['ga'];
    Map<String, dynamic> gam;
    if (ga is Map<String, dynamic>) {
      gam = ga;
    } else {
      gam = {};
      device['ga'] = gam;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Groepadressen', style: Theme.of(context).textTheme.titleSmall),
        for (final k in gam.keys.toList())
          _BoundStrField(
            k,
            gam,
            onChanged,
            key: ValueKey('ga-${device['id']}-$k'),
            gaSearch: true,
            gaDptHint: _gaDptHint(k),
          ),
        TextButton.icon(
          onPressed: () async {
            final role = await _prompt(context, 'Rol (bv. switch)');
            if (!context.mounted) return;
            final addr = await _prompt(context, 'GA (x/y/z)');
            if (!context.mounted) return;
            if (role != null &&
                role.isNotEmpty &&
                addr != null &&
                addr.isNotEmpty) {
              gam[role] = addr;
              onChanged();
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('GA-regel toevoegen'),
        ),
      ],
    );
  }

  static Future<String?> _prompt(BuildContext context, String label) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleer')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _NestedStringFields extends StatelessWidget {
  const _NestedStringFields({
    required this.label,
    required this.jsonKey,
    required this.device,
    required this.fields,
    required this.onChanged,
    this.intFields = const {},
  });
  final String label;
  final String jsonKey;
  final Map<String, dynamic> device;
  final List<String> fields;
  final Set<String> intFields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = device[jsonKey];
    Map<String, dynamic> m;
    if (o is Map<String, dynamic>) {
      m = o;
    } else {
      m = {};
      device[jsonKey] = m;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        for (final f in fields)
          _BoundStrField(f, m, onChanged, number: intFields.contains(f)),
      ],
    );
  }
}

/// Installer panel to define custom logs (graphs) of arbitrary group
/// addresses. Thermostats are logged automatically; this is for everything
/// else (e.g. power meters, humidity, CO?, water usage).
class _LogsInstallerPanel extends StatelessWidget {
  const _LogsInstallerPanel({
    required this.logs,
    required this.uuid,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> logs;
  final Uuid uuid;
  final VoidCallback onChanged;

  void _addLog() {
    logs.add({
      'id': 'log-${uuid.v4().substring(0, 8)}',
      'name': 'Nieuwe log',
      'entries': <Map<String, dynamic>>[],
    });
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Logs / grafieken',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Maak grafieken aan van willekeurige groepsadressen. Waarden worden '
          'op de server gelogd zodra ze veranderen (numerieke DPT\'s, ~90 dagen '
          'bewaard).',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 6),
        Text(
          'Thermostaten worden automatisch gelogd (gemeten + ingestelde '
          'temperatuur) en hoeven hier niet te worden toegevoegd.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.black45),
        ),
        const SizedBox(height: 20),
        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nog geen eigen logs aangemaakt.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black45),
            ),
          ),
        for (var i = 0; i < logs.length; i++)
          _LogCard(
            key: ObjectKey(logs[i]),
            log: logs[i],
            onChanged: onChanged,
            onDelete: () {
              logs.removeAt(i);
              onChanged();
            },
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addLog,
            icon: const Icon(Icons.add),
            label: const Text('Log toevoegen'),
          ),
        ),
      ],
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    super.key,
    required this.log,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> log;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  List<Map<String, dynamic>> _entries() {
    final e = log['entries'];
    if (e is! List) {
      log['entries'] = <Map<String, dynamic>>[];
    }
    return (log['entries'] as List).cast<Map<String, dynamic>>();
  }

  void _addEntry() {
    _entries().add({'ga': '', 'label': '', 'unit': ''});
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (log['name'] as String?)?.trim().isNotEmpty == true
                        ? log['name'] as String
                        : 'Log',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Log verwijderen',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _BoundStrField(
              'name',
              log,
              onChanged,
              labelOverride: 'Naam',
              hintText: 'bijv. Verbruik woonkamer',
            ),
            _BoundStrField(
              'id',
              log,
              onChanged,
              labelOverride: 'Log-ID (uniek)',
              hintText: 'bijv. verbruik-wk',
            ),
            const SizedBox(height: 4),
            Text(
              'Groepsadressen',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Voeg minstens ??n groepsadres toe.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black45),
                ),
              ),
            for (var i = 0; i < entries.length; i++)
              _LogEntryRow(
                key: ObjectKey(entries[i]),
                index: i,
                entry: entries[i],
                onChanged: onChanged,
                onDelete: () {
                  entries.removeAt(i);
                  onChanged();
                },
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addEntry,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Groepsadres toevoegen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> entry;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Adres ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
          _BoundStrField(
            'ga',
            entry,
            onChanged,
            labelOverride: 'Groepsadres',
            hintText: 'bijv. 3/1/5',
          ),
          _BoundStrField(
            'label',
            entry,
            onChanged,
            labelOverride: 'Naam in grafiek',
            hintText: 'bijv. Vermogen',
          ),
          _BoundStrField(
            'unit',
            entry,
            onChanged,
            labelOverride: 'Eenheid (optioneel)',
            hintText: '?C, %, W, kWh ...',
            emptyMeansRemove: true,
          ),
        ],
      ),
    );
  }
}

/// Small pill shown in the sidebar to indicate whether an integration is
/// enabled or disabled, so the installer can see the status at a glance.
class _IntegrationBadge extends StatelessWidget {
  const _IntegrationBadge({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: enabled
            ? Colors.green.shade50
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? Colors.green.shade300
              : Colors.grey.shade300,
        ),
      ),
      child: Text(
        enabled ? 'AAN' : 'UIT',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: enabled ? Colors.green.shade700 : Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Satel alarm installer panel
// ---------------------------------------------------------------------------

class _SatelInstallerPanel extends ConsumerWidget {
  const _SatelInstallerPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(satelEnabledProvider);
    final enabled = enabledAsync.value ?? false;
    final loading = enabledAsync.isLoading;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Icon(Icons.security_outlined, size: 22),
            const SizedBox(width: 10),
            Text('Satel alarm',
                style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Schakel de Satel INTEGRA-koppeling in of uit. '
          'Als uitgeschakeld worden er geen peilingen of TCP-verbindingen '
          'naar het alarmpaneel gemaakt. '
          'Partities, zones en kamerkoppeling stelt u hieronder in.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.power_settings_new_outlined, size: 20),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Integratie inschakelen',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text(
                        'Zet aan om alarmpagina, ruimtesensoren en '
                        'inlooptijd-overlay te activeren.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(
                        value: enabled,
                        onChanged: (v) => ref
                            .read(satelEnabledProvider.notifier)
                            .setEnabled(v),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (enabled) _SatelLiveStatus(),
        const SizedBox(height: 20),
        if (enabled) _SatelPartitionsCard(),
        const SizedBox(height: 20),
        if (enabled) _SatelZonesCard(),
        const SizedBox(height: 20),
        if (enabled) _SatelPinCard(),
        const SizedBox(height: 20),
        if (enabled) _SatelEncryptionCard(),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Configuratie',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                _cfgRow('Service-adres',
                    'SATEL_BASE dart-define of http://localhost:8001'),
                _cfgRow('Zone-indeling', 'satel/config.json op de server'),
                _cfgRow('Sensortypes',
                    'magneetcontact ? pir_beweging ? trilcontact ? glasbreuk ? rookmelder ? watermelder ? gasmelder ? paniekknop'),
                _cfgRow('Polling', '1,5 seconde'),
                _cfgRow('Arm / disarm',
                    'POST /satel/arm  ?  POST /satel/disarm'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cfgRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5E5F66))),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Partitions editor
// ---------------------------------------------------------------------------

class _SatelPartitionsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelPartitionsCard> createState() =>
      _SatelPartitionsCardState();
}

class _SatelPartitionsCardState extends ConsumerState<_SatelPartitionsCard> {
  List<SatelPartitionConfig>? _local; // null = not yet loaded / editing
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Load after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // Number + name come from the main backend (shared across devices);
    // arm modes live in the Satel service, so merge them in by number.
    final mainCfg = await ref.read(satelMainConfigProvider.future);
    final svc = await ref.read(satelServiceConfigProvider.future);
    final svcByNum = {for (final p in (svc?.partitions ?? const [])) p.number: p};

    final base = mainCfg.partitions.isNotEmpty
        ? mainCfg.partitions
        : (svc?.partitions ?? const <SatelPartitionConfig>[]);

    final merged = base.map((p) {
      final modes = svcByNum[p.number]?.armModes;
      return p.copyWith(
        armModes: (modes != null && modes.isNotEmpty) ? modes : p.armModes,
      );
    }).toList();
    if (mounted) setState(() => _local = merged);
  }

  Future<void> _save() async {
    if (_local == null) return;
    setState(() { _saving = true; _error = null; });
    final token = ref.read(authProvider).token;
    final result = await saveSatelPartitions(_local!, token: token);
    if (!mounted) return;
    setState(() { _saving = false; });
    if (!result.ok) {
      setState(() => _error = result.error ?? 'Onbekende fout');
    } else {
      // Re-fetch config so all devices see the updated partition list.
      ref.invalidate(satelMainConfigProvider);
      ref.invalidate(satelServiceConfigProvider);
    }
  }

  void _add() {
    setState(() {
      final next = (_local!.isEmpty ? 0 : _local!.map((p) => p.number).reduce((a,b) => a>b?a:b)) + 1;
      if (next > 32) return;
      _local!.add(SatelPartitionConfig(number: next, name: 'Partitie $next'));
    });
  }

  void _remove(int i) => setState(() => _local!.removeAt(i));

  @override
  Widget build(BuildContext context) {
    final list = _local;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Partities',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (list != null)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Toevoegen'),
                    onPressed: list.length < 32 ? _add : null,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Voer voor elke partitie een nummer (1?32) en naam in. '
              'Het nummer moet overeenkomen met de INTEGRA-configuratie.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),

            if (list == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (list.isEmpty)
              const Text('Geen partities ? voeg er een toe.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF98989F)))
            else
              ...List.generate(list.length, (i) {
                final p = list[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F4EC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x14000000)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: TextFormField(
                              initialValue: '${p.number}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Nr.',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n >= 1 && n <= 32) {
                                  setState(() =>
                                      _local![i] = p.copyWith(number: n));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: p.name,
                              decoration: const InputDecoration(
                                labelText: 'Naam',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(
                                  () => _local![i] = p.copyWith(name: v)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: const Color(0xFF98989F),
                            onPressed: () => _remove(i),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ArmModesEditor(
                        modes: p.armModes,
                        onChanged: (m) => setState(
                            () => _local![i] = p.copyWith(armModes: m)),
                      ),
                    ],
                  ),
                );
              }),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFD64545), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: list == null ? null : _load,
                  child: const Text('Herladen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (list == null || _saving) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Opslaan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor for a partition's arm modes (Satel mode 0-3 + installer-chosen name).
class _ArmModesEditor extends StatelessWidget {
  const _ArmModesEditor({required this.modes, required this.onChanged});
  final List<SatelArmMode> modes;
  final ValueChanged<List<SatelArmMode>> onChanged;

  static String _defaultName(int n) => switch (n) {
        0 => 'Volledig',
        1 => 'Nacht',
        2 => 'Dag',
        _ => 'Modus $n',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Inschakelmodi',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF98989F))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Modus'),
              onPressed: modes.length >= 4
                  ? null
                  : () {
                      final used = modes.map((m) => m.mode).toSet();
                      final next = [0, 1, 2, 3]
                          .firstWhere((n) => !used.contains(n), orElse: () => 0);
                      onChanged([
                        ...modes,
                        SatelArmMode(mode: next, name: _defaultName(next)),
                      ]);
                    },
            ),
          ],
        ),
        ...List.generate(modes.length, (j) {
          final m = modes[j];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: DropdownButtonFormField<int>(
                    initialValue: m.mode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Modus',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final n in [0, 1, 2, 3])
                        DropdownMenuItem(value: n, child: Text('Modus $n')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final copy = [...modes];
                      copy[j] = SatelArmMode(mode: v, name: m.name);
                      onChanged(copy);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: m.name,
                    decoration: const InputDecoration(
                      labelText: 'Naam',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final copy = [...modes];
                      copy[j] = SatelArmMode(mode: m.mode, name: v);
                      onChanged(copy);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: const Color(0xFF98989F),
                  onPressed: modes.length <= 1
                      ? null
                      : () => onChanged([...modes]..removeAt(j)),
                ),
              ],
            ),
          );
        }),
        const Text(
          'Modus 0 = volledig inschakelen. Modi 1-3 zijn door de installateur '
          'geprogrammeerde (deel)inschakelingen; geef ze een herkenbare naam.',
          style: TextStyle(fontSize: 11, color: Color(0xFF98989F)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Zones / sensors card — couple each Satel zone to a sensor type + app room
// ---------------------------------------------------------------------------

class _SatelZonesCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelZonesCard> createState() => _SatelZonesCardState();
}

class _SatelZonesCardState extends ConsumerState<_SatelZonesCard> {
  List<SatelZoneMapping>? _local; // null = not yet loaded
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final cfg = await ref.read(satelServiceConfigProvider.future);
    if (mounted) {
      setState(() => _local = List.of(cfg?.zoneMappings ?? const []));
    }
  }

  Future<void> _save() async {
    if (_local == null) return;
    setState(() { _saving = true; _error = null; });
    final result = await saveSatelZones(_local!);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.ok) {
      setState(() => _error = result.error ?? 'Onbekende fout');
    } else {
      ref.invalidate(satelServiceConfigProvider);
      ref.invalidate(satelStatusProvider);
    }
  }

  void _add() {
    setState(() {
      final next = (_local!.isEmpty
              ? 0
              : _local!.map((z) => z.zoneNumber).reduce((a, b) => a > b ? a : b)) +
          1;
      if (next > 128) return;
      _local!.add(SatelZoneMapping(
        zoneNumber: next,
        name: 'Zone $next',
        deviceType: 'magneetcontact',
      ));
    });
  }

  void _remove(int i) => setState(() => _local!.removeAt(i));

  /// Flatten all rooms across floors into (id, label) options for the dropdown.
  List<({String id, String label})> _roomOptions(HouseConfig? cfg) {
    if (cfg == null) return const [];
    final out = <({String id, String label})>[];
    for (final f in cfg.floors) {
      for (final r in f.rooms) {
        out.add((id: r.id, label: '${r.name} · ${f.name}'));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final list = _local;
    final cfg = ref.watch(configProvider).value;
    final rooms = _roomOptions(cfg);
    final knownRoomIds = rooms.map((r) => r.id).toSet();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Zones / sensoren',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (list != null)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Toevoegen'),
                    onPressed: list.length < 128 ? _add : null,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Koppel elk zonenummer (1–128, zoals geprogrammeerd in de INTEGRA) '
              'aan een sensortype en een kamer uit de app. De kamerkoppeling '
              'blijft werken ook als de kamer later wordt hernoemd.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),

            if (list == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (list.isEmpty)
              const Text('Nog geen zones — voeg er een toe.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF98989F)))
            else
              ...List.generate(list.length, (i) {
                final z = list[i];
                // Only feed the dropdown a value it actually knows, else null.
                final roomValue =
                    (z.roomId != null && knownRoomIds.contains(z.roomId))
                        ? z.roomId
                        : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F4EC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x14000000)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: TextFormField(
                              initialValue: '${z.zoneNumber}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Nr.',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n >= 1 && n <= 128) {
                                  setState(() => _local![i] =
                                      z.copyWith(zoneNumber: n));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: z.name,
                              decoration: const InputDecoration(
                                labelText: 'Naam',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(
                                  () => _local![i] = z.copyWith(name: v)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: const Color(0xFF98989F),
                            onPressed: () => _remove(i),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: z.deviceType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Type',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final t in satelDeviceTypes)
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(satelDeviceTypeLabel(t),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() =>
                                      _local![i] = z.copyWith(deviceType: v));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: roomValue,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Kamer',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Geen kamer',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                for (final r in rooms)
                                  DropdownMenuItem<String?>(
                                    value: r.id,
                                    child: Text(r.label,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  if (v == null) {
                                    _local![i] = z.copyWith(clearRoom: true);
                                  } else {
                                    final label = rooms
                                        .firstWhere((r) => r.id == v)
                                        .label;
                                    // Store the room name (before the " · floor")
                                    // for the alarm-page grouping label.
                                    final name = label.split(' · ').first;
                                    _local![i] = z.copyWith(
                                        roomId: v, roomName: name);
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFD64545), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: list == null ? null : _load,
                  child: const Text('Herladen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (list == null || _saving) ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Opslaan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN configuration card
// ---------------------------------------------------------------------------

class _SatelPinCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelPinCard> createState() => _SatelPinCardState();
}

class _SatelPinCardState extends ConsumerState<_SatelPinCard> {
  final _pin1Ctrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _pin1Ctrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p1 = _pin1Ctrl.text.trim();
    final p2 = _pin2Ctrl.text.trim();
    if (p1.isEmpty) {
      setState(() { _error = 'Voer een pincode in.'; _success = null; });
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
      setState(() { _error = 'Pincode moet 4?8 cijfers zijn.'; _success = null; });
      return;
    }
    if (p1 != p2) {
      setState(() { _error = 'Pincodes komen niet overeen.'; _success = null; });
      return;
    }
    setState(() { _saving = true; _error = null; _success = null; });
    final result = await saveSatelPin(p1);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.ok) {
        _success = 'Pincode opgeslagen.';
        _pin1Ctrl.clear();
        _pin2Ctrl.clear();
        ref.invalidate(satelServiceConfigProvider);
      } else {
        _error = result.error ?? 'Opslaan mislukt.';
      }
    });
  }

  void _reset() {
    _pin1Ctrl.clear();
    _pin2Ctrl.clear();
    setState(() { _error = null; _success = null; });
  }

  @override
  Widget build(BuildContext context, ) {
    final cfgAsync = ref.watch(satelServiceConfigProvider);
    final hasPin   = cfgAsync.value?.hasPin ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pin_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('In/uit-schakel pincode',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        hasPin
                            ? 'Pincode is ingesteld (niet leesbaar via API).'
                            : 'Nog geen pincode ingesteld.',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasPin
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFD64545),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pin1Ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Nieuwe pincode (4?8 cijfers)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pin2Ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Herhaal pincode',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFD64545), fontSize: 13)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 8),
              Text(_success!, style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Opslaan'),
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Wissen'),
                  onPressed: _reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encryption (AES integration key) card — optional
// ---------------------------------------------------------------------------

class _SatelEncryptionCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelEncryptionCard> createState() =>
      _SatelEncryptionCardState();
}

class _SatelEncryptionCardState extends ConsumerState<_SatelEncryptionCard> {
  final _keyCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveKey(String key) async {
    setState(() { _saving = true; _error = null; _success = null; });
    final result = await saveSatelEncryptionKey(key);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.ok) {
        _success = key.isEmpty
            ? 'Encryptie uitgeschakeld.'
            : 'Integratiesleutel opgeslagen.';
        _keyCtrl.clear();
        ref.invalidate(satelServiceConfigProvider);
      } else {
        _error = result.error ?? 'Opslaan mislukt.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(satelServiceConfigProvider);
    final hasEnc = cfgAsync.value?.hasEncryption ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Encryptie (optioneel)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        hasEnc
                            ? 'Versleutelde integratie actief.'
                            : 'Geen encryptie (plain-text verbinding).',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasEnc
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF98989F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Alleen invullen als de installateur in DLOADX "Versleutelde '
              'integratie" heeft aangezet. Vul dan exact dezelfde '
              'integratiesleutel in. Laat leeg voor een onversleutelde verbinding.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Integratiesleutel',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Color(0xFFD64545), fontSize: 13)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 8),
              Text(_success!,
                  style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Opslaan'),
                  onPressed: _saving
                      ? null
                      : () {
                          final k = _keyCtrl.text.trim();
                          if (k.isEmpty) {
                            setState(() {
                              _error = 'Vul een sleutel in (of gebruik '
                                  '"Encryptie uit").';
                              _success = null;
                            });
                            return;
                          }
                          _saveKey(k);
                        },
                ),
                const SizedBox(width: 8),
                if (hasEnc)
                  TextButton.icon(
                    icon: const Icon(Icons.lock_open_outlined, size: 16),
                    label: const Text('Encryptie uit'),
                    onPressed: _saving ? null : () => _saveKey(''),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SatelLiveStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(satelStatusProvider);
    final connected = status.connected;
    final stateLabel = switch (status.worstState) {
      SatelPartitionState.armed => 'Ingeschakeld',
      SatelPartitionState.exitDelay => 'Uitlooptijd?',
      SatelPartitionState.entryDelay => 'Inlooptijd!',
      _ => 'Uitgeschakeld',
    };
    final violated = status.allZones.where((z) => z.violated).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF98989F),
                  ),
                ),
                Text(
                  connected ? 'Verbonden' : 'Geen verbinding',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.shield_outlined, size: 15),
                const SizedBox(width: 6),
                Text(stateLabel, style: const TextStyle(fontSize: 13)),
              ],
            ),
            if (violated.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: violated.map((z) {
                  return Chip(
                    label: Text('${z.room} ? ${z.name}',
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor:
                        const Color(0xFFD64545).withValues(alpha: 0.10),
                    side: BorderSide(
                        color: const Color(0xFFD64545)
                            .withValues(alpha: 0.30)),
                    padding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
