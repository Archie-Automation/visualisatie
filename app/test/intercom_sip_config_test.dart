import 'package:flutter_test/flutter_test.dart';

import 'package:archie_os/src/installer/intercom_sip_config.dart';

void main() {
  group('RTSP', () {
    test('accepts rtsp and rtsps', () {
      expect(isValidRtspUrl('rtsp://192.168.1.50:554/stream'), isTrue);
      expect(
        isValidRtspUrl('rtsps://user:pass@doorbird.local/h264'),
        isTrue,
      );
      expect(validateRtspUrl('rtsp://192.168.1.10/live'), isNull);
    });

    test('rejects empty and non-rtsp', () {
      expect(validateRtspUrl(''), isNotNull);
      expect(validateRtspUrl('http://192.168.1.10/stream'), isNotNull);
      expect(validateRtspUrl('rtsp://'), isNotNull);
      expect(validateRtspUrl('  '), isNotNull);
    });
  });

  group('DTMF', () {
    test('allows a single door code', () {
      expect(isValidDtmfDigit('#'), isTrue);
      expect(isValidDtmfDigit('0'), isTrue);
      expect(isValidDtmfDigit('A'), isTrue);
      expect(validateDtmfDigit('#'), isNull);
    });

    test('rejects empty and multi-character codes', () {
      expect(validateDtmfDigit(''), isNotNull);
      expect(validateDtmfDigit('#123'), isNotNull);
      expect(isValidDtmfDigit('##'), isFalse);
    });
  });

  group('belgroep', () {
    test('createBelgroep writes default name and timeout', () {
      final house = <String, dynamic>{
        'users': <Map<String, dynamic>>[],
        'voip': {'enabled': false, 'endpoints': <dynamic>[], 'groups': <dynamic>[]},
      };
      final g = createBelgroep(house);
      expect(g['name'], defaultBelgroepName);
      expect(g['timeoutSec'], defaultRingTimeoutSec);
      expect(house['voip']['enabled'], isTrue);
    });

    test('addExtraRingButton maps knop 2 to an unused group', () {
      final groups = [
        {'id': 'grp-1', 'name': 'Woning', 'ext': '900', 'memberIds': <dynamic>[]},
        {'id': 'grp-2', 'name': 'Praktijk', 'ext': '901', 'memberIds': <dynamic>[]},
      ];
      final o = <String, dynamic>{'ringGroupId': 'grp-1'};
      expect(addExtraRingButton(o, groups), isTrue);
      expect(o['ringButtons'], [
        {'ringGroupId': 'grp-2'},
      ]);
      expect(addExtraRingButton(o, groups), isFalse);
    });

    test('deleteBelgroep clears extra ring buttons', () {
      final house = <String, dynamic>{
        'voip': {
          'enabled': true,
          'groups': [
            {'id': 'grp-1', 'name': 'Woning'},
            {'id': 'grp-2', 'name': 'Praktijk'},
          ],
        },
        'intercoms': [
          {
            'id': 'ic-1',
            'intercom': {
              'ringGroupId': 'grp-1',
              'ringButtons': [
                {'ringGroupId': 'grp-2'},
              ],
            },
          },
        ],
      };
      deleteBelgroep(house, 'grp-2');
      final o = (house['intercoms'] as List).first['intercom'] as Map;
      expect(o.containsKey('ringButtons'), isFalse);
      expect(o['ringGroupId'], 'grp-1');
    });

    test('extraRingButtonIssues flags a duplicated group', () {
      final groups = [
        {'id': 'grp-1', 'name': 'Woning'},
        {'id': 'grp-2', 'name': 'Praktijk'},
      ];
      final issues = extraRingButtonIssues(
        {
          'ringGroupId': 'grp-1',
          'ringButtons': [
            {'ringGroupId': 'grp-1'},
          ],
        },
        groups,
      );
      expect(issues, isNotEmpty);
    });
  });

  group('wizard issues', () {
    test('flags incomplete intercom', () {
      final house = <String, dynamic>{
        'voip': {
          'enabled': true,
          'endpoints': <dynamic>[],
          'groups': [
            {'id': 'grp-1', 'name': 'Deurbel belgroep', 'memberIds': <dynamic>[]},
          ],
        },
      };
      final device = <String, dynamic>{
        'id': 'dev-ic-1',
        'name': '',
        'type': 'intercom',
        'intercom': <String, dynamic>{},
      };
      final issues = intercomWizardIssues(device: device, house: house);
      expect(issues, isNotEmpty);
    });

    test('accepts a complete intercom', () {
      final house = <String, dynamic>{
        'voip': {
          'enabled': true,
          'endpoints': <dynamic>[],
          'groups': [
            {'id': 'grp-1', 'name': 'Deurbel belgroep', 'memberIds': <dynamic>[]},
          ],
        },
      };
      final device = <String, dynamic>{
        'id': 'dev-ic-1',
        'name': 'Voordeur',
        'type': 'intercom',
        'intercom': {
          'sipExt': '100',
          'sipPassword': 'secret',
          'rtsp': 'rtsp://192.168.1.50/live',
          'dtmfDigit': '#',
          'ringGroupId': 'grp-1',
        },
      };
      expect(intercomWizardIssues(device: device, house: house), isEmpty);
    });
  });
}
