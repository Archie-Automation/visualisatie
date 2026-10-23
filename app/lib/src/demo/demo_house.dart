import '../ac_mode_config.dart';
import '../models.dart';

/// Vast demohuis. Eén keer opgebouwd, daarna alleen de buswaarden veranderen.
class DemoHouseData {
  DemoHouseData({
    required this.config,
    required this.bus,
    required this.mediaIds,
    required this.livingMediaId,
    required this.wtwId,
    required this.issuedGas,
  });

  final HouseConfig config;
  final Map<String, dynamic> bus;
  final List<String> mediaIds;
  final String livingMediaId;
  final String wtwId;
  final int issuedGas;
}

DemoHouseData? _cached;

DemoHouseData get demoHouse => _cached ??= _build();

class _Gas {
  int _n = 1;
  int issued = 0;
  final values = <String, dynamic>{};

  String hold(dynamic value) {
    issued++;
    final sub = _n % 255;
    final mid = (_n ~/ 255) % 7;
    final main = 8 + (_n ~/ (255 * 7));
    _n++;
    final ga = '$main/$mid/${sub == 0 ? 1 : sub}';
    values[ga] = value;
    return ga;
  }
}

Map<String, dynamic> _switch(_Gas g, String id, String name, {bool on = false}) {
  final ga = g.hold(on);
  return {
    'id': id,
    'name': name,
    'type': 'light_switch',
    'ga': {'switch': ga, 'switch_status': ga},
  };
}

Map<String, dynamic> _dim(
  _Gas g,
  String id,
  String name, {
  bool on = false,
  int percent = 0,
  bool favorite = false,
}) {
  final sw = g.hold(on);
  final dim = g.hold(on ? percent : 0);
  return {
    'id': id,
    'name': name,
    'type': 'light_dimmer',
    if (favorite) 'favorite': true,
    'ga': {
      'switch': sw,
      'switch_status': sw,
      'dim_value': dim,
      'dim_status': dim,
    },
  };
}

class _Climate {
  _Climate(this.json, this.setpoint, this.demand, this.actual);
  final Map<String, dynamic> json;
  final String setpoint;
  final String demand;
  final double actual;
}

_Climate _climate(
  _Gas g,
  String id,
  double actual,
  double setpoint, {
  bool cool = false,
}) {
  final actualGa = g.hold(actual);
  final sp = g.hold(setpoint);
  final mode = g.hold(1);
  final hvac = g.hold(true);
  final heat = g.hold(actual < setpoint - 0.05);
  final coolGa = g.hold(false);
  return _Climate(
    {
      'id': id,
      'name': 'Thermostaat',
      'type': 'climate',
      'ga': {
        'actual_temp': actualGa,
        'setpoint': sp,
        'setpoint_status': sp,
        'mode': mode,
        'mode_status': mode,
        'hvac_mode': hvac,
        'hvac_mode_status': hvac,
        'heat_demand': heat,
        'cool_demand': coolGa,
      },
      'climate': {
        'canHeat': true,
        'canCool': cool,
        'userCanSwitchMode': cool,
        'minTemp': 16,
        'maxTemp': 26,
        'tempStep': 0.5,
        'modes': {
          'comfort': true,
          'standby': true,
          'economy': true,
          'buildingProtection': false,
        },
      },
    },
    sp,
    heat,
    actual,
  );
}

Map<String, dynamic> _ac(
  _Gas g,
  String id, {
  bool on = false,
  double setpoint = 22,
  int mode = 1,
  double actual = 21.5,
}) {
  final onGa = g.hold(on);
  final sp = g.hold(setpoint);
  final modeGa = g.hold(mode);
  final actualGa = g.hold(actual);
  return {
    'id': id,
    'name': 'Airco',
    'type': 'ac',
    'ga': {
      'switch': onGa,
      'switch_status': onGa,
      'setpoint': sp,
      'setpoint_status': sp,
      'mode': modeGa,
      'mode_status': modeGa,
      'actual_temp': actualGa,
    },
    'ac': {
      'onOff': {'ga': onGa, 'statusGa': onGa},
      'setpoint': {'ga': sp, 'statusGa': sp, 'min': 16, 'max': 30},
      'actualTemp': {'ga': actualGa},
      'mode': {
        'ga': modeGa,
        'statusGa': modeGa,
        'options': [
          for (final option in defaultAcModeOptions)
            Map<String, dynamic>.from(option),
        ],
      },
      'modeVisibility': Map<String, dynamic>.from(defaultAcModeVisibility),
    },
  };
}

