import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/intercom/intercom_release_ui.dart';

void main() {
  test('hides door button without a release target', () {
    expect(
      intercomShowsDoorButton(
        canRelease: false,
        sipInCall: false,
        intercomRaw: {'kind': 'sip'},
      ),
      isFalse,
    );
    expect(
      intercomShowsDoorButton(
        canRelease: false,
        sipInCall: false,
        intercomRaw: null,
      ),
      isFalse,
    );
  });

  test('shows door button when the server allows release', () {
    expect(
      intercomShowsDoorButton(
        canRelease: true,
        sipInCall: false,
        intercomRaw: {'kind': 'sip'},
      ),
      isTrue,
    );
  });

  test('shows door button for a configured DoorBird without a call', () {
    expect(
      intercomShowsDoorButton(
        canRelease: false,
        sipInCall: false,
        intercomRaw: {'kind': 'doorbird'},
      ),
      isTrue,
    );
    expect(
      intercomShowsDoorButton(
        canRelease: false,
        sipInCall: false,
        intercomRaw: {
          'kind': 'other',
          'doorbird': {'host': '192.168.1.172'},
        },
      ),
      isTrue,
    );
  });
}
