import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/system_category.dart';

void main() {
  const intercom = Device(
    id: 'ic-1',
    name: 'Voordeur',
    type: DeviceType.intercom,
    favorite: false,
    ga: {},
    raw: {},
  );

  test('single intercom skips the system tile list', () {
    final sys = houseSystemBySlug('intercom')!;
    expect(houseSystemOpenPath(sys, [intercom]), '/intercom/ic-1');
  });

  test('multiple intercoms keep the picker', () {
    final sys = houseSystemBySlug('intercom')!;
    expect(
      houseSystemOpenPath(sys, [
        intercom,
        Device(
          id: 'ic-2',
          name: 'Poort',
          type: DeviceType.intercom,
          favorite: false,
          ga: {},
          raw: {},
        ),
      ]),
      '/system/intercom',
    );
  });

  test('cameras still open the overview', () {
    final sys = houseSystemBySlug('cameras')!;
    expect(houseSystemOpenPath(sys, const []), '/cameras');
  });

  test('diverse is not a built-in system tile', () {
    expect(houseSystemBySlug('diverse'), isNull);
  });

  test('custom house system is addressable by slug', () {
    final cfg = HouseConfig(
      projectId: 'p',
      projectName: 'n',
      floors: const [],
      cameras: const [],
      intercoms: const [],
      scenes: const [],
      customHouseSystems: const [
        CustomHouseSystem(id: 'poorten', name: 'Poorten', icon: 'gate'),
      ],
    );
    expect(houseSystemBySlug('poorten', cfg)?.name, 'Poorten');
  });

  test('unassigned universal has no system tile', () {
    const d = Device(
      id: 'u1',
      name: 'Heater',
      type: DeviceType.universal,
      favorite: false,
      ga: {},
      raw: {'type': 'universal'},
    );
    expect(systemSlugForDevice(d), isNull);
  });

  test('custom tile lists pinned room universal via deviceIds', () {
    const universal = Device(
      id: 'u1',
      name: 'Poort',
      type: DeviceType.universal,
      favorite: false,
      ga: {},
      raw: {'type': 'universal'},
    );
    final cfg = HouseConfig(
      projectId: 'p',
      projectName: 'n',
      floors: const [
        Floor(
          id: 'f1',
          name: 'BG',
          order: 0,
          rooms: [
            Room(
              id: 'r1',
              name: 'Hal',
              devices: [universal],
              scenes: [],
            ),
          ],
        ),
      ],
      cameras: const [],
      intercoms: const [],
      scenes: const [],
      customHouseSystems: const [
        CustomHouseSystem(
          id: 'poorten',
          name: 'Poorten',
          icon: 'gate',
          deviceIds: ['u1'],
        ),
      ],
    );
    final sys = houseSystemBySlug('poorten', cfg)!;
    expect(
      devicesForHouseSystem(cfg, sys).map((d) => d.id),
      contains('u1'),
    );
  });
}
