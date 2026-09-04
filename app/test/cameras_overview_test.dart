import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/models.dart';

void main() {
  test('camerasOverview merges flagged intercoms', () {
    final cfg = HouseConfig.fromJson({
      'project': {'id': 'p', 'name': 't'},
      'floors': <dynamic>[],
      'cameras': [
        {'id': 'cam-1', 'name': 'Tuin', 'type': 'camera'},
      ],
      'intercoms': [
        {
          'id': 'ic-1',
          'name': 'Voordeur',
          'type': 'intercom',
          'intercom': {'showInCameras': true, 'rtsp': 'rtsp://x/s'},
        },
        {
          'id': 'ic-2',
          'name': 'Poort',
          'type': 'intercom',
          'intercom': {'showInCameras': false},
        },
      ],
      'scenes': <dynamic>[],
    });
    expect(cfg.cameras.map((d) => d.id).toList(), ['cam-1']);
    expect(cfg.camerasOverview.map((d) => d.id).toList(), ['cam-1', 'ic-1']);
  });
}
