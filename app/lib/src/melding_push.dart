import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'melding_nav.dart';

/// Systeemnotificatie voor een rookmelder of andere melding terwijl de app dicht is.
class MeldingPush {
  MeldingPush._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static var _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'meldingen',
      'Meldingen',
      channelDescription: 'Rookmelders en andere meldingen',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
  );

  static int idFor(String deviceId, String itemId) =>
      ('$deviceId::$itemId').hashCode & 0x3fffffff;

  static Future<void> ensureReady({bool listen = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_ready && !listen) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: listen
          ? (response) {
              if (response.payload == 'meldingen') MeldingNav.request();
            }
          : null,
    );
    _ready = true;
    if (!listen) return;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload == 'meldingen') {
      MeldingNav.request();
    }
  }

  static Future<void> show({
    required String deviceId,
    required String itemId,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await ensureReady();
    await _plugin.show(
      id: idFor(deviceId, itemId),
      title: title.trim().isEmpty ? 'Melding' : title.trim(),
      body: body.trim().isEmpty ? 'Melding actief' : body.trim(),
      notificationDetails: _details,
      payload: 'meldingen',
    );
  }

  static Future<void> cancel(String deviceId, String itemId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await ensureReady();
    await _plugin.cancel(id: idFor(deviceId, itemId));
  }
}