class _Shade {
  _Shade(this.json, this.position);
  final Map<String, dynamic> json;
  final String position;
}

_Shade _shade(
  _Gas g,
  String id,
  String name,
  String subtype,
  int position, {
  int? slat,
}) {
  final up = g.hold(false);
  final stop = g.hold(false);
  final pos = g.hold(position);
  final moving = g.hold(false);
  final ga = <String, String>{
    'up_down': up,
    'stop_step': stop,
    'position': pos,
    'position_status': pos,
    'moving': moving,
  };
  if (slat != null) {
    final s = g.hold(slat);
    ga['slat'] = s;
    ga['slat_status'] = s;
  }
  return _Shade(
    {
      'id': id,
      'name': name,
      'type': 'shading',
      'subtype': subtype,
      'slider': true,
      'ga': ga,
    },
    pos,
  );
}

Map<String, dynamic> _media(String id, String name, {bool favorite = false}) => {
      'id': id,
      'name': name,
      'type': 'media_sonos',
      if (favorite) 'favorite': true,
      'sonos': {'room': name},
    };

Map<String, dynamic> _act(
  String ga,
  String role,
  Object value, {
  int? delayMs,
}) =>
    {
      'ga': ga,
      'role': role,
      'value': value,
      if (delayMs != null) 'delayMs': delayMs,
    };

