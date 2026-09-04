import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/software_version.dart';

void main() {
  test('APK install only when GitHub APK is newer than the tablet', () {
    final client = SoftwareVersionInfo.parse('0.2.0+191');
    final same = SoftwareVersionInfo.parse('0.2.0+191');
    final newer = SoftwareVersionInfo.parse('0.2.0+192');
    expect(client.compareTo(same), 0);
    expect(client.compareTo(newer), lessThan(0));
    expect(newer.compareTo(client), greaterThan(0));
  });
}
