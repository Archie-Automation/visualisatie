import 'package:flutter_test/flutter_test.dart';
import 'package:archie_os/src/models.dart';

HouseConfig _cfg({required List<Building> buildings}) {
  return HouseConfig(
    projectId: 'p',
    projectName: 'Huis',
    buildings: buildings,
    floors: [
      const Floor(
        id: 'bg',
        name: 'Begane grond',
        order: 0,
        rooms: [],
      ),
      const Floor(
        id: 'guest-bg',
        name: 'Gastenverblijf',
        order: 1,
        buildingId: 'guest',
        rooms: [],
      ),
    ],
    cameras: const [],
    intercoms: const [],
    scenes: const [
      Scene(id: 'avond', name: 'Avond', actions: []),
      Scene(id: 'pool', name: 'Zwemmen', actions: [], buildingId: 'pool'),
      Scene(
        id: 'alles',
        name: 'Alles uit',
        actions: [],
        buildingIds: ['main', 'guest', 'pool'],
      ),
    ],
    globalDevices: const [
      Device(
        id: 'lamp-los',
        name: 'Losse lamp',
        type: DeviceType.lightSwitch,
        favorite: false,
        ga: {},
        raw: {'buildingId': 'pool'},
      ),
    ],
  );
}

void main() {
  test('één of geen gebouw laat alles zichtbaar', () {
    final single = _cfg(buildings: const [
      Building(id: 'main', name: 'Woning', order: 0),
    ]);
    expect(single.usesBuildings, isFalse);
    expect(single.floorsIn('main'), single.floors);
    expect(single.scenesIn(null), single.scenes);
    expect(single.deviceInBuilding(single.globalDevices.first, 'pool'), isTrue);
  });

  test('meerdere gebouwen filteren verdiepingen, scenes en losse apparaten', () {
    final cfg = _cfg(buildings: const [
      Building(id: 'main', name: 'Woning', order: 0),
      Building(id: 'guest', name: 'Gastenverblijf', order: 1),
      Building(id: 'pool', name: 'Zwembadhuis', order: 2),
    ]);

    expect(cfg.usesBuildings, isTrue);
    expect(cfg.floorsIn('main').map((f) => f.id), ['bg']);
    expect(cfg.floorsIn('guest').map((f) => f.id), ['guest-bg']);
    expect(cfg.scenesIn('main').map((s) => s.id), ['avond', 'alles']);
    expect(cfg.scenesIn('guest').map((s) => s.id), ['alles']);
    expect(cfg.scenesIn('pool').map((s) => s.id), ['pool', 'alles']);
    expect(cfg.deviceInBuilding(cfg.globalDevices.first, 'pool'), isTrue);
    expect(cfg.deviceInBuilding(cfg.globalDevices.first, 'main'), isFalse);
    expect(cfg.scopedBuildingId('nope'), isNull);
  });
}