DemoHouseData _build() {
  final g = _Gas();

  final entreeLight = _switch(g, 'demo-light-entree', 'Plafond', on: true);
  final gevel = _switch(g, 'demo-light-gevel', 'Gevel');
  final tuin = _switch(g, 'demo-light-tuin', 'Tuinpad');
  final woonSpots = _dim(
    g,
    'demo-light-woon',
    'Spots',
    on: true,
    percent: 65,
    favorite: true,
  );
  final woonWand = _switch(g, 'demo-light-woon-wand', 'Wandlamp');
  final keukenEiland = _dim(g, 'demo-light-keuken', 'Eiland', on: true, percent: 40);
  final keukenBlad = _switch(g, 'demo-light-keuken-blad', 'Werkblad');
  final bijkeuken = _switch(g, 'demo-light-bijkeuken', 'Plafond');
  final toilet = _switch(g, 'demo-light-toilet', 'Plafond');
  final werk = _dim(g, 'demo-light-werk', 'Bureaulamp', on: true, percent: 50);
  final overloop = _dim(g, 'demo-light-overloop', 'Plafond');
  final sl1 = _dim(g, 'demo-light-sl1', 'Plafond');
  final sl1Lees = _switch(g, 'demo-light-sl1-lees', 'Leeslamp');
  final sl2 = _dim(g, 'demo-light-sl2', 'Plafond');
  final sl2Lees = _switch(g, 'demo-light-sl2-lees', 'Leeslamp');
  final sl3 = _dim(g, 'demo-light-sl3', 'Plafond');
  final sl3Lees = _switch(g, 'demo-light-sl3-lees', 'Leeslamp');
  final bad = _dim(g, 'demo-light-bad', 'Spots');

  final climates = <String, _Climate>{
    'entree': _climate(g, 'demo-cl-entree', 19.8, 21),
    'woon': _climate(g, 'demo-cl-woon', 21.2, 21.5, cool: true),
    'keuken': _climate(g, 'demo-cl-keuken', 20.6, 21),
    'bijkeuken': _climate(g, 'demo-cl-bijkeuken', 18.4, 19),
    'toilet': _climate(g, 'demo-cl-toilet', 20.0, 20),
    'werk': _climate(g, 'demo-cl-werk', 20.8, 21),
    'overloop': _climate(g, 'demo-cl-overloop', 19.2, 19),
    'sl1': _climate(g, 'demo-cl-sl1', 18.8, 19),
    'sl2': _climate(g, 'demo-cl-sl2', 18.5, 19),
    'sl3': _climate(g, 'demo-cl-sl3', 19.1, 19),
    'bad': _climate(g, 'demo-cl-bad', 22.0, 22),
  };

  final woonGordijn = _shade(g, 'demo-sh-woon-g', 'Gordijn', 'curtain', 0);
  final woonJal = _shade(g, 'demo-sh-woon-j', 'Jaloezie', 'jalousie', 20, slat: 40);
  final keukenGordijn = _shade(g, 'demo-sh-keuken-g', 'Gordijn', 'curtain', 10);
  final keukenJal = _shade(g, 'demo-sh-keuken-j', 'Jaloezie', 'jalousie', 30, slat: 45);
  final sl1G = _shade(g, 'demo-sh-sl1-g', 'Gordijn', 'curtain', 100);
  final sl1J = _shade(g, 'demo-sh-sl1-j', 'Jaloezie', 'jalousie', 80, slat: 20);
  final sl2G = _shade(g, 'demo-sh-sl2-g', 'Gordijn', 'curtain', 100);
  final sl2J = _shade(g, 'demo-sh-sl2-j', 'Jaloezie', 'jalousie', 100, slat: 0);
  final sl3G = _shade(g, 'demo-sh-sl3-g', 'Gordijn', 'curtain', 70);
  final sl3J = _shade(g, 'demo-sh-sl3-j', 'Jaloezie', 'jalousie', 60, slat: 50);

  final haardAan = g.hold(false);
  final haardVlam = g.hold(0);
  final haard = {
    'id': 'demo-haard',
    'name': 'Openhaard',
    'type': 'fireplace',
    'favorite': true,
    'fireplace': {
      'controlMode': 'analog',
      'onOff': {'ga': haardAan, 'statusGa': haardAan},
      'flame': {
        'ga': haardVlam,
        'statusGa': haardVlam,
        'levelDisplay': 'percent',
        'onPercent': 40,
        'stepRanges': [
          {'min': 1, 'max': 25, 'write': 20},
          {'min': 26, 'max': 50, 'write': 40},
          {'min': 51, 'max': 75, 'write': 60},
          {'min': 76, 'max': 100, 'write': 90},
        ],
      },
    },
  };

  const livingMedia = 'demo-media-woon';
  const mediaIds = [
    livingMedia,
    'demo-media-keuken',
    'demo-media-sl1',
    'demo-media-sl2',
    'demo-media-sl3',
  ];

  final filter = g.hold(false);
  final rook = g.hold(false);

  String stand(String key, bool on) => g.hold(on);
  final away = stand('away', false);
  final s1 = stand('stand1', false);
  final s2 = stand('stand2', false);
  final s3 = stand('stand3', false);
  final auto = stand('auto', true);
  final boost = stand('boost', false);
  final boostTime = g.hold(1800);
  final fault = g.hold(false);
  final filterDays = g.hold(17);

  final wtw = {
    'id': 'demo-wtw',
    'name': 'WTW',
    'type': 'wtw',
    'wtw': {
      'model': 'zehnder_comfoConnect',
      'zehnder': {
        'minutes': 30,
        'awayGa': away,
        'awayStatusGa': away,
        'stand1Ga': s1,
        'stand1StatusGa': s1,
        'stand2Ga': s2,
        'stand2StatusGa': s2,
        'stand3Ga': s3,
        'stand3StatusGa': s3,
        'autoGa': auto,
        'autoStatusGa': auto,
        'boostGa': boost,
        'boostStatusGa': boost,
        'boostTimeGa': boostTime,
        'boostTimeStatusGa': boostTime,
        'faultGa': fault,
        'filterGa': filter,
        'filterDaysGa': filterDays,
      },
    },
  };

  Map<String, dynamic> melding(
    String id,
    String name,
    List<Map<String, dynamic>> items,
  ) =>
      {
        'id': id,
        'name': name,
        'type': 'melding',
        'melding': {'items': items},
      };

  Map<String, dynamic> alert(
    String id,
    String label,
    String ga,
    String urgency, {
    String? category,
    bool reset = false,
  }) =>
      {
        'id': id,
        'label': label,
        'ga': ga,
        'dpt': '1.001',
        'urgency': urgency,
        if (category != null) 'category': category,
        if (reset) 'resetMode': 'same_ga',
      };

  String sw(Map<String, dynamic> d) =>
      (d['ga'] as Map)['switch'] as String;
  String dim(Map<String, dynamic> d) =>
      (d['ga'] as Map)['dim_value'] as String;

  List<Map<String, dynamic>> lightsOff(List<Map<String, dynamic>> devices, {int? delayMs}) {
    final out = <Map<String, dynamic>>[];
    for (final d in devices) {
      final type = d['type'];
      if (type == 'light_switch') {
        out.add(_act(sw(d), 'switch', false, delayMs: delayMs));
      } else if (type == 'light_dimmer') {
        out.add(_act(sw(d), 'switch', false, delayMs: delayMs));
        out.add(_act(dim(d), 'dim_value', 0, delayMs: delayMs));
      }
    }
    return out;
  }

  List<Map<String, dynamic>> dimSet(Map<String, dynamic> d, int percent, {int? delayMs}) => [
        _act(sw(d), 'switch', percent > 0, delayMs: delayMs),
        _act(dim(d), 'dim_value', percent, delayMs: delayMs),
      ];

  List<Map<String, dynamic>> shadeSet(List<_Shade> shades, int position, {int? delayMs}) => [
        for (final s in shades) _act(s.position, 'position', position, delayMs: delayMs),
      ];

  List<Map<String, dynamic>> wtwStand(String active) => [
        _act(away, 'bit', active == 'away'),
        _act(s1, 'bit', active == 'stand1'),
        _act(s2, 'bit', active == 'stand2'),
        _act(s3, 'bit', active == 'stand3'),
        _act(auto, 'bit', active == 'auto'),
        _act(boost, 'bit', active == 'boost'),
      ];

  Map<String, dynamic> sp(String key, double value, {int? delayMs}) =>
      _act(climates[key]!.setpoint, 'setpoint', value, delayMs: delayMs);

  final groundLights = [
    entreeLight,
    woonSpots,
    woonWand,
    keukenEiland,
    keukenBlad,
    bijkeuken,
    toilet,
    werk,
  ];
  final upperLights = [overloop, sl1, sl1Lees, sl2, sl2Lees, sl3, sl3Lees, bad];
  final dayShades = [woonGordijn, woonJal, keukenGordijn, keukenJal];
  final nightShades = [sl1G, sl1J, sl2G, sl2J, sl3G, sl3J];
  final allShades = [...dayShades, ...nightShades];

  final scenes = [
    {
      'id': 'scn-welkom',
      'name': 'Welkom thuis',
      'icon': 'welcome',
      'actions': [
        ...dimSet(woonSpots, 70),
        _act(sw(entreeLight), 'switch', true, delayMs: 80),
        ...dimSet(keukenEiland, 45, delayMs: 80),
        ...shadeSet(dayShades, 0, delayMs: 160),
        sp('woon', 21.5, delayMs: 160),
        sp('keuken', 21, delayMs: 160),
        _act(haardAan, 'switch', false, delayMs: 200),
        _act(haardVlam, 'percent', 0, delayMs: 200),
        ...wtwStand('auto'),
      ],
      'mediaActions': [
        {'deviceId': livingMedia, 'kind': 'transport', 'action': 'play'},
        {'deviceId': livingMedia, 'kind': 'volume', 'value': 22},
      ],
    },
    {
      'id': 'scn-film',
      'name': 'Filmavond',
      'icon': 'movie',
      'actions': [
        ...lightsOff([
          entreeLight,
          woonWand,
          keukenEiland,
          keukenBlad,
          bijkeuken,
          toilet,
          werk,
        ]),
        ...dimSet(woonSpots, 12, delayMs: 120),
        ...shadeSet(dayShades, 100, delayMs: 180),
        _act(haardAan, 'switch', true, delayMs: 240),
        _act(haardVlam, 'percent', 40, delayMs: 280),
      ],
      'mediaActions': [
        {
          'deviceId': livingMedia,
          'kind': 'preset',
          'presetId': 'jazz',
          'presetName': 'Jazz FM',
        },
        {'deviceId': livingMedia, 'kind': 'volume', 'value': 18, 'delayMs': 80},
      ],
    },
    {
      'id': 'scn-koken',
      'name': 'Koken',
      'icon': 'dinner',
      'actions': [
        ...dimSet(keukenEiland, 100),
        _act(sw(keukenBlad), 'switch', true),
        ...dimSet(woonSpots, 35, delayMs: 100),
      ],
      'mediaActions': [
        {'deviceId': 'demo-media-keuken', 'kind': 'transport', 'action': 'play'},
      ],
    },
    {
      'id': 'scn-nacht',
      'name': 'Goedenacht',
      'icon': 'moon',
      'actions': [
        ...lightsOff(groundLights),
        ...lightsOff([sl1, sl1Lees, sl2, sl2Lees, sl3, sl3Lees, bad], delayMs: 80),
        ...dimSet(overloop, 15, delayMs: 80),
        ...shadeSet(allShades, 100, delayMs: 140),
        sp('sl1', 17.5, delayMs: 180),
        sp('sl2', 17.5, delayMs: 180),
        sp('sl3', 17.5, delayMs: 180),
        sp('woon', 18, delayMs: 180),
        _act(climates['sl1']!.demand, 'bit', false, delayMs: 180),
        _act(climates['sl2']!.demand, 'bit', false, delayMs: 180),
        _act(climates['sl3']!.demand, 'bit', false, delayMs: 180),
        _act(climates['woon']!.demand, 'bit', false, delayMs: 180),
        _act(haardAan, 'switch', false, delayMs: 200),
        _act(haardVlam, 'percent', 0, delayMs: 200),
        ...wtwStand('stand1'),
      ],
      'mediaActions': [
        for (final id in mediaIds)
          {'deviceId': id, 'kind': 'transport', 'action': 'stop'},
      ],
    },
    {
      'id': 'scn-weg',
      'name': 'Afwezig',
      'icon': 'door',
      'actions': [
        ...lightsOff([...groundLights, ...upperLights]),
        ...shadeSet(allShades, 100, delayMs: 120),
        _act(haardAan, 'switch', false, delayMs: 160),
        _act(haardVlam, 'percent', 0, delayMs: 160),
        ...wtwStand('away'),
      ],
      'mediaActions': [
        for (final id in mediaIds)
          {'deviceId': id, 'kind': 'transport', 'action': 'stop'},
      ],
    },
  ];

  final json = {
    'project': {
      'id': 'demo-woning',
      'name': 'Demo Archie',
      'timezone': 'Europe/Amsterdam',
      'location': {'lat': 52.09, 'lon': 5.12},
    },
    'displayPanel': {
      'enabled': true,
      'idleHomeMinutes': 3,
      'screensaverMinutes': 8,
      'panelRoomId': 'room-woonkamer',
      'temperatureRoomId': 'room-woonkamer',
      'suppressScreensaverWhenMusicPlaying': true,
    },
    'users': [
      {
        'id': 'user-demo',
        'username': 'Demo',
        'displayName': 'Demo',
        'role': 'user',
        'enabled': true,
        'access': {'editScenes': false},
      },
    ],
    'satel': {'enabled': true},
    'floors': [
      {
        'id': 'floor-bg',
        'name': 'Begane grond',
        'order': 0,
        'icon': 'home',
        'rooms': [
          {
            'id': 'room-entree',
            'name': 'Entree',
            'icon': 'door',
            'devices': [
              entreeLight,
              gevel,
              tuin,
              climates['entree']!.json,
            ],
          },
          {
            'id': 'room-woonkamer',
            'name': 'Woonkamer',
            'icon': 'sofa',
            'devices': [
              woonSpots,
              woonWand,
              climates['woon']!.json,
              _ac(g, 'demo-ac-woon', on: true, setpoint: 21, actual: 22.4),
              haard,
              woonGordijn.json,
              woonJal.json,
              _media(livingMedia, 'Woonkamer', favorite: true),
            ],
            'scenes': [
              {
                'id': 'scn-lezen',
                'name': 'Lezen',
                'icon': 'book',
                'actions': [
                  ...dimSet(woonSpots, 40),
                  _act(woonGordijn.position, 'position', 35, delayMs: 80),
                ],
              },
            ],
          },
          {
            'id': 'room-keuken',
            'name': 'Keuken',
            'icon': 'kitchen',
            'devices': [
              keukenEiland,
              keukenBlad,
              climates['keuken']!.json,
              keukenGordijn.json,
              keukenJal.json,
              _media('demo-media-keuken', 'Keuken'),
            ],
          },
          {
            'id': 'room-bijkeuken',
            'name': 'Bijkeuken',
            'icon': 'laundry',
            'devices': [bijkeuken, climates['bijkeuken']!.json],
          },
          {
            'id': 'room-toilet',
            'name': 'Toilet',
            'icon': 'wc',
            'devices': [toilet, climates['toilet']!.json],
          },
          {
            'id': 'room-werk',
            'name': 'Werkkamer',
            'icon': 'desk',
            'devices': [werk, climates['werk']!.json],
          },
        ],
      },
      {
        'id': 'floor-1',
        'name': 'Verdieping',
        'order': 1,
        'icon': 'stairs',
        'rooms': [
          {
            'id': 'room-overloop',
            'name': 'Overloop',
            'icon': 'stairs',
            'devices': [overloop, climates['overloop']!.json],
          },
          {
            'id': 'room-sl1',
            'name': 'Slaapkamer 1',
            'icon': 'bed',
            'devices': [
              sl1,
              sl1Lees,
              climates['sl1']!.json,
              _ac(g, 'demo-ac-sl1', setpoint: 19, mode: 2, actual: 18.6),
              sl1G.json,
              sl1J.json,
              _media('demo-media-sl1', 'Slaapkamer 1'),
            ],
          },
          {
            'id': 'room-sl2',
            'name': 'Slaapkamer 2',
            'icon': 'bed',
            'devices': [
              sl2,
              sl2Lees,
              climates['sl2']!.json,
              _ac(g, 'demo-ac-sl2', setpoint: 19, mode: 2, actual: 18.8),
              sl2G.json,
              sl2J.json,
              _media('demo-media-sl2', 'Slaapkamer 2'),
            ],
          },
          {
            'id': 'room-sl3',
            'name': 'Slaapkamer 3',
            'icon': 'bed',
            'devices': [
              sl3,
              sl3Lees,
              climates['sl3']!.json,
              _ac(g, 'demo-ac-sl3', setpoint: 19, mode: 2, actual: 19.1),
              sl3G.json,
              sl3J.json,
              _media('demo-media-sl3', 'Slaapkamer 3'),
            ],
          },
          {
            'id': 'room-bad',
            'name': 'Badkamer',
            'icon': 'bath',
            'devices': [bad, climates['bad']!.json],
          },
        ],
      },
    ],
    'devices': [
      wtw,
      melding('demo-meld-installatie', 'Installatie', [
        alert('meld-filter', 'Filter WTW', filter, 'belangrijk', reset: true),
        alert('meld-rook', 'Rookmelder overloop', rook, 'urgent'),
      ]),
    ],
    'cameras': [
      {'id': 'demo-cam-deur', 'name': 'Voordeur', 'type': 'camera'},
      {'id': 'demo-cam-tuin', 'name': 'Achtertuin', 'type': 'camera'},
      {'id': 'demo-cam-oprit', 'name': 'Oprit', 'type': 'camera'},
    ],
    'intercoms': [
      {
        'id': 'demo-intercom',
        'name': 'Voordeur',
        'type': 'intercom',
        'intercom': {
          'kind': 'doorbird',
          'releaseMode': 'doorbird',
          'showInCameras': true,
        },
      },
    ],
    'scenes': scenes,
  };

  return DemoHouseData(
    config: HouseConfig.fromJson(json),
    bus: Map<String, dynamic>.from(g.values),
    mediaIds: mediaIds,
    livingMediaId: livingMedia,
    wtwId: 'demo-wtw',
    issuedGas: g.issued,
  );
}
