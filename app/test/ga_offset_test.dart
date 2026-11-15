import 'package:archie_os/src/installer/ga_offset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verschuift geneste adressen en een lijst in één keer', () {
    final device = <String, dynamic>{
      'id': '1/2/3',
      'name': 'Lamp',
      'ga': {'switch': '1/0/10', 'status': '1/0/11'},
      'climate': {
        'setpoint': '2/3/4',
      },
      'notes': ['geen adres', '3/1/8'],
    };

    final preview = previewDeviceGaOffset(device, main: 0, middle: 1, sub: 5);
    expect(preview.count, 4);
    expect(preview.canApply, isTrue);
    expect(preview.before, '1/0/10');
    expect(preview.after, '1/1/15');

    expect(
      applyDeviceGaOffset(device, main: 0, middle: 1, sub: 5),
      isNull,
    );
    expect(device['id'], '1/2/3');
    expect(device['ga'], {'switch': '1/1/15', 'status': '1/1/16'});
    expect(device['climate'], {'setpoint': '2/4/9'});
    expect(device['notes'], ['geen adres', '3/2/13']);
  });

  test('wijzigt niets als één adres buiten bereik valt', () {
    final device = <String, dynamic>{
      'ga': {'a': '1/7/1', 'b': '1/0/2'},
    };
    final preview = previewDeviceGaOffset(device, main: 0, middle: 1, sub: 0);
    expect(preview.error, contains('1/7/1'));
    expect(
      applyDeviceGaOffset(device, main: 0, middle: 1, sub: 0),
      isNotNull,
    );
    expect(device['ga'], {'a': '1/7/1', 'b': '1/0/2'});
  });
}
