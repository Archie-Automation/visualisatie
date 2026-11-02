import 'dart:convert';

import 'package:archie_os/src/api.dart';
import 'package:archie_os/src/installer/house_editor_screen.dart';
import 'package:archie_os/src/software_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() {
    return const AuthState(
      token: 'test-installer',
      username: 'installateur',
      role: 'installer',
      restoreComplete: true,
    );
  }
}

Map<String, dynamic> _house() => {
      'project': {'id': 'p1', 'name': 'Testwoning'},
      'floors': [
        {
          'id': 'fl-1',
          'name': 'Begane grond',
          'rooms': [
            {
              'id': 'rm-1',
              'name': 'Woonkamer',
              'devices': [
                {
                  'id': 'dev-1',
                  'name': 'Leeslamp',
                  'type': 'light_switch',
                },
              ],
            },
            {
              'id': 'rm-2',
              'name': 'Keuken',
              'devices': <Map<String, dynamic>>[],
            },
          ],
        },
        {
          'id': 'fl-2',
          'name': 'Boven',
          'rooms': [
            {
              'id': 'rm-3',
              'name': 'Slaapkamer',
              'devices': <Map<String, dynamic>>[],
            },
          ],
        },
      ],
    };

Future<void> _openWoonkamer(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuth.new),
        softwareVersionStatusProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        home: HouseEditorScreen(useCustomerSession: true),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final roomsNav = find.text('Kamergebonden devices');
  await tester.ensureVisible(roomsNav.first);
  await tester.tap(roomsNav.first);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Begane grond'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Woonkamer'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plakken in een andere kamer maakt een kopie', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await http.runWithClient(() async {
      await _openWoonkamer(tester);

      await tester.tap(find.text('Leeslamp'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kopiëren (Ctrl+C)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keuken'));
      await tester.pumpAndSettle();
      expect(find.text('Plak apparaat in deze kamer'), findsOneWidget);

      await tester.tap(find.text('Plak apparaat in deze kamer'));
      await tester.pumpAndSettle();

      expect(find.text('Leeslamp (kopie)'), findsWidgets);
      expect(find.text('Leeslamp (kopie) geplakt'), findsOneWidget);

      await tester.tap(find.text('Woonkamer'));
      await tester.pumpAndSettle();
      expect(find.text('Leeslamp'), findsWidgets);
    }, () {
      return MockClient((request) async {
        if (request.url.path.endsWith('/api/installer/house')) {
          return http.Response(jsonEncode(_house()), 200);
        }
        return http.Response('{"catalog":[]}', 200);
      });
    });
  });

  testWidgets('slepen zet het apparaat in de andere kamer', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await http.runWithClient(() async {
      await _openWoonkamer(tester);

      final from = tester.getCenter(find.text('Leeslamp'));
      final to = tester.getCenter(find.text('Keuken'));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Leeslamp verplaatst'), findsOneWidget);
      expect(find.text('Leeslamp'), findsWidgets);

      await tester.tap(find.text('Woonkamer'));
      await tester.pumpAndSettle();
      expect(find.text('Nog geen apparaat'), findsOneWidget);
    }, () {
      return MockClient((request) async {
        if (request.url.path.endsWith('/api/installer/house')) {
          return http.Response(jsonEncode(_house()), 200);
        }
        return http.Response('{"catalog":[]}', 200);
      });
    });
  });

  testWidgets('tik op de greep verplaatst naar een kamer op een andere verdieping',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await http.runWithClient(() async {
      await _openWoonkamer(tester);
      await tester.tap(find.text('Leeslamp'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(
          'Sleep naar een andere kamer, of tik om een kamer te kiezen',
        ).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Boven · Slaapkamer'));
      await tester.pumpAndSettle();

      expect(find.text('Leeslamp verplaatst'), findsOneWidget);
      await tester.tap(find.text('Begane grond'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Woonkamer'));
      await tester.pumpAndSettle();
      expect(find.text('Nog geen apparaat'), findsOneWidget);
    }, () {
      return MockClient((request) async {
        if (request.url.path.endsWith('/api/installer/house')) {
          return http.Response(jsonEncode(_house()), 200);
        }
        return http.Response('{"catalog":[]}', 200);
      });
    });
  });
}
