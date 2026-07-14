import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luxe_knx/src/app.dart';

void main() {
  testWidgets('customer app builds', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LuxeKnxApp()));
    await tester.pump();
    expect(find.byType(LuxeKnxApp), findsOneWidget);
  });
}
