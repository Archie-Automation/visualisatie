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
        SatelDiscoverImport,
        SatelDiscoverResult,
        SatelPartitionConfig,
        SatelPartitionState,
        SatelServiceConfig,
        SatelZoneMapping,
        discoverSatelPanel,
        mergeImportedSatelPartitions,
        mergeImportedSatelZones,
        satelDeviceTypes,
        satelDeviceTypeLabel,
        satelDiscoverImportProvider,
        satelEnabledProvider,
        satelMainConfigProvider,
        satelServiceConfigProvider,
        satelStatusProvider,
        saveSatelPartitions,
        saveSatelZones,
        saveSatelConnection,
        saveSatelEncryptionKey,
        saveSatelPin;
import '../shading_subtype_glyph.dart';
import '../theme.dart';
import '../roles.dart';
import '../room_control_category.dart';
import '../system_category.dart';
import '../user_credentials.dart';
import '../ui/responsive.dart';
import '../ui/user_access_editor.dart';
import '../ui/widgets/admin_full_restart_card.dart';
import '../ui/widgets/admin_server_update_card.dart';
import '../ui/widgets/back_pill.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/function_screen_header.dart';
import '../ui/widgets/luxe_backdrop.dart';
import '../ui/widgets/luxe_form.dart';
import '../ui/widgets/heater_icon.dart';
import 'installer_api.dart';
import 'installer_auth.dart';
import 'installer_form_sections.dart';
import 'intercom_installer_wizard.dart';
import 'intercom_sip_config.dart';
import 'knx_ga_catalog.dart';
import 'voip_installer_section.dart';

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
];

/// Huisbrede apparaten (niet aan één kamer gekoppeld) — sectie Algemeen.
const _deviceTypesGeneral = [
  'wtw',
  'melding',
  'universal',
  'fan',
  'position_actuator',
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

/// Twee stappen: eerst KNX of Lutron, daarna alleen passende types.
/// [lockBus] slaat de buskeuze over (Audio is geen bus: alleen Sonos/Bluesound).
Future<DeviceTypePick?> showPickDeviceTypeSheet(
  BuildContext context, {
  DeviceBusCategory? lockBus,
}) {
  return showModalBottomSheet<DeviceTypePick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _DeviceTypePickerSheet(lockBus: lockBus),
  );
}

/// Picker voor huisbrede apparaten (Algemeen): WTW/MV, meldingen, …
Future<DeviceTypePick?> showPickGeneralDeviceTypeSheet(BuildContext context) {
  return showModalBottomSheet<DeviceTypePick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Algemeen apparaat',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Niet gekoppeld aan één kamer — voor het hele huis.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final dt in _deviceTypesGeneral)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(_deviceTypeLabels[dt] ?? dt),
                onTap: () => Navigator.pop(
                  ctx,
                  DeviceTypePick(type: dt, bus: DeviceBusCategory.knx),
                ),
              ),
            SizedBox(height: 8 + bottom),
          ],
        ),
      );
    },
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
  'wtw': 'WTW / MV / ventilatie',
  'melding': 'Meldingen / Alarmen monitor',
  'lutron_homeworks': 'Lutron Homeworks → KNX',
};

class _DeviceTypePickerSheet extends StatefulWidget {
  const _DeviceTypePickerSheet({this.lockBus});

  final DeviceBusCategory? lockBus;

  @override
  State<_DeviceTypePickerSheet> createState() => _DeviceTypePickerSheetState();
}

class _DeviceTypePickerSheetState extends State<_DeviceTypePickerSheet> {
  DeviceBusCategory? _bus;

  @override
  void initState() {
    super.initState();
    _bus = widget.lockBus;
  }

