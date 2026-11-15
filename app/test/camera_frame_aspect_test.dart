import 'package:archie_os/src/ui/widgets/live_video_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(clearCameraFrameAspectCache);

  Future<void> pumpStage(
    WidgetTester tester, {
    required String id,
    required double fallback,
    required void Function(ValueChanged<double> report) onBuild,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: LiveVideoHuggingStage(
                identity: id,
                fallbackAspect: fallback,
                builder: (report) {
                  onBuild(report);
                  return const ColoredBox(color: Color(0xFF112233));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('eerste meting zet de maat en een latere meting verspringt niet',
      (tester) async {
    late ValueChanged<double> report;
    await pumpStage(
      tester,
      id: 'cam-a',
      fallback: 16 / 9,
      onBuild: (cb) => report = cb,
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

    report(4 / 3);
    await tester.pump();

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    final first = tester.getSize(find.byType(LiveVideoStage));
    expect(first.width, closeTo(300, 0.1));
    expect(first.height, closeTo(225, 0.1));

    report(16 / 9);
    await tester.pump();
    expect(tester.getSize(find.byType(LiveVideoStage)), first);
  });

  testWidgets('opnieuw openen begint op de onthouden verhouding', (tester) async {
    late ValueChanged<double> report;
    await pumpStage(
      tester,
      id: 'cam-b',
      fallback: 16 / 9,
      onBuild: (cb) => report = cb,
    );
    report(4 / 3);
    await tester.pump();

    await pumpStage(
      tester,
      id: 'cam-b',
      fallback: 16 / 9,
      onBuild: (cb) => report = cb,
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    final size = tester.getSize(find.byType(LiveVideoStage));
    expect(size.width, closeTo(300, 0.1));
    expect(size.height, closeTo(225, 0.1));

    report(16 / 9);
    await tester.pump();
    expect(tester.getSize(find.byType(LiveVideoStage)), size);
  });
}
