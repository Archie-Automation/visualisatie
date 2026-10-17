import 'package:archie_os/src/device_control_specs.dart';
import 'package:archie_os/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

Device climate(Map<String, dynamic>? cfg) {
  return Device(
    id: 'c',
    name: 'Woonkamer',
    type: DeviceType.climate,
    favorite: false,
    ga: const {'actual_temp': '1/1/1', 'setpoint': '1/1/2'},
    raw: {if (cfg != null) 'climate': cfg},
  );
}

void main() {
  test('absolute setpoint keeps °C defaults', () {
    final spec = climateSetpointSpec(climate(null));
    expect(spec.relative, isFalse);
    expect(spec.min, 5);
    expect(spec.max, 35);
    expect(spec.fallback, 21);
    expect(spec.tileText(21), '21.0°');
  });

  test('relative shift shows a signed kelvin value', () {
    final spec = climateSetpointSpec(
      climate({'setpointControl': 'relative_6.010', 'tempStep': 0.5}),
    );
    expect(spec.relative, isTrue);
    expect(spec.min, -5);
    expect(spec.max, 5);
    expect(spec.fallback, 0);
    expect(spec.tileText(1.5), '+1.5 K');
    expect(spec.tileText(-0.5), '-0.5 K');
    expect(spec.tileText(0), '0.0 K');
    expect(spec.format(1.2), '+1.0 K');
  });

  test('DPT 6.010 cannot exceed the 1-byte range', () {
    final spec = climateSetpointSpec(
      climate({
        'setpointControl': 'relative_6.010',
        'minTemp': -20,
        'maxTemp': 20,
      }),
    );
    expect(spec.min, -12.8);
    expect(spec.max, 12.7);
  });

  test('DPT 9.002 uses the programmed kelvin limits', () {
    final spec = climateSetpointSpecFromConfig({
      'setpointControl': 'relative_9.002',
      'minTemp': -2,
      'maxTemp': 3,
      'tempStep': 0.1,
    });
    expect(spec.min, -2);
    expect(spec.max, 3);
    expect(spec.decimals, 1);
  });
}