  static const _physicalBuses = [
    DeviceBusCategory.knx,
    DeviceBusCategory.lutron,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final locked = widget.lockBus != null;

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
            for (final bus in _physicalBuses)
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
              icon: Icon(locked ? Icons.close : Icons.arrow_back),
              onPressed: locked
                  ? () => Navigator.pop(context)
                  : () => setState(() => _bus = null),
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

class _CopyInstallerDeviceIntent extends Intent {
  const _CopyInstallerDeviceIntent();
}

class _PasteInstallerDeviceIntent extends Intent {
  const _PasteInstallerDeviceIntent();
}

/// Device copy/paste shortcuts must not win from a focused text field.
class _UnlessEditingAction<T extends Intent> extends Action<T> {
  _UnlessEditingAction(this._invoke);
  final VoidCallback _invoke;

  @override
  bool isEnabled(T intent) {
    final w = FocusManager.instance.primaryFocus?.context?.widget;
    return w is! EditableText;
  }

  @override
  Object? invoke(T intent) {
    _invoke();
    return null;
  }
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
  floors,
  floor,
  room,
  device,
  houseSystems,
  globalDevices,
  /// A device that is NOT placed in any room.
  globalDevice,
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
  const _Focus.floors()
      : kind = _FocusKind.floors,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.houseSystems()
      : kind = _FocusKind.houseSystems,
        fi = -1,
        ri = -1,
        di = -1,
        ci = null;
  const _Focus.globalDevices()
      : kind = _FocusKind.globalDevices,
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
      if (!_isInstallerWide()) {
        _mobileShowDetail = true;
      }
    });
  }

  bool _isInstallerWide([double? width]) {
    final w = width ?? MediaQuery.sizeOf(context).width;
    return w >= 900 && !context.isPhone;
  }

  bool get _hasInstallerBack =>
      !_isInstallerWide() && _mobileShowDetail;

  bool get _isBuildingFocus =>
      _sel.kind == _FocusKind.floors ||
      _sel.kind == _FocusKind.floor ||
      _sel.kind == _FocusKind.room ||
      _sel.kind == _FocusKind.device;

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
      final credErr = validateUsersLoginCredentials(_users());
      if (credErr != null) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(credErr), backgroundColor: Colors.red.shade800),
        );
        return;
      }
      _stripEmptyPasswordFields();
      _normalizeHouseIntercoms();
      final payload = Map<String, dynamic>.from(house);
      payload['users'] = usersPayloadForSave(_users());
      await putInstallerHouse(token, payload);
      if (!mounted) return;
      clearNewUserFlags(_users());
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

  List<({String id, String label})> _sceneLearnRooms() {
    final out = <({String id, String label})>[];
    for (final f in _floors()) {
      final floorName = '${f['name'] ?? ''}'.trim();
      final rooms = f['rooms'];
      if (rooms is! List) continue;
      for (final r in rooms) {
        if (r is! Map) continue;
        final id = '${r['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final roomName = '${r['name'] ?? ''}'.trim();
        final label = floorName.isEmpty
            ? (roomName.isEmpty ? id : roomName)
            : '$floorName · ${roomName.isEmpty ? id : roomName}';
        out.add((id: id, label: label));
      }
    }
    return out;
  }

  Map<String, dynamic> _ensureProject() {
    final h = _house!;
    final p = h['project'];
    if (p is Map<String, dynamic>) return p;
    final m = <String, dynamic>{'id': '', 'name': ''};
    h['project'] = m;
    return m;
  }

  Map<String, dynamic> _ensureSceneLearn() {
    final h = _house!;
    var sl = h['knxSceneLearn'];
    if (sl is! Map<String, dynamic>) {
      sl = <String, dynamic>{'addresses': <dynamic>[]};
      h['knxSceneLearn'] = sl;
    }
    if (sl['addresses'] is! List) sl['addresses'] = <dynamic>[];
    return sl;
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
      'username': '',
      'displayName': '',
      'role': 'user',
      'passwordHash': '',
      '_new': true,
      'access': {
        'floors': '*',
        'rooms': '*',
        'functions': '*',
        'devices': '*',
        'scenes': '*',
        'editScenes': true,
      },
      'enabled': true,
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
    _selectFocus(_Focus.floor(_floors().length - 1));
  }

  void _addRoom(int fi) {
    final rooms = _roomList(fi);
    rooms.add({
      'id': 'rm-${_uuid.v4()}',
      'name': 'Nieuwe ruimte',
      'devices': <Map<String, dynamic>>[],
    });
    _selectFocus(_Focus.room(fi, rooms.length - 1));
  }

  Widget _rowTrash({
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.delete_outline),
      onPressed: onPressed,
    );
  }

  void _deleteFloorAt(int fi) {
    final kind = _sel.kind;
    final selFi = _sel.fi;
    final ri = _sel.ri;
    final di = _sel.di;
    _floors().removeAt(fi);
    setState(() {
      if (selFi == fi &&
          (kind == _FocusKind.floor ||
              kind == _FocusKind.room ||
              kind == _FocusKind.device)) {
        _sel = const _Focus.floors();
      } else if (selFi > fi) {
        final n = selFi - 1;
        _sel = switch (kind) {
          _FocusKind.floor => _Focus.floor(n),
          _FocusKind.room => _Focus.room(n, ri),
          _FocusKind.device => _Focus.device(n, ri, di),
          _ => _sel,
        };
      }
    });
  }

  void _deleteRoomAt(int fi, int ri) {
    final kind = _sel.kind;
    final selFi = _sel.fi;
    final selRi = _sel.ri;
    final di = _sel.di;
    _roomList(fi).removeAt(ri);
    setState(() {
      if (selFi != fi) return;
      if (selRi == ri &&
          (kind == _FocusKind.room || kind == _FocusKind.device)) {
        _sel = _Focus.floor(fi);
      } else if (selRi > ri) {
        final n = selRi - 1;
        _sel = switch (kind) {
          _FocusKind.room => _Focus.room(fi, n),
          _FocusKind.device => _Focus.device(fi, n, di),
          _ => _sel,
        };
      }
    });
  }

  void _deleteDeviceAt(int fi, int ri, int di) {
    final kind = _sel.kind;
    final selFi = _sel.fi;
    final selRi = _sel.ri;
    final selDi = _sel.di;
    _deviceList(fi, ri).removeAt(di);
    setState(() {
      if (kind != _FocusKind.device || selFi != fi || selRi != ri) return;
      if (selDi == di) {
        _sel = _Focus.room(fi, ri);
      } else if (selDi > di) {
        _sel = _Focus.device(fi, ri, selDi - 1);
      }
    });
  }

  void _deleteCameraAt(int i) {
    _cameras().removeAt(i);
    setState(() {
      if (_sel.kind != _FocusKind.cameraDetail) return;
      final ci = _sel.ci;
      if (ci == null) return;
      if (ci == i) {
        _sel = const _Focus.cameras();
      } else if (ci > i) {
        _sel = _Focus.cameraDetail(ci - 1);
      }
    });
  }

  void _deleteIntercomAt(int i) {
    _intercoms().removeAt(i);
    setState(() {
      if (_sel.kind != _FocusKind.intercomDetail) return;
      final ci = _sel.ci;
      if (ci == null) return;
      if (ci == i) {
        _sel = const _Focus.intercoms();
      } else if (ci > i) {
        _sel = _Focus.intercomDetail(ci - 1);
      }
    });
  }

  void _deleteGlobalDeviceAt(int i) {
    _globalDeviceList().removeAt(i);
    setState(() {
      if (_sel.kind != _FocusKind.globalDevice) return;
      if (_sel.di == i) {
        _sel = const _Focus.globalDevices();
      } else if (_sel.di > i) {
        _sel = _Focus.globalDevice(_sel.di - 1);
      }
    });
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
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );
    if (picked == null) return;
    Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
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

  /// Devices at the project root level — NOT placed in any room.
  List<Map<String, dynamic>> _globalDeviceList() {
    final h = _house!;
    final d = h['devices'];
    if (d is! List) {
      h['devices'] = <dynamic>[];
    }
    return (h['devices'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> _houseSystemsList() {
    final h = _house!;
    final raw = h['houseSystems'];
    if (raw is! List) {
      h['houseSystems'] = <dynamic>[];
    }
    return (h['houseSystems'] as List).cast<Map<String, dynamic>>();
  }

  void _addHouseSystemTile() {
    final list = _houseSystemsList();
    final reserved = {
      for (final s in kHouseSystems) s.slug,
      kFavorietenSlug,
      kGrafiekenSlug,
      kHeatersActivitySlug,
      'alarm',
      'diverse',
      for (final e in list) (e['id'] as String? ?? ''),
    };
    var n = 1;
    var id = 'tegel';
    while (reserved.contains(id)) {
      n++;
      id = 'tegel-$n';
    }
    list.add(<String, dynamic>{
      'id': id,
      'name': 'Nieuwe tegel',
      'icon': 'grid',
      'deviceIds': <dynamic>[],
    });
    setState(() {});
  }

  void _deleteHouseSystemTile(int index) {
    final list = _houseSystemsList();
    if (index < 0 || index >= list.length) return;
    final id = list[index]['id'] as String? ?? '';
    list.removeAt(index);
    if (id.isNotEmpty) {
      for (final d in _globalDeviceList()) {
        if (d['systemId'] == id) d.remove('systemId');
      }
    }
    setState(() {});
  }

  List<dynamic> _tileDeviceIds(Map<String, dynamic> tile) {
    final raw = tile['deviceIds'];
    if (raw is List) return raw;
    final list = <dynamic>[];
    tile['deviceIds'] = list;
    return list;
  }

  List<({String id, String name, String type, String where})>
      _catalogAllDevices() {
    final out = <({String id, String name, String type, String where})>[];
    void add(Map<String, dynamic> d, String where) {
      final id = (d['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) return;
      out.add((
        id: id,
        name: _namedOr(d, 'Apparaat'),
        type: d['type'] as String? ?? '',
        where: where,
      ));
    }

    final floors = _floors();
    for (var fi = 0; fi < floors.length; fi++) {
      final fn = _namedOr(floors[fi], 'Verdieping');
      final rooms = _roomList(fi);
      for (var ri = 0; ri < rooms.length; ri++) {
        final rn = _namedOr(rooms[ri], 'Kamer');
        for (final d in _deviceList(fi, ri)) {
          add(d, '$fn · $rn');
        }
      }
    }
    for (final d in _globalDeviceList()) {
      add(d, 'Algemeen');
    }
    for (final d in _cameras()) {
      add(d, "Camera's");
    }
    for (final d in _intercoms()) {
      add(d, 'Intercom');
    }
    return out;
  }

  ({String id, String name, String type, String where})? _catalogDevice(
      String id) {
    for (final d in _catalogAllDevices()) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _pickDeviceForSystemTile(int tileIndex) async {
    if (!mounted) return;
    final tile = _houseSystemsList()[tileIndex];
    final taken = {
      for (final e in _tileDeviceIds(tile)) e.toString(),
    };
    final choices = [
      for (final d in _catalogAllDevices())
        if (!taken.contains(d.id)) d,
    ];
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen apparaten meer om toe te voegen')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Apparaat op tegel',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Blijft ook in de kamer of onder Algemeen staan.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final d in choices)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(d.name),
                  subtitle: Text(
                    [
                      _deviceTypeLabels[d.type] ?? d.type,
                      d.where,
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  onTap: () => Navigator.pop(ctx, d.id),
                ),
              SizedBox(height: 8 + bottom),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final ids = _tileDeviceIds(_houseSystemsList()[tileIndex]);
    if (!ids.contains(picked)) ids.add(picked);
    setState(() {});
  }

  void _addGlobalDevice(DeviceTypePick pick) {
    final id = 'dev-${_uuid.v4()}';
    _globalDeviceList().add(_defaultDevice(pick.type, id, bus: pick.bus));
    _selectFocus(_Focus.globalDevice(_globalDeviceList().length - 1));
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

  static String _cameraListSubtitle(Map<String, dynamic> cam) {
    final o = cam['camera'];
    final rtsp = o is Map ? (o['rtsp'] as String?)?.trim() ?? '' : '';
    if (rtsp.isEmpty) return 'Nog geen stream-URL';
    final u = Uri.tryParse(rtsp);
    if (u != null && u.host.isNotEmpty) return u.host;
    return 'Stream ingesteld';
  }

  Widget _camerasInstallerPanel(BuildContext context) {
    final list = _cameras();
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: Text(
            'Voeg een camera toe met een naam en de stream-URL. '
            'Ze horen bij het hele huis, niet bij één kamer.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ),
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Text(
                    'Nog geen camera\'s',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: Icons.videocam_outlined,
                  title: list[i]['name'] as String? ??
                      list[i]['id'] as String? ??
                      '',
                  subtitle: _cameraListSubtitle(list[i]),
                  selected: _sel.kind == _FocusKind.cameraDetail && _sel.ci == i,
                  trailing: _rowTrash(
                    tooltip: 'Camera verwijderen',
                    onPressed: () => _deleteCameraAt(i),
                  ),
                  onTap: () => _selectFocus(_Focus.cameraDetail(i)),
                ),
              ],
              if (list.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Camera toevoegen',
                onTap: _addCamera,
              ),
            ],
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
    final house = _house!;
    enableIntercomCalling(house);
    final groups = voipGroupMaps(house);
    if (groups.isEmpty) createBelgroep(house);
    final map = _defaultDevice('intercom', 'dev-ic-${_uuid.v4()}');
    final o = ensureIntercomMap(map);
    final g = voipGroupMaps(house);
    if (g.isNotEmpty) o['ringGroupId'] = g.first['id'];
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
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: Text(
            'Apparaten staan in de gekozen kamer. Tik om te bewerken.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ),
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Text(
                    'Nog geen Sonos of Bluesound in kamers',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: rows[i].dev['type'] == 'media_bluesound'
                      ? Icons.speaker_group_outlined
                      : Icons.speaker_outlined,
                  title: rows[i].dev['name'] as String? ??
                      rows[i].dev['id'] as String? ??
                      '',
                  subtitle: rows[i].location,
                  trailing: _rowTrash(
                    tooltip: 'Apparaat verwijderen',
                    onPressed: () => _deleteDeviceAt(
                      rows[i].fi,
                      rows[i].ri,
                      rows[i].di,
                    ),
                  ),
                  onTap: () => setState(
                    () => _sel = _Focus.device(rows[i].fi, rows[i].ri, rows[i].di),
                  ),
                ),
              ],
              if (rows.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Audio toevoegen',
                onTap: () async {
                  final pick = await showPickDeviceTypeSheet(
                    context,
                    lockBus: DeviceBusCategory.audio,
                  );
                  if (pick != null && context.mounted) {
                    await _pickRoomAndAddDevice(context, pick);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _intercomsInstallerPanel(BuildContext context) {
    final list = _intercoms();
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        LuxeListCard(
          child: VoipInstallerSection(
            house: _house!,
            onChanged: () => setState(() {}),
            getToken: () async {
              if (widget.useCustomerSession) {
                return ref.read(authProvider).token;
              }
              return ref.read(installerAuthProvider).token;
            },
          ),
        ),
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 14, 4),
                child: LuxeSectionTitle(
                  icon: Icons.sensor_door_outlined,
                  title: 'Deurstations',
                  subtitle:
                      'Stap 1: toestel  ·  Stap 2: belgroep  ·  Stap 3: belknoppen',
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Text(
                    'Nog geen deurstation. Voeg er één toe en vul de drie stappen in.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: Icons.doorbell_outlined,
                  title: () {
                    final name = (list[i]['name'] as String?)?.trim();
                    if (name != null && name.isNotEmpty) return name;
                    return 'Intercom';
                  }(),
                  subtitle: () {
                    final o = list[i]['intercom'];
                    if (o is! Map) return 'Tik om in te stellen';
                    final rtsp = (o['rtsp'] as String?)?.trim() ?? '';
                    final groupId = (o['ringGroupId'] as String?)?.trim() ?? '';
                    String? groupName;
                    for (final g in voipGroupMaps(_house!)) {
                      if ('${g['id']}' == groupId) {
                        groupName = (g['name'] as String?)?.trim();
                        break;
                      }
                    }
                    if (rtsp.isEmpty) return 'Camerastream ontbreekt';
                    if (groupName != null && groupName.isNotEmpty) {
                      return groupName;
                    }
                    return 'Nog geen belgroep gekoppeld';
                  }(),
                  selected:
                      _sel.kind == _FocusKind.intercomDetail && _sel.ci == i,
                  trailing: _rowTrash(
                    tooltip: 'Intercom verwijderen',
                    onPressed: () => _deleteIntercomAt(i),
                  ),
                  onTap: () => _selectFocus(_Focus.intercomDetail(i)),
                ),
              ],
              if (list.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Intercom toevoegen',
                onTap: _addIntercom,
              ),
            ],
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
          'camera': {'rtsp': ''},
        };
      case 'intercom':
        return {
          'id': id,
          'name': 'Voordeur',
          'type': 'intercom',
          'intercom': {
            'kind': 'other',
            'rtsp': '',
            'dtmfDigit': '#',
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
          'fan': <String, dynamic>{},
        };
      case 'wtw':
        return {
          'id': id,
          'name': 'WTW',
          'type': 'wtw',
          'wtw': <String, dynamic>{},
        };
      case 'melding':
        return {
          'id': id,
          'name': 'Meldingen',
          'type': 'melding',
          'melding': {
            'items': <Map<String, dynamic>>[],
          },
        };
      case 'universal':
        return {
          'id': id,
          'name': 'Universeel paneel',
          'type': 'universal',
          'universal': {
            'icon': 'grid',
            'layout': 'buttons',
            'buttons': <Map<String, dynamic>>[],
          },
        };
      case 'lutron_homeworks':
        return {
          'id': id,
          'name': 'Lutron → KNX',
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
    _selectFocus(_Focus.device(fi, ri, _deviceList(fi, ri).length - 1));
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
      case _FocusKind.globalDevices:
        await _pasteDeviceIntoList(
          _globalDeviceList(),
          onPasted: (i) => _selectFocus(_Focus.globalDevice(i)),
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

  String get _headerTitle {
    final wide = _isInstallerWide();
    if (!wide && _mobileShowDetail) return _focusTitle(_sel);
    return widget.useCustomerSession
        ? 'Technische configuratie'
        : 'Huisconfiguratie';
  }

  String _focusTitle(_Focus sel) => switch (sel.kind) {
        _FocusKind.project => 'Project',
        _FocusKind.knx => 'KNX-gateway',
        _FocusKind.lutron => 'Lutron QSX/QS',
        _FocusKind.cameras => "Camera's",
        _FocusKind.cameraDetail => 'Camera',
        _FocusKind.audio => 'Audio',
        _FocusKind.intercoms => 'Intercom',
        _FocusKind.intercomDetail => 'Intercom',
        _FocusKind.users => 'Gebruikers',
        _FocusKind.user => 'Gebruiker',
        _FocusKind.logs => 'Logs / grafieken',
        _FocusKind.satel => 'Satel alarm',
        _FocusKind.floors => 'Kamergebonden devices',
        _FocusKind.floor => 'Verdieping',
        _FocusKind.room => 'Kamer',
        _FocusKind.device => 'Apparaat',
        _FocusKind.houseSystems => 'Custom systeemtegels',
        _FocusKind.globalDevices => 'Algemene devices',
        _FocusKind.globalDevice => 'Apparaat',
      };

  bool _stepBackInInstaller() {
    if (!_mobileShowDetail) return false;
    switch (_sel.kind) {
      case _FocusKind.device:
        _selectFocus(_Focus.room(_sel.fi, _sel.ri));
        return true;
      case _FocusKind.room:
        _selectFocus(_Focus.floor(_sel.fi));
        return true;
      case _FocusKind.floor:
        _selectFocus(const _Focus.floors());
        return true;
      case _FocusKind.globalDevice:
        _selectFocus(const _Focus.globalDevices());
        return true;
      default:
        setState(() => _mobileShowDetail = false);
        return true;
    }
  }

  Future<void> _onHeaderBack({required bool wide}) async {
    if (!wide && _stepBackInInstaller()) return;
    if (widget.useCustomerSession) {
      if (mounted) context.pop();
    } else {
      await ref.read(installerAuthProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: LuxeBackdrop(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_loadErr != null || _house == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: LuxeBackdrop(
          child: Center(
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
        ),
      );
    }

    final wide = _isInstallerWide();
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _CopyInstallerDeviceIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _PasteInstallerDeviceIntent(),
      },
      child: Actions(
        actions: {
          _CopyInstallerDeviceIntent:
              _UnlessEditingAction(_tryCopyFocusedDevice),
          _PasteInstallerDeviceIntent: _UnlessEditingAction(() {
            _tryPasteFocusedDevice();
          }),
        },
        child: Focus(
        autofocus: true,
        child: PopScope(
      canPop: wide || !_hasInstallerBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onHeaderBack(wide: wide);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LuxeBackdrop(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FunctionScreenHeader(
                onBack: () => _onHeaderBack(wide: wide),
                title: _headerTitle,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      HeaderIconButton(
                        icon: Icons.refresh,
                        tooltip: 'Herladen van server',
                        onTap: _saving ? () {} : _load,
                      ),
                      const SizedBox(width: 6),
                      if (context.isPhone)
                        HeaderIconButton(
                          icon: Icons.check,
                          tooltip: 'Opslaan',
                          onTap: _saving ? () {} : _save,
                        )
                      else
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: LuxeColors.ink,
                            foregroundColor: LuxeColors.onInk,
                            disabledBackgroundColor:
                                LuxeColors.ink.withValues(alpha: 0.28),
                            minimumSize: const Size(88, 48),
                            shape: const StadiumBorder(),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Opslaan'),
                        ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    final isWide = _isInstallerWide(c.maxWidth);
                    final tree = _buildTree(ctx);
                    if (!isWide) {
                      if (_mobileShowDetail) return _buildDetail(ctx);
                      return tree;
                    }
                    if (_isBuildingFocus) {
                      return _buildingStructureWide(ctx, tree);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 360, child: tree),
                        Expanded(child: _buildDetail(ctx)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
      ),
    );
  }

  Widget _buildTree(BuildContext context) => _mainNavTree(context);

  Widget _navChapter(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }

  Widget _navChapterCard({
    String? chapter,
    required List<Widget> rows,
  }) {
    return LuxeListCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chapter != null) _navChapter(chapter),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _mainNavTree(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        _navChapterCard(
          rows: [
            LuxeNavRow(
              icon: Icons.home_work_outlined,
              title: 'Project',
              selected: _sel.kind == _FocusKind.project,
              onTap: () => _selectFocus(const _Focus.project()),
            ),
            LuxeNavRow(
              icon: Icons.people_outline,
              title: 'Gebruikers',
              selected: _sel.kind == _FocusKind.users ||
                  _sel.kind == _FocusKind.user,
              onTap: () => _selectFocus(const _Focus.users()),
            ),
          ],
        ),
        _navChapterCard(
          chapter: 'IP',
          rows: [
            LuxeNavRow(
              icon: Icons.hub_outlined,
              title: 'KNX-gateway',
              selected: _sel.kind == _FocusKind.knx,
              trailing: _IntegrationBadge(
                  enabled: (_house?['knx']?['enabled'] as bool?) != false &&
                      _house?['knx'] != null),
              onTap: () => _selectFocus(const _Focus.knx()),
            ),
            LuxeNavRow(
              icon: Icons.tune_outlined,
              title: 'Lutron QSX/QS',
              selected: _sel.kind == _FocusKind.lutron,
              trailing: _IntegrationBadge(
                  enabled:
                      (_house?['lutron']?['telnet']?['enabled'] as bool?) ==
                          true),
              onTap: () => _selectFocus(const _Focus.lutron()),
            ),
            LuxeNavRow(
              icon: Icons.videocam_outlined,
              title: "Camera's",
              selected: _sel.kind == _FocusKind.cameras ||
                  _sel.kind == _FocusKind.cameraDetail,
              onTap: () => _selectFocus(const _Focus.cameras()),
            ),
            LuxeNavRow(
              icon: Icons.speaker_group_outlined,
              title: 'Audio',
              selected: _sel.kind == _FocusKind.audio,
              onTap: () => _selectFocus(const _Focus.audio()),
            ),
            LuxeNavRow(
              icon: Icons.doorbell_outlined,
              title: 'Intercom',
              selected: _sel.kind == _FocusKind.intercoms ||
                  _sel.kind == _FocusKind.intercomDetail,
              trailing: _IntegrationBadge(
                  enabled: (_house?['voip']?['enabled'] as bool?) == true),
              onTap: () => _selectFocus(const _Focus.intercoms()),
            ),
            LuxeNavRow(
              icon: Icons.security_outlined,
              title: 'Satel alarm',
              selected: _sel.kind == _FocusKind.satel,
              onTap: () => _selectFocus(const _Focus.satel()),
            ),
          ],
        ),
        _navChapterCard(
          chapter: 'Visualisatie',
          rows: [
            LuxeNavRow(
              icon: Icons.dashboard_outlined,
              title: 'Custom systeemtegels',
              selected: _sel.kind == _FocusKind.houseSystems,
              onTap: () => _selectFocus(const _Focus.houseSystems()),
            ),
            LuxeNavRow(
              icon: Icons.devices_other_outlined,
              title: 'Algemene devices',
              selected: _sel.kind == _FocusKind.globalDevices ||
                  _sel.kind == _FocusKind.globalDevice,
              onTap: () => _selectFocus(const _Focus.globalDevices()),
            ),
            LuxeNavRow(
              icon: Icons.layers_outlined,
              title: 'Kamergebonden devices',
              selected: _isBuildingFocus,
              onTap: () => _selectFocus(const _Focus.floors()),
            ),
          ],
        ),
        _navChapterCard(
          chapter: 'Diagnose',
          rows: [
            LuxeNavRow(
              icon: Icons.show_chart_outlined,
              title: 'Logs / grafieken',
              selected: _sel.kind == _FocusKind.logs,
              onTap: () => _selectFocus(const _Focus.logs()),
            ),
          ],
        ),
      ],
    );
  }

  String _countLabel(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';

  String _deviceRowSubtitle(Map<String, dynamic> d) {
    final type = d['type'] as String? ?? '';
    return _deviceTypeLabels[type] ?? type;
  }

  String _namedOr(Map<String, dynamic> m, String fallback) {
    final n = (m['name'] as String?)?.trim();
    return (n != null && n.isNotEmpty) ? n : fallback;
  }

  Widget _buildingStructureWide(BuildContext context, Widget tree) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final navW = c.maxWidth >= 1280 ? 280.0 : 220.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: navW, child: tree),
            Expanded(
              flex: 5,
              child: _millerRow(context),
            ),
            Expanded(
              flex: 4,
              child: _buildingInspector(context),
            ),
          ],
        );
      },
    );
  }

  Widget _millerRow(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        const minCol = 176.0;
        final floors = _millerFloorsColumn(context);
        final rooms = _millerRoomsColumn(context);
        final devices = _millerDevicesColumn(context);
        if (c.maxWidth >= minCol * 3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: floors),
              Expanded(child: rooms),
              Expanded(child: devices),
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 200, child: floors),
              SizedBox(width: 200, child: rooms),
              SizedBox(width: 200, child: devices),
            ],
          ),
        );
      },
    );
  }

  Widget _millerColumn({
    required BuildContext context,
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
    String? emptyText,
    Widget? footer,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
          child: LuxeSectionTitle(
            icon: icon,
            title: title,
            trailing: trailing,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
            children: [
              if (children.isEmpty && emptyText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  child: Text(
                    emptyText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ),
              ...children,
            ],
          ),
        ),
        if (footer != null) footer,
      ],
    );
  }

  Widget _millerFloorsColumn(BuildContext context) {
    final floors = _floors();
    return _millerColumn(
      context: context,
      title: 'Verdieping',
      icon: Icons.layers_outlined,
      emptyText: floors.isEmpty ? 'Nog geen verdieping' : null,
      children: [
        for (var i = 0; i < floors.length; i++)
          LuxeNavRow(
            icon: Icons.layers_outlined,
            title: _namedOr(floors[i], 'Verdieping'),
            subtitle: _countLabel(_roomList(i).length, 'kamer', 'kamers'),
            selected: _sel.fi == i &&
                (_sel.kind == _FocusKind.floor ||
                    _sel.kind == _FocusKind.room ||
                    _sel.kind == _FocusKind.device),
            trailing: _rowTrash(
              tooltip: 'Verdieping verwijderen',
              onPressed: () => _deleteFloorAt(i),
            ),
            rounded: true,
            onTap: () => _selectFocus(_Focus.floor(i)),
          ),
      ],
      footer: LuxeAddRow(
        label: 'Verdieping toevoegen',
        onTap: _addFloor,
      ),
    );
  }

  Widget _millerRoomsColumn(BuildContext context) {
    final hasFloor = _sel.fi >= 0 &&
        (_sel.kind == _FocusKind.floor ||
            _sel.kind == _FocusKind.room ||
            _sel.kind == _FocusKind.device);
    if (!hasFloor) {
      return _millerColumn(
        context: context,
        title: 'Kamer',
        icon: Icons.meeting_room_outlined,
        emptyText: 'Kies een verdieping',
        children: const [],
      );
    }
    final fi = _sel.fi;
    final rooms = _roomList(fi);
    return _millerColumn(
      context: context,
      title: 'Kamer',
      icon: Icons.meeting_room_outlined,
      emptyText: rooms.isEmpty ? 'Nog geen kamer' : null,
      children: [
        for (var ri = 0; ri < rooms.length; ri++)
          LuxeNavRow(
            icon: Icons.meeting_room_outlined,
            title: _namedOr(rooms[ri], 'Kamer'),
            subtitle: _countLabel(
                _deviceList(fi, ri).length, 'apparaat', 'apparaten'),
            selected: _sel.ri == ri &&
                (_sel.kind == _FocusKind.room ||
                    _sel.kind == _FocusKind.device),
            trailing: _rowTrash(
              tooltip: 'Kamer verwijderen',
              onPressed: () => _deleteRoomAt(fi, ri),
            ),
            rounded: true,
            onTap: () => _selectFocus(_Focus.room(fi, ri)),
          ),
      ],
      footer: LuxeAddRow(
        label: 'Kamer toevoegen',
        onTap: () => _addRoom(fi),
      ),
    );
  }

  Widget _millerDevicesColumn(BuildContext context) {
    final hasRoom = _sel.ri >= 0 &&
        (_sel.kind == _FocusKind.room || _sel.kind == _FocusKind.device);
    if (!hasRoom) {
      return _millerColumn(
        context: context,
        title: 'Apparaat',
        icon: Icons.tune_outlined,
        emptyText: 'Kies een kamer',
        children: const [],
      );
    }
    final fi = _sel.fi;
    final ri = _sel.ri;
    final devices = _deviceList(fi, ri);
    return _millerColumn(
      context: context,
      title: 'Apparaat',
      icon: Icons.tune_outlined,
      trailing: IconButton(
        tooltip: 'Apparaat plakken',
        icon: const Icon(Icons.content_paste_outlined),
        onPressed: () => _pasteDeviceIntoList(
          devices,
          onPasted: (i) => _selectFocus(_Focus.device(fi, ri, i)),
        ),
      ),
      emptyText: devices.isEmpty ? 'Nog geen apparaat' : null,
      children: [
        for (var di = 0; di < devices.length; di++)
          LuxeNavRow(
            icon: Icons.tune_outlined,
            title: _namedOr(devices[di], 'Apparaat'),
            subtitle: _deviceRowSubtitle(devices[di]),
            selected:
                _sel.kind == _FocusKind.device && _sel.di == di,
            trailing: _rowTrash(
              tooltip: 'Apparaat verwijderen',
              onPressed: () => _deleteDeviceAt(fi, ri, di),
            ),
            rounded: true,
            onTap: () => _selectFocus(_Focus.device(fi, ri, di)),
          ),
      ],
      footer: LuxeAddRow(
        label: 'Apparaat toevoegen',
        onTap: () async {
          final pick = await showPickDeviceTypeSheet(context);
          if (!context.mounted) return;
          if (pick != null) _addDevice(fi, ri, pick);
        },
      ),
    );
  }

  Widget _buildingInspector(BuildContext context) {
    switch (_sel.kind) {
      case _FocusKind.floor:
        return ListView(
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            _floorNameCard(),
          ],
        );
      case _FocusKind.room:
        return ListView(
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            _roomFieldsCard(),
          ],
        );
      case _FocusKind.device:
        return _DeviceForm(
          device: _deviceList(_sel.fi, _sel.ri)[_sel.di],
          house: _house!,
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_deviceList(_sel.fi, _sel.ri)[_sel.di]),
          onPaste: () => _pasteDeviceIntoList(
            _deviceList(_sel.fi, _sel.ri),
            afterIndex: _sel.di,
            onPasted: (i) => _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
          ),
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'Kies een apparaat om de gegevens te zien.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: LuxeColors.inkSoft,
                  ),
            ),
          ),
        );
    }
  }

  Widget _floorsPathCard() {
    final crumbs = <(String, VoidCallback, bool)>[
      (
        'Kamers',
        () => _selectFocus(const _Focus.floors()),
        _sel.kind == _FocusKind.floors,
      ),
    ];
    if (_sel.fi >= 0 &&
        (_sel.kind == _FocusKind.floor ||
            _sel.kind == _FocusKind.room ||
            _sel.kind == _FocusKind.device)) {
      crumbs.add((
        _namedOr(_floors()[_sel.fi], 'Verdieping'),
        () => _selectFocus(_Focus.floor(_sel.fi)),
        _sel.kind == _FocusKind.floor,
      ));
    }
    if (_sel.ri >= 0 &&
        (_sel.kind == _FocusKind.room || _sel.kind == _FocusKind.device)) {
      crumbs.add((
        _namedOr(_roomList(_sel.fi)[_sel.ri], 'Kamer'),
        () => _selectFocus(_Focus.room(_sel.fi, _sel.ri)),
        _sel.kind == _FocusKind.room,
      ));
    }
    return LuxeListCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: LuxeColors.inkSoft,
                ),
              ),
            InkWell(
              onTap: crumbs[i].$3 ? null : crumbs[i].$2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  crumbs[i].$1,
                  style: TextStyle(
                    fontWeight:
                        crumbs[i].$3 ? FontWeight.w600 : FontWeight.w400,
                    color: crumbs[i].$3 ? LuxeColors.ink : LuxeColors.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _floorsInstallerPanel(BuildContext context) {
    final floors = _floors();
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: LuxeSectionTitle(
                  icon: Icons.layers_outlined,
                  title: 'Kamergebonden devices',
                  trailing: LuxeInfoIconButton(
                    title: 'Kamergebonden devices',
                    body:
                        'Apparaten die bij een kamer horen: eerst een verdieping, '
                        'daarna kamers, daarna de apparaten in die kamer. '
                        'Op de telefoon: tik door en gebruik terug om in één scherm te blijven.',
                  ),
                ),
              ),
              if (floors.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Text(
                    'Nog geen verdieping',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < floors.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: Icons.layers_outlined,
                  title: _namedOr(floors[i], 'Verdieping'),
                  subtitle:
                      _countLabel(_roomList(i).length, 'kamer', 'kamers'),
                  selected: _sel.kind == _FocusKind.floor && _sel.fi == i,
                  trailing: _rowTrash(
                    tooltip: 'Verdieping verwijderen',
                    onPressed: () => _deleteFloorAt(i),
                  ),
                  onTap: () => _selectFocus(_Focus.floor(i)),
                ),
              ],
              if (floors.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Verdieping toevoegen',
                onTap: _addFloor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _systemTileIconRow(String key, {bool expanded = false}) {
    final icon = universalIconData(key);
    final glyph = iconWidgetForData(
          icon,
          size: 18,
          color: LuxeColors.ink,
        ) ??
        Icon(icon, size: 18, color: LuxeColors.ink);
    final label = Text(key, overflow: TextOverflow.ellipsis);
    return Row(
      children: [
        glyph,
        const SizedBox(width: 8),
        if (expanded) Expanded(child: label) else Flexible(child: label),
      ],
    );
  }

  Widget _houseSystemsEditorCard(BuildContext context) {
    final tiles = _houseSystemsList();
    final iconKeys = kUniversalIconMap.keys.toList()..sort();
    return LuxeListCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: LuxeSectionTitle(
              icon: Icons.dashboard_outlined,
              title: 'Custom systeemtegels',
              trailing: LuxeInfoIconButton(
                title: 'Custom systeemtegels',
                body:
                    'Deze tegels komen onder Systemen op het startscherm. '
                    'Voeg met + elk apparaat toe (ook universeel, ook uit een kamer). '
                    'Het apparaat blijft op de oude plek staan.',
              ),
            ),
          ),
          if (tiles.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(
                'Nog geen extra tegel. Vaste tegels (verlichting, ventilatie, …) '
                'verschijnen vanzelf als er apparaten van dat type zijn.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('sys-icon-${tiles[i]['id']}'),
                      initialValue: iconKeys.contains(tiles[i]['icon'])
                          ? tiles[i]['icon'] as String
                          : 'grid',
                      isExpanded: true,
                      decoration: luxeFilledDecoration(),
                      selectedItemBuilder: (context) => [
                        for (final key in iconKeys)
                          _systemTileIconRow(key, expanded: true),
                      ],
                      items: [
                        for (final key in iconKeys)
                          DropdownMenuItem(
                            value: key,
                            child: _systemTileIconRow(key),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        tiles[i]['icon'] = v;
                        setState(() {});
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tegel verwijderen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteHouseSystemTile(i),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: _BoundStrField(
                'name',
                tiles[i],
                () => setState(() {}),
                key: ValueKey('sys-name-${tiles[i]['id']}'),
                labelOverride: 'Naam',
              ),
            ),
            for (final rawId in List<dynamic>.from(_tileDeviceIds(tiles[i])))
              Builder(
                builder: (context) {
                  final id = rawId.toString();
                  final info = _catalogDevice(id);
                  final title = info?.name ?? id;
                  final sub = info == null
                      ? 'Apparaat ontbreekt'
                      : [
                          _deviceTypeLabels[info.type] ?? info.type,
                          info.where,
                        ].where((s) => s.isNotEmpty).join(' · ');
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 8, right: 0),
                      title: Text(title),
                      subtitle: Text(sub),
                      trailing: IconButton(
                        tooltip: 'Van tegel halen',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _tileDeviceIds(tiles[i]).remove(rawId);
                          setState(() {});
                        },
                      ),
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: LuxeAddRow(
                label: 'Apparaat toevoegen',
                onTap: () => _pickDeviceForSystemTile(i),
              ),
            ),
          ],
          if (tiles.isNotEmpty)
            Divider(height: 1, color: LuxeColors.lineSoft),
          LuxeAddRow(
            label: 'Tegel toevoegen',
            onTap: _addHouseSystemTile,
          ),
        ],
      ),
    );
  }

  Widget _houseSystemsInstallerPanel(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        _houseSystemsEditorCard(context),
      ],
    );
  }

  Widget _globalDevicesInstallerPanel(BuildContext context) {
    final list = _globalDeviceList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: LuxeSectionTitle(
                  icon: Icons.devices_other_outlined,
                  title: 'Algemene devices',
                  trailing: LuxeInfoIconButton(
                    title: 'Algemene devices',
                    body:
                        'Apparaten die bij het hele huis horen, niet bij één kamer. '
                        'Kies per apparaat op welke systeemtegel het komt.',
                  ),
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Text(
                    'Nog geen algemeen apparaat',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: Icons.devices_other_outlined,
                  title: _namedOr(list[i], 'Apparaat'),
                  subtitle: _globalDeviceSubtitle(list[i]),
                  selected:
                      _sel.kind == _FocusKind.globalDevice && _sel.di == i,
                  trailing: _rowTrash(
                    tooltip: 'Apparaat verwijderen',
                    onPressed: () => _deleteGlobalDeviceAt(i),
                  ),
                  onTap: () => _selectFocus(_Focus.globalDevice(i)),
                ),
              ],
              if (list.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Toevoegen',
                onTap: () async {
                  final pick = await showPickGeneralDeviceTypeSheet(context);
                  if (!context.mounted) return;
                  if (pick != null) _addGlobalDevice(pick);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _globalDeviceSubtitle(Map<String, dynamic> d) {
    final type = _deviceRowSubtitle(d);
    final sid = (d['systemId'] as String?)?.trim();
    if (sid == null || sid.isEmpty) return type;
    for (final s in kHouseSystems) {
      if (s.slug == sid) return '$type · ${s.name}';
    }
    for (final t in _houseSystemsList()) {
      if (t['id'] == sid) {
        final n = (t['name'] as String?)?.trim();
        return '$type · ${n == null || n.isEmpty ? sid : n}';
      }
    }
    return type;
  }

  Widget _roomDevicesCard(int fi, int ri) {
    final devices = _deviceList(fi, ri);
    return LuxeListCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: LuxeSectionTitle(
              icon: Icons.tune_outlined,
              title: 'Apparaten',
              trailing: IconButton(
                tooltip: 'Apparaat plakken',
                icon: const Icon(Icons.content_paste_outlined),
                onPressed: () => _pasteDeviceIntoList(
                  devices,
                  onPasted: (i) => _selectFocus(_Focus.device(fi, ri, i)),
                ),
              ),
            ),
          ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(
                'Nog geen apparaat',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (var di = 0; di < devices.length; di++) ...[
            if (di > 0) Divider(height: 1, color: LuxeColors.lineSoft),
            LuxeNavRow(
              icon: Icons.tune_outlined,
              title: _namedOr(devices[di], 'Apparaat'),
              subtitle: _deviceRowSubtitle(devices[di]),
              selected: _sel.kind == _FocusKind.device &&
                  _sel.fi == fi &&
                  _sel.ri == ri &&
                  _sel.di == di,
              trailing: _rowTrash(
                tooltip: 'Apparaat verwijderen',
                onPressed: () => _deleteDeviceAt(fi, ri, di),
              ),
              onTap: () => _selectFocus(_Focus.device(fi, ri, di)),
            ),
          ],
          if (devices.isNotEmpty)
            Divider(height: 1, color: LuxeColors.lineSoft),
          LuxeAddRow(
            label: 'Apparaat toevoegen',
            onTap: () async {
              final pick = await showPickDeviceTypeSheet(context);
              if (!context.mounted) return;
              if (pick != null) _addDevice(fi, ri, pick);
            },
          ),
        ],
      ),
    );
  }

  Widget _floorNameCard() {
    final floor = _floors()[_sel.fi];
    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSectionTitle(
            icon: Icons.layers_outlined,
            title: 'Verdieping',
            trailing: LuxeInfoIconButton(
              title: 'Verdieping',
              body: 'Naam zoals in de app.',
            ),
          ),
          _BoundStrField('name', floor, () => setState(() {}),
              labelOverride: 'Naam'),
        ],
      ),
    );
  }

  Widget _roomFieldsCard() {
    final room = _roomList(_sel.fi)[_sel.ri];
    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSectionTitle(
            icon: Icons.meeting_room_outlined,
            title: 'Kamer',
            trailing: LuxeInfoIconButton(
              title: 'Kamer',
              body: 'Naam zoals in de app.',
            ),
          ),
          _BoundStrField('name', room, () => setState(() {}),
              labelOverride: 'Naam'),
        ],
      ),
    );
  }

  Widget _floorInstallerPanel(BuildContext context) {
    final fi = _sel.fi;
    final rooms = _roomList(fi);
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        _floorsPathCard(),
        _floorNameCard(),
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 14, 4),
                child: LuxeSectionTitle(
                  icon: Icons.meeting_room_outlined,
                  title: 'Kamers',
                ),
              ),
              if (rooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Text(
                    'Nog geen kamer',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var ri = 0; ri < rooms.length; ri++) ...[
                if (ri > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: Icons.meeting_room_outlined,
                  title: _namedOr(rooms[ri], 'Kamer'),
                  subtitle: _countLabel(
                      _deviceList(fi, ri).length, 'apparaat', 'apparaten'),
                  selected:
                      _sel.kind == _FocusKind.room && _sel.fi == fi && _sel.ri == ri,
                  trailing: _rowTrash(
                    tooltip: 'Kamer verwijderen',
                    onPressed: () => _deleteRoomAt(fi, ri),
                  ),
                  onTap: () => _selectFocus(_Focus.room(fi, ri)),
                ),
              ],
              if (rooms.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Kamer toevoegen',
                onTap: () => _addRoom(fi),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roomInstallerPanel(BuildContext context) {
    final fi = _sel.fi;
    final ri = _sel.ri;
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        _floorsPathCard(),
        _roomFieldsCard(),
        _roomDevicesCard(fi, ri),
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
          sceneLearn: _ensureSceneLearn(),
          rooms: _sceneLearnRooms(),
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
          house: _house!,
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_cameras()[_sel.ci!]),
          onPaste: () => _pasteDeviceIntoList(
            _cameras(),
            afterIndex: _sel.ci,
            onPasted: (i) => _selectFocus(_Focus.cameraDetail(i)),
          ),
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
          house: _house!,
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_intercoms()[_sel.ci!]),
          onPaste: () => _pasteDeviceIntoList(
            _intercoms(),
            afterIndex: _sel.ci,
            onPasted: (i) => _selectFocus(_Focus.intercomDetail(i)),
          ),
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
      case _FocusKind.floors:
        return _floorsInstallerPanel(context);
      case _FocusKind.houseSystems:
        return _houseSystemsInstallerPanel(context);
      case _FocusKind.globalDevices:
        return _globalDevicesInstallerPanel(context);
      case _FocusKind.floor:
        return _floorInstallerPanel(context);
      case _FocusKind.room:
        return _roomInstallerPanel(context);
      case _FocusKind.device:
        return _DeviceForm(
          device: _deviceList(_sel.fi, _sel.ri)[_sel.di],
          house: _house!,
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_deviceList(_sel.fi, _sel.ri)[_sel.di]),
          onPaste: () => _pasteDeviceIntoList(
            _deviceList(_sel.fi, _sel.ri),
            afterIndex: _sel.di,
            onPasted: (i) => _selectFocus(_Focus.device(_sel.fi, _sel.ri, i)),
          ),
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
          leading: [
            _floorsPathCard(),
          ],
        );
      case _FocusKind.globalDevice:
        return _DeviceForm(
          device: _globalDeviceList()[_sel.di],
          house: _house!,
          onChanged: () => setState(() {}),
          onCopy: () => _copyDevice(_globalDeviceList()[_sel.di]),
          onPaste: () => _pasteDeviceIntoList(
            _globalDeviceList(),
            afterIndex: _sel.di,
            onPasted: (i) => _selectFocus(_Focus.globalDevice(i)),
          ),
          getInstallerToken: () async {
            if (widget.useCustomerSession) {
              return ref.read(authProvider).token;
            }
            return ref.read(installerAuthProvider).token;
          },
          showSystemTile: true,
        );
    }
  }

  Widget _usersPanel(BuildContext context) {
    final list = _users();
    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: Text(
            'Nieuwe gebruikers: vul een code in en kies Opslaan. '
            'Bestaande: laat code leeg om hem te houden.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuxeColors.inkSoft,
                ),
          ),
        ),
        LuxeListCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Text(
                    'Nog geen gebruikers',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, color: LuxeColors.lineSoft),
                LuxeNavRow(
                  icon: isInstallerRole(list[i]['role'] as String?)
                      ? Icons.construction_outlined
                      : isSuperUserRole(list[i]['role'] as String?)
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                  title: () {
                    final name = (list[i]['displayName'] as String?)?.trim();
                    final username = list[i]['username'] as String? ?? '';
                    if (name != null && name.isNotEmpty) return name;
                    return username.isEmpty ? 'Nieuwe gebruiker' : username;
                  }(),
                  subtitle: [
                    if ((list[i]['username'] as String?)?.isNotEmpty == true)
                      list[i]['username'],
                    roleLabel(list[i]['role'] as String?),
                  ].join(' · '),
                  selected: _sel.kind == _FocusKind.user && _sel.fi == i,
                  trailing: LuxeOnOffSwitch(
                    value: list[i]['enabled'] != false,
                    onChanged: (v) {
                      list[i]['enabled'] = v;
                      setState(() {});
                    },
                  ),
                  onTap: () => _selectFocus(_Focus.user(i)),
                ),
              ],
              if (list.isNotEmpty)
                Divider(height: 1, color: LuxeColors.lineSoft),
              LuxeAddRow(
                label: 'Gebruiker toevoegen',
                onTap: _addUser,
              ),
            ],
          ),
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
      house: _house!,
      user: list[i],
      floors: aclFloorsFromHouseMaps(_floors()),
      extras: AclHouseExtras.fromHouseMap(_house!),
      onChanged: () => setState(() {}),
      onDelete: () {
        unbindSipFromUser(_house!, list[i]);
        list.removeAt(i);
        setState(() => _sel = const _Focus.users());
      },
    );
  }
}

