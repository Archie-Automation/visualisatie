import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/ui/intercom_screen.dart';

void main() {
  test('hides door button without a release target', () {
    const device = Device(
      id: 'ic-1',
      name: 'Voordeur',
      type: DeviceType.intercom,
      favorite: false,
      ga: {},
      raw: {
        'intercom': {'kind': 'sip'},
      },
    );
    expect(intercomHasReleaseTarget(device), isFalse);
    expect(intercomHasReleaseTarget(null), isFalse);
  });

  test('shows door button when a KNX GA is configured', () {
    const device = Device(
      id: 'ic-1',
      name: 'Voordeur',
      type: DeviceType.intercom,
      favorite: false,
      ga: {},
      raw: {
        'intercom': {
          'releaseMode': 'knx',
          'release': {'ga': '1/2/3'},
        },
      },
    );
    expect(intercomHasReleaseTarget(device), isTrue);
  });
}
