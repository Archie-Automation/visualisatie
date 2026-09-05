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

  test('APK without own version is not treated as GitHub latest', () {
    const apk = GithubAndroidApkInfo(
      available: true,
      name: 'app-release.apk',
      sizeBytes: 107413974,
      downloadPath: '/api/app/android.apk',
    );
    final client = SoftwareVersionInfo.parse('0.2.0+194');
    expect(
      androidApkNewerThanClient(
        apkSupported: true,
        apk: apk,
        client: client,
      ),
      isFalse,
    );
  });

  test('APK labeled newer than the tablet offers install', () {
    const apk = GithubAndroidApkInfo(
      available: true,
      name: 'archie-os.apk',
      sizeBytes: 1,
      downloadPath: '/api/app/android.apk',
      version: '0.2.0+196',
    );
    final client = SoftwareVersionInfo.parse('0.2.0+194');
    expect(
      androidApkNewerThanClient(
        apkSupported: true,
        apk: apk,
        client: client,
      ),
      isTrue,
    );
  });

  test('rolling archie-os.apk is offered when the tablet lags the server', () {
    const apk = GithubAndroidApkInfo(
      available: true,
      name: 'archie-os.apk',
      sizeBytes: 1,
      downloadPath: '/api/app/android.apk',
      version: '0.2.0+202',
    );
    final client = SoftwareVersionInfo.parse('0.2.0+202');
    expect(
      androidApkNewerThanClient(
        apkSupported: true,
        apk: apk,
        client: client,
        clientStale: true,
      ),
      isTrue,
    );
  });
}