class _InstallerUserForm extends StatefulWidget {
  const _InstallerUserForm({
    super.key,
    required this.house,
    required this.user,
    required this.floors,
    required this.extras,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> house;
  final Map<String, dynamic> user;
  final List<AclNavFloor> floors;
  final AclHouseExtras extras;
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
    final r = normalizeRole(widget.user['role'] as String?);
    widget.user['role'] = switch (r) {
      AppRole.installer => 'installer',
      AppRole.superuser => 'superuser',
      AppRole.user => 'user',
    };
    if (widget.user['enabled'] == null) widget.user['enabled'] = true;
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
      'functions': '*',
      'devices': '*',
      'scenes': '*',
      'editScenes': true,
    };
    widget.user['access'] = m;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    _ensureAccess();
    final roleRaw = u['role'] as String? ?? 'user';
    final role = normalizeRole(roleRaw);
    final roleValue = switch (role) {
      AppRole.installer => 'installer',
      AppRole.superuser => 'superuser',
      AppRole.user => 'user',
    };

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Gebruiker', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _BoundStrField('id', u, widget.onChanged),
        _BoundStrField(
          'username',
          u,
          widget.onChanged,
          labelOverride: 'Inlognaam',
          hintText: 'Uniek, waarmee deze persoon inlogt',
        ),
        _BoundStrField(
          'displayName',
          u,
          widget.onChanged,
          labelOverride: 'Weergavenaam',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LuxeFieldLabel('Rol'),
              DropdownButtonFormField<String>(
                initialValue: roleValue,
                decoration: luxeFilledDecoration(),
                items: const [
                  DropdownMenuItem(value: 'installer', child: Text('Installer')),
                  DropdownMenuItem(value: 'superuser', child: Text('Super user')),
                  DropdownMenuItem(value: 'user', child: Text('Gebruiker')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    u['role'] = v;
                    widget.onChanged();
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LuxeFieldLabel(
                u['_new'] == true
                    ? 'Code'
                    : 'Nieuwe code (leeg = ongewijzigd)',
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: luxeFilledDecoration(
                  hint: u['_new'] == true ? 'Minstens 4 tekens' : null,
                  helper: u['_new'] == true
                      ? 'Verplicht bij een nieuw account.'
                      : null,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LuxeSwitchRow(
                      title: 'Ontvangt deurbel-oproepen',
                      subtitle: ensureVoipMap(widget.house)['enabled'] == true
                          ? 'Automatisch gekoppeld aan het toestel van deze gebruiker.'
                          : 'Zet deurbel-oproepen aan bij Intercom.',
                      value: sipEndpointForUser(widget.house, u) != null,
                      onChanged: ensureVoipMap(widget.house)['enabled'] == true
                          ? (v) {
                              if (v) {
                                bindSipToUser(widget.house, u);
                              } else {
                                unbindSipFromUser(widget.house, u);
                              }
                              widget.onChanged();
                              setState(() {});
                            }
                          : null,
                    ),
                  ),
                  if (ensureVoipMap(widget.house)['enabled'] == true)
                    const LuxeInfoIconButton(
                      title: 'Deurbel-oproepen',
                      body:
                          'Dit account gaat over als het in een belgroep staat. '
                          'Nummer en wachtwoord worden automatisch aangemaakt — '
                          'niet nodig op het toestel in te vullen.',
                    ),
                ],
              ),
            ],
          ),
        ),
        if (role == AppRole.user) ...[
          const SizedBox(height: 16),
          Text('Vrijgegeven toegang', style: Theme.of(context).textTheme.titleMedium),
          UserAccessEditor(
            user: u,
            floors: widget.floors,
            extras: widget.extras,
            onChanged: () {
              widget.onChanged();
              setState(() {});
            },
          ),
        ],
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
          const AdminServerUpdateCard(),
          const SizedBox(height: 16),
          const AdminFullRestartCard(),
        ],
      ],
    );
  }
}

