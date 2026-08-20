import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:archie_os/src/app.dart';

void main() {
  testWidgets('customer app builds', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ArchieOsApp()));
    await tester.pump();
    expect(find.byType(ArchieOsApp), findsOneWidget);
  });
}
