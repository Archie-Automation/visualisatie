// Web-only entry: conditional import from full_app_restart.dart
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<void> fullAppRemountOrReload() async {
  html.window.location.reload();
}
