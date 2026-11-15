import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/ui/widgets/device_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _QuietBus extends BusController {
  @override
  BusState build() => const BusState({'1/1/1': true});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('slepen op de kleurencirkel scrollt de pagina niet', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    final device = Device.fromJson({
      'id': 'rgb-1',
      'name': 'Sfeer',
      'type': 'rgbw_ww',
      'ga': {
        'on': '1/1/1',
        'r': '1/2/1',
        'g': '1/2/2',
        'b': '1/2/3',
      },
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [busProvider.overrideWith(_QuietBus.new)],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                controller: scroll,
                children: [
                  RgbwWwTile(device: device),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Rect? wheel;
      final paints = find.byType(CustomPaint);
      for (var i = 0; i < paints.evaluate().length; i++) {
        final rect = tester.getRect(paints.at(i));
        if (rect.width >= 180 && (rect.width - rect.height).abs() < 2) {
          wheel = rect;
          break;
        }
      }
      expect(wheel, isNotNull);

      final gesture = await tester.startGesture(wheel!.center);
      await gesture.moveBy(const Offset(0, 140));
      await tester.pump();
      expect(scroll.offset, 0);
      await gesture.up();
      await tester.pump();
      expect(scroll.offset, 0);
    }, () {
      return MockClient((request) async => http.Response('{}', 200));
    });
  });
}
