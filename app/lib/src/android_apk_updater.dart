import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';

const _installChannel = MethodChannel('luxe_knx/apk_install');

/// Whether this build can offer in-app APK install from the NUC proxy.
bool get supportsAndroidApkUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class AndroidApkInstallResult {
  const AndroidApkInstallResult._(this.ok, {this.error});

  final bool ok;
  final String? error;

  factory AndroidApkInstallResult.success() =>
      const AndroidApkInstallResult._(true);

  factory AndroidApkInstallResult.fail(String error) =>
      AndroidApkInstallResult._(false, error: error);
}

/// Download latest APK via the backend (`/api/app/android.apk`) and open the
/// system package installer. User must confirm the Android install prompt.
Future<AndroidApkInstallResult> downloadAndInstallAndroidApk({
  void Function(double progress)? onProgress,
  String? fileName,
}) async {
  if (!supportsAndroidApkUpdate) {
    return AndroidApkInstallResult.fail('not_android');
  }

  final installPerm = await Permission.requestInstallPackages.request();
  if (!installPerm.isGranted) {
    // Open settings so the user can allow "install unknown apps".
    await openAppSettings();
    return AndroidApkInstallResult.fail('install_permission_denied');
  }

  final uri = Uri.parse('$apiBase/api/app/android.apk');
  final request = http.Request('GET', uri);
  final client = http.Client();
  try {
    final response = await client.send(request).timeout(
          const Duration(minutes: 10),
        );
    if (response.statusCode != 200) {
      return AndroidApkInstallResult.fail(
        'download_http_${response.statusCode}',
      );
    }

    final total = response.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final safeName = (fileName == null || fileName.trim().isEmpty)
        ? 'luxe-knx-update.apk'
        : p.basename(fileName);
    final file = File(p.join(dir.path, safeName));
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received < 1024) {
      try {
        await file.delete();
      } catch (_) {}
      return AndroidApkInstallResult.fail('apk_too_small');
    }

    onProgress?.call(1);
    final launched = await _installChannel.invokeMethod<bool>(
      'installApk',
      {'path': file.path},
    );
    if (launched != true) {
      return AndroidApkInstallResult.fail('install_intent_failed');
    }
    return AndroidApkInstallResult.success();
  } on PlatformException catch (e) {
    return AndroidApkInstallResult.fail(e.code);
  } catch (e) {
    return AndroidApkInstallResult.fail(e.toString());
  } finally {
    client.close();
  }
}