class _KnxInstallerSection extends StatefulWidget {
  const _KnxInstallerSection({
    required this.knx,
    required this.sceneLearn,
    required this.rooms,
    required this.onChanged,
    required this.getToken,
    required this.onImport,
    required this.onImportInfo,
  });

  final Map<String, dynamic> knx;
  final Map<String, dynamic> sceneLearn;
  final List<({String id, String label})> rooms;
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
            sceneLearn: widget.sceneLearn,
            rooms: widget.rooms,
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
        LuxeSwitchRow(
          title: 'Telnet ingeschakeld',
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
    required this.sceneLearn,
    required this.rooms,
    required this.onChanged,
    required this.onImport,
    required this.onImportInfo,
  });
  final Map<String, dynamic> knx;
  final Map<String, dynamic> sceneLearn;
  final List<({String id, String label})> rooms;
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
        LuxeSwitchRow(
          title: 'KNX ingeschakeld',
          subtitle:
              'Schakel uit als er geen KNX-bus aanwezig is. '
              'De app start dan direct op zonder verbindingspogingen.',
          value: enabled,
          onChanged: (v) {
            knx['enabled'] = v;
            onChanged();
          },
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
          const Divider(height: 32),
          Text(
            "KNX scene's inleren",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Vul hier de scene-groepsadressen in (DPT 18.001) zoals ze in ETS '
            'op de muurknoppen staan, en kies per adres de ruimte.\n\n'
            'Gebruikers kunnen daarna in Instellingen de waarden van die '
            'KNX-scenes zelf bijstellen (licht, gordijnen) en opslaan in KNX — '
            'mits scene opslaan (store/leren) in ETS is vrijgegeven.\n\n'
            'Zonder adressen hieronder verschijnt die functie niet in Instellingen. '
            'De KNX-programmeur bepaalt welke lampen op de scene zitten; de app '
            'past alleen de waarden aan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _SceneAddressList(
            sceneLearn: sceneLearn,
            rooms: rooms,
            onChanged: onChanged,
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

class _SceneAddressList extends StatelessWidget {
  const _SceneAddressList({
    required this.sceneLearn,
    required this.rooms,
    required this.onChanged,
  });
  final Map<String, dynamic> sceneLearn;
  final List<({String id, String label})> rooms;
  final VoidCallback onChanged;

  List<Map<String, dynamic>> _rows() {
    final raw = sceneLearn['addresses'];
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(e);
      } else if (e is String && e.trim().isNotEmpty) {
        out.add({'ga': e.trim()});
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (sceneLearn['addresses'] is! List ||
        (sceneLearn['addresses'] as List).length != rows.length) {
      sceneLearn['addresses'] = rows;
    }
    final knownIds = {for (final r in rooms) r.id};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _BoundStrField(
                  'ga',
                  rows[i],
                  onChanged,
                  labelOverride: 'Scene-adres (GA)',
                  gaSearch: true,
                  gaDptHint: 'DPT18.001',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _sceneRoomDropdown(rows[i], knownIds),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                onPressed: () {
                  rows.removeAt(i);
                  sceneLearn['addresses'] = rows;
                  onChanged();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _BoundStrField(
            'name',
            rows[i],
            onChanged,
            labelOverride: 'Naam (optioneel, intern)',
            emptyMeansRemove: true,
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              rows.add(<String, dynamic>{'ga': '', 'roomId': ''});
              sceneLearn['addresses'] = rows;
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Scene-adres toevoegen'),
          ),
        ),
      ],
    );
  }

  Widget _sceneRoomDropdown(
    Map<String, dynamic> row,
    Set<String> knownIds,
  ) {
    final current = '${row['roomId'] ?? ''}'.trim();
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Kies ruimte')),
      for (final r in rooms)
        DropdownMenuItem(value: r.id, child: Text(r.label)),
    ];
    if (current.isNotEmpty && !knownIds.contains(current)) {
      items.add(DropdownMenuItem(value: current, child: Text(current)));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LuxeFieldLabel('Ruimte / kamer'),
          DropdownButtonFormField<String>(
            key: ValueKey('scene-room-$current-${rooms.length}'),
            initialValue: current,
            isExpanded: true,
            decoration: luxeFilledDecoration(),
            items: items,
            onChanged: (v) {
              final next = (v ?? '').trim();
              if (next.isEmpty) {
                row.remove('roomId');
              } else {
                row['roomId'] = next;
              }
              onChanged();
            },
          ),
        ],
      ),
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
    final next = _initialText();
    if (_c.text != next) {
      _c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _gaSearchEnabled {
    if (widget.gaSearch) return true;
    return knxFieldLooksLikeGa(
      keyName: widget.keyName,
      label: widget.labelOverride,
    );
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeFieldLabel(widget.labelOverride ?? widget.keyName),
          TextField(
            controller: _c,
            decoration: luxeFilledDecoration(
              hint: widget.hintText,
              helper: resolvedName,
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
                widget.keyName == 'onPercent' ||
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
        ],
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeFieldLabel(label),
          DropdownButtonFormField<String>(
            initialValue: value,
            decoration: luxeFilledDecoration(),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
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
          Row(
            children: [
              Expanded(
                child: Text('Type zonwering',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              const LuxeInfoIconButton(
                title: 'Type zonwering',
                body:
                    'Bepaalt het icoon en de bediening in de app: '
                    'open/dicht (gordijn, vitrage) of omhoog/omlaag '
                    '(jaloezie, rolluik, screen).',
              ),
            ],
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
          Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
              const LuxeInfoIconButton(
                title: 'Zichtbare bediening',
                body:
                    'Kies welke knoppen en sliders in de app staan. '
                    'Zonder eigen keuze toont de app wat de groepadressen toelaten. '
                    'Lamellen stap zet het lamellen-adres telkens 5 procent bij of af.',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasPos)
            LuxeSwitchRow(
              title: 'Positie-slider',
              value: _get('showPositionSlider', defPosSlider),
              onChanged: (v) => _setBool('showPositionSlider', v),
            ),
          LuxeSwitchRow(
            title: 'Rij knoppen onder positie-slider (omhoog/stop/omlaag)',
            subtitle: 'Alleen als de positie-slider aan staat',
            value: _get('showMoveButtonsUnderSlider', defPosSlider && hasPos),
            onChanged: (hasPos && _get('showPositionSlider', defPosSlider))
                ? (v) => _setBool('showMoveButtonsUnderSlider', v)
                : null,
          ),
          LuxeSwitchRow(
            title: 'Knop omhoog / open',
            value: _get('showMoveUp', true),
            onChanged: (v) => _setBool('showMoveUp', v),
          ),
          LuxeSwitchRow(
            title: 'Knop stop',
            subtitle: hasStop ? null : 'Geen stop_step-GA in config',
            value: _get('showMoveStop', hasStop),
            onChanged: hasStop ? (v) => _setBool('showMoveStop', v) : null,
          ),
          LuxeSwitchRow(
            title: 'Knop omlaag / dicht',
            value: _get('showMoveDown', true),
            onChanged: (v) => _setBool('showMoveDown', v),
          ),
          LuxeSwitchRow(
            title: 'Lamellen-slider',
            value: _get('showSlatSlider', showSlatsLegacy),
            onChanged:
                showSlatsLegacy ? (v) => _setBool('showSlatSlider', v) : null,
          ),
          LuxeSwitchRow(
            title: 'Lamellen stap (+ / − 5 %)',
            subtitle: hasSlat ? null : 'Geen slat-GA',
            value: _get('showSlatStepButtons', false),
            onChanged: hasSlat ? (v) => _setBool('showSlatStepButtons', v) : null,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _clearUi,
              child: const Text('Herstel standaardweergave'),
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
    if (n != 3 && n != 4) return;
    var list = flame['stepRanges'];
    if (list is! List || list.isEmpty) {
      flame['stepRanges'] = _defaultAnalogStepRanges(count: n);
      flame['steps'] = n;
      return;
    }
    while (list.length < n) {
      final prev = list.last;
      var prevMax = 0;
      if (prev is Map) {
        prevMax = (prev['max'] as num?)?.round() ?? 0;
      }
      final min = prevMax >= 100 ? 100 : prevMax + 1;
      list.add(<String, dynamic>{
        'min': min,
        'max': 100,
        'write': 100,
      });
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

    final rows = _mutableRanges();
    final err = rows.length >= 3
        ? validateFireplaceStepRanges(rows)
        : 'Kies 3 of 4 standen.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Vlamstanden — knoppen in de app',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Kies 3 of 4 standen. Per stand: min–max % op de bus (terugmelding) '
          'en optioneel het schrijf-% dat de knop stuurt. Geen overlap: het '
          'maximum van stap n moet strikt kleiner zijn dan het minimum van stap n+1.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(
            children: [
              Text('Aantal standen',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: rows.length == 4 ? 4 : 3,
                items: const [
                  DropdownMenuItem(value: 3, child: Text('3 knoppen')),
                  DropdownMenuItem(value: 4, child: Text('4 knoppen')),
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
          LuxeSwitchRow(
          title: 'Percentage verbergen op knoppen',
          subtitle: 
                'Verberg het %-bereik als sublabel op de vlamstand-knoppen.',
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
    );
  }
}

/// Openhaard: geen JSON — KNX-configurateur kiest werking en vult GA’s in.
enum _FireplaceOpMode {
  analogFlame,
  analogSwitchOnly,
  discretePulses,
  planika,
}

List<Map<String, dynamic>> _defaultAnalogStepRanges({int count = 3}) {
  if (count == 4) {
    return [
      <String, dynamic>{'min': 1, 'max': 25, 'write': 20},
      <String, dynamic>{'min': 26, 'max': 50, 'write': 40},
      <String, dynamic>{'min': 51, 'max': 75, 'write': 60},
      <String, dynamic>{'min': 76, 'max': 100, 'write': 90},
    ];
  }
  return [
    <String, dynamic>{'min': 1, 'max': 33, 'write': 20},
    <String, dynamic>{'min': 34, 'max': 66, 'write': 50},
    <String, dynamic>{'min': 67, 'max': 100, 'write': 80},
  ];
}

void _ensureAnalogStands(Map<String, dynamic> flame) {
  final parsed = parseFireplaceStepRanges(flame);
  if (parsed != null && parsed.length >= 3 && parsed.length <= 4) return;
  flame['stepRanges'] = _defaultAnalogStepRanges();
  flame['steps'] = 3;
}

_FireplaceOpMode _fireplaceReadMode(Map<String, dynamic> fp) {
  if (fp['protocol'] == 'planika' ||
      (fp['controlMode'] == 'discrete' && fp['statusBits'] is Map)) {
    return _FireplaceOpMode.planika;
  }
  if (fp['controlMode'] == 'discrete') {
    return _FireplaceOpMode.discretePulses;
  }
  if (fp['protocol'] == 'analog_interface' || fp['flame'] is Map) {
    return _FireplaceOpMode.analogFlame;
  }
  return _FireplaceOpMode.analogSwitchOnly;
}

void _fireplaceStripPulseMs(Map<String, dynamic> fp) {
  final dl = fp['discreteLevel'];
  if (dl is! Map) return;
  for (final k in const ['on', 'off', 'up', 'down']) {
    final ch = dl[k];
    if (ch is Map) ch.remove('pulseMs');
  }
}

void _fireplaceApplyMode(Map<String, dynamic> fp, _FireplaceOpMode mode) {
  switch (mode) {
    case _FireplaceOpMode.analogFlame:
      fp['controlMode'] = 'analog';
      fp['protocol'] = 'analog_interface';
      fp.remove('discreteLevel');
      fp.remove('statusBits');
      _ensureOnOff(fp);
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
      final sr = oldM['stepRanges'];
      if (sr is List) flame['stepRanges'] = sr;
      if (oldM['hideStepPercent'] == true) {
        flame['hideStepPercent'] = true;
      }
      final onP = oldM['onPercent'];
      if (onP is num) {
        flame['onPercent'] = onP.round().clamp(0, 100);
      } else {
        flame['onPercent'] = 20;
      }
      _ensureAnalogStands(flame);
      fp['flame'] = flame;
      break;
    case _FireplaceOpMode.analogSwitchOnly:
      fp['controlMode'] = 'analog';
      fp.remove('discreteLevel');
      fp.remove('statusBits');
      fp.remove('protocol');
      fp.remove('flame');
      _ensureOnOff(fp);
      break;
    case _FireplaceOpMode.discretePulses:
      fp['controlMode'] = 'discrete';
      fp['protocol'] = 'mertik_gv60';
      fp.remove('flame');
      fp.remove('statusBits');
      fp['discreteLevel'] ??= <String, dynamic>{};
      _ensureOnOff(fp);
      break;
    case _FireplaceOpMode.planika:
      fp['controlMode'] = 'discrete';
      fp['protocol'] = 'planika';
      fp.remove('flame');
      fp.remove('onOff');
      fp['discreteLevel'] ??= <String, dynamic>{};
      fp['statusBits'] ??= <String, dynamic>{};
      _fireplaceStripPulseMs(fp);
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
    final planika = mode == _FireplaceOpMode.planika;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LuxeFieldLabel('Werking'),
        DropdownButtonFormField<_FireplaceOpMode>(
            key: ValueKey('fp-mode-${device['id']}-$mode'),
            decoration: luxeFilledDecoration(),
            initialValue: mode,
            items: const [
              DropdownMenuItem(
                value: _FireplaceOpMode.analogFlame,
                child: Text('Analoge interface 0–10 V / 0–3 V'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.analogSwitchOnly,
                child: Text('Alleen bit (aan/uit)'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.discretePulses,
                child: Text('Mertik GV60 (4× puls start/stop/omhoog/omlaag)'),
              ),
              DropdownMenuItem(
                value: _FireplaceOpMode.planika,
                child: Text('Planika (start/stop + 4 status)'),
              ),
            ],
            onChanged: (_FireplaceOpMode? next) {
              if (next == null) return;
              _fireplaceApplyMode(fp, next);
              onChanged();
            },
          ),
          if (mode == _FireplaceOpMode.analogFlame) ...[
            const SizedBox(height: 8),
            Text(
              'Analoge interface: aan/uit-bit plus vlam als DPT5 (0–100 % op de bus = '
              '0–10 V of 0–3 V). De gebruiker krijgt 3 of 4 standknoppen. Vul per '
              'stand de percentages in, plus het percentage bij aanzetten.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
          if (planika) ...[
            const SizedBox(height: 8),
            Text(
              'Planika: 4 commando-GA’s (Start/Stop/Omhoog/Omlaag) — de app '
              'schrijft alleen 1; de puls maakt KNX. Status alleen via de 4 '
              'contacten; geen aan/uit-adres. Working = aan. Combinaties: '
              'Error+Fuel = Bijvullen, Working+Ready = Wachten/Koelen.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
          if (mode == _FireplaceOpMode.discretePulses) ...[
            const SizedBox(height: 8),
            Text(
              'Mertik GV60: 4 pulscontacten. De app stuurt 1 en daarna 0 '
              '(standaard 250 ms). Optioneel een aan/uit-statusadres voor de app.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
          if (!planika) ...[
          const SizedBox(height: 20),
          Text('Aan / uit', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Schrijf-Groepadres (bit). Optioneel status voor terugmelding in de app.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final onOff = _ensureOnOff(fp);
              return Column(
                children: [
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
                ],
              );
            },
          ),
          ],
          if (mode == _FireplaceOpMode.analogFlame) ...[
            const SizedBox(height: 20),
            Text('Vlamsterkte (DPT5, 0–100 % op de bus)',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Schrijf-GA voor het analoge niveau. 100 % = 10 V of 3 V, afhankelijk '
              'van de actor. De app toont de gekozen schaal; de bus blijft 0–100 %.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final flame = _ensureFlame(fp);
                _ensureAnalogStands(flame);
                if (flame['onPercent'] is! num) {
                  flame['onPercent'] = 20;
                }
                final ld = (flame['levelDisplay'] as String?) ?? 'percent';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BoundStrField(
                      'ga',
                      flame,
                      onChanged,
                      labelOverride: 'Groepsadres schrijven (byte 0–100 %)',
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
                    _BoundStrField(
                      'onPercent',
                      flame,
                      onChanged,
                      number: true,
                      labelOverride: 'Percentage bij aanzetten (0–100)',
                      hintText: 'bijv. 20',
                      key: ValueKey('fp-fl-${device['id']}-onpct'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Na het aan-bit schrijft de app dit percentage naar het '
                        'vlamadres (ontsteking). Daarna kiest de gebruiker een stand.',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
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
                              child: Text('Percent (0–100 %)'),
                            ),
                            DropdownMenuItem(
                              value: 'volt_10',
                              child: Text('0–10 V (bus blijft 0–100 %)'),
                            ),
                            DropdownMenuItem(
                              value: 'volt_3',
                              child: Text('0–3 V (bus blijft 0–100 %)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            flame['levelDisplay'] = v;
                            onChanged();
                          },
                        );
                      },
                    ),
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
              mode == _FireplaceOpMode.planika) ...[
            const SizedBox(height: 16),
            Text(
              planika
                  ? 'Commando’s — per functie één bit-GA. De app schrijft alleen 1; de puls maakt KNX.'
                  : 'Mertik GV60 — per functie één bit-GA. De app stuurt 1 en daarna 0. Pulsduur standaard 250 ms.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final dl = _ensureDiscreteLevel(fp);
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
                          labelOverride: planika
                              ? 'Groepsadres (schrijf 1)'
                              : 'Groepsadres (puls 1→0)',
                          key: ValueKey('fp-dl-${device['id']}-$key-ga'),
                        ),
                        if (!planika)
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
                    row('on', 'Start'),
                    row('off', 'Stop'),
                    row('up', 'Omhoog'),
                    row('down', 'Omlaag'),
                  ],
                );
              },
            ),
          ],
          if (planika) ...[
            const SizedBox(height: 8),
            Text('Statuscontacten (bit)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Planika-status. Combinaties: Error+Fuel = Bijvullen, '
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

class _DeviceSystemTilePicker extends StatelessWidget {
  const _DeviceSystemTilePicker({
    required this.device,
    required this.house,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> house;
  final VoidCallback onChanged;

  static const _auto = '__auto__';

  @override
  Widget build(BuildContext context) {
    final choices = <(String, String)>[
      for (final s in kHouseSystems) (s.slug, s.name),
    ];
    final custom = house['houseSystems'];
    if (custom is List) {
      for (final e in custom) {
        if (e is! Map) continue;
        final id = (e['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        final name = (e['name'] as String?)?.trim();
        choices.add((id, (name == null || name.isEmpty) ? id : name));
      }
    }
    final current = (device['systemId'] as String?)?.trim() ?? '';
    final value = current.isEmpty
        ? _auto
        : (choices.any((c) => c.$1 == current) ? current : _auto);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeFieldLabel('Systeemtegel'),
          DropdownButtonFormField<String>(
            key: ValueKey('dev-sys-${device['id']}'),
            initialValue: value,
            isExpanded: true,
            decoration: luxeFilledDecoration(
              helper:
                  'Op het startscherm onder Systemen. '
                  'Universeel en extra tegels: kies hier een tegel.',
            ),
            items: [
              const DropdownMenuItem(
                value: _auto,
                child: Text('Automatisch (op type)'),
              ),
              for (final c in choices)
                DropdownMenuItem(value: c.$1, child: Text(c.$2)),
            ],
            onChanged: (v) {
              if (v == null || v == _auto) {
                device.remove('systemId');
              } else {
                device['systemId'] = v;
              }
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _DeviceForm extends StatelessWidget {
  const _DeviceForm({
    required this.device,
    required this.house,
    required this.onChanged,
    this.onCopy,
    this.onPaste,
    this.getInstallerToken,
    this.leading = const [],
    this.showSystemTile = false,
  });
  final Map<String, dynamic> device;
  final Map<String, dynamic> house;
  final VoidCallback onChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final Future<String?> Function()? getInstallerToken;
  final List<Widget> leading;
  final bool showSystemTile;

  @override
  Widget build(BuildContext context) {
    final type = device['type'] as String? ?? '';
    final typeLabel = _deviceTypeLabels[type] ?? type;
    final lutronOnly =
        device['control'] == 'lutron' && !_deviceHasKnxGa(device);
    final showBus = type == 'light_switch' ||
        type == 'light_dimmer' ||
        type == 'shading';
    final knxLight = (type == 'light_switch' || type == 'light_dimmer') &&
        device['control'] != 'lutron';
    final shadingGa = type == 'position_actuator' ||
        (type == 'shading' && device['control'] != 'lutron');
    const typed = {
      'climate',
      'rgbw_ww',
      'shading',
      'position_actuator',
      'media_sonos',
      'media_bluesound',
      'camera',
      'intercom',
      'fireplace',
      'ac',
      'fan',
      'universal',
      'wtw',
      'melding',
      'lutron_homeworks',
    };
    final showTypeCard = knxLight || shadingGa || typed.contains(type);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 36),
      children: [
        ...leading,
        LuxeListCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LuxeSectionTitle(
                icon: _deviceFormIcon(type),
                title: 'Apparaat',
                subtitle: typeLabel,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              ),
              if (type != 'intercom')
                _BoundStrField('name', device, onChanged,
                    labelOverride: 'Naam'),
              LuxeSwitchRow(
                title: 'Toon als favoriet op het dashboard',
                subtitle:
                    'Standaard-instelling voor alle gebruikers. '
                    'Gebruikers kunnen dit daarna zelf aanpassen met de ster-knop.',
                value: device['favorite'] as bool? ?? false,
                onChanged: (v) {
                  device['favorite'] = v;
                  onChanged();
                },
              ),
              if (showSystemTile) _DeviceSystemTilePicker(
                device: device,
                house: house,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (showBus)
          LuxeListCard(
            child: _DeviceBusControlSection(
              device: device,
              onChanged: onChanged,
              lutronOnly: lutronOnly,
            ),
          ),
        if (showTypeCard && type != 'intercom')
        LuxeListCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LuxeSectionTitle(
                icon: Icons.tune_outlined,
                title: _deviceConfigTitle(type),
                subtitle: _deviceConfigSubtitle(type),
                trailing: switch (type) {
                  'wtw' => const LuxeInfoIconButton(
                    title: 'WTW',
                    body:
                        'Kies eerst het type. Zehnder ComfoConnect: standen en boost '
                        'als 1-bit met eigen status-GA. Boost-tijd: set-GA en '
                        'status-set-GA (minuten in de app, seconden op de bus). '
                        'De afteller loopt in de app.',
                  ),
                  'melding' => const LuxeInfoIconButton(
                    title: 'Meldingen',
                    body:
                        'Eén regel per KNX-punt. Urgentie kleurt de app. '
                        'Reset: 0 op hetzelfde groepsadres of 1 op een eigen adres. '
                        'Zet in ETS cyclisch zenden op het meldingsadres. '
                        'Zoek groepadressen in de catalogus. Extra velden: '
                        'actief bij (gelijk, hoger of lager dan), teksten aan/uit, icoon.',
                  ),
                  _ => null,
                },
              ),
              if (shadingGa)
                _ShadingLikeGaSection(device: device, onChanged: onChanged)
              else if (knxLight)
                _LightLikeGaSection(device: device, onChanged: onChanged),
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
                  _SonosProbeCard(
                      device: device, getToken: getInstallerToken!),
                MediaKnxInstallerSection(
                  key: ValueKey('${device['id']}-media-knx'),
                  device: device,
                  onChanged: onChanged,
                ),
              ],
              if (type == 'media_bluesound') ...[
                _NestedStringFields(
                  label: 'Bluesound',
                  jsonKey: 'bluesound',
                  device: device,
                  fields: const ['host'],
                  intFields: const {'port'},
                  onChanged: onChanged,
                ),
                MediaKnxInstallerSection(
                  key: ValueKey('${device['id']}-media-knx'),
                  device: device,
                  onChanged: onChanged,
                ),
              ],
              if (type == 'camera')
                _CameraInstallerSection(
                    device: device, onChanged: onChanged),
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
                    'in de boom. Hier kun je optioneel extra keypad → KNX mappings zetten.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                LutronButtonToKnxListEditor(
                  parent: _ensureChildMap(device, 'lutronHomeworks'),
                  onChanged: onChanged,
                ),
              ],
            ],
          ),
        ),
        if (type == 'intercom') ...[
          IntercomInstallerWizard(
            device: device,
            house: house,
            onChanged: onChanged,
            getToken: getInstallerToken,
          ),
          LuxeListCard(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Geavanceerd'),
                subtitle: const Text(
                  'Merk, KNX-deur, DoorBird-API, webhook — alleen als DTMF niet volstaat',
                ),
                children: [
                  _IntercomKnxExtras(
                    device: device,
                    onChanged: onChanged,
                  ),
                  _NestedStringFields(
                    label: 'Extra stream-opties',
                    jsonKey: 'intercom',
                    device: device,
                    fields: const ['path', 'aspect'],
                    onChanged: onChanged,
                  ),
                  _RtspDeviceExtra(
                    device: device,
                    nestedKey: 'intercom',
                    includeRepublish: false,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

IconData _deviceFormIcon(String type) => switch (type) {
      'light_switch' || 'light_dimmer' || 'rgbw_ww' =>
        Icons.lightbulb_outline,
      'shading' => Icons.blinds_outlined,
      'position_actuator' => Icons.sensor_window_outlined,
      'climate' => Icons.thermostat_outlined,
      'fireplace' => Icons.local_fire_department_outlined,
      'ac' => Icons.ac_unit_outlined,
      'fan' => Icons.air,
      'universal' => Icons.grid_view_outlined,
      'wtw' => Icons.hvac_outlined,
      'melding' => Icons.notifications_outlined,
      'media_sonos' || 'media_bluesound' => Icons.speaker_outlined,
      'camera' => Icons.videocam_outlined,
      'intercom' => Icons.doorbell_outlined,
      'lutron_homeworks' => Icons.dialpad_outlined,
      _ => Icons.devices_outlined,
    };

String _deviceConfigTitle(String type) => switch (type) {
      'media_sonos' || 'media_bluesound' => 'Verbinding',
      'camera' => 'Beeld',
      'intercom' => 'Stream & koppeling',
      'lutron_homeworks' => 'Keypad → KNX',
      _ => 'Groepadressen & opties',
    };

String _deviceConfigSubtitle(String type) => switch (type) {
      'light_switch' || 'light_dimmer' =>
        'Zelfde velden als bij zonwering: schrijven, optioneel status, zoeken in de GA-catalogus.',
      'rgbw_ww' =>
        'Modus en groepadressen. Zoek elk adres in de geïmporteerde catalogus.',
      'shading' || 'position_actuator' =>
        'Jaloezie-object: schrijf- en statusadressen, plus weergave in de app.',
      'climate' || 'ac' || 'fan' || 'fireplace' || 'wtw' =>
        'Vul per functie het groepadres in. Status-GA\'s zijn optioneel.',
      'universal' || 'melding' =>
        'Zelfde opbouw: label, groepadres, DPT/waarde — met zoeken in de catalogus.',
      'media_sonos' || 'media_bluesound' =>
        'Host en poort, plus optioneel KNX-drukknoppen voor play, volume en skip.',
      'camera' =>
        'Alleen de stream-URL is nodig — dezelfde link als in VLC.',
      'intercom' =>
        'RTSP/URL en optionele KNX-groepadressen voor bel of deuropener.',
      'lutron_homeworks' =>
        'Optionele extra mappings. Telnet staat onder de Lutron-processor.',
      _ => 'Type-specifieke instellingen.',
    };

/// Camera: naam staat in de apparaatkaart; hier alleen de stream-URL.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BoundStrField(
          'rtsp',
          m,
          widget.onChanged,
          labelOverride: 'Stream-URL',
          maxLines: 3,
          hintText: 'rtsp://gebruiker:wachtwoord@192.168.1.10:554/stream',
        ),
        const SizedBox(height: 8),
        _CameraStreamProbePanel(
          rtsp: (m['rtsp'] as String?) ?? '',
          token: _installerToken(),
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
    required this.token,
  });

  final String rtsp;
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
      setState(() => _err = 'Vul eerst de stream-URL in');
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
    final live = r?.live;
    String? status;
    Color? statusColor;
    if (live != null) {
      if (live.ok) {
        final res = live.width != null && live.height != null
            ? ' · ${live.width}×${live.height}'
            : '';
        status = 'Beeld OK$res';
      } else {
        status =
            'Geen beeld. Controleer de URL, gebruikersnaam en wachtwoord.';
        statusColor = Colors.red.shade700;
      }
    }
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
          label: const Text('Verbinding testen'),
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_err!, style: TextStyle(color: Colors.red.shade700)),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                  ),
            ),
          ),
      ],
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
          LuxeSwitchRow(
          title: 'Stream opnieuw publiceren (go2rtc)',
          subtitle: 
                'Standaard aan. Zet uit alleen als go2rtc deze stream niet mag opnemen.',
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
                LuxeSwitchRow(
          title: 'Forceer FFmpeg voor live',
          subtitle: 
                      'Transcodeert naar H.264 met korte GOP — vloeiender op tablets',
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
                LuxeSwitchRow(
          title: 'Forceer: geen audio op RTSP',
          subtitle: 
                      'Helpt als WebRTC geen beeld geeft door audio op de stream',
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
                LuxeSwitchRow(
          title: 'go2rtc: backchannel uit (#backchannel=0)',
          subtitle: 
                      'Alleen bij glitchy NVR two-way-audio op RTSP',
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
  const _IntercomKnxExtras({
    required this.device,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = device['intercom'];
    if (o is! Map<String, dynamic>) return const SizedBox.shrink();
    final doorbell = _ensureChildMap(o, 'doorbell');
    final release = _ensureChildMap(o, 'release');
    final doorbird = _ensureChildMap(o, 'doorbird');
    final kind = (o['kind'] as String?) ?? 'doorbird';
    const kinds = <String, String>{
      'doorbird': 'DoorBird',
      'twoN': '2N',
      'axis': 'Axis',
      'mobotix': 'Mobotix',
      'siedle': 'Siedle (SIP-modellen)',
      'comelit': 'Comelit (SIP-modellen)',
      'unifi': 'UniFi (meestal geen SIP)',
      'other': 'Overig SIP',
      'sip': 'SIP (legacy)',
    };
    final doorMode = (o['releaseMode'] as String?) ?? 'knx';
    final doorViaDoorbird = doorMode == 'doorbird';
    final doorViaHttp = doorMode == 'http';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Merk', style: Theme.of(context).textTheme.titleSmall),
            ),
            LuxeInfoIconButton(
              title: 'Merk',
              body: kind == 'unifi'
                  ? 'UniFi Protect is meestal geen SIP-toestel. Gebruik RTSP + webhook, of UniFi Talk apart.'
                  : kind == 'siedle' || kind == 'comelit'
                      ? 'Alleen IP-modellen met SIP. Oudere bus-systemen (Vario/Simplebus) koppelen hier niet.'
                      : 'Alleen nodig als de deuropener via KNX, HTTP of DoorBird-API gaat in plaats van de DTMF-code.',
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: kinds.containsKey(kind) ? kind : 'other',
          decoration: luxeFilledDecoration(),
          items: [
            for (final e in kinds.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v == null) return;
            o['kind'] = v;
            onChanged();
          },
        ),
        const SizedBox(height: 20),
        Text('Deur / poort open',
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
              label: Text('DoorBird'),
              icon: Icon(Icons.lock_open, size: 18),
            ),
            ButtonSegment<String>(
              value: 'http',
              label: Text('HTTP'),
              icon: Icon(Icons.http, size: 18),
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
        if (!doorViaDoorbird && !doorViaHttp) ...[
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
          LuxeSwitchRow(
          title: 'HTTPS',
          subtitle: 'Poort 443 standaard bij TLS.',
          value: doorbird['useTls'] == true,
          onChanged: (v) {
              doorbird['useTls'] = v;
              onChanged();
            },
        ),
          LuxeSwitchRow(
          title: 'Zelfondertekend certificaat accepteren',
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
        if (doorViaHttp) ...[
          const SizedBox(height: 8),
          Text(
            'GET of POST naar een URL op het LAN (2N switch, Axis VAPIX, …). '
            'Gebruikersnaam mag in de URL: http://user:pass@192.168.1.50/...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          _BoundStrField(
            'url',
            _ensureChildMap(o, 'httpRelease'),
            onChanged,
            labelOverride: 'HTTP-URL',
            key: ValueKey('http-url-${device['id']}'),
          ),
          _BoundStrField(
            'method',
            _ensureChildMap(o, 'httpRelease'),
            onChanged,
            labelOverride: 'Methode (GET of POST)',
            key: ValueKey('http-method-${device['id']}'),
          ),
          _BoundStrField(
            'body',
            _ensureChildMap(o, 'httpRelease'),
            onChanged,
            labelOverride: 'Body (alleen POST, optioneel)',
            emptyMeansRemove: true,
            key: ValueKey('http-body-${device['id']}'),
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
        Text(
          isPosition
              ? 'Zelfde KNX-object als zonwering: percentage positie, '
                  'omhoog/omlaag/stop. Status-GA\'s zijn optioneel maar '
                  'aanbevolen voor live weergave in de app.'
              : 'KNX jaloezie / zonwering: schrijf- en leesadressen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final (fieldKey, label, optional) in _fields)
          _BoundStrField(
            fieldKey,
            ga,
            onChanged,
            key: ValueKey('ga-${device['id']}-$fieldKey'),
            labelOverride: optional ? '$label (optioneel)' : label,
            emptyMeansRemove: optional,
            gaSearch: true,
            gaDptHint: _gaDptHint(fieldKey),
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

class _LightLikeGaSection extends StatelessWidget {
  const _LightLikeGaSection({required this.device, required this.onChanged});
  final Map<String, dynamic> device;
  final VoidCallback onChanged;

  Map<String, dynamic> _gaMap() {
    final ga = device['ga'];
    if (ga is Map<String, dynamic>) return ga;
    final m = <String, dynamic>{};
    device['ga'] = m;
    return m;
  }

  static const _switchFields = <(String key, String label, bool optional)>[
    ('switch', 'Aan / uit (schrijven)', false),
    ('switch_status', 'Aan / uit status (lezen)', true),
  ];

  static const _dimmerFields = <(String key, String label, bool optional)>[
    ('switch', 'Aan / uit (schrijven)', false),
    ('switch_status', 'Aan / uit status (lezen)', true),
    ('dim_value', 'Dimwaarde % (schrijven)', false),
    ('dim_status', 'Dimwaarde status (lezen)', true),
  ];

  @override
  Widget build(BuildContext context) {
    final ga = _gaMap();
    final fields = device['type'] == 'light_dimmer' ? _dimmerFields : _switchFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (fieldKey, label, optional) in fields)
          _BoundStrField(
            fieldKey,
            ga,
            onChanged,
            key: ValueKey('ga-${device['id']}-$fieldKey'),
            labelOverride: optional ? '$label (optioneel)' : label,
            emptyMeansRemove: optional,
            gaSearch: true,
            gaDptHint: _gaDptHint(fieldKey),
          ),
      ],
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

/// Installer panel to define custom graphs of arbitrary group addresses.
/// Thermostats are logged automatically; this is for everything else
/// (e.g. power meters, humidity, CO₂, water usage).
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
      'name': 'Nieuwe grafiek',
      'visibleToUsers': false,
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
          'Maak grafieken van groepsadressen. Waarden worden op de server '
          'gelogd zodra ze veranderen (numerieke DPT\'s, ~90 dagen bewaard). '
          'Zet een grafiek aan voor gebruikers om hem onder Systemen → Grafieken '
          'te tonen.',
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
            LuxeSwitchRow(
              title: 'Zichtbaar voor gebruikers',
              subtitle:
                  'Anders alleen in de technische configuratie en voor de installer.',
              value: log['visibleToUsers'] == true,
              onChanged: (v) {
                log['visibleToUsers'] = v;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Groepsadressen',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Voeg minstens één groepsadres toe.',
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
            hintText: '°C, %, W, kWh …',
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
      padding: const EdgeInsets.only(top: 8, bottom: 36),
      children: [
        LuxeListCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LuxeSectionTitle(
                icon: Icons.security_outlined,
                title: 'Satel alarm',
                trailing: LuxeInfoIconButton(
                  title: 'Satel',
                  body:
                      'Koppeling met een Satel INTEGRA via ETHM-1 / INT-ETHER. '
                      'Zet aan, vul IP-adres en poort in (standaard 7094). '
                      'Partities en zones kun je uitlezen uit DLOADX; kamers koppel je zelf.',
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                LuxeSwitchRow(
                  title: 'Integratie',
                  value: enabled,
                  onChanged: (v) =>
                      ref.read(satelEnabledProvider.notifier).setEnabled(v),
                ),
              if (enabled) ...[
                const SizedBox(height: 8),
                _SatelConnectionCard(),
              ],
            ],
          ),
        ),
        if (enabled) ...[
          LuxeListCard(child: _SatelLiveStatus()),
          LuxeListCard(child: _SatelDiscoverCard()),
          LuxeListCard(child: _SatelPartitionsCard()),
          LuxeListCard(child: _SatelZonesCard()),
          LuxeListCard(child: _SatelPinCard()),
          LuxeListCard(child: _SatelEncryptionCard()),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ETHM-1 / INT-ETHER connection
// ---------------------------------------------------------------------------

InputDecoration _satelCellDeco() => luxeFilledDecoration().copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

class _SatelTableHeader extends StatelessWidget {
  const _SatelTableHeader(this.cells);
  final List<({String label, int flex, double? width})> cells;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            if (cells[i].width != null)
              SizedBox(
                width: cells[i].width,
                child: Text(cells[i].label, style: style),
              )
            else
              Expanded(
                flex: cells[i].flex,
                child: Text(cells[i].label, style: style),
              ),
          ],
        ],
      ),
    );
  }
}

class _SatelConnectionCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelConnectionCard> createState() =>
      _SatelConnectionCardState();
}

class _SatelConnectionCardState extends ConsumerState<_SatelConnectionCard> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _fillFrom(SatelServiceConfig? cfg) {
    if (_loaded) return;
    _hostCtrl.text = cfg?.host ?? '';
    _portCtrl.text = '${cfg?.port ?? 7094}';
    _loaded = true;
  }

  Future<void> _save() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      setState(() {
        _error = 'Vul het IP-adres van de ETHM-1 in.';
        _success = null;
      });
      return;
    }
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;
    if (port < 1 || port > 65535) {
      setState(() {
        _error = 'Poort moet tussen 1 en 65535 liggen (standaard 7094).';
        _success = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    final result = await saveSatelConnection(host: host, port: port);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.ok) {
        _success = 'Opgeslagen. De koppeling wordt opnieuw opgezet.';
        ref.invalidate(satelServiceConfigProvider);
        ref.invalidate(satelStatusProvider);
      } else {
        _error = result.error ?? 'Opslaan mislukt.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(satelServiceConfigProvider);
    cfgAsync.whenData(_fillFrom);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LuxeSectionTitle(
          icon: Icons.lan_outlined,
          title: 'ETHM-1 / INT-ETHER',
          trailing: LuxeInfoIconButton(
            title: 'ETHM-1',
            body:
                'IP-adres van de ETHM-1 of INT-ETHER in hetzelfde netwerk als de NUC. '
                'Integratiepoort is meestal 7094 (DLOADX: Integratie).',
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LuxeFieldLabel('IP-adres'),
                  TextField(
                    controller: _hostCtrl,
                    keyboardType: TextInputType.url,
                    decoration: luxeFilledDecoration(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LuxeFieldLabel('Poort'),
                  TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: luxeFilledDecoration(),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 12)),
        ],
        if (_success != null) ...[
          const SizedBox(height: 8),
          Text(_success!,
              style: TextStyle(color: LuxeColors.inkSoft, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Opslaan'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel name dump (DLOADX via ETHM-1 0xEE)
// ---------------------------------------------------------------------------

class _SatelDiscoverCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SatelDiscoverCard> createState() => _SatelDiscoverCardState();
}

class _SatelDiscoverCardState extends ConsumerState<_SatelDiscoverCard> {
  bool _busy = false;
  String? _error;
  String? _ok;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
    });
    final result = await discoverSatelPanel();
    if (!mounted) return;
    if (!result.ok || result.data == null) {
      setState(() {
        _busy = false;
        _error = result.error ?? 'Uitlezen mislukt.';
      });
      return;
    }
    final data = result.data!;
    ref.read(satelDiscoverImportProvider.notifier).publish(data);
    setState(() {
      _busy = false;
      _ok =
          '${data.partitions.length} partities, ${data.zones.length} zones. '
          'Koppel kamers en sla daarna op. Bestaande rijen blijven staan.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(satelStatusProvider).connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LuxeSectionTitle(
          icon: Icons.download_outlined,
          title: 'Uitlezen van paneel',
          trailing: LuxeInfoIconButton(
            title: 'Uitlezen',
            body:
                'Haalt partitie- en zonenamen uit DLOADX (ETHM-1). '
                'Kamers in het alarm komen niet overeen met Archie-kamers — die koppel je zelf. '
                'Opnieuw uitlezen overschrijft geen bestaande namen, types of kamers; alleen nieuwe nummers komen erbij. '
                'Daarna per kaart Opslaan.',
          ),
        ),
        if (!connected) ...[
          Text(
            'Eerst ETHM-1 verbinden (IP-adres opslaan). Kan tot een minuut duren.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined, size: 18),
            label: Text(_busy ? 'Uitlezen…' : 'Uitlezen van paneel'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 12)),
        ],
        if (_ok != null) ...[
          const SizedBox(height: 8),
          Text(_ok!,
              style: TextStyle(color: LuxeColors.inkSoft, fontSize: 12)),
        ],
      ],
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
  int _formEpoch = 0;
  int _appliedImportSeq = 0;

  @override
  void initState() {
    super.initState();
    // Load after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _mergeImport(SatelDiscoverResult data) {
    if (_local == null) return;
    setState(() {
      _formEpoch++;
      _local = mergeImportedSatelPartitions(_local!, data.partitions);
    });
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

    var merged = base.map((p) {
      final modes = svcByNum[p.number]?.armModes;
      return p.copyWith(
        armModes: (modes != null && modes.isNotEmpty) ? modes : p.armModes,
      );
    }).toList();
    final import = ref.read(satelDiscoverImportProvider);
    if (import != null) {
      merged = mergeImportedSatelPartitions(merged, import.data.partitions);
      _appliedImportSeq = import.seq;
    }
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

    ref.listen<SatelDiscoverImport?>(satelDiscoverImportProvider, (prev, next) {
      if (next == null || next.seq == _appliedImportSeq) return;
      _appliedImportSeq = next.seq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mergeImport(next.data);
      });
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LuxeSectionTitle(
          icon: Icons.shield_outlined,
          title: 'Partities',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LuxeInfoIconButton(
                title: 'Partities',
                body:
                    'Nummer zoals in DLOADX (1–32). '
                    'Inschakelmodi: 0 = volledig, 1–3 = deelinschakeling uit DLOADX. '
                    'Uitlezen van paneel vult nummers en namen; daarna finetunen.',
              ),
              if (list != null)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Toevoegen'),
                  onPressed: list.length < 32 ? _add : null,
                ),
            ],
          ),
        ),
        if (list == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (list.isEmpty)
          Text('Geen partities.',
              style: Theme.of(context).textTheme.bodySmall)
        else ...[
          const _SatelTableHeader([
            (label: 'Nr.', flex: 0, width: 56.0),
            (label: 'Naam', flex: 2, width: null),
            (label: 'Inschakelmodi', flex: 4, width: null),
            (label: '', flex: 0, width: 40.0),
          ]),
          ...List.generate(list.length, (i) {
            final p = list[i];
            return Padding(
              key: ValueKey('satel-p-$_formEpoch-${p.number}-$i'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: TextFormField(
                      initialValue: '${p.number}',
                      keyboardType: TextInputType.number,
                      decoration: _satelCellDeco(),
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
                    flex: 2,
                    child: TextFormField(
                      initialValue: p.name,
                      decoration: _satelCellDeco(),
                      onChanged: (v) => setState(
                          () => _local![i] = p.copyWith(name: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: _ArmModesEditor(
                      modes: p.armModes,
                      onChanged: (m) => setState(
                          () => _local![i] = p.copyWith(armModes: m)),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: LuxeColors.inkSoft,
                      onPressed: () => _remove(i),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 12)),
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
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var j = 0; j < modes.length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  SizedBox(
                    width: 108,
                    child: DropdownButtonFormField<int>(
                      initialValue: modes[j].mode,
                      isExpanded: true,
                      decoration: _satelCellDeco(),
                      items: [
                        for (final n in [0, 1, 2, 3])
                          DropdownMenuItem(value: n, child: Text('Modus $n')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        final copy = [...modes];
                        copy[j] = SatelArmMode(mode: v, name: modes[j].name);
                        onChanged(copy);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      initialValue: modes[j].name,
                      decoration: _satelCellDeco(),
                      onChanged: (v) {
                        final copy = [...modes];
                        copy[j] = SatelArmMode(mode: modes[j].mode, name: v);
                        onChanged(copy);
                      },
                    ),
                  ),
                  if (modes.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: LuxeColors.inkSoft,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onChanged([...modes]..removeAt(j)),
                    ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          tooltip: 'Modus',
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
  int _formEpoch = 0;
  int _appliedImportSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _mergeImport(SatelDiscoverResult data) {
    if (_local == null) return;
    setState(() {
      _formEpoch++;
      _local = mergeImportedSatelZones(_local!, data.zones);
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final cfg = await ref.read(satelServiceConfigProvider.future);
    var list = List<SatelZoneMapping>.of(cfg?.zoneMappings ?? const []);
    final import = ref.read(satelDiscoverImportProvider);
    if (import != null) {
      list = mergeImportedSatelZones(list, import.data.zones);
      _appliedImportSeq = import.seq;
    }
    if (mounted) {
      setState(() => _local = list);
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

    ref.listen<SatelDiscoverImport?>(satelDiscoverImportProvider, (prev, next) {
      if (next == null || next.seq == _appliedImportSeq) return;
      _appliedImportSeq = next.seq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mergeImport(next.data);
      });
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LuxeSectionTitle(
          icon: Icons.sensors_outlined,
          title: 'Zones',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LuxeInfoIconButton(
                title: 'Zones',
                body:
                    'Zonenummer zoals in DLOADX (1–128). '
                    'Type en kamer bepalen hoe de sensor in de app verschijnt. '
                    'Uitlezen vult namen; kamer koppel je zelf (DLOADX-kamers komen niet overeen).',
              ),
              if (list != null)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Toevoegen'),
                  onPressed: list.length < 128 ? _add : null,
                ),
            ],
          ),
        ),
        if (list == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (list.isEmpty)
          Text('Geen zones.', style: Theme.of(context).textTheme.bodySmall)
        else ...[
          const _SatelTableHeader([
            (label: 'Nr.', flex: 0, width: 56.0),
            (label: 'Naam', flex: 2, width: null),
            (label: 'Type', flex: 2, width: null),
            (label: 'Kamer', flex: 2, width: null),
            (label: '', flex: 0, width: 40.0),
          ]),
          ...List.generate(list.length, (i) {
            final z = list[i];
            final roomValue =
                (z.roomId != null && knownRoomIds.contains(z.roomId))
                    ? z.roomId
                    : null;
            return Padding(
              key: ValueKey('satel-z-$_formEpoch-${z.zoneNumber}-$i'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: TextFormField(
                      initialValue: '${z.zoneNumber}',
                      keyboardType: TextInputType.number,
                      decoration: _satelCellDeco(),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 1 && n <= 128) {
                          setState(() =>
                              _local![i] = z.copyWith(zoneNumber: n));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: z.name,
                      decoration: _satelCellDeco(),
                      onChanged: (v) => setState(
                          () => _local![i] = z.copyWith(name: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: z.deviceType,
                      isExpanded: true,
                      decoration: _satelCellDeco(),
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
                    flex: 2,
                    child: DropdownButtonFormField<String?>(
                      initialValue: roomValue,
                      isExpanded: true,
                      decoration: _satelCellDeco(),
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
                            final label =
                                rooms.firstWhere((r) => r.id == v).label;
                            final name = label.split(' · ').first;
                            _local![i] =
                                z.copyWith(roomId: v, roomName: name);
                          }
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: LuxeColors.inkSoft,
                      onPressed: () => _remove(i),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 12)),
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
      setState(() { _error = 'Pincode moet 4–8 cijfers zijn.'; _success = null; });
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
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(satelServiceConfigProvider);
    final hasPin = cfgAsync.value?.hasPin ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LuxeSectionTitle(
          icon: Icons.pin_outlined,
          title: 'Pincode',
          trailing: LuxeInfoIconButton(
            title: 'Pincode',
            body:
                '4–8 cijfers. Zelfde code als op het Satel-toestel, '
                'voor in- en uitschakelen vanuit de app.',
          ),
        ),
        Text(
          hasPin ? 'Ingesteld' : 'Niet ingesteld',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: hasPin ? const Color(0xFF4CAF50) : LuxeColors.danger,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LuxeFieldLabel('Pincode'),
                  TextField(
                    controller: _pin1Ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: luxeFilledDecoration().copyWith(counterText: ''),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LuxeFieldLabel('Herhaal'),
                  TextField(
                    controller: _pin2Ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: luxeFilledDecoration().copyWith(counterText: ''),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 13)),
        ],
        if (_success != null) ...[
          const SizedBox(height: 8),
          Text(_success!,
              style: TextStyle(color: LuxeColors.inkSoft, fontSize: 13)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LuxeSectionTitle(
          icon: Icons.lock_outline,
          title: 'Encryptie',
          trailing: LuxeInfoIconButton(
            title: 'Encryptie',
            body:
                'Alleen als in DLOADX versleutelde integratie aan staat. '
                'Zelfde sleutel als op het paneel.',
          ),
        ),
        Text(
          hasEnc ? 'Aan' : 'Uit',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: hasEnc ? const Color(0xFF4CAF50) : LuxeColors.inkSoft,
              ),
        ),
        const SizedBox(height: 12),
        const LuxeFieldLabel('Integratiesleutel'),
        TextField(
          controller: _keyCtrl,
          obscureText: true,
          decoration: luxeFilledDecoration(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: LuxeColors.danger, fontSize: 13)),
        ],
        if (_success != null) ...[
          const SizedBox(height: 8),
          Text(_success!,
              style: TextStyle(color: LuxeColors.inkSoft, fontSize: 13)),
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
                          _error = 'Vul een sleutel in.';
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
      SatelPartitionState.exitDelay => 'Uitlooptijd',
      SatelPartitionState.entryDelay => 'Inlooptijd',
      _ => 'Uitgeschakeld',
    };
    final violated = status.allZones.where((z) => z.violated).toList();

    return Column(
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
                    : LuxeColors.inkSoft,
              ),
            ),
            Text(
              connected ? 'Verbonden' : 'Geen verbinding',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(width: 20),
            Icon(Icons.shield_outlined, size: 15, color: LuxeColors.ink),
            const SizedBox(width: 6),
            Text(stateLabel, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        if (violated.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: violated.map((z) {
              return Chip(
                label: Text(
                  z.room.trim().isEmpty ? z.name : '${z.room} · ${z.name}',
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor:
                    LuxeColors.danger.withValues(alpha: 0.10),
                side: BorderSide(
                    color: LuxeColors.danger.withValues(alpha: 0.30)),
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
