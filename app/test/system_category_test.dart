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
}
