import 'package:archie_os/src/doorbell_ringer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ding dong is the default panel ringtone', () {
    expect(DoorbellRinger.defaultToneId, 'dingdong');
    expect(DoorbellRinger.migrateToneId(null), 'dingdong');
    expect(DoorbellRinger.migrateToneId('chime'), 'dingdong');
    expect(DoorbellRinger.migrateToneId('modern'), 'dingdong');
    expect(DoorbellRinger.migrateToneId('friendly'), 'friendly');
    expect(DoorbellRinger.migrateToneId('westminster'), 'westminster');
  });
}
