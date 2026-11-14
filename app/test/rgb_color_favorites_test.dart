import 'dart:convert';

import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/lutron_levels.dart';
import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/rgb_color_favorites.dart';
import 'package:archie_os/src/ui/widgets/device_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QuietBus extends BusController {
  @override
  BusState build() => const BusState({});

  @override
  Future<void> send(Map<String, dynamic> command) async {}
}

class _CaptureBus extends BusController {
  final List<Map<String, dynamic>> commands = [];

  @override
  BusState build() => const BusState({});

  @override
  Future<void> send(Map<String, dynamic> command) async {
    commands.add(Map<String, dynamic>.from(command));
  }
}

class _SeededZones extends LutronZoneController {
  @override
  Map<int, LutronZoneLive> build() => const {
        1: LutronZoneLive(
          id: 1,
          level: 80,
          recall: 80,
          hue: 20,
          saturation: 90,
        ),
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bewaart een kleur, weigert een bijna-duplicaat en stopt bij 8', () async {
    const id = 'lamp-a';
    expect(await RgbColorFavoriteStore.load(id), isEmpty);

    final colors = <RgbFavoriteColor>[
      const RgbFavoriteColor.rgb(hue: 10, saturation: 1),
    ];
    expect(
      tryAddRgbFavorite(
        colors,
        const RgbFavoriteColor.rgb(hue: 12, saturation: 0.98, white: 4),
      ),
      RgbFavoriteSave.duplicate,
    );
    expect(
      tryAddRgbFavorite(
        colors,
        const RgbFavoriteColor.rgb(hue: 200, saturation: 1, white: 40),
      ),
      RgbFavoriteSave.added,
    );
    expect(
      tryAddRgbFavorite(
        colors,
        const RgbFavoriteColor.tunable(warmCool: 0.2),
      ),
      RgbFavoriteSave.added,
    );

    while (colors.length < RgbFavoriteColor.maxCount) {
      colors.add(RgbFavoriteColor.rgb(hue: colors.length * 30, saturation: 1));
    }
    expect(
      tryAddRgbFavorite(
        colors,
        const RgbFavoriteColor.rgb(hue: 350, saturation: 0.2),
      ),
      RgbFavoriteSave.full,
    );

    expect(await RgbColorFavoriteStore.write(id, colors), isTrue);
    final loaded = await RgbColorFavoriteStore.load(id);
    expect(loaded, hasLength(RgbFavoriteColor.maxCount));
    expect(loaded[1].hue, 200);
    expect(loaded[1].white, 40);
    expect(loaded[2].tunable, isTrue);
    expect(loaded[2].warmCool, closeTo(0.2, 0.001));

    final raw = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
        RgbColorFavoriteStore.keyFor(id),
      )!,
    );
    expect(raw, isA<List>());
  });

  testWidgets('lutron bookmark staat rechts van de twee modus-icoontjes',
      (tester) async {
    await _pump(tester, _lutron());

    final fav = find.byTooltip('Favoriete kleuren');
    expect(fav, findsOneWidget);
    expect(
      tester.getTopLeft(fav).dx,
      greaterThan(tester.getTopRight(find.byTooltip('Kleurtemperatuur')).dx),
    );
    expect(find.text('Wit (W)'), findsNothing);
  });

  testWidgets('knx bookmark staat naast de witslider', (tester) async {
    await _pump(tester, _knx());

    final fav = find.byTooltip('Favoriete kleuren');
    final white = find.text('Wit (W)');
    expect(fav, findsOneWidget);
    expect(white, findsOneWidget);
    expect(tester.getTopLeft(fav).dx, greaterThan(tester.getTopRight(white).dx));
    expect(find.byTooltip('RGB(W)'), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });

  testWidgets('opgeslagen kleur gaat naar de lamp', (tester) async {
    SharedPreferences.setMockInitialValues({
      RgbColorFavoriteStore.keyFor('knx-rgbw'): jsonEncode([
        const RgbFavoriteColor.rgb(hue: 120, saturation: 1, white: 200).toJson(),
      ]),
    });
    final bus = _CaptureBus();
    await _pump(tester, _knx(), bus: bus);

    await tester.tap(find.byTooltip('Favoriete kleuren'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Huidige kleur opslaan'), findsOneWidget);
    await tester.tap(find.byTooltip('Favoriet 1'));
    await tester.pump();
    await tester.pump();

    final channels = {
      for (final c in bus.commands.where((c) => c['kind'] == 'rgbw_ww.channel'))
        c['channel'] as String: c['value'],
    };
    expect(bus.commands.first['kind'], 'light.switch');
    expect(bus.commands.first['on'], isTrue);
    expect(channels['r'], 0);
    expect(channels['g'], greaterThan(180));
    expect(channels['b'], 0);
    expect(channels['w'], 200);
  });

  testWidgets('huidige kleur opslaan en nog eens weigeren', (tester) async {
    await _pump(tester, _lutron(), zones: true);

    await tester.tap(find.byTooltip('Favoriete kleuren'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Huidige kleur opslaan'));
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Favoriet 1'), findsOneWidget);

    await tester.tap(find.text('Huidige kleur opslaan'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Die kleur staat er al bij.'), findsOneWidget);
    expect(find.byTooltip('Favoriet 1'), findsOneWidget);
    expect(find.byTooltip('Favoriet 2'), findsNothing);
  });
}

const _lutronDevice = Device(
  id: 'rgb1',
  name: 'Eettafel',
  type: DeviceType.rgbwWw,
  favorite: false,
  ga: {},
  raw: {
    'control': 'lutron',
    'lutronIntegrationId': 1,
    'rgbwWw': {'mode': 'color'},
  },
);

const _knxDevice = Device(
  id: 'knx-rgbw',
  name: 'Ledstrip',
  type: DeviceType.rgbwWw,
  favorite: false,
  ga: {
    'r': '1/3/1',
    'g': '1/3/2',
    'b': '1/3/3',
    'w': '1/3/4',
    'on': '1/3/0',
  },
  raw: {
    'rgbwWw': {'mode': 'channels'},
  },
);

Device _lutron() => _lutronDevice;
Device _knx() => _knxDevice;

Future<void> _pump(
  WidgetTester tester,
  Device device, {
  BusController? bus,
  bool zones = false,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (bus != null) busProvider.overrideWith(() => bus),
        if (bus == null) busProvider.overrideWith(_QuietBus.new),
        if (zones) lutronZoneProvider.overrideWith(_SeededZones.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 390, child: RgbwWwTile(device: device)),
        ),
      ),
    ),
  );
  await tester.pump();
}
