import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/media_api.dart';
import 'package:archie_os/src/models.dart';
import 'package:archie_os/src/ui/widgets/media_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speler toont hoes en transport op het scherm', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWith((ref) async => HouseConfig.fromJson({
                'project': {'id': 'p', 'name': 'Huis'},
                'floors': const [],
              })),
        ],
        child: const MaterialApp(
          home: MediaPlayerScreen(deviceId: 'sonos-1'),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MediaPlayerScreen)),
    );
    container.read(mediaStateProvider.notifier).snapshot([
      const MediaState(
        deviceId: 'sonos-1',
        brand: MediaBrand.sonos,
        online: true,
        transport: MediaTransport.playing,
        title: 'Dromen',
        artist: 'Balthazar',
        volume: 18,
        presets: [MediaPreset(id: 'fav-1', name: 'Radio 1')],
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));

    expect(tester.takeException(), isNull);
    expect(find.text('Dromen'), findsOneWidget);

    final screen = tester.getSize(find.byType(MediaPlayerScreen));
    final art = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(Icons.music_note_outlined),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    final transport = tester.getRect(find.byIcon(Icons.pause_rounded));
    expect(art.height, greaterThan(48));
    expect(art.top, greaterThanOrEqualTo(0));
    expect(transport.top, greaterThan(art.bottom));
    expect(transport.bottom, lessThan(screen.height));
    expect(find.text('FAVORIETEN'), findsOneWidget);
    final favorites = tester.getRect(find.text('FAVORIETEN'));
    expect(favorites.bottom, lessThan(screen.height));
  });
}
