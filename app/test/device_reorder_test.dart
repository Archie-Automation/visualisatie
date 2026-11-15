import 'package:archie_os/src/installer/device_reorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('neemt de plek van de rij waarop je loslaat', () {
    final list = ['A', 'B', 'C'];
    expect(placeListItem(list, 0, 1), 1);
    expect(list, ['B', 'A', 'C']);

    expect(placeListItem(list, 0, 2), 2);
    expect(list, ['A', 'C', 'B']);

    expect(placeListItem(list, 2, 0), 0);
    expect(list, ['B', 'A', 'C']);
  });

  test('dezelfde plek doet niets', () {
    final list = ['A', 'B'];
    expect(placeListItem(list, 1, 1), isNull);
    expect(list, ['A', 'B']);
  });
}
