import 'package:archie_os/src/installer/installer_api.dart';
import 'package:archie_os/src/installer/lutron_zone_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ControlType wordt een apparaattype', () {
    expect(suggestLutronImportKind('Dimmed'), LutronImportKind.dimmer);
    expect(suggestLutronImportKind('Switched'), LutronImportKind.switchLoad);
    expect(suggestLutronImportKind('SpectrumTune'), LutronImportKind.color);
    expect(suggestLutronImportKind('WhiteTune'), LutronImportKind.white);
    expect(suggestLutronImportKind('Shade'), LutronImportKind.shade);
    expect(suggestLutronImportKind('ShadeWithTilt'), LutronImportKind.jalousie);
    expect(suggestLutronImportKind('FanSpeed'), isNull);
  });

  test('zones komen per gebied in kamers, bestaande zone-id blijft staan', () {
    final house = <String, dynamic>{
      'floors': [
        {
          'id': 'fl-1',
          'name': 'Begane grond',
          'rooms': [
            {
              'id': 'rm-keuken',
              'name': 'Keuken',
              'devices': [
                {
                  'id': 'dev-oud',
                  'name': 'Eettafel',
                  'type': 'light_dimmer',
                  'control': 'lutron',
                  'lutronIntegrationId': 7,
                },
              ],
            },
          ],
        },
      ],
    };

    final added = applyLutronZoneImport(
      house: house,
      target: const LutronZoneImportTarget.perArea(0),
      newId: _ids(),
      items: const [
        LutronZoneImportItem(id: 7, name: 'Eettafel', area: 'Keuken', kind: LutronImportKind.dimmer),
        LutronZoneImportItem(id: 8, name: 'Spot', area: 'Keuken', kind: LutronImportKind.switchLoad),
        LutronZoneImportItem(id: 9, name: 'Raam', area: 'Woonkamer', kind: LutronImportKind.jalousie),
        LutronZoneImportItem(id: 10, name: 'Wand', area: '', kind: LutronImportKind.white),
      ],
    );

    expect(added, 3);
    final rooms = (house['floors'] as List).first['rooms'] as List;
    expect(rooms.map((room) => room['name']), ['Keuken', 'Woonkamer', 'Lutron']);
    final keuken = (rooms[0]['devices'] as List);
    expect(keuken, hasLength(2));
    expect(keuken[1]['type'], 'light_switch');
    expect(keuken[1]['lutronIntegrationId'], 8);
    final raam = (rooms[1]['devices'] as List).single as Map;
    expect(raam['type'], 'shading');
    expect(raam['subtype'], 'jalousie');
    expect(raam['lutronSlatIntegrationId'], 9);
    final wand = (rooms[2]['devices'] as List).single as Map;
    expect(wand['rgbwWw']['mode'], 'tunable_white');
    expect(wand.containsKey('ga'), isFalse);
  });

  test('één bestaande kamer krijgt alle gekozen zones', () {
    final house = <String, dynamic>{
      'floors': [
        {
          'name': 'Verdieping',
          'rooms': [
            {'name': 'Hal', 'devices': <Map<String, dynamic>>[]},
          ],
        },
      ],
    };
    final added = applyLutronZoneImport(
      house: house,
      target: const LutronZoneImportTarget.room(0, 0),
      newId: _ids(),
      items: const [
        LutronZoneImportItem(id: 3, name: 'Plafond', area: 'Hal', kind: LutronImportKind.dimmer),
        LutronZoneImportItem(id: 4, name: 'Sfeer', area: 'Zaal', kind: LutronImportKind.color),
      ],
    );
    expect(added, 2);
    final rooms = (house['floors'] as List).first['rooms'] as List;
    expect(rooms, hasLength(1));
    final devices = rooms.first['devices'] as List;
    expect(devices[1]['type'], 'rgbw_ww');
    expect(devices[1]['rgbwWw']['mode'], 'channels');
  });

  testWidgets('pagina toont de zone en zet hem in de kamer', (tester) async {
    final house = <String, dynamic>{
      'floors': [
        {
          'name': 'Begane grond',
          'rooms': [
            {'name': 'Hal', 'devices': <Map<String, dynamic>>[]},
          ],
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openLutronZoneImportPage(
              context: context,
              house: house,
              zones: const [
                LutronZoneInfo(
                  id: 4,
                  name: 'Spot',
                  controlType: 'Dimmed',
                  area: 'Hal',
                ),
                LutronZoneInfo(
                  id: 5,
                  name: 'Ventilator',
                  controlType: 'FanSpeed',
                  area: 'Hal',
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Spot'), findsOneWidget);
    expect(find.text('Ventilator'), findsOneWidget);
    expect(find.text('1 toevoegen'), findsOneWidget);

    await tester.tap(find.text('1 toevoegen'));
    await tester.pumpAndSettle();
    final devices = (((house['floors'] as List).first as Map)['rooms'] as List)
        .first['devices'] as List;
    expect(devices, hasLength(1));
    expect(devices.single['name'], 'Spot');
    expect(devices.single['lutronIntegrationId'], 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('een ruimtenaam geldt voor iedere zone in die ruimte', (tester) async {
    final house = <String, dynamic>{
      'floors': [
        {
          'name': 'Begane grond',
          'rooms': <Map<String, dynamic>>[],
        },
      ],
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openLutronZoneImportPage(
              context: context,
              house: house,
              zones: const [
                LutronZoneInfo(id: 1, name: 'Spot', controlType: 'Dimmed', area: 'Keuken'),
                LutronZoneInfo(id: 2, name: 'Wand', controlType: 'Switched', area: 'Keuken'),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keuken leef');
    await tester.tap(find.text('2 toevoegen'));
    await tester.pumpAndSettle();
    final rooms = ((house['floors'] as List).first as Map)['rooms'] as List;
    expect(rooms, hasLength(1));
    expect(rooms.single['name'], 'Keuken leef');
    final devices = rooms.single['devices'] as List;
    expect(devices, hasLength(2));
    expect(devices.map((device) => device['name']), ['Spot', 'Wand']);
  });
}

String Function() _ids() {
  var n = 0;
  return () => '${n++}';
}
