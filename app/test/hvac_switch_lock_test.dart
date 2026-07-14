import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_knx/src/hvac_switch_lock.dart';

void main() {
  group('HvacLockStore.formatRemaining', () {
    test('3 min lock: pas 2 min na volle minuut verstreken', () {
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 180)),
        'nog 3 min',
      );
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 179)),
        'nog 3 min',
      );
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 121)),
        'nog 3 min',
      );
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 120)),
        'nog 2 min',
      );
    });

    test('laatste minuut in seconden', () {
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 61)),
        'nog 2 min',
      );
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 60)),
        'nog 60 sec',
      );
      expect(
        HvacLockStore.formatRemaining(const Duration(seconds: 1)),
        'nog 1 sec',
      );
    });
  });
}
