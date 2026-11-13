import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/lutron_levels.dart';
import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/ui/widgets/device_widgets.dart';
import 'package:archie_os/src/ui/widgets/tunable_white_icon.dart';

class _QuietBus extends BusController {
  @override
  BusState build() => const BusState({});

  @override
  Future<void> send(Map<String, dynamic> command) async {}
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

  testWidgets('rgb and colour temperature keep the tile and dimmer row fixed',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const device = Device(
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          busProvider.overrideWith(_QuietBus.new),
          lutronZoneProvider.overrideWith(_SeededZones.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: RgbwWwTile(device: device),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final tile = find.byType(RgbwWwTile);
    final rgb = find.byTooltip('RGB(W)');
    final cct = find.byTooltip('Kleurtemperatuur');
    final size = tester.getSize(tile);
    final rgbAt = tester.getTopLeft(rgb);
    final cctAt = tester.getTopLeft(cct);

    void expectRowFixed() {
      expect(tester.getSize(tile), size);
      expect(tester.getTopLeft(rgb), rgbAt);
      expect(tester.getTopLeft(cct), cctAt);
    }

    expect(find.text('Kleurtemperatuur (warm → koud)'), findsNothing);
    expect(_wheelCount(tester), 1);
    expect(find.byType(TunableWhiteIcon), findsOneWidget);

    final label = find.text('Kleurtemperatuur (warm → koud)');

    await tester.tap(cct);
    await tester.pump();
    expectRowFixed();
    expect(find.byType(TunableWhiteIcon), findsNWidgets(2));

    // Eerste helft: cirkel fadede uit, balk is nog weg.
    await tester.pump(const Duration(milliseconds: 200));
    expectRowFixed();
    expect(_nearestOpacity(tester, label), 0);
    expect(_wheelOpacity(tester), greaterThan(0));
    expect(_wheelOpacity(tester), lessThan(1));

    // Op de helft zijn beide even onzichtbaar, daarna komt alleen de balk op.
    await tester.pump(const Duration(milliseconds: 60));
    expectRowFixed();
    expect(_nearestOpacity(tester, label), 0);
    expect(_wheelOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 800));
    expectRowFixed();
    expect(_nearestOpacity(tester, label), 1);
    expect(_wheelCount(tester), 0);

    await tester.tap(rgb);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expectRowFixed();
    expect(_nearestOpacity(tester, label), greaterThan(0));
    expect(_nearestOpacity(tester, label), lessThan(1));
    expect(_wheelOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 800));
    expectRowFixed();
    expect(label, findsNothing);
    expect(_wheelCount(tester), 1);
    expect(_wheelOpacity(tester), 1);
    expect(find.byType(TunableWhiteIcon), findsOneWidget);
  });

  testWidgets('knx rgbw uses the same header icon as the colour wheel',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const device = Device(
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          busProvider.overrideWith(_QuietBus.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 390, child: RgbwWwTile(device: device)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ledstrip'), findsOneWidget);
    expect(find.text('RGBW'), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byType(TunableWhiteIcon), findsNothing);
    expect(find.text('Wit (W)'), findsOneWidget);
    expect(_wheelCount(tester), 1);
  });
}

int _wheelCount(WidgetTester tester) {
  return find.byType(CustomPaint).evaluate().where((element) {
    final box = element.renderObject;
    return box is RenderBox &&
        box.hasSize &&
        (box.size.width - 200).abs() < 1 &&
        (box.size.height - 200).abs() < 1;
  }).length;
}

double _wheelOpacity(WidgetTester tester) {
  final wheel = find.byType(CustomPaint).evaluate().firstWhere((element) {
    final box = element.renderObject;
    return box is RenderBox &&
        box.hasSize &&
        (box.size.width - 200).abs() < 1;
  });
  return _opacityOf(wheel);
}

double _nearestOpacity(WidgetTester tester, Finder target) {
  return _opacityOf(tester.element(target));
}

double _opacityOf(Element start) {
  double? value;
  start.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) {
      value = widget.opacity;
      return false;
    }
    return true;
  });
  return value!;
}
