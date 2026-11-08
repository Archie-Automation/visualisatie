import 'package:web/web.dart';

/// Browser: soort apparaat plus browser, zodat de lijst niet alleen "Browser" zegt.
String deviceLabel() {
  final nav = window.navigator;
  final ua = nav.userAgent.toLowerCase();
  final platform = nav.platform.toLowerCase();
  final touches = nav.maxTouchPoints;

  final String kind;
  if (ua.contains('ipad') || (platform.contains('mac') && touches > 1)) {
    kind = 'iPad';
  } else if (ua.contains('iphone') || ua.contains('ipod')) {
    kind = 'iPhone';
  } else if (ua.contains('android') && ua.contains('mobile')) {
    kind = 'Android-telefoon';
  } else if (ua.contains('android')) {
    kind = 'Android-tablet';
  } else if (ua.contains('cros')) {
    kind = 'Chromebook';
  } else if (ua.contains('windows')) {
    kind = 'Windows';
  } else if (ua.contains('mac os') || platform.contains('mac')) {
    kind = 'Mac';
  } else if (ua.contains('linux')) {
    kind = 'Linux';
  } else {
    kind = 'Browser';
  }

  final browser = _browser(ua);
  final label = browser == null ? kind : '$kind · $browser';
  return label.length > 64 ? label.substring(0, 64) : label;
}

String? _browser(String ua) {
  if (ua.contains('edg/')) return 'Edge';
  if (ua.contains('opr/') || ua.contains('opera')) return 'Opera';
  if (ua.contains('chrome/') || ua.contains('crios')) return 'Chrome';
  if (ua.contains('firefox') || ua.contains('fxios')) return 'Firefox';
  if (ua.contains('safari')) return 'Safari';
  return null;
}
